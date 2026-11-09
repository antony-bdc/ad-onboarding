function New-SamAccountName {
    <#
    .SYNOPSIS
        Builds a unique sAMAccountName in the form firstname.lastname (max. 20 characters).
    .DESCRIPTION
        Collisions get a number appended: anna.meier, anna.meier2, anna.meier3 ...
        The 20-character limit of sAMAccountName is respected, including the suffix.
    .PARAMETER Exists
        Script block that returns $true if a name is already taken. Defaults to an AD lookup.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only computes a name; changes no system state.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $GivenName,
        [Parameter(Mandatory)] [string] $Surname,
        [scriptblock] $Exists = { param($name) [bool](Get-ADUser -Filter "SamAccountName -eq '$name'" -ErrorAction SilentlyContinue) }
    )
    $first = ConvertTo-AsciiName $GivenName
    $last = ConvertTo-AsciiName $Surname
    if (-not $first -or -not $last) {
        throw "Cannot build an account name from '$GivenName' '$Surname'."
    }
    $base = "$first.$last"

    for ($i = 1; $i -lt 100; $i++) {
        $suffix = if ($i -eq 1) { '' } else { "$i" }
        $max = 20 - $suffix.Length
        $candidate = $base.Substring(0, [Math]::Min($base.Length, $max)).TrimEnd('.', '-') + $suffix
        if (-not (& $Exists $candidate)) { return $candidate }
    }
    throw "No free account name found for '$base'."
}
