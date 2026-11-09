function Write-ProvisioningLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('INFO', 'WARN', 'ERROR')] [string] $Level,
        [Parameter(Mandatory)] [string] $Message,
        [string] $LogFile
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'), $Level, $Message
    if ($LogFile) { Add-Content -Path $LogFile -Value $line -Encoding UTF8 }
    switch ($Level) {
        'ERROR' { Write-Warning $Message }
        'WARN' { Write-Warning $Message }
        default { Write-Verbose $Message }
    }
}
