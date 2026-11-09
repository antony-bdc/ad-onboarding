<#
.SYNOPSIS
    Step 2 of the test lab: creates the OUs and groups that config/provisioning.json expects.
    Idempotent: existing OUs and groups are left alone.
#>
#Requires -Modules ActiveDirectory
[CmdletBinding(SupportsShouldProcess)]
param([string] $ConfigPath = (Join-Path $PSScriptRoot '..\config\provisioning.json'))

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$domainDn = (Get-ADDomain).DistinguishedName

function Confirm-OU {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $Dn)
    if (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$Dn'" -ErrorAction SilentlyContinue) { return }
    $name, $parent = $Dn -split ',', 2
    if ($parent -ne $domainDn) { Confirm-OU $parent }
    if ($PSCmdlet.ShouldProcess($Dn, 'Create OU')) {
        New-ADOrganizationalUnit -Name ($name -replace '^OU=') -Path $parent -ProtectedFromAccidentalDeletion $true
        Write-Output "created OU $Dn"
    }
}

$groupsOu = "OU=Groups,$domainDn"
Confirm-OU $groupsOu
Confirm-OU $config.DisabledOU
$groups = @($config.DefaultGroups)
foreach ($dept in $config.Departments.PSObject.Properties) {
    Confirm-OU $dept.Value.OU
    $groups += $dept.Value.Groups
}
foreach ($g in $groups | Sort-Object -Unique) {
    if (-not (Get-ADGroup -Filter "Name -eq '$g'" -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess($g, 'Create group')) {
            New-ADGroup -Name $g -GroupScope Global -GroupCategory Security -Path $groupsOu
            Write-Output "created group $g"
        }
    }
}
