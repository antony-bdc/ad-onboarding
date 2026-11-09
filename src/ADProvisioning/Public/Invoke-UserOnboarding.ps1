function Invoke-UserOnboarding {
    <#
    .SYNOPSIS
        Creates AD users from a CSV file: validated, idempotent, with -WhatIf and a report.
    .DESCRIPTION
        For every row:
          1. validate the record (nothing is changed if a row is invalid),
          2. skip it if a user with the same EmployeeId already exists (safe to run again),
          3. create the user in the department's OU with a random initial password
             that must be changed at first logon,
          4. add default and department groups, set the manager.
        Writes a result report (CSV, no passwords) and, unless -NoCredentialExport is set,
        a separate credentials file that only the current user can read.
    .EXAMPLE
        Invoke-UserOnboarding -Path .\samples\new-hires.csv -ConfigPath .\config\provisioning.json -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateScript({ Test-Path $_ -PathType Leaf })] [string] $Path,
        [Parameter(Mandatory)] [ValidateScript({ Test-Path $_ -PathType Leaf })] [string] $ConfigPath,
        [string] $OutputDirectory = (Join-Path (Get-Location) 'reports'),
        [switch] $NoCredentialExport
    )

    $config = Get-ProvisioningConfig -Path $ConfigPath
    $rows = @(Import-Csv -Path $Path -Encoding UTF8)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    if (-not (Test-Path $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory | Out-Null }
    $log = Join-Path $OutputDirectory "onboarding-$stamp.log"
    Write-ProvisioningLog INFO "onboarding $($rows.Count) rows from $Path (WhatIf: $([bool]$WhatIfPreference))" $log

    # Validate everything first: a half-imported batch is worse than none.
    $invalid = 0
    for ($i = 0; $i -lt $rows.Count; $i++) {
        foreach ($problem in (Test-UserRecord -Record $rows[$i] -Config $config)) {
            Write-ProvisioningLog ERROR "row $($i + 2): $problem" $log
            $invalid++
        }
    }
    if ($invalid) { throw "$invalid validation error(s) in $Path - nothing was changed. See $log." }

    $results = [Collections.Generic.List[object]]::new()
    # Names handed out in this run count as taken, also under -WhatIf (two "Anna Meier" in one file).
    $reserved = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $exists = {
        param($name)
        $reserved.Contains($name) -or [bool](Get-ADUser -Filter "SamAccountName -eq '$name'" -ErrorAction SilentlyContinue)
    }
    $credentials = [Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $existing = Get-ADUser -Filter "EmployeeID -eq '$($row.EmployeeId)'" -Properties EmployeeID -ErrorAction SilentlyContinue
        if ($existing) {
            Write-ProvisioningLog INFO "skip $($row.EmployeeId): already exists as $($existing.SamAccountName)" $log
            $results.Add([pscustomobject]@{ EmployeeId = $row.EmployeeId; SamAccountName = $existing.SamAccountName; Result = 'Skipped (exists)' })
            continue
        }

        $dept = $config.Departments[$row.Department]
        $sam = New-SamAccountName -GivenName $row.GivenName -Surname $row.Surname -Exists $exists
        [void] $reserved.Add($sam)
        $plain = New-InitialPassword -AsPlainText
        $params = @{
            Name                  = "$($row.GivenName) $($row.Surname)"
            DisplayName           = "$($row.GivenName) $($row.Surname)"
            GivenName             = $row.GivenName
            Surname               = $row.Surname
            SamAccountName        = $sam
            UserPrincipalName     = "$sam@$($config.UpnSuffix)"
            EmployeeID            = $row.EmployeeId
            Department            = $row.Department
            Path                  = $dept.OU
            AccountPassword       = (ConvertTo-SecureString $plain -AsPlainText -Force)
            ChangePasswordAtLogon = $true
            Enabled               = $true
        }
        if ($row.PSObject.Properties['Title'] -and $row.Title) { $params.Title = $row.Title }
        if ($row.PSObject.Properties['Manager'] -and $row.Manager) { $params.Manager = $row.Manager }

        if (-not $PSCmdlet.ShouldProcess("$sam in $($dept.OU)", 'Create AD user')) {
            $results.Add([pscustomobject]@{ EmployeeId = $row.EmployeeId; SamAccountName = $sam; Result = 'WhatIf' })
            continue
        }
        try {
            New-ADUser @params -ErrorAction Stop
            foreach ($group in @($config.DefaultGroups) + @($dept.Groups) | Where-Object { $_ }) {
                Add-ADGroupMember -Identity $group -Members $sam -ErrorAction Stop
            }
            Write-ProvisioningLog INFO "created $sam ($($row.EmployeeId)) in $($dept.OU)" $log
            $results.Add([pscustomobject]@{ EmployeeId = $row.EmployeeId; SamAccountName = $sam; Result = 'Created' })
            $credentials.Add([pscustomobject]@{ SamAccountName = $sam; InitialPassword = $plain })
        }
        catch {
            Write-ProvisioningLog ERROR "failed $sam ($($row.EmployeeId)): $($_.Exception.Message)" $log
            $results.Add([pscustomobject]@{ EmployeeId = $row.EmployeeId; SamAccountName = $sam; Result = "Failed: $($_.Exception.Message)" })
        }
    }

    $report = Join-Path $OutputDirectory "onboarding-$stamp.csv"
    $results | Export-Csv -Path $report -NoTypeInformation -Encoding UTF8
    if ($credentials.Count -and -not $NoCredentialExport) {
        $credFile = Join-Path $OutputDirectory "credentials-$stamp.csv"
        $credentials | Export-Csv -Path $credFile -NoTypeInformation -Encoding UTF8
        Protect-File -Path $credFile
        Write-Warning "Initial passwords in $credFile - hand them over and delete the file."
    }
    Write-ProvisioningLog INFO "done: $(@($results | Where-Object Result -eq 'Created').Count) created, report $report" $log
    foreach ($r in $results) { $r }
}
