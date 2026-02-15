# Export-U21Alert

## SYNOPSIS
Exports alerts from Unit21 to a local file.

## SYNTAX
```powershell
Export-U21Alert -ApiKey <string> -StartDate <string> -OutputPath <string>
               [-EndDate <string>] [-BaseUri <string>] [-IsSummary <bool>] [-Verbose]
```

## DESCRIPTION
Triggers a bulk export of alerts from Unit21, polls for completion, and downloads
the resulting file. The full workflow is automated: initiate export, poll status,
retrieve download URL, save file to disk.

**Important:** Unit21 exports are delivered as ZIP files containing multiple CSV
files. The ZIP includes the primary alert data along with related objects. Based
on testing, the alert export contains:

- `alert_alert_contents.csv` - The alert data (primary)
- Additional related object CSVs may be included

The module saves the ZIP file as-is to the specified OutputPath.

## PARAMETERS

### -ApiKey (Required)
The Unit21 API key. Must have `read:alerts` and `read:datafile_uploads` permissions.
Passed per-call and never stored in memory.

### -StartDate (Required)
Alert creation start date. Must be in ISO format: `YYYY-MM-DD`.

### -EndDate (Optional)
Alert creation end date. Must be in ISO format: `YYYY-MM-DD`. Defaults to today.

### -OutputPath (Required)
The local file path where the export file will be saved. Recommended extension: `.zip`.

### -BaseUri (Optional)
The Unit21 API base URL. Defaults to `https://api.prod2.unit21.com/v1`.
Useful for switching environments. Use the Environment Discovery script
(`Test-U21Connection.ps1`) to determine the correct URL for your API key.

### -IsSummary (Optional)
If `$true` (default), generates the summary report. If `$false`, generates the
detailed report.

### -Verbose (Optional)
Enables detailed progress output showing each step of the export workflow.
Recommended for first-time use and troubleshooting.

## EXAMPLES

### Example 1: Basic export
```powershell
Export-U21Alert -ApiKey "your-key" -StartDate "2026-02-12" -OutputPath "C:\Exports\alerts.zip"
```

### Example 2: Date range with detailed report and verbose output
```powershell
Export-U21Alert -ApiKey "your-key" -StartDate "2026-02-01" -EndDate "2026-02-13" `
    -OutputPath "C:\Exports\alerts.zip" -IsSummary $false -Verbose
```

### Example 3: Extract the ZIP contents after download
```powershell
Export-U21Alert -ApiKey "your-key" -StartDate "2026-02-12" -OutputPath "C:\Exports\alerts.zip"
Expand-Archive -Path "C:\Exports\alerts.zip" -DestinationPath "C:\Exports\alerts\"
```

## API DETAILS
- **Endpoint:** `POST /v1/alerts/bulk-export`
- **Date filter fields:** `start_date` / `end_date` (inside `filters` object)
- **Permission:** `read:alerts`, `read:datafile_uploads`

## OUTPUT FORMAT
The downloaded file is a ZIP archive containing multiple CSV files. The primary
alert data and all related objects are included as separate CSV files within the ZIP.

## REQUIRED PERMISSIONS
- `read:alerts` - Required to initiate the alert export
- `read:datafile_uploads` - Required to list and download the export file

## ERROR HANDLING
- **HTTP 400**: Bad request - check filter parameters.
- **HTTP 401**: Unauthorized - invalid API key or wrong environment.
  Use `Test-U21Connection.ps1` to verify your API key and environment.
- **HTTP 403**: Forbidden - key lacks required permissions.
- **HTTP 429**: Automatic retry with exponential backoff.
- **HTTP 500/503**: Automatic retry with exponential backoff.
- **Timeout**: Terminating error if export does not complete within 30 minutes.

## NOTES
- The `-Verbose` flag is recommended to monitor export progress.
- Alerts use `start_date`/`end_date` filter fields (not `created_at_start`/`created_at_end`).
- Default API environment is Production 2 (`https://api.prod2.unit21.com/v1`).
