function New-InitialPassword {
    <#
    .SYNOPSIS
        Creates a random initial password that meets AD complexity rules.
    .DESCRIPTION
        Uses a cryptographic random generator and guarantees at least one character from each class.
        Look-alike characters (0/O, 1/l/I) are excluded because the password is read out or typed by hand.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only generates a value; changes no system state.')]
    [CmdletBinding()]
    [OutputType([securestring])]
    param(
        [ValidateRange(12, 64)] [int] $Length = 16,
        [switch] $AsPlainText
    )
    $sets = @(
        'ABCDEFGHJKLMNPQRSTUVWXYZ'
        'abcdefghijkmnopqrstuvwxyz'
        '23456789'
        '!#%+-=?@_'
    )
    $all = -join $sets
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $pick = {
        param([string] $set)
        $bytes = [byte[]]::new(4)
        $rng.GetBytes($bytes)
        $set[[BitConverter]::ToUInt32($bytes, 0) % $set.Length]
    }

    $chars = [Collections.Generic.List[char]]::new()
    foreach ($set in $sets) { $chars.Add((& $pick $set)) }
    while ($chars.Count -lt $Length) { $chars.Add((& $pick $all)) }

    # Fisher-Yates shuffle so the guaranteed characters are not always at the start.
    for ($i = $chars.Count - 1; $i -gt 0; $i--) {
        $bytes = [byte[]]::new(4); $rng.GetBytes($bytes)
        $j = [BitConverter]::ToUInt32($bytes, 0) % ($i + 1)
        $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
    }
    $rng.Dispose()

    $plain = -join $chars
    if ($AsPlainText) { return $plain }
    ConvertTo-SecureString -String $plain -AsPlainText -Force
}
