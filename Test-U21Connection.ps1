<#
.SYNOPSIS
    Unit21 API Connection Test Script

.DESCRIPTION
    Simple test script to verify API key authentication against the Unit21 API.
    Uses the u21-key header and correct endpoint paths per Unit21 API documentation.

.NOTES
    Usage: .\Test-U21Connection.ps1 -ApiKey "your-api-key"
    Sandbox: .\Test-U21Connection.ps1 -ApiKey "your-api-key" -BaseUri "https://api.sandbox1.unit21.com/v1"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ApiKey,

    [Parameter()]
    [string]$BaseUri = "https://api.prod2.unit21.com/v1"
)

# Force TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$headers = @{
    "accept"       = "application/json"
    "content-type" = "application/json"
    "u21-key"      = $ApiKey
}

$testUri = "$BaseUri/sars/bulk-export"

# Build a minimal filter body using the date string format from the docs
$yesterday = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd HH:mm:ss")
$today     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

$bodyHashtable = @{
    filters = @{
        created_at_start = $yesterday
        created_at_end   = $today
    }
}

$bodyJson  = $bodyHashtable | ConvertTo-Json -Depth 10
$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Unit21 API Connection Test" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Base URI  : $BaseUri"
Write-Host "Endpoint  : $testUri"
Write-Host "Method    : POST"
Write-Host "Auth      : u21-key header"
Write-Host "API Key   : $($ApiKey.Substring(0, [Math]::Min(8, $ApiKey.Length)))..." -ForegroundColor Yellow
Write-Host ""
Write-Host "Date Range: $yesterday to $today"
Write-Host ""
Write-Host "Request Body:"
Write-Host $bodyJson
Write-Host ""
Write-Host "Sending request..." -ForegroundColor Cyan

try {
    $response = Invoke-WebRequest -Method POST -Uri $testUri -Headers $headers -Body $bodyBytes -ErrorAction Stop

    Write-Host ""
    Write-Host "[SUCCESS] HTTP $($response.StatusCode)" -ForegroundColor Green
    Write-Host ""

    Write-Host "--- Response Headers ---" -ForegroundColor Cyan
    foreach ($key in $response.Headers.Keys) {
        Write-Host "  $key : $($response.Headers[$key])"
    }

    Write-Host ""
    Write-Host "--- Response Body ---" -ForegroundColor Cyan
    $body = $response.Content
    if ($body.Length -gt 2000) {
        Write-Host $body.Substring(0, 2000)
        Write-Host ""
        Write-Host "... (truncated, total length: $($body.Length) chars)" -ForegroundColor Yellow
    }
    else {
        Write-Host $body
    }
}
catch {
    $statusCode = $null
    if ($_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode
    }

    Write-Host ""
    Write-Host "[FAILED] HTTP $statusCode" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red

    if ($_.Exception.Response) {
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $responseBody = $reader.ReadToEnd()
            $reader.Close()
            $stream.Close()

            if ($responseBody) {
                Write-Host "Response: $responseBody" -ForegroundColor Red
            }
        }
        catch {}
    }

    Write-Host ""
    switch ($statusCode) {
        400 { Write-Host "DIAGNOSIS: Bad Request - Check the request body format." -ForegroundColor Yellow }
        401 { Write-Host "DIAGNOSIS: Unauthorized - API key is invalid." -ForegroundColor Yellow }
        403 { Write-Host "DIAGNOSIS: Forbidden - Key lacks read:sars permission." -ForegroundColor Yellow }
        404 { Write-Host "DIAGNOSIS: Not Found - Check the Base URI and endpoint path." -ForegroundColor Yellow }
        409 { Write-Host "DIAGNOSIS: Conflict - Resource conflict." -ForegroundColor Yellow }
        423 { Write-Host "DIAGNOSIS: Locked - Object update in progress, try again later." -ForegroundColor Yellow }
        429 { Write-Host "DIAGNOSIS: Rate Limited - Too many requests, try again later." -ForegroundColor Yellow }
        500 { Write-Host "DIAGNOSIS: Server Error - Unit21 internal issue, try again later." -ForegroundColor Yellow }
        503 { Write-Host "DIAGNOSIS: Service Unavailable - Unit21 is under maintenance." -ForegroundColor Yellow }
        default { Write-Host "DIAGNOSIS: Unexpected error. Check details above." -ForegroundColor Yellow }
    }
}
