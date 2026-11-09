function Invoke-UserOffboarding {
    <#
    .SYNOPSIS
        Offboards users: disable, remove group memberships, move to the disabled OU, document.
    .DESCRIPTION
        Nothing is deleted. The account is kept disabled so files, mailbox and audit history
        stay traceable; the description records when, by whom and why. Removed groups are
        written to the report so access can be restored if someone was offboarded by mistake.
    .EXAMPLE
        Invoke-UserOffboarding -SamAccountName anna.meier -Reason 'Ticket 4711' -ConfigPath .\config\provisioning.json -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]] $SamAccountName,
        [Parameter(Mandatory)] [string] $Reason,
        [Parameter(Mandatory)] [ValidateScript({ Test-Path $_ -PathType Leaf })] [string] $ConfigPath,
        [string] $OutputDirectory = (Join-Path (Get-Location) 'reports')
    )
    begin {
        $config = Get-ProvisioningConfig -Path $ConfigPath
        if (-not (Test-Path $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory | Out-Null }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $log = Join-Path $OutputDirectory "offboarding-$stamp.log"
        $results = [Collections.Generic.List[object]]::new()
        $operator = [Environment]::UserName
    }
    process {
        foreach ($sam in $SamAccountName) {
            $user = Get-ADUser -Identity $sam -Properties MemberOf, Description -ErrorAction SilentlyContinue
            if (-not $user) {
                Write-ProvisioningLog WARN "offboarding: $sam not found" $log
                $results.Add([pscustomobject]@{ SamAccountName = $sam; Result = 'Not found'; RemovedGroups = '' })
                continue
            }
            $groups = @($user.MemberOf)
            if (-not $PSCmdlet.ShouldProcess($sam, "Disable, remove from $($groups.Count) group(s), move to $($config.DisabledOU)")) {
                $results.Add([pscustomobject]@{ SamAccountName = $sam; Result = 'WhatIf'; RemovedGroups = ($groups -join '; ') })
                continue
            }
            try {
                Disable-ADAccount -Identity $user -ErrorAction Stop
                foreach ($group in $groups) {
                    Remove-ADGroupMember -Identity $group -Members $user -Confirm:$false -ErrorAction Stop
                }
                $note = "Disabled $(Get-Date -Format 'yyyy-MM-dd') by $operator - $Reason"
                Set-ADUser -Identity $user -Description $note -ErrorAction Stop
                Move-ADObject -Identity $user.DistinguishedName -TargetPath $config.DisabledOU -ErrorAction Stop
                Write-ProvisioningLog INFO "offboarded $sam ($Reason), removed $($groups.Count) groups" $log
                $results.Add([pscustomobject]@{ SamAccountName = $sam; Result = 'Offboarded'; RemovedGroups = ($groups -join '; ') })
            }
            catch {
                Write-ProvisioningLog ERROR "failed $sam : $($_.Exception.Message)" $log
                $results.Add([pscustomobject]@{ SamAccountName = $sam; Result = "Failed: $($_.Exception.Message)"; RemovedGroups = '' })
            }
        }
    }
    end {
        $results | Export-Csv -Path (Join-Path $OutputDirectory "offboarding-$stamp.csv") -NoTypeInformation -Encoding UTF8
        foreach ($r in $results) { $r }
    }
}
