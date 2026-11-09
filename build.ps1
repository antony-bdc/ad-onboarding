<#
.SYNOPSIS
    Local quality gate: PSScriptAnalyzer + Pester. Same as CI.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$settings = "$PSScriptRoot/PSScriptAnalyzerSettings.psd1"
$findings = foreach ($dir in 'src', 'lab') {
    Invoke-ScriptAnalyzer -Path (Join-Path $PSScriptRoot $dir) -Recurse -Settings $settings
}
if ($findings) {
    $findings | Format-Table RuleName, ScriptName, Line, Message -AutoSize
    throw "PSScriptAnalyzer: $(@($findings).Count) finding(s)"
}
Write-Output 'PSScriptAnalyzer: clean'

$config = New-PesterConfiguration
$config.Run.Path = "$PSScriptRoot/tests"
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = "$PSScriptRoot/src"
Invoke-Pester -Configuration $config
