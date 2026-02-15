# Export-U21Sar

## SYNOPSIS
Exports SARs (Suspicious Activity Reports) from Unit21 to a local file.

## SYNTAX
```powershell
Export-U21Sar -ApiKey <string> -StartDate <string> -OutputPath <string>
              [-EndDate <string>] [-BaseUri <string>] [-Verbose]
```

## DESCRIPTION
Triggers a bulk export of SARs from Unit21, polls for completion, and downloads
the resulting file. The full workflow is automated: initiate export, poll status,
retrieve download URL, save file to disk.

**Important:** Unit21 exports are delivered as ZIP files containing multiple CSV
files. Based on testing, the SAR export contains:

- `sarfiling_sar_contents.csv` - The SAR filing data (primary)
- `sarfiling_sar_alerts.csv` - Alerts linked to the SARs
- `sarfiling_sar_cases.csv` - Cases associated with the SARs
- `sarfiling_sar_entities.csv` - Entities (people/businesses) involved
- `sarfiling_sar_events.csv` - Transactions/events referenced

The module saves the ZIP file as-is to the specified OutputPath.

## PARAMETERS

### -ApiKey (Required)
The Unit21 API key. Must have `read:sars` and `read:datafile_uploads` permissions.
Passed per-call and never stored in memory.

### -StartDate (Required)
Report creation start date. Must be in ISO format: `YYYY-MM-DD`.

### -EndDate (Optional)
Report creation end date. Must be in ISO format: `YYYY-MM-DD`. Defaults to today.

### -OutputPath (Required)
The local file path where the export file will be saved. Recommended extension: `.zip`.

### -BaseUri (Optional)
The Unit21 API base URL. Defaults to `https://api.prod2.unit21.com/v1`.
Useful for switching environments. Use the Environment Discovery script
(`Test-U21Connection.ps1`) to determine the correct URL for your API key.

### -Verbose (Optional)
Enables detailed progress output showing each step of the export workflow.
Recommended for first-time use and troubleshooting.

## EXAMPLES

### Example 1: Basic export
```powershell
Export-U21Sar -ApiKey "your-key" -StartDate "2026-02-12" -OutputPath "C:\Exports\sars.zip"
```

### Example 2: Date range with verbose output
```powershell
Export-U21Sar -ApiKey "your-key" -StartDate "2026-02-01" -EndDate "2026-02-13" `
    -OutputPath "C:\Exports\sars.zip" -Verbose
```

### Example 3: Extract the ZIP contents after download
```powershell
Export-U21Sar -ApiKey "your-key" -StartDate "2026-02-12" -OutputPath "C:\Exports\sars.zip"
Expand-Archive -Path "C:\Exports\sars.zip" -DestinationPath "C:\Exports\sars\"
```

## API DETAILS
- **Endpoint:** `POST /v1/sars/bulk-export`
- **Date filter fields:** `created_at_start` / `created_at_end` (inside `filters` object)
- **Permission:** `read:sars`, `read:datafile_uploads`
- **Note:** SARs use different date field names than Alerts and Cases.

## OUTPUT FORMAT
The downloaded file is a ZIP archive containing multiple CSV files. The primary
SAR filing data and all related objects (alerts, cases, entities, events) are
included as separate CSV files within the ZIP.

## REQUIRED PERMISSIONS
- `read:sars` - Required to initiate the SAR export
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
- SARs use `created_at_start`/`created_at_end` filter fields (different from Alerts and Cases which use `start_date`/`end_date`).
- Default API environment is Production 2 (`https://api.prod2.unit21.com/v1`).
