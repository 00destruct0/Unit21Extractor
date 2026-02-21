#Requires -Version 5.1

<#
.SYNOPSIS
    Unit21Extractor - PowerShell module for exporting Alerts, Cases, and SARs from the Unit21 API.

.DESCRIPTION
    This module provides cmdlets to export compliance data from Unit21's bulk export
    API endpoints. Exports are triggered via the API, polled for completion, and
    downloaded as CSV files to a local path.

    Supports both PowerShell 5.1 (Desktop) and PowerShell 7+ (Core).

    Public Cmdlets:
        Export-U21Alert  - Export alerts to a local CSV file
        Export-U21Case   - Export cases to a local CSV file
        Export-U21Sar    - Export SARs to a local CSV file

    Required API Key Permissions:
        read:alerts, read:cases, read:sars, read:datafile_uploads

.NOTES
    Module:  Unit21Extractor
    Version: 1.1.0
#>

# ---------------------------------------------------------------------------
# TLS Configuration
# ---------------------------------------------------------------------------
# Force TLS 1.2 for all API calls (required for PowerShell 5.1 compatibility)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------------------
# Module Configuration (Private)
# ---------------------------------------------------------------------------
$script:Config = @{
    Api    = @{
        BaseUrl   = "https://api.prod2.unit21.com/v1"
        Headers   = @{
            "accept"       = "application/json"
            "content-type" = "application/json"
        }
        Endpoints = @{
            AlertBulkExport = "/alerts/bulk-export"
            CaseBulkExport  = "/cases/bulk-export"
            SarBulkExport   = "/sars/bulk-export"
            FileExportList  = "/file-exports/list"
            FileExportDown  = "/file-exports/download"   # /{file_export_id}
        }
    }
    Retry  = @{
        MaxRetries     = 5      # Maximum number of retry attempts
        BaseDelay      = 2      # Initial delay in seconds for exponential backoff
        HardMaxBackoff = 45     # Maximum seconds to wait between retries
    }
    Export = @{
        PollIntervalSeconds = 15    # Seconds between export status polls
        TimeoutMinutes      = 30    # Maximum minutes to wait for an export job
    }
}

# ===========================================================================
# Private Functions
# ===========================================================================

function Write-U21Log {
    <#
    .SYNOPSIS
        Writes a log message to the appropriate PowerShell output stream.

    .DESCRIPTION
        Internal logging helper that routes messages to Verbose, Warning, or Error
        streams. Prepends a timestamp and module name for consistent formatting.

    .PARAMETER Message
        The log message to write.

    .PARAMETER Level
        The severity level. Valid values: Verbose, Warning, Error. Defaults to Verbose.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Verbose', 'Warning', 'Error')]
        [string]$Level = 'Verbose'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $formattedMessage = "[$timestamp] [Unit21Extractor] $Message"

    switch ($Level) {
        'Verbose' { Write-Verbose -Message $formattedMessage }
        'Warning' { Write-Warning -Message $formattedMessage }
        'Error'   { Write-Error   -Message $formattedMessage }
    }
}

function Connect-U21Api {
    <#
    .SYNOPSIS
        Builds the authentication headers for a Unit21 API request.

    .DESCRIPTION
        Internal helper that constructs the HTTP headers required for Unit21 API
        authentication using the u21-key header. Returns a headers hashtable for
        use in a single request. No credentials are stored in module scope.

    .PARAMETER ApiKey
        The Unit21 API key.

    .OUTPUTS
        [hashtable] Headers hashtable containing accept, content-type, and u21-key.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApiKey
    )

    Write-U21Log -Message "Building authentication headers"

    $headers = @{}
    foreach ($key in $script:Config.Api.Headers.Keys) {
        $headers[$key] = $script:Config.Api.Headers[$key]
    }

    # Unit21 uses the u21-key header for authentication
    $headers['u21-key'] = $ApiKey

    return $headers
}

function Invoke-U21ApiRequest {
    <#
    .SYNOPSIS
        Makes an authenticated HTTP request to the Unit21 API with retry logic.

    .DESCRIPTION
        Internal helper that executes an HTTP request against the Unit21 API.
        Retries on HTTP 429 (rate limit), 500, and 503 responses with exponential
        backoff. Raises terminating errors for non-retryable failures.

        All requests use UTF-8 encoding and the -UseBasicParsing switch for
        compatibility with PowerShell 5.1.

    .PARAMETER Method
        The HTTP method. Defaults to POST.

    .PARAMETER Uri
        The full URI of the API endpoint.

    .PARAMETER Headers
        The authentication headers hashtable from Connect-U21Api.

    .PARAMETER Body
        Optional request body as a hashtable. Will be converted to JSON and
        encoded as UTF-8 bytes.

    .OUTPUTS
        [PSCustomObject] The parsed JSON response from the API.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('GET', 'POST')]
        [string]$Method = 'POST',

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter()]
        [hashtable]$Body
    )

    $maxRetries     = $script:Config.Retry.MaxRetries
    $baseDelay      = $script:Config.Retry.BaseDelay
    $hardMaxBackoff = $script:Config.Retry.HardMaxBackoff
    $attempt        = 0

    while ($true) {
        $attempt++
        Write-U21Log -Message "API request: $Method $Uri (attempt $attempt of $($maxRetries + 1))"

        try {
            $requestParams = @{
                Method          = $Method
                Uri             = $Uri
                Headers         = $Headers
                UseBasicParsing = $true
                ErrorAction     = 'Stop'
            }

            if ($null -ne $Body) {
                $bodyJson  = $Body | ConvertTo-Json -Depth 10
                $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)
                $requestParams['Body'] = $bodyBytes
            }

            $response = Invoke-RestMethod @requestParams

            Write-U21Log -Message "API request successful: $Method $Uri"
            return $response
        }
        catch {
            $statusCode  = $null
            $rawResponse = $null

            if ($_.Exception.Response) {
                $statusCode  = [int]$_.Exception.Response.StatusCode
                $rawResponse = $_.Exception.Response
            }

            Write-U21Log -Message "API request failed: HTTP $statusCode - $($_.Exception.Message)" -Level Warning

            # Retryable status codes: 429 (rate limit), 500 (server error), 503 (maintenance)
            $isRetryable = ($statusCode -eq 429) -or ($statusCode -eq 500) -or ($statusCode -eq 503)

            if (-not $isRetryable) {
                $errorMessage = "Unit21 API error: HTTP $statusCode on $Method $Uri - $($_.Exception.Message)"
                Write-U21Log -Message $errorMessage -Level Error
                throw $errorMessage
            }

            if ($attempt -gt $maxRetries) {
                $errorMessage = "Unit21 API error: Max retries ($maxRetries) exhausted on $Method $Uri (last status: HTTP $statusCode)"
                Write-U21Log -Message $errorMessage -Level Error
                throw $errorMessage
            }

            # Calculate backoff delay
            # Check for Retry-After header first
            $delay = $null
            if ($null -ne $rawResponse -and $null -ne $rawResponse.Headers) {
                $retryAfter = $null
                if ($rawResponse.Headers -is [System.Net.WebHeaderCollection]) {
                    $retryAfter = $rawResponse.Headers['Retry-After']
                }
                elseif ($rawResponse.Headers.ContainsKey('Retry-After')) {
                    $headerValue = $rawResponse.Headers['Retry-After']
                    if ($headerValue -is [System.Collections.IEnumerable] -and $headerValue -isnot [string]) {
                        $retryAfter = $headerValue[0]
                    }
                    else {
                        $retryAfter = $headerValue
                    }
                }

                if ($null -ne $retryAfter -and $retryAfter -match '^\d+$') {
                    $delay = [int]$retryAfter
                    Write-U21Log -Message "Retry-After header: $delay seconds"
                }
            }

            # Fall back to exponential backoff with jitter
            if ($null -eq $delay) {
                $exponential = $baseDelay * [math]::Pow(2, ($attempt - 1))
                $jitter      = Get-Random -Minimum 0 -Maximum ($baseDelay + 1)
                $delay       = [int]($exponential + $jitter)
                Write-U21Log -Message "Exponential backoff: $delay seconds (attempt $attempt)"
            }

            # Cap at hard maximum
            if ($delay -gt $hardMaxBackoff) {
                $delay = $hardMaxBackoff
                Write-U21Log -Message "Delay capped at $hardMaxBackoff seconds"
            }

            Write-U21Log -Message "Waiting $delay seconds before retry..." -Level Warning
            Start-Sleep -Seconds $delay
        }
    }
}

function Wait-U21ExportJob {
    <#
    .SYNOPSIS
        Polls the Unit21 file-exports/list endpoint until the export is ready or fails.

    .DESCRIPTION
        Internal helper that monitors the status of a bulk export job by polling
        the /v1/file-exports/list endpoint. Returns the export details once status
        reaches READY_FOR_DOWNLOAD. Raises a terminating error on FAILED or timeout.

        Export statuses: REQUESTED, GENERATING, READY_FOR_DOWNLOAD, FAILED

    .PARAMETER ExportId
        The export job ID returned by the bulk-export endpoint.

    .PARAMETER Headers
        The authentication headers hashtable from Connect-U21Api.

    .PARAMETER BaseUri
        The base URL of the Unit21 API.

    .OUTPUTS
        [PSCustomObject] The export details including status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$ExportId,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$BaseUri
    )

    $pollInterval = $script:Config.Export.PollIntervalSeconds
    $timeoutMin   = $script:Config.Export.TimeoutMinutes
    $listUri      = "$BaseUri$($script:Config.Api.Endpoints.FileExportList)"
    $stopwatch    = [System.Diagnostics.Stopwatch]::StartNew()

    Write-U21Log -Message "Polling export job $ExportId (interval: ${pollInterval}s, timeout: ${timeoutMin}m)"

    while ($true) {
        # Check for timeout
        if ($stopwatch.Elapsed.TotalMinutes -ge $timeoutMin) {
            $stopwatch.Stop()
            $errorMessage = "Export job $ExportId timed out after $timeoutMin minutes"
            Write-U21Log -Message $errorMessage -Level Error
            throw $errorMessage
        }

        # Poll the file-exports/list endpoint filtering by our export ID
        $body = @{
            file_export_ids = @($ExportId)
            offset          = 1
            limit           = 1
        }

        $response = Invoke-U21ApiRequest -Method 'POST' -Uri $listUri -Headers $Headers -Body $body

        # Extract the export record from the response
        $exportRecord = $null
        if ($response -and $response.file_exports) {
            $exportRecord = $response.file_exports | Where-Object { $_.id -eq $ExportId } | Select-Object -First 1
        }

        if ($null -eq $exportRecord) {
            Write-U21Log -Message "Export job $ExportId not yet found in list, waiting..."
            Start-Sleep -Seconds $pollInterval
            continue
        }

        $status = $exportRecord.status
        Write-U21Log -Message "Export job $ExportId status: $status"

        switch ($status) {
            'READY_FOR_DOWNLOAD' {
                $stopwatch.Stop()
                $elapsed = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
                Write-U21Log -Message "Export job $ExportId ready for download (elapsed: ${elapsed}s)"
                return $exportRecord
            }
            'FAILED' {
                $stopwatch.Stop()
                $errorMessage = "Export job $ExportId failed"
                Write-U21Log -Message $errorMessage -Level Error
                throw $errorMessage
            }
            default {
                # REQUESTED or GENERATING - wait and poll again
                Write-U21Log -Message "Waiting $pollInterval seconds before next poll..."
                Start-Sleep -Seconds $pollInterval
            }
        }
    }
}

function Get-U21ExportDownloadUrl {
    <#
    .SYNOPSIS
        Retrieves the signed download URL for a completed export.

    .DESCRIPTION
        Internal helper that calls GET /v1/file-exports/download/{file_export_id}
        to obtain a signed URL for downloading the export file.

    .PARAMETER ExportId
        The export job ID.

    .PARAMETER Headers
        The authentication headers hashtable from Connect-U21Api.

    .PARAMETER BaseUri
        The base URL of the Unit21 API.

    .OUTPUTS
        [string] The signed download URL.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$ExportId,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$BaseUri
    )

    $downloadUri = "$BaseUri$($script:Config.Api.Endpoints.FileExportDown)/$ExportId"
    Write-U21Log -Message "Requesting download URL for export $ExportId"

    $response = Invoke-U21ApiRequest -Method 'GET' -Uri $downloadUri -Headers $Headers

    # The response should contain a signed URL
    $downloadUrl = $null
    if ($response -is [string]) {
        $downloadUrl = $response
    }
    elseif ($response.url) {
        $downloadUrl = $response.url
    }
    elseif ($response.download_url) {
        $downloadUrl = $response.download_url
    }
    elseif ($response.signed_url) {
        $downloadUrl = $response.signed_url
    }

    if (-not $downloadUrl) {
        $errorMessage = "No download URL returned for export $ExportId. Response: $($response | ConvertTo-Json -Depth 5 -Compress)"
        Write-U21Log -Message $errorMessage -Level Error
        throw $errorMessage
    }

    Write-U21Log -Message "Download URL obtained for export $ExportId"
    return $downloadUrl
}

function Save-U21ExportFile {
    <#
    .SYNOPSIS
        Downloads an export file from a signed URL to a local path.

    .DESCRIPTION
        Internal helper that downloads the export CSV file from the signed URL
        returned by the download endpoint. Uses Invoke-WebRequest with -OutFile
        for efficient streaming to disk.

    .PARAMETER DownloadUrl
        The signed URL to download the file from.

    .PARAMETER OutputPath
        The local file path where the file will be saved.

    .OUTPUTS
        [string] The full path of the saved file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DownloadUrl,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    Write-U21Log -Message "Downloading export file to: $OutputPath"

    # Ensure the output directory exists
    $outputDir = Split-Path -Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path -Path $outputDir)) {
        Write-U21Log -Message "Creating output directory: $outputDir"
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }

    try {
        $requestParams = @{
            Uri             = $DownloadUrl
            OutFile         = $OutputPath
            UseBasicParsing = $true
            ErrorAction     = 'Stop'
        }

        Invoke-WebRequest @requestParams

        # Validate the file was written
        if (Test-Path -Path $OutputPath) {
            $fileSize   = (Get-Item -Path $OutputPath).Length
            $fileSizeKB = [math]::Round($fileSize / 1KB, 2)
            Write-U21Log -Message "Export file saved: $OutputPath ($fileSizeKB KB)"
        }
        else {
            throw "Download completed but file not found at: $OutputPath"
        }

        return $OutputPath
    }
    catch {
        $errorMessage = "Failed to download export file: $($_.Exception.Message)"
        Write-U21Log -Message $errorMessage -Level Error
        throw $errorMessage
    }
}

# ===========================================================================
# Public Functions
# ===========================================================================

function Export-U21Alert {
    <#
    .SYNOPSIS
        Exports alerts from Unit21 to a local CSV file.

    .DESCRIPTION
        Triggers a bulk export of alerts from Unit21, polls for completion, and
        downloads the resulting CSV file to the specified output path.

    .PARAMETER ApiKey
        The Unit21 API key. Passed per-call and never stored.

    .PARAMETER StartDate
        The beginning of the date range in ISO format (YYYY-MM-DD).

    .PARAMETER EndDate
        The end of the date range in ISO format (YYYY-MM-DD). Defaults to today.

    .PARAMETER OutputPath
        The local file path where the CSV will be saved.

    .PARAMETER BaseUri
        Optional. Overrides the default API base URL.

    .PARAMETER Summary
        Optional switch. When specified, generates a summary report instead of the
        default detailed report.

    .EXAMPLE
        Export-U21Alert -ApiKey "your-key" -StartDate "2026-02-01" -OutputPath "C:\Exports\alerts.zip"

    .EXAMPLE
        Export-U21Alert -ApiKey "your-key" -StartDate "2026-02-01" -EndDate "2026-02-13" -OutputPath "C:\Exports\alerts.zip" -Verbose

    .EXAMPLE
        Export-U21Alert -ApiKey "your-key" -StartDate "2026-02-01" -OutputPath "C:\Exports\alerts_summary.zip" -Summary
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApiKey,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
        [string]$StartDate,

        [Parameter()]
        [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
        [string]$EndDate,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter()]
        [string]$BaseUri,

        [Parameter()]
        [switch]$Summary
    )

    if (-not $BaseUri) { $BaseUri = $script:Config.Api.BaseUrl }
    if (-not $EndDate) { $EndDate = (Get-Date).ToString('yyyy-MM-dd') }

    # Build date strings in the format Unit21 expects
    $startDateStr = "$StartDate 00:00:00"
    $endDateStr   = "$EndDate 23:59:59"

    Write-U21Log -Message "Exporting alerts from $startDateStr to $endDateStr"

    # Build authentication headers
    $headers = Connect-U21Api -ApiKey $ApiKey

    # Build the export request body
    # Note: Alerts use start_date/end_date, NOT created_at_start/created_at_end
    # Default is detailed report (is_summary=false). Use -Summary for summary report.
    $body = @{
        filters = @{
            start_date = $startDateStr
            end_date   = $endDateStr
        }
        is_summary = [bool]$Summary
        use_csv    = $true
    }

    # Step 1: Initiate the bulk export
    $exportUri = "$BaseUri$($script:Config.Api.Endpoints.AlertBulkExport)"
    Write-U21Log -Message "Initiating alert export: $exportUri"

    $exportResponse = Invoke-U21ApiRequest -Method 'POST' -Uri $exportUri -Headers $headers -Body $body

    $exportId = $exportResponse.id
    if (-not $exportId) {
        throw "Alert export failed: No export ID returned. Response: $($exportResponse | ConvertTo-Json -Depth 5 -Compress)"
    }

    Write-U21Log -Message "Alert export initiated: ID $exportId - $($exportResponse.message)"

    # Step 2: Poll for completion
    $exportRecord = Wait-U21ExportJob -ExportId $exportId -Headers $headers -BaseUri $BaseUri

    # Step 3: Get the download URL
    $downloadUrl = Get-U21ExportDownloadUrl -ExportId $exportId -Headers $headers -BaseUri $BaseUri

    # Step 4: Download the file
    $savedPath = Save-U21ExportFile -DownloadUrl $downloadUrl -OutputPath $OutputPath

    Write-U21Log -Message "Alert export complete: $savedPath"
    return $savedPath
}

function Export-U21Case {
    <#
    .SYNOPSIS
        Exports cases from Unit21 to a local CSV file.

    .DESCRIPTION
        Triggers a bulk export of cases from Unit21, polls for completion, and
        downloads the resulting CSV file to the specified output path.

        Note: Unit21 requires either an agent ID or agent email to initiate
        a case export.

    .PARAMETER ApiKey
        The Unit21 API key. Passed per-call and never stored.

    .PARAMETER StartDate
        The beginning of the date range in ISO format (YYYY-MM-DD).

    .PARAMETER EndDate
        The end of the date range in ISO format (YYYY-MM-DD). Defaults to today.

    .PARAMETER OutputPath
        The local file path where the CSV will be saved.

    .PARAMETER BaseUri
        Optional. Overrides the default API base URL.

    .EXAMPLE
        Export-U21Case -ApiKey "your-key" -StartDate "2026-02-01" -OutputPath "C:\Exports\cases.csv"

    .EXAMPLE
        Export-U21Case -ApiKey "your-key" -StartDate "2026-02-01" -EndDate "2026-02-13" -OutputPath "C:\Exports\cases.csv" -Verbose
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApiKey,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
        [string]$StartDate,

        [Parameter()]
        [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
        [string]$EndDate,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter()]
        [string]$BaseUri
    )

    if (-not $BaseUri) { $BaseUri = $script:Config.Api.BaseUrl }
    if (-not $EndDate) { $EndDate = (Get-Date).ToString('yyyy-MM-dd') }

    # Build date strings in the format Unit21 expects
    $startDateStr = "$StartDate 00:00:00"
    $endDateStr   = "$EndDate 23:59:59"

    Write-U21Log -Message "Exporting cases from $startDateStr to $endDateStr"

    # Build authentication headers
    $headers = Connect-U21Api -ApiKey $ApiKey

    # Build the export request body
    # Note: Cases use start_date/end_date, NOT created_at_start/created_at_end
    $body = @{
        filters = @{
            start_date = $startDateStr
            end_date   = $endDateStr
        }
        use_csv = $true
    }

    # Step 1: Initiate the bulk export
    $exportUri = "$BaseUri$($script:Config.Api.Endpoints.CaseBulkExport)"
    Write-U21Log -Message "Initiating case export: $exportUri"

    $exportResponse = Invoke-U21ApiRequest -Method 'POST' -Uri $exportUri -Headers $headers -Body $body

    $exportId = $exportResponse.id
    if (-not $exportId) {
        throw "Case export failed: No export ID returned. Response: $($exportResponse | ConvertTo-Json -Depth 5 -Compress)"
    }

    Write-U21Log -Message "Case export initiated: ID $exportId - $($exportResponse.message)"

    # Step 2: Poll for completion
    $exportRecord = Wait-U21ExportJob -ExportId $exportId -Headers $headers -BaseUri $BaseUri

    # Step 3: Get the download URL
    $downloadUrl = Get-U21ExportDownloadUrl -ExportId $exportId -Headers $headers -BaseUri $BaseUri

    # Step 4: Download the file
    $savedPath = Save-U21ExportFile -DownloadUrl $downloadUrl -OutputPath $OutputPath

    Write-U21Log -Message "Case export complete: $savedPath"
    return $savedPath
}

function Export-U21Sar {
    <#
    .SYNOPSIS
        Exports SARs (Suspicious Activity Reports) from Unit21 to a local CSV file.

    .DESCRIPTION
        Triggers a bulk export of SARs from Unit21, polls for completion, and
        downloads the resulting CSV file to the specified output path.

    .PARAMETER ApiKey
        The Unit21 API key. Passed per-call and never stored.

    .PARAMETER StartDate
        The beginning of the date range in ISO format (YYYY-MM-DD).

    .PARAMETER EndDate
        The end of the date range in ISO format (YYYY-MM-DD). Defaults to today.

    .PARAMETER OutputPath
        The local file path where the CSV will be saved.

    .PARAMETER BaseUri
        Optional. Overrides the default API base URL.

    .EXAMPLE
        Export-U21Sar -ApiKey "your-key" -StartDate "2026-02-01" -OutputPath "C:\Exports\sars.csv"

    .EXAMPLE
        Export-U21Sar -ApiKey "your-key" -StartDate "2026-02-01" -EndDate "2026-02-13" -OutputPath "C:\Exports\sars.csv" -Verbose
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApiKey,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
        [string]$StartDate,

        [Parameter()]
        [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
        [string]$EndDate,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter()]
        [string]$BaseUri
    )

    if (-not $BaseUri) { $BaseUri = $script:Config.Api.BaseUrl }
    if (-not $EndDate) { $EndDate = (Get-Date).ToString('yyyy-MM-dd') }

    # Build date strings in the format Unit21 expects
    $startDateStr = "$StartDate 00:00:00"
    $endDateStr   = "$EndDate 23:59:59"

    Write-U21Log -Message "Exporting SARs from $startDateStr to $endDateStr"

    # Build authentication headers
    $headers = Connect-U21Api -ApiKey $ApiKey

    # Build the export request body
    $body = @{
        filters = @{
            created_at_start = $startDateStr
            created_at_end   = $endDateStr
        }
        use_csv = $true
    }

    # Step 1: Initiate the bulk export
    $exportUri = "$BaseUri$($script:Config.Api.Endpoints.SarBulkExport)"
    Write-U21Log -Message "Initiating SAR export: $exportUri"

    $exportResponse = Invoke-U21ApiRequest -Method 'POST' -Uri $exportUri -Headers $headers -Body $body

    $exportId = $exportResponse.id
    if (-not $exportId) {
        throw "SAR export failed: No export ID returned. Response: $($exportResponse | ConvertTo-Json -Depth 5 -Compress)"
    }

    Write-U21Log -Message "SAR export initiated: ID $exportId - $($exportResponse.message)"

    # Step 2: Poll for completion
    $exportRecord = Wait-U21ExportJob -ExportId $exportId -Headers $headers -BaseUri $BaseUri

    # Step 3: Get the download URL
    $downloadUrl = Get-U21ExportDownloadUrl -ExportId $exportId -Headers $headers -BaseUri $BaseUri

    # Step 4: Download the file
    $savedPath = Save-U21ExportFile -DownloadUrl $downloadUrl -OutputPath $OutputPath

    Write-U21Log -Message "SAR export complete: $savedPath"
    return $savedPath
}
