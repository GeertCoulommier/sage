#Requires -Version 7.5

<#
.SYNOPSIS
    Writes themed text to the console, using Spectre markup or ConsoleColor fallback.
.DESCRIPTION
    When $script:UseSpectre is true and Color is a Spectre colour string, renders
    using AnsiConsole.Markup / AnsiConsole.MarkupLine so that all 256-colour Spectre
    palette names (e.g. 'springgreen3', 'grey85') are displayed accurately.

    When Spectre is unavailable or the colour value is already a System.ConsoleColor,
    falls back to the 16-colour ConsoleColor path via Write-Host / Console.Write.

    Markup-special characters '[' and ']' in the text are automatically escaped.
.PARAMETER Text
    The text to write.
.PARAMETER Color
    A Spectre colour string (e.g. 'springgreen3', 'black on gold1') or a
    System.ConsoleColor value.
.PARAMETER NoNewline
    Write without a trailing newline.  In non-Spectre mode this uses
    [System.Console]::Write instead of Write-Host.
.OUTPUTS
    [void]
.EXAMPLE
    Write-SageColor -Color 'springgreen3' -Text 'PASS'
.EXAMPLE
    Write-SageColor -Color ([System.ConsoleColor]::Green) -Text 'PASS' -NoNewline
#>
function Write-SageColor {
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'TUI rendering requires Write-Host to write directly to the host.')]
    param(
        [Parameter(Mandatory)][AllowEmptyString()]                                         [string] $Text,
        [Parameter(Mandatory)]                                                             [object] $Color,
        [Parameter()]                                                                      [switch] $NoNewline
    )

    $ErrorActionPreference = 'Stop'

    if ($script:UseSpectre -and ($Color -is [string]) -and (-not [string]::IsNullOrEmpty($Color))) {
        # Spectre markup: escape [ and ] in text content, wrap in colour tag
        $Safe = $Text -replace '\[', '[[' -replace '\]', ']]'
        $Markup = "[$Color]$Safe[/]"
        if ($NoNewline) {
            [Spectre.Console.AnsiConsole]::Markup($Markup)
        }
        else {
            [Spectre.Console.AnsiConsole]::MarkupLine($Markup)
        }
    }
    else {
        $CC = if ($Color -is [System.ConsoleColor] -and [int]$Color -ge 0) {
            $Color
        }
        elseif ($Color -is [string]) {
            ConvertTo-FallbackConsoleColor -SpectreColor $Color
        }
        else {
            [System.ConsoleColor]::White
        }

        if ($NoNewline) {
            Write-Host $Text -ForegroundColor $CC -NoNewline
        }
        else {
            Write-Host $Text -ForegroundColor $CC
        }
    }
}

<#
.SYNOPSIS
    Converts a Spectre colour name to the nearest System.ConsoleColor fallback.
.DESCRIPTION
    Used by Write-SageColor when PwshSpectreConsole is not available.
    For 'X on Y' accent colour strings the background colour (Y) is used as the
    display colour so the text is still visually distinct.
.PARAMETER SpectreColor
    The Spectre colour string, e.g. 'springgreen3' or 'black on springgreen3'.
.OUTPUTS
    [System.ConsoleColor]
.EXAMPLE
    ConvertTo-FallbackConsoleColor -SpectreColor 'springgreen3'
.EXAMPLE
    ConvertTo-FallbackConsoleColor -SpectreColor 'black on gold1'
#>
function ConvertTo-FallbackConsoleColor {
    [CmdletBinding()]
    [OutputType([System.ConsoleColor])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()]                                         [string] $SpectreColor
    )

    # For 'X on Y' accent colours, extract the background colour for display
    $ColorName = $SpectreColor.ToLower()
    if ($ColorName -match ' on (.+)$') {
        $ColorName = $Matches[1].Trim()
    }

    switch -Regex ($ColorName) {
        '^grey(9[0-9]|100)|^white$|^silver$' { return [System.ConsoleColor]::White }
        '^grey[6-8][0-9]' { return [System.ConsoleColor]::Gray }
        '^grey[0-5][0-9]|^dimgray$' { return [System.ConsoleColor]::DarkGray }
        'springgreen|palegreen|darkseagreen|mediumspringgreen|aquamarine' { return [System.ConsoleColor]::Green }
        '^green[13]' { return [System.ConsoleColor]::Green }
        '^darkgreen$' { return [System.ConsoleColor]::DarkGreen }
        '^green' { return [System.ConsoleColor]::Green }
        '^cyan|^turquoise|^aqua' { return [System.ConsoleColor]::Cyan }
        '^darkcyan$|^teal$' { return [System.ConsoleColor]::DarkCyan }
        'skyblue|steelblue|cadetblue|dodgerblue|deepskyblue|lightsky|lightsteel' { return [System.ConsoleColor]::Cyan }
        '^darkblue$|^navy$' { return [System.ConsoleColor]::DarkBlue }
        '^blue' { return [System.ConsoleColor]::Blue }
        'deeppink|hotpink|lightpink|salmon|lightsalmon|indianred' { return [System.ConsoleColor]::Red }
        '^darkred$|^crimson$|^firebrick$' { return [System.ConsoleColor]::DarkRed }
        '^red' { return [System.ConsoleColor]::Red }
        '^magenta$|^fuchsia$' { return [System.ConsoleColor]::Magenta }
        'orchid|plum|mediumpurple|mediumorchid|violet|purple|darkviolet|darkmagenta|blueviolet|mediumslate' {
            return [System.ConsoleColor]::Magenta
        }
        '^gold|^yellow|^khaki|lightyellow|lemon' { return [System.ConsoleColor]::Yellow }
        '^orange|^tan$|^wheat|navajowhite|sandybrown|goldenrod|darkgoldenrod|peru|darkorange' {
            return [System.ConsoleColor]::DarkYellow
        }
        '^black$' { return [System.ConsoleColor]::Black }
        default { return [System.ConsoleColor]::White }
    }
}

<#
.SYNOPSIS
    Resolves a theme colour value to a System.ConsoleColor.
.DESCRIPTION
    Converts a Spectre colour string or System.ConsoleColor value to a safe
    System.ConsoleColor for use with [System.Console]::ForegroundColor.
    Used by TUI screens that render with the direct Console API.
.PARAMETER Color
    A Spectre colour string or System.ConsoleColor value.
.OUTPUTS
    [System.ConsoleColor]
.EXAMPLE
    [System.Console]::ForegroundColor = Resolve-ThemeColor $Theme.Primary
#>
function Resolve-ThemeColor {
    [CmdletBinding()]
    [OutputType([System.ConsoleColor])]
    param(
        [Parameter(Mandatory)]                                                             [object] $Color
    )

    if ($Color -is [System.ConsoleColor]) { return $Color }
    return ConvertTo-FallbackConsoleColor -SpectreColor "$Color"
}
