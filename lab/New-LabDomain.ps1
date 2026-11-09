<#
.SYNOPSIS
    Step 1 of the test lab: turns a fresh Windows Server (evaluation) VM into a domain controller for lab.local.
.NOTES
    Run in an elevated PowerShell on a throwaway VM. The server reboots at the end.
    Never run this on a machine that is already part of a real domain.
#>
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $DomainName = 'lab.local',
    [string] $NetbiosName = 'LAB'
)

if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
    throw 'This machine is already joined to a domain. Use a fresh VM for the lab.'
}
if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Install AD DS and create forest $DomainName")) {
    Install-WindowsFeature AD-Domain-Services -IncludeManagementTools | Out-Null
    $dsrm = Read-Host -AsSecureString 'Directory Services Restore Mode password'
    Install-ADDSForest -DomainName $DomainName -DomainNetbiosName $NetbiosName `
        -SafeModeAdministratorPassword $dsrm -InstallDns -Force
}
