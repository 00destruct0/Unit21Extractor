# Export-U21Case

## SYNOPSIS
Exports cases from Unit21 to a local file.

## SYNTAX
```powershell
Export-U21Case -ApiKey <string> -StartDate <string> -OutputPath <string>
               [-EndDate <string>] [-BaseUri <string>] [-Verbose]
```

## DESCRIPTION
Triggers a bulk export of cases from Unit21, polls for completion, and downloads
the resulting file. The full workflow is automated: initiate export, poll status,
retrieve download URL, save file to disk.

**Important:** Unit21 exports are delivered as ZIP files containing multiple CSV
files. Based on testing, the case export contains:

- `case_case_contents.csv` - The case data (primary)
- `case_case_alerts.csv` - Alerts linked to the cases
- `case_case_action_events.csv` - Action events associated with the cases
- `case_case_entities.csv` - Entities (people/businesses) involved
- `case_case_events.csv` - Transactions/events referenced

The module saves the ZIP file as-is to the specified OutputPath.

## PARAMETERS

### -ApiKey (Required)
The Unit21 API key. Must have `read:cases` and `read:datafile_uploads` permissions.
Passed per-call and never stored in memory.

### -StartDate (Required)
Case creation start date. Must be in ISO format: `YYYY-MM-DD`.

### -EndDate (Optional)
Case creation end date. Must be in ISO format: `YYYY-MM-DD`. Defaults to today.

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
Export-U21Case -ApiKey "your-key" -StartDate "2026-02-12" -OutputPath "C:\Exports\cases.zip"
```

### Example 2: Date range with verbose output
```powershell
Export-U21Case -ApiKey "your-key" -StartDate "2026-02-01" -EndDate "2026-02-13" `
    -OutputPath "C:\Exports\cases.zip" -Verbose
```

### Example 3: Extract the ZIP contents after download
```powershell
Export-U21Case -ApiKey "your-key" -StartDate "2026-02-12" -OutputPath "C:\Exports\cases.zip"
Expand-Archive -Path "C:\Exports\cases.zip" -DestinationPath "C:\Exports\cases\"
```

## API DETAILS
- **Endpoint:** `POST /v1/cases/bulk-export`
- **Date filter fields:** `start_date` / `end_date` (inside `filters` object)
- **Permission:** `read:cases`, `read:datafile_uploads`
- **Note:** Unit21 documentation states that an agent ID or email is required,
  but testing confirmed the export works without one when using date filters.

## OUTPUT FORMAT
The downloaded file is a ZIP archive containing multiple CSV files. The primary
case data and all related objects (alerts, action events, entities, events) are
included as separate CSV files within the ZIP.

## REQUIRED PERMISSIONS
- `read:cases` - Required to initiate the case export
- `read:datafile_uploads` - Required to list and download the export file

## ERROR HANDLING
- **HTTP 400**: Bad request - check filter parameters. If date filters fail,
  the endpoint may require an agent ID or email for your configuration.
- **HTTP 401**: Unauthorized - invalid API key or wrong environment.
  Use `Test-U21Connection.ps1` to verify your API key and environment.
- **HTTP 403**: Forbidden - key lacks required permissions.
- **HTTP 429**: Automatic retry with exponential backoff.
- **HTTP 500/503**: Automatic retry with exponential backoff.
- **Timeout**: Terminating error if export does not complete within 30 minutes.

## NOTES
- The `-Verbose` flag is recommended to monitor export progress.
- Cases use `start_date`/`end_date` filter fields (not `created_at_start`/`created_at_end`).
- Default API environment is Production 2 (`https://api.prod2.unit21.com/v1`).
