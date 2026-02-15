# Test-U21Connection

## SYNOPSIS
Discovers which Unit21 environment an API key belongs to by testing all available environments.

## SYNTAX
```powershell
.\Test-U21Connection.ps1 -ApiKey <string>
```

## DESCRIPTION
Tests a Unit21 API key against all six Unit21 environments (three production,
one EU production, one sandbox, one EU sandbox) and displays the results in a
table. Identifies which environment the key is valid for and provides the correct
`-BaseUri` value to use with the Unit21Extractor module.

This is a standalone script (not a module cmdlet) intended for onboarding new
API keys and troubleshooting authentication issues.

## PARAMETERS

### -ApiKey (Required)
The Unit21 API key to test.

## HOW IT WORKS
The script sends a POST request to the `/v1/sars/bulk-export` endpoint on each
environment using the `u21-key` authentication header. A successful HTTP 200
response indicates the key belongs to that environment. All other responses
(401, 403, 404, etc.) are reported with diagnostic details.

**Note:** A successful test against the SAR endpoint will initiate an actual
export job in that environment. This is harmless — the export will appear in
the Unit21 dashboard and can be ignored.

## ENVIRONMENTS TESTED

| Environment | Base URL |
|---|---|
| Production 1 | `https://api.unit21.com` |
| Production 2 | `https://api.prod2.unit21.com` |
| Production 3 | `https://api.prod3.unit21.com` |
| Production (EU) | `https://api.prod1.eu-central-1.unit21.com` |
| Sandbox | `https://sandbox1-api.unit21.com` |
| Sandbox (EU) | `https://api.sandbox1.eu-central-1.unit21.com` |

## EXAMPLE OUTPUT

```
============================================
 Unit21 API Environment Discovery
============================================

API Key : 9ff613ac...
Endpoint: /v1/sars/bulk-export (POST)

Testing all environments...

  Testing Production 1... 401
  Testing Production 2... OK
  Testing Production 3... 401
  Testing Production (EU)... 401
  Testing Sandbox... 401
  Testing Sandbox (EU)... 401

============================================
 Results
============================================

Environment     HTTP Result  Detail
-----------     ---- ------  ------
Production 1     401 FAILED  Unauthorized (wrong environment or invalid key)
Production 2     200 SUCCESS File export has started
Production 3     401 FAILED  Unauthorized (wrong environment or invalid key)
Production (EU)  401 FAILED  Unauthorized (wrong environment or invalid key)
Sandbox          401 FAILED  Unauthorized (wrong environment or invalid key)
Sandbox (EU)     401 FAILED  Unauthorized (wrong environment or invalid key)

MATCH FOUND:
  Environment : Production 2
  Base URL    : https://api.prod2.unit21.com
  Use in module: -BaseUri "https://api.prod2.unit21.com/v1"
```

## INTERPRETING RESULTS

| Result | HTTP | Meaning |
|---|---|---|
| SUCCESS | 200 | Key is valid for this environment. Use the provided `-BaseUri` value. |
| FAILED | 401 | Key is not valid for this environment (wrong environment or invalid key). |
| FAILED | 403 | Key is valid but lacks `read:sars` permission. Contact your administrator. |
| FAILED | 404 | Endpoint not found. The environment URL may have changed. |
| FAILED | 429 | Rate limited. Wait and try again. |
| FAILED | 500/503 | Server error. The environment may be temporarily unavailable. |

## USE CASES

### Onboarding a new API key
When a new API key is generated, run this script to determine which environment
it belongs to before configuring the module:

```powershell
.\Test-U21Connection.ps1 -ApiKey "new-api-key"
```

### Troubleshooting HTTP 401 errors
If an export cmdlet returns a 401 Unauthorized error, run this script to verify
the key is still active and confirm the correct environment:

```powershell
.\Test-U21Connection.ps1 -ApiKey "your-key"
```

### Verifying key permissions
If the script returns HTTP 403 for an environment (instead of 401), the key is
valid for that environment but lacks the `read:sars` permission needed for the
test. Contact your Unit21 administrator to verify permissions.

## REQUIREMENTS
- PowerShell 5.1+
- API key must have `read:sars` permission for the test to return SUCCESS
- Network access to Unit21 API endpoints (HTTPS on port 443)

## NOTES
- The script tests `read:sars` permission specifically. A SUCCESS result confirms
  that permission but does not verify `read:alerts`, `read:cases`, or
  `read:datafile_uploads`. Those should be confirmed separately or in the
  Unit21 dashboard.
- The default environment for the Unit21Extractor module is Production 2.
  If your key matches a different environment, pass `-BaseUri` to the export cmdlets.
