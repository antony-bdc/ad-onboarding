function Test-UserRecord {
    <#
    .SYNOPSIS
        Validates one CSV row before anything is changed in AD. Outputs one string per problem (no output = valid).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [psobject] $Record,
        [Parameter(Mandatory)] [hashtable] $Config
    )
    $problems = [Collections.Generic.List[string]]::new()
    foreach ($field in 'EmployeeId', 'GivenName', 'Surname', 'Department') {
        $value = $Record.PSObject.Properties[$field]
        if (-not $value -or [string]::IsNullOrWhiteSpace([string]$value.Value)) {
            $problems.Add("missing $field")
        }
    }
    if ($problems.Count) { foreach ($p in $problems) { $p }; return }

    if ($Record.EmployeeId -notmatch '^\d{4,10}$') {
        $problems.Add("EmployeeId '$($Record.EmployeeId)' must be 4-10 digits")
    }
    if (-not $Config.Departments.ContainsKey($Record.Department)) {
        $problems.Add("unknown department '$($Record.Department)' (known: $($Config.Departments.Keys -join ', '))")
    }
    $manager = $Record.PSObject.Properties['Manager']
    if ($manager -and $manager.Value -and $manager.Value -notmatch '^[a-z0-9.-]{1,20}$') {
        $problems.Add("Manager must be a sAMAccountName, got '$($manager.Value)'")
    }
    $start = $Record.PSObject.Properties['StartDate']
    if ($start -and $start.Value) {
        [datetime] $parsed = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($start.Value, 'yyyy-MM-dd', $null, 'None', [ref] $parsed)) {
            $problems.Add("StartDate '$($start.Value)' must be yyyy-MM-dd")
        }
    }
    foreach ($p in $problems) { $p }
}
