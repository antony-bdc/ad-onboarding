@{
    Severity     = @('Error', 'Warning', 'Information')
    ExcludeRules = @(
        # Initial passwords are generated, never typed in; converting them for New-ADUser is intended.
        'PSAvoidUsingConvertToSecureStringWithPlainText'
    )
    Rules        = @{
        PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @('5.1', '7.4') }
    }
}
