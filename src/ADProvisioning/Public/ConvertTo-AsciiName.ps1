function ConvertTo-AsciiName {
    <#
    .SYNOPSIS
        Turns a person's name into a lowercase ASCII string usable in account names.
    .EXAMPLE
        ConvertTo-AsciiName 'Mueller'   # mueller (umlauts become ae/oe/ue)
    .EXAMPLE
        ConvertTo-AsciiName 'Francois'  # accents are removed
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string] $Name
    )
    process {
        # Lowercase first, then German umlauts get the conventional two-letter spelling.
        # (A hashtable would not work here: its keys are case-insensitive, so 'a-umlaut' and
        # 'A-umlaut' collide.) Code points instead of literals, because Windows PowerShell 5.1
        # reads BOM-less files as ANSI and would silently break literal umlauts.
        $text = $Name.Trim().ToLowerInvariant()
        $text = $text.Replace([string][char]0x00E4, 'ae').Replace([string][char]0x00F6, 'oe')
        $text = $text.Replace([string][char]0x00FC, 'ue').Replace([string][char]0x00DF, 'ss')

        # Accented letters (e.g. e-acute, c-cedilla): decompose and drop the combining marks.
        $decomposed = $text.Normalize([Text.NormalizationForm]::FormD)
        $sb = [Text.StringBuilder]::new()
        foreach ($ch in $decomposed.ToCharArray()) {
            if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
                [void] $sb.Append($ch)
            }
        }
        $ascii = $sb.ToString().ToLowerInvariant()
        $ascii = $ascii -replace '\s+', '-' -replace "[^a-z0-9-]", '' -replace '-{2,}', '-'
        $ascii.Trim('-')
    }
}
