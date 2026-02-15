@{
    # Module Information
    RootModule        = 'Unit21Extractor.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '7f3c2e91-5b6a-4d8f-9c2a-3e7b1f6a8d42'
    Author            = 'Ryan Terp'
    Copyright         = 'Copyright (c) 2026 Ryan Terp'
    Description       = 'PowerShell module for exporting Alerts, Cases, and SARs from the Unit21 API as CSV files.'

    # Requirements
    PowerShellVersion = '5.1'
    CompatiblePSEditions    = @('Desktop','Core')

    # Exported Functions - only public cmdlets are visible
    FunctionsToExport = @(
        'Export-U21Alert'
        'Export-U21Case'
        'Export-U21Sar'
    )

    # Nothing else to export
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    # Private Data
    PrivateData = @{
        PSData = @{
            Tags       = @('Unit21', 'Compliance', 'Export', 'API', 'AML', 'BSA')
            LicenseUri = 'https://opensource.org/licenses/MIT'
            ProjectUri = 'https://github.com/00destruct0/Unit21Extractor'
        }
    }
}
