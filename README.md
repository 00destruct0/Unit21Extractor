# Unit21Extractor PowerShell Module

This open-source PowerShell module provides a streamlined interface for interacting with the [Unit21 API](https://www.unit21.ai/). It enables programmatic exports of Alerts, Cases, and Suspicious Activity Reports (SARs) by fully automating the Unit21 bulk export workflow. The module initiates the export request, monitors the job until completion, retrieves the generated download URL, and saves the resulting ZIP file locally.

This project is independently developed and is not affiliated with or endorsed by Unit21.


## Requirements

- PowerShell 5.1+ (Windows) or PowerShell 7+ (Core)
- Unit21 API key with the following permissions:
  - `read:alerts` (for alert exports)
  - `read:cases` (for case exports)
  - `read:sars` (for SAR exports)
  - `read:datafile_uploads` (required for all exports — enables file listing and download)

## Installation

> 📝 **Which PowerShell version am I using?**
>
> Most Windows systems include **Windows PowerShell 5.1** by default, as it ships preinstalled with the operating system. If you have not intentionally installed PowerShell 7, you are almost certainly running **PowerShell 5.1**.


1. Extract `Unit21Extractor_1_1_0.zip`.
2. Copy the extracted `Unit21Extractor` folder to the appropriate module directory shown below.

| Version         | Scope         | Path                                            |
|-----------------|--------------|--------------------------------------------------|
| PowerShell 5.1  | Current User | `$HOME\Documents\WindowsPowerShell\Modules`      |
| PowerShell 7    | Current User | `$HOME\Documents\PowerShell\Modules`             |

After copying the module, import it:

```powershell
Import-Module Unit21Extractor
```

## What’s New in v1.1.0

- **Export-U21Alert: Export Enhancements**  
  `Export-U21Alert` now generates a **detailed report** (`is_summary=false`) by default, based on user feedback indicating this is the preferred format. A new `-Summary` switch has been added to generate a summary report when needed.


## Usage

| Function | Description | Example | 
| ----------- | ----------- | ----------- |
| Export-U21Alert | Initiates a bulk alert export from Unit21 for a specified date range, automatically polls until the export is complete, and downloads the resulting ZIP file. | `Export-U21Alert -ApiKey "your-key" -StartDate "2026-02-12" -OutputPath "C:\Exports\alerts.zip"` |
| Export-U21Case | Initiates a bulk case export from Unit21 for a specified date range, automatically polls until the export is complete, and downloads the resulting ZIP file. | `Export-U21Case -ApiKey "your-key" -StartDate "2026-02-12" -OutputPath "C:\Exports\cases.zip"` |
| Export-U21Sar  | Initiates a bulk export of SARs (Suspicious Activity Reports) from Unit21 for a specified date range, automatically polls until the export completes, and downloads the resulting ZIP. | `Export-U21Sar -ApiKey "your-key" -StartDate "2026-02-12" -OutputPath "C:\Exports\sars.zip"` |

## Detailed Documentation
- [Export-U21Alert](docs/Export-U21Alert.md)
- [Export-U21Case](docs/Export-U21Case.md)
- [Export-U21Sar](docs/Export-U21Sar.md)
- [Test-U21Connection](docs/Test-U21Connection.md) - Environment discovery utility



## Environment Discovery

Use the included `Test-U21Connection.ps1` script to determine which Unit21 environment your API key belongs to:

```powershell
.\Test-U21Connection.ps1 -ApiKey "your-key"
```

This tests all six Unit21 environments and shows which one accepts your key.

The module defaults to Production 2 (`https://api.prod2.unit21.com/v1`) if `-BaseUri` is not specified. To use a different environment, pass the `-BaseUri` parameter:

```powershell
Export-U21Sar -ApiKey "your-key" -StartDate "2026-02-01" `
    -OutputPath "C:\Exports\sars.zip" -BaseUri "https://api.unit21.com/v1"
```

## Available Environments

| Environment | Base URL |
|---|---|
| Production 1 | `https://api.unit21.com/v1` |
| Production 2 | `https://api.prod2.unit21.com/v1` |
| Production 3 | `https://api.prod3.unit21.com/v1` |
| Production (EU) | `https://api.prod1.eu-central-1.unit21.com/v1` |
| Sandbox | `https://sandbox1-api.unit21.com/v1` |
| Sandbox (EU) | `https://api.sandbox1.eu-central-1.unit21.com/v1` |



## API Notes

- **Authentication:** Uses the `u21-key` HTTP header (not Bearer token)
- **Encoding:** UTF-8 only. Unicode NULL characters (`\u0000`) are rejected.
- **Rate Limit:** 600 requests per interval. The module automatically retries on HTTP 429.
- **Date Filter Fields:**
  - Alerts and Cases use `start_date` / `end_date`
  - SARs use `created_at_start` / `created_at_end`
- **Export Workflow:** Bulk export → poll file-exports/list → download via signed URL
- **TLS:** All requests use TLS 1.2

## Troubleshooting

| Error | Cause | Solution |
|---|---|---|
| HTTP 401 | Wrong environment or invalid key | Run `Test-U21Connection.ps1` to find your environment |
| HTTP 400 | Invalid request body | Check date format (YYYY-MM-DD) |
| HTTP 403 | Missing permissions | Verify key has `read:alerts`, `read:cases`, `read:sars`, `read:datafile_uploads` |
| HTTP 429 | Rate limited | Automatic retry — no action needed |
| Timeout | Export taking too long | Increase timeout or narrow date range |
| No output | Missing `-Verbose` | Add `-Verbose` to see progress |

## License
This module is released under the [MIT License](https://opensource.org/licenses/MIT). You may use, modify, and distribute it freely.

## Author
Ryan Terp
📧 ryan.terp@gmail.com