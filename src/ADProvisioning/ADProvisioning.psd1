@{
    RootModule        = 'ADProvisioning.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '6f1d2c4e-8a37-4f5b-9c0e-2b7a1d9e4c31'
    Author            = 'Antony BDC'
    Description       = 'CSV-driven onboarding and offboarding of Active Directory users with validation, WhatIf and reports.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Invoke-UserOnboarding'
        'Invoke-UserOffboarding'
        'ConvertTo-AsciiName'
        'New-SamAccountName'
        'New-InitialPassword'
        'Test-UserRecord'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()
    VariablesToExport = @()
    PrivateData       = @{ PSData = @{ Tags = @('ActiveDirectory', 'Onboarding', 'Automation'); LicenseUri = 'https://opensource.org/licenses/MIT' } }
}
