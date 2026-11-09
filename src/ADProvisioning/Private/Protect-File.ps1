function Protect-File {
    <#
    .SYNOPSIS
        Restricts a file to the current user (removes inherited permissions).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if ($IsLinux -or $IsMacOS) {
        chmod 600 $Path
        return
    }
    $acl = Get-Acl -Path $Path
    $acl.SetAccessRuleProtection($true, $false)
    $acl.Access | ForEach-Object { [void] $acl.RemoveAccessRule($_) }
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $rule = [Security.AccessControl.FileSystemAccessRule]::new($me, 'FullControl', 'Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -Path $Path -AclObject $acl
}
