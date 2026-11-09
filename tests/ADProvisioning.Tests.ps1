#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    # The ActiveDirectory module isn't available in CI. These stubs declare the real parameter
    # names, so Pester's mocks can bind them and ParameterFilter can check $Path, $Identity, ...
    if (-not (Get-Module -ListAvailable ActiveDirectory)) {
        function global:Get-ADUser { [CmdletBinding()] param($Filter, $Identity, $Properties) }
        function global:New-ADUser {
            [CmdletBinding()]
            param($Name, $DisplayName, $GivenName, $Surname, $SamAccountName, $UserPrincipalName, $EmployeeID,
                $Department, $Path, $AccountPassword, $ChangePasswordAtLogon, $Enabled, $Title, $Manager)
        }
        function global:Add-ADGroupMember { [CmdletBinding()] param($Identity, $Members) }
        function global:Disable-ADAccount { [CmdletBinding()] param($Identity) }
        function global:Remove-ADGroupMember { [CmdletBinding(SupportsShouldProcess)] param($Identity, $Members) }
        function global:Set-ADUser { [CmdletBinding()] param($Identity, $Description) }
        function global:Move-ADObject { [CmdletBinding()] param($Identity, $TargetPath) }
    }
    Import-Module "$PSScriptRoot/../src/ADProvisioning/ADProvisioning.psd1" -Force
    $script:config = "$PSScriptRoot/../config/provisioning.json"
}

Describe 'ConvertTo-AsciiName' {
    It 'converts <In> to <Out>' -ForEach @(
        @{ In = 'Anna'; Out = 'anna' }
        @{ In = 'Müller-Lüdenscheidt'; Out = 'mueller-luedenscheidt' }
        @{ In = 'Jürg'; Out = 'juerg' }
        @{ In = 'Strauß'; Out = 'strauss' }
        @{ In = 'François'; Out = 'francois' }
        @{ In = 'Núñez'; Out = 'nunez' }
        @{ In = "O'Brien"; Out = 'obrien' }
        @{ In = '  van der Berg  '; Out = 'van-der-berg' }
    ) {
        ConvertTo-AsciiName $In | Should -Be $Out
    }
}

Describe 'New-SamAccountName' {
    It 'builds firstname.lastname' {
        New-SamAccountName -GivenName 'Anna' -Surname 'Meier' -Exists { $false } | Should -Be 'anna.meier'
    }
    It 'appends a number on collision' {
        $taken = @('anna.meier', 'anna.meier2')
        New-SamAccountName -GivenName 'Anna' -Surname 'Meier' -Exists { param($n) $n -in $taken } | Should -Be 'anna.meier3'
    }
    It 'never exceeds 20 characters, including the suffix' {
        $taken = @('maximilian.mueller-l')
        $name = New-SamAccountName -GivenName 'Maximilian' -Surname 'Müller-Lüdenscheidt' -Exists { param($n) $n -in $taken }
        $name.Length | Should -BeLessOrEqual 20
        $name | Should -Be 'maximilian.mueller2'   # trailing '-' is trimmed before the suffix
    }
    It 'throws for names without usable characters' {
        { New-SamAccountName -GivenName '!!!' -Surname 'Meier' -Exists { $false } } | Should -Throw
    }
}

Describe 'New-InitialPassword' {
    It 'meets length and complexity' {
        1..50 | ForEach-Object {
            $p = New-InitialPassword -Length 16 -AsPlainText
            $p.Length | Should -Be 16
            $p | Should -MatchExactly '[A-Z]'
            $p | Should -MatchExactly '[a-z]'
            $p | Should -Match '\d'
            $p | Should -Match '[!#%+\-=?@_]'
            $p | Should -Not -MatchExactly '[0O1lI]'
        }
    }
    It 'returns a SecureString by default' {
        New-InitialPassword | Should -BeOfType [securestring]
    }
}

Describe 'Test-UserRecord' {
    BeforeAll {
        $cfg = @{ Departments = @{ IT = @{ OU = 'OU=IT'; Groups = @() } } }
    }
    It 'accepts a valid record' {
        $r = [pscustomobject]@{ EmployeeId = '100231'; GivenName = 'Anna'; Surname = 'Meier'; Department = 'IT'; StartDate = '2026-12-01' }
        Test-UserRecord -Record $r -Config $cfg | Should -BeNullOrEmpty
    }
    It 'reports missing fields' {
        $r = [pscustomobject]@{ EmployeeId = ''; GivenName = 'Anna'; Surname = ''; Department = 'IT' }
        $problems = Test-UserRecord -Record $r -Config $cfg
        $problems | Should -Contain 'missing EmployeeId'
        $problems | Should -Contain 'missing Surname'
    }
    It 'rejects unknown departments, bad ids and bad dates' {
        $r = [pscustomobject]@{ EmployeeId = 'x1'; GivenName = 'A'; Surname = 'B'; Department = 'Sales'; StartDate = '01.12.2026' }
        $problems = Test-UserRecord -Record $r -Config $cfg
        $problems.Count | Should -Be 3
    }
}

Describe 'Invoke-UserOnboarding' {
    BeforeEach {
        $script:out = Join-Path $TestDrive ([guid]::NewGuid())
        $script:csv = Join-Path $TestDrive 'hires.csv'
        @'
EmployeeId,GivenName,Surname,Department,Title
100231,Anna,Meier,IT,Engineer
100232,Anna,Meier,Finance,Accountant
'@ | Set-Content -Path $csv -Encoding UTF8
        Mock -ModuleName ADProvisioning Get-ADUser { $null }
        Mock -ModuleName ADProvisioning New-ADUser { }
        Mock -ModuleName ADProvisioning Add-ADGroupMember { }
    }

    It 'creates users with unique names and the right groups' {
        $result = Invoke-UserOnboarding -Path $csv -ConfigPath $config -OutputDirectory $out -NoCredentialExport
        $result.SamAccountName | Should -Be @('anna.meier', 'anna.meier2')
        $result.Result | Should -Be @('Created', 'Created')
        Should -Invoke -ModuleName ADProvisioning New-ADUser -Times 2 -Exactly
        Should -Invoke -ModuleName ADProvisioning New-ADUser -ParameterFilter {
            $Path -eq 'OU=IT,OU=Staff,DC=lab,DC=local' -and $ChangePasswordAtLogon -and $UserPrincipalName -eq 'anna.meier@lab.local'
        } -Times 1 -Exactly
        Should -Invoke -ModuleName ADProvisioning Add-ADGroupMember -ParameterFilter { $Identity -eq 'GG-VPN' } -Times 1 -Exactly
    }

    It 'changes nothing with -WhatIf' {
        $result = Invoke-UserOnboarding -Path $csv -ConfigPath $config -OutputDirectory $out -WhatIf
        $result.Result | Should -Be @('WhatIf', 'WhatIf')
        $result.SamAccountName | Should -Be @('anna.meier', 'anna.meier2')
        Should -Invoke -ModuleName ADProvisioning New-ADUser -Times 0 -Exactly
    }

    It 'skips users that already exist (idempotent)' {
        Mock -ModuleName ADProvisioning Get-ADUser { [pscustomobject]@{ SamAccountName = 'anna.meier' } } -ParameterFilter { $Filter -like 'EmployeeID*100231*' }
        $result = Invoke-UserOnboarding -Path $csv -ConfigPath $config -OutputDirectory $out -NoCredentialExport
        $result[0].Result | Should -Be 'Skipped (exists)'
        Should -Invoke -ModuleName ADProvisioning New-ADUser -Times 1 -Exactly
    }

    It 'aborts the whole batch on validation errors' {
        "EmployeeId,GivenName,Surname,Department`n100231,Anna,Meier,Sales" | Set-Content $csv
        { Invoke-UserOnboarding -Path $csv -ConfigPath $config -OutputDirectory $out } | Should -Throw '*nothing was changed*'
        Should -Invoke -ModuleName ADProvisioning New-ADUser -Times 0 -Exactly
    }

    It 'never writes passwords into the report' {
        Invoke-UserOnboarding -Path $csv -ConfigPath $config -OutputDirectory $out -WarningAction SilentlyContinue | Out-Null
        $report = Get-ChildItem $out -Filter 'onboarding-*.csv' | Get-Content -Raw
        $report | Should -Not -Match 'Password'
        Get-ChildItem $out -Filter 'credentials-*.csv' | Should -HaveCount 1
    }
}

Describe 'Invoke-UserOffboarding' {
    BeforeEach {
        $script:out = Join-Path $TestDrive ([guid]::NewGuid())
        Mock -ModuleName ADProvisioning Get-ADUser {
            [pscustomobject]@{ SamAccountName = 'anna.meier'; DistinguishedName = 'CN=Anna Meier,OU=IT,OU=Staff,DC=lab,DC=local'
                MemberOf = @('CN=GG-IT,OU=Groups,DC=lab,DC=local', 'CN=GG-VPN,OU=Groups,DC=lab,DC=local') }
        }
        Mock -ModuleName ADProvisioning Disable-ADAccount { }
        Mock -ModuleName ADProvisioning Remove-ADGroupMember { }
        Mock -ModuleName ADProvisioning Set-ADUser { }
        Mock -ModuleName ADProvisioning Move-ADObject { }
    }

    It 'disables, removes groups, documents and moves the account' {
        $r = Invoke-UserOffboarding -SamAccountName anna.meier -Reason 'Ticket 4711' -ConfigPath $config -OutputDirectory $out -Confirm:$false
        $r.Result | Should -Be 'Offboarded'
        $r.RemovedGroups | Should -Match 'GG-VPN'
        Should -Invoke -ModuleName ADProvisioning Disable-ADAccount -Times 1 -Exactly
        Should -Invoke -ModuleName ADProvisioning Remove-ADGroupMember -Times 2 -Exactly
        Should -Invoke -ModuleName ADProvisioning Set-ADUser -ParameterFilter { $Description -like '*Ticket 4711*' } -Times 1 -Exactly
        Should -Invoke -ModuleName ADProvisioning Move-ADObject -ParameterFilter { $TargetPath -eq 'OU=Disabled,OU=Staff,DC=lab,DC=local' } -Times 1 -Exactly
    }

    It 'changes nothing with -WhatIf' {
        Invoke-UserOffboarding -SamAccountName anna.meier -Reason 'x' -ConfigPath $config -OutputDirectory $out -WhatIf | Out-Null
        Should -Invoke -ModuleName ADProvisioning Disable-ADAccount -Times 0 -Exactly
    }
}
