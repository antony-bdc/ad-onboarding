function Get-ProvisioningConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [string] $Path)

    $json = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $departments = @{}
    foreach ($p in $json.Departments.PSObject.Properties) {
        $departments[$p.Name] = @{ OU = $p.Value.OU; Groups = @($p.Value.Groups) }
    }
    foreach ($key in 'UpnSuffix', 'DisabledOU') {
        if (-not $json.$key) { throw "Config '$Path' is missing '$key'." }
    }
    @{
        UpnSuffix     = $json.UpnSuffix
        DisabledOU    = $json.DisabledOU
        DefaultGroups = @($json.DefaultGroups)
        Departments   = $departments
    }
}
