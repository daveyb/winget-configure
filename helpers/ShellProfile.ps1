# PowerShell 7 profile, Terminal-Icons, Departure Mono, and Windows Terminal.
#
# winget configure can run this file under Windows PowerShell 5.1. $PROFILE
# and Install-Module in that host are not the PowerShell 7 paths, so a 5.1
# host relaunches this file with pwsh. Terminal-Icons is installed into the
# PowerShell 7 CurrentUser module path for the same reason.
#
# Fonts are registered for the current user. An elevated DSC securityContext
# makes every WinGetPackage fail with "The file name is too long."
#
# Terminal-Icons is installed for the current user from PSGallery. Trust is
# raised only for that Install-Module call, then the previous
# InstallationPolicy is restored. It does not leave PSGallery Trusted.
# Uninstall-Module -Name Terminal-Icons -Scope CurrentUser removes it.
#
# profiles.defaults.font does not replace a font set on a profile. Those
# per-profile font keys are removed so the default face applies to every
# profile. defaultProfile is the profile a new tab opens. List order is the
# dropdown order. PowerShell has to be first in both. Comments already in
# settings.json are kept.

$ErrorActionPreference = 'Stop'

# winget configure runs this text as a script block under StrictMode.
# ScriptInfo has no Path property, so that member is read only when it exists.
# A 5.1 script block also has no PSCommandPath. Test, Set, and Get write this
# text to a temp file and relaunch that file with pwsh.
$script:ShellProfileFile = $null
$script:ShellProfileDefinition = $null
$script:ShellProfileRelaunchTemp = $null
$commandInfo = $MyInvocation.MyCommand
if ($null -ne $commandInfo)
{
    $pathProperty = $commandInfo.PSObject.Properties['Path']
    if ($null -ne $pathProperty -and -not [string]::IsNullOrWhiteSpace([string]$pathProperty.Value))
    {
        $script:ShellProfileFile = [string]$pathProperty.Value
    }

    $definitionProperty = $commandInfo.PSObject.Properties['Definition']
    if ($null -ne $definitionProperty)
    {
        $definitionText = [string]$definitionProperty.Value
        if ($definitionText -match 'function Invoke-ShellProfileOnPwsh')
        {
            $script:ShellProfileDefinition = $definitionText
        }
    }

    # Some script-block hosts expose the text on ScriptBlock rather than
    # Definition. Either one is enough to write a file and relaunch.
    if ([string]::IsNullOrWhiteSpace($script:ShellProfileDefinition))
    {
        $scriptBlockProperty = $commandInfo.PSObject.Properties['ScriptBlock']
        if ($null -ne $scriptBlockProperty -and $null -ne $scriptBlockProperty.Value)
        {
            $scriptBlockText = $scriptBlockProperty.Value.ToString()
            if ($scriptBlockText -match 'function Invoke-ShellProfileOnPwsh')
            {
                $script:ShellProfileDefinition = $scriptBlockText
            }
        }
    }
}
if ([string]::IsNullOrWhiteSpace($script:ShellProfileFile) -and -not [string]::IsNullOrWhiteSpace($PSCommandPath))
{
    $script:ShellProfileFile = $PSCommandPath
}
if (-not [string]::IsNullOrWhiteSpace($script:ShellProfileFile))
{
    $libraryIsFile = (Test-Path -LiteralPath $script:ShellProfileFile -PathType Leaf)
    $libraryText = ''
    if ($libraryIsFile)
    {
        $libraryText = [System.IO.File]::ReadAllText($script:ShellProfileFile)
    }
    if (-not $libraryIsFile -or $libraryText -notmatch 'function Invoke-ShellProfileOnPwsh')
    {
        $script:ShellProfileFile = $null
    }
}

if (($PSVersionTable.PSVersion.Major -lt 7) -and
    ($MyInvocation.InvocationName -ne '.') -and
    -not [string]::IsNullOrWhiteSpace($script:ShellProfileFile))
{
    $pwshCmd = Get-Command -Name pwsh -ErrorAction Stop
    $output = & $pwshCmd.Source -NoProfile -NonInteractive -File $script:ShellProfileFile
    $code = $LASTEXITCODE
    if ($code -ne 0)
    {
        exit $code
    }

    if ($null -eq $output)
    {
        return
    }

    $lines = @($output | Where-Object { $null -ne $_ -and "$_" -ne '' })
    if ($lines.Count -eq 0)
    {
        return
    }
    if ($lines.Count -eq 1 -and "$($lines[0])" -eq 'True')
    {
        return $true
    }
    if ($lines.Count -eq 1 -and "$($lines[0])" -eq 'False')
    {
        return $false
    }

    return $lines
}

$script:DefaultFontFace = 'DepartureMono Nerd Font'
$script:FontZipUri = 'https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/DepartureMono.zip'
$script:PowerShellProfileGuid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
$script:PowerShellProfileSource = 'Windows.Terminal.PowershellCore'
$script:DepartureMonoFonts = @(
    @{ File = 'DepartureMonoNerdFont-Regular.otf'; Family = 'DepartureMono Nerd Font' }
    @{ File = 'DepartureMonoNerdFontMono-Regular.otf'; Family = 'DepartureMono Nerd Font Mono' }
    @{ File = 'DepartureMonoNerdFontPropo-Regular.otf'; Family = 'DepartureMono Nerd Font Propo' }
)

function Get-ShellProfileText
{
    [CmdletBinding()]
    param()

    $lines = @(
        'oh-my-posh --init --shell pwsh --config https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/refs/heads/main/themes/marcduiker.omp.json | Invoke-Expression'
        ''
        '# Install-Module -Name Terminal-Icons -Repository PSGallery'
        'Import-Module -Name Terminal-Icons'
    )
    return (($lines -join "`n") + "`n")
}

function ConvertTo-NormalizedProfileText
{
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrEmpty($Text))
    {
        return "`n"
    }

    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    return ($normalized.TrimEnd("`n") + "`n")
}

function Get-UserFontRegistryValueName
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Family,
        [Parameter(Mandatory)][string]$FileName
    )

    $extension = [System.IO.Path]::GetExtension($FileName).ToLowerInvariant()
    $kind = if ($extension -eq '.otf') { 'OpenType' } else { 'TrueType' }
    return ('{0} ({1})' -f $Family, $kind)
}

function Test-IsWindowsPowerShellProfile
{
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Name,
        [AllowEmptyString()][string]$CommandLine
    )

    if ($Name -eq 'Windows PowerShell')
    {
        return $true
    }
    if ($CommandLine -match '(?i)WindowsPowerShell\\v1\.0\\powershell\.exe')
    {
        return $true
    }

    return $false
}

function Get-PowerShellProfileRank
{
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Name,
        [AllowEmptyString()][string]$CommandLine,
        [AllowEmptyString()][string]$Source
    )

    if (Test-IsWindowsPowerShellProfile -Name $Name -CommandLine $CommandLine)
    {
        return -1
    }

    $commandIsPwsh = $CommandLine -match '(?i)(^|[\\/\s])pwsh\.exe(\s|$)'
    $sourceIsCore = $Source -eq $script:PowerShellProfileSource
    $nameIsPowerShell = $Name -eq 'PowerShell'
    if (-not ($nameIsPowerShell -or $sourceIsCore -or $commandIsPwsh))
    {
        return -1
    }
    if ($nameIsPowerShell -and $sourceIsCore)
    {
        return 0
    }
    if ($nameIsPowerShell)
    {
        return 1
    }
    if ($sourceIsCore)
    {
        return 2
    }

    return 3
}

function Get-JsonObjectString
{
    [CmdletBinding()]
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object)
    {
        return ''
    }

    $jsonObject = $Object.AsObject()
    if (-not $jsonObject.ContainsKey($Name))
    {
        return ''
    }

    $value = $jsonObject[$Name]
    if ($null -eq $value)
    {
        return ''
    }

    # JsonNode.ToString() is JSON text. A string field comes back quoted, so
    # "PowerShell" does not match the profile name and a second profile is inserted.
    try
    {
        return [string]$value.GetValue[string]()
    }
    catch
    {
        return ''
    }
}

function Remove-JsonObjectKey
{
    [CmdletBinding()]
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name
    )

    $jsonObject = $Object.AsObject()
    if ($jsonObject.ContainsKey($Name))
    {
        [void]$jsonObject.Remove($Name)
    }
}

function New-JsoncReader
{
    param([string]$Text)

    $normalized = $Text
    if ($normalized.Length -gt 0 -and [int]$normalized[0] -eq 0xFEFF)
    {
        $normalized = $normalized.Substring(1)
    }

    return @{
        Text    = $normalized
        Index   = 0
        Length  = $normalized.Length
        Pending = New-Object System.Collections.Generic.List[string]
    }
}

function Test-JsoncEnd
{
    param($Reader)
    return ($Reader.Index -ge $Reader.Length)
}

function Peek-JsoncChar
{
    param($Reader)
    if (Test-JsoncEnd $Reader)
    {
        return $null
    }

    return $Reader.Text[$Reader.Index]
}

function Read-JsoncChar
{
    param($Reader)
    if (Test-JsoncEnd $Reader)
    {
        throw 'Unexpected end of Windows Terminal settings JSON.'
    }

    $char = $Reader.Text[$Reader.Index]
    $Reader.Index++
    return $char
}

function Add-JsoncPendingComment
{
    param($Reader, [string]$Comment)
    $Reader.Pending.Add($Comment)
}

function Skip-JsoncTrivia
{
    param($Reader)
    while (-not (Test-JsoncEnd $Reader))
    {
        $char = Peek-JsoncChar $Reader
        if ($char -eq ' ' -or $char -eq "`t" -or $char -eq "`r" -or $char -eq "`n")
        {
            [void](Read-JsoncChar $Reader)
            continue
        }

        if ($char -ne '/')
        {
            break
        }

        $nextIndex = $Reader.Index + 1
        if ($nextIndex -ge $Reader.Length)
        {
            break
        }

        $next = $Reader.Text[$nextIndex]
        if ($next -eq '/')
        {
            [void](Read-JsoncChar $Reader)
            [void](Read-JsoncChar $Reader)
            $start = $Reader.Index
            while (-not (Test-JsoncEnd $Reader))
            {
                $lineChar = Peek-JsoncChar $Reader
                if ($lineChar -eq "`n" -or $lineChar -eq "`r")
                {
                    break
                }

                [void](Read-JsoncChar $Reader)
            }

            Add-JsoncPendingComment $Reader ('//' + $Reader.Text.Substring($start, $Reader.Index - $start))
            continue
        }

        if ($next -eq '*')
        {
            [void](Read-JsoncChar $Reader)
            [void](Read-JsoncChar $Reader)
            $start = $Reader.Index
            $closed = $false
            while (-not (Test-JsoncEnd $Reader))
            {
                if ((Peek-JsoncChar $Reader) -eq '*' -and ($Reader.Index + 1) -lt $Reader.Length -and $Reader.Text[$Reader.Index + 1] -eq '/')
                {
                    $body = $Reader.Text.Substring($start, $Reader.Index - $start)
                    [void](Read-JsoncChar $Reader)
                    [void](Read-JsoncChar $Reader)
                    Add-JsoncPendingComment $Reader ('/*' + $body + '*/')
                    $closed = $true
                    break
                }

                [void](Read-JsoncChar $Reader)
            }

            if (-not $closed)
            {
                throw 'Unclosed block comment in Windows Terminal settings JSON.'
            }

            continue
        }

        break
    }
}

function Take-JsoncComments
{
    param($Reader)
    $copy = New-Object System.Collections.Generic.List[string]
    foreach ($item in $Reader.Pending)
    {
        $copy.Add([string]$item)
    }

    $Reader.Pending.Clear()
    return ,$copy
}

function Read-JsoncLiteral
{
    param($Reader, [string]$Literal)
    for ($index = 0; $index -lt $Literal.Length; $index++)
    {
        $char = Read-JsoncChar $Reader
        if ($char -ne $Literal[$index])
        {
            throw 'Invalid literal in Windows Terminal settings JSON.'
        }
    }
}

function Read-JsoncString
{
    param($Reader)
    if ((Read-JsoncChar $Reader) -ne '"')
    {
        throw 'Expected a string in Windows Terminal settings JSON.'
    }

    $builder = New-Object System.Text.StringBuilder
    while ($true)
    {
        $char = Read-JsoncChar $Reader
        if ($char -eq '"')
        {
            break
        }

        if ($char -eq '\')
        {
            $escape = Read-JsoncChar $Reader
            if ($escape -eq '"') { [void]$builder.Append('"'); continue }
            if ($escape -eq '\') { [void]$builder.Append('\'); continue }
            if ($escape -eq '/') { [void]$builder.Append('/'); continue }
            if ($escape -eq 'b') { [void]$builder.Append([char]8); continue }
            if ($escape -eq 'f') { [void]$builder.Append([char]12); continue }
            if ($escape -eq 'n') { [void]$builder.Append("`n"); continue }
            if ($escape -eq 'r') { [void]$builder.Append("`r"); continue }
            if ($escape -eq 't') { [void]$builder.Append("`t"); continue }
            if ($escape -eq 'u')
            {
                $hex = ''
                for ($index = 0; $index -lt 4; $index++)
                {
                    $hex += Read-JsoncChar $Reader
                }

                [void]$builder.Append([char][Convert]::ToInt32($hex, 16))
                continue
            }

            throw 'Invalid escape in Windows Terminal settings JSON.'
        }

        if ([int]$char -lt 0x20)
        {
            throw 'Unescaped control character in Windows Terminal settings JSON.'
        }

        [void]$builder.Append($char)
    }

    return $builder.ToString()
}

function Read-JsoncNumber
{
    param($Reader)
    $start = $Reader.Index
    if ((Peek-JsoncChar $Reader) -eq '-')
    {
        [void](Read-JsoncChar $Reader)
    }

    $digit = Peek-JsoncChar $Reader
    if ($digit -eq '0')
    {
        [void](Read-JsoncChar $Reader)
    }
    elseif ($null -ne $digit -and $digit -match '[1-9]')
    {
        while ($null -ne (Peek-JsoncChar $Reader) -and (Peek-JsoncChar $Reader) -match '[0-9]')
        {
            [void](Read-JsoncChar $Reader)
        }
    }
    else
    {
        throw 'Invalid number in Windows Terminal settings JSON.'
    }

    if ((Peek-JsoncChar $Reader) -eq '.')
    {
        [void](Read-JsoncChar $Reader)
        if ($null -eq (Peek-JsoncChar $Reader) -or (Peek-JsoncChar $Reader) -notmatch '[0-9]')
        {
            throw 'Invalid number in Windows Terminal settings JSON.'
        }

        while ($null -ne (Peek-JsoncChar $Reader) -and (Peek-JsoncChar $Reader) -match '[0-9]')
        {
            [void](Read-JsoncChar $Reader)
        }
    }

    $exponent = Peek-JsoncChar $Reader
    if ($exponent -eq 'e' -or $exponent -eq 'E')
    {
        [void](Read-JsoncChar $Reader)
        $sign = Peek-JsoncChar $Reader
        if ($sign -eq '+' -or $sign -eq '-')
        {
            [void](Read-JsoncChar $Reader)
        }

        if ($null -eq (Peek-JsoncChar $Reader) -or (Peek-JsoncChar $Reader) -notmatch '[0-9]')
        {
            throw 'Invalid number in Windows Terminal settings JSON.'
        }

        while ($null -ne (Peek-JsoncChar $Reader) -and (Peek-JsoncChar $Reader) -match '[0-9]')
        {
            [void](Read-JsoncChar $Reader)
        }
    }

    return $Reader.Text.Substring($start, $Reader.Index - $start)
}

function Read-JsoncObject
{
    param($Reader)
    if ((Read-JsoncChar $Reader) -ne '{')
    {
        throw 'Expected an object in Windows Terminal settings JSON.'
    }

    $properties = New-Object System.Collections.Generic.List[object]
    $expectComma = $false
    while ($true)
    {
        Skip-JsoncTrivia $Reader
        $char = Peek-JsoncChar $Reader
        if ($char -eq '}')
        {
            [void](Read-JsoncChar $Reader)
            break
        }

        if ($expectComma)
        {
            throw 'Expected a comma or end of object in Windows Terminal settings JSON.'
        }

        if ($char -ne '"')
        {
            throw 'Expected a property name in Windows Terminal settings JSON.'
        }

        $comments = Take-JsoncComments $Reader
        $name = Read-JsoncString $Reader
        Skip-JsoncTrivia $Reader
        if ((Read-JsoncChar $Reader) -ne ':')
        {
            throw 'Expected a colon in Windows Terminal settings JSON.'
        }

        $value = Read-JsoncValue $Reader
        $properties.Add(@{
                Name     = $name
                Comments = $comments
                Value    = $value
            })
        Skip-JsoncTrivia $Reader
        if ((Peek-JsoncChar $Reader) -eq ',')
        {
            [void](Read-JsoncChar $Reader)
            $expectComma = $false
        }
        else
        {
            $expectComma = $true
        }
    }

    return @{
        Kind             = 'object'
        Properties       = $properties
        Comments         = (New-Object System.Collections.Generic.List[string])
        TrailingComments = (Take-JsoncComments $Reader)
        AfterComments    = (New-Object System.Collections.Generic.List[string])
    }
}

function Read-JsoncArray
{
    param($Reader)
    if ((Read-JsoncChar $Reader) -ne '[')
    {
        throw 'Expected an array in Windows Terminal settings JSON.'
    }

    $items = New-Object System.Collections.Generic.List[object]
    $expectComma = $false
    while ($true)
    {
        Skip-JsoncTrivia $Reader
        $char = Peek-JsoncChar $Reader
        if ($char -eq ']')
        {
            [void](Read-JsoncChar $Reader)
            break
        }

        if ($expectComma)
        {
            throw 'Expected a comma or end of array in Windows Terminal settings JSON.'
        }

        $items.Add((Read-JsoncValue $Reader))
        Skip-JsoncTrivia $Reader
        if ((Peek-JsoncChar $Reader) -eq ',')
        {
            [void](Read-JsoncChar $Reader)
            $expectComma = $false
        }
        else
        {
            $expectComma = $true
        }
    }

    return @{
        Kind             = 'array'
        Items            = $items
        Comments         = (New-Object System.Collections.Generic.List[string])
        TrailingComments = (Take-JsoncComments $Reader)
        AfterComments    = (New-Object System.Collections.Generic.List[string])
    }
}

function Read-JsoncValue
{
    param($Reader)
    Skip-JsoncTrivia $Reader
    $comments = Take-JsoncComments $Reader
    if (Test-JsoncEnd $Reader)
    {
        throw 'Unexpected end of Windows Terminal settings JSON.'
    }

    $char = Peek-JsoncChar $Reader
    $node = $null
    if ($char -eq '{')
    {
        $node = Read-JsoncObject $Reader
    }
    elseif ($char -eq '[')
    {
        $node = Read-JsoncArray $Reader
    }
    elseif ($char -eq '"')
    {
        $node = @{
            Kind             = 'string'
            Value            = (Read-JsoncString $Reader)
            Comments         = (New-Object System.Collections.Generic.List[string])
            TrailingComments = (New-Object System.Collections.Generic.List[string])
            AfterComments    = (New-Object System.Collections.Generic.List[string])
        }
    }
    elseif ($char -eq 't')
    {
        Read-JsoncLiteral $Reader 'true'
        $node = @{
            Kind             = 'bool'
            Value            = $true
            Comments         = (New-Object System.Collections.Generic.List[string])
            TrailingComments = (New-Object System.Collections.Generic.List[string])
            AfterComments    = (New-Object System.Collections.Generic.List[string])
        }
    }
    elseif ($char -eq 'f')
    {
        Read-JsoncLiteral $Reader 'false'
        $node = @{
            Kind             = 'bool'
            Value            = $false
            Comments         = (New-Object System.Collections.Generic.List[string])
            TrailingComments = (New-Object System.Collections.Generic.List[string])
            AfterComments    = (New-Object System.Collections.Generic.List[string])
        }
    }
    elseif ($char -eq 'n')
    {
        Read-JsoncLiteral $Reader 'null'
        $node = @{
            Kind             = 'null'
            Value            = $null
            Comments         = (New-Object System.Collections.Generic.List[string])
            TrailingComments = (New-Object System.Collections.Generic.List[string])
            AfterComments    = (New-Object System.Collections.Generic.List[string])
        }
    }
    elseif ($char -eq '-' -or ($null -ne $char -and $char -match '[0-9]'))
    {
        $node = @{
            Kind             = 'number'
            Value            = (Read-JsoncNumber $Reader)
            Comments         = (New-Object System.Collections.Generic.List[string])
            TrailingComments = (New-Object System.Collections.Generic.List[string])
            AfterComments    = (New-Object System.Collections.Generic.List[string])
        }
    }
    else
    {
        throw 'Unexpected token in Windows Terminal settings JSON.'
    }

    $node.Comments = $comments
    return $node
}

function ConvertFrom-JsoncDocument
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $reader = New-JsoncReader $Text
    $node = Read-JsoncValue $reader
    Skip-JsoncTrivia $reader
    $after = Take-JsoncComments $reader
    if (-not (Test-JsoncEnd $reader))
    {
        throw 'Unexpected trailing text in Windows Terminal settings JSON.'
    }

    $node.AfterComments = $after
    return $node
}

function Write-JsoncString
{
    param([AllowEmptyString()][string]$Value)
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    foreach ($char in $Value.ToCharArray())
    {
        $code = [int]$char
        if ($char -eq '"') { [void]$builder.Append('\"'); continue }
        if ($char -eq '\') { [void]$builder.Append('\\'); continue }
        if ($char -eq "`b") { [void]$builder.Append('\b'); continue }
        if ($char -eq "`f") { [void]$builder.Append('\f'); continue }
        if ($char -eq "`n") { [void]$builder.Append('\n'); continue }
        if ($char -eq "`r") { [void]$builder.Append('\r'); continue }
        if ($char -eq "`t") { [void]$builder.Append('\t'); continue }
        if ($code -lt 0x20)
        {
            [void]$builder.Append('\u')
            [void]$builder.Append($code.ToString('x4'))
            continue
        }

        [void]$builder.Append($char)
    }

    [void]$builder.Append('"')
    return $builder.ToString()
}

function Add-JsoncCommentLine
{
    param($Lines, $Comment, [int]$Indent)
    $text = [string]$Comment
    if ([string]::IsNullOrWhiteSpace($text))
    {
        return
    }

    $flat = (($text -replace "`r`n", "`n" -replace "`r", "`n") -replace "`n", ' ').Trim()
    $Lines.Add((' ' * $Indent) + $flat)
}

function Format-JsoncScalar
{
    param($Node)
    if ($Node.Kind -eq 'string')
    {
        return (Write-JsoncString -Value ([string]$Node.Value))
    }

    if ($Node.Kind -eq 'bool')
    {
        if ($Node.Value) { return 'true' }
        return 'false'
    }

    if ($Node.Kind -eq 'null')
    {
        return 'null'
    }

    if ($Node.Kind -eq 'number')
    {
        return [string]$Node.Value
    }

    throw 'Windows Terminal settings contain a value that is not JSON.'
}

function Write-JsoncChildren
{
    param($Node, $Lines, [int]$Indent)

    if ($Node.Kind -eq 'object')
    {
        $index = 0
        $count = $Node.Properties.Count
        foreach ($property in $Node.Properties)
        {
            $index++
            Write-JsoncProperty -Property $property -Lines $Lines -Indent $Indent -Comma:($index -lt $count)
        }
    }
    else
    {
        $index = 0
        $count = $Node.Items.Count
        foreach ($item in $Node.Items)
        {
            $index++
            Write-JsoncNode -Node $item -Lines $Lines -Indent $Indent -Comma:($index -lt $count)
        }
    }

    foreach ($comment in $Node.TrailingComments)
    {
        Add-JsoncCommentLine -Lines $Lines -Comment $comment -Indent $Indent
    }
}

function Write-JsoncNode
{
    param($Node, $Lines, [int]$Indent, [switch]$Comma)

    foreach ($comment in $Node.Comments)
    {
        Add-JsoncCommentLine -Lines $Lines -Comment $comment -Indent $Indent
    }

    $pad = ' ' * $Indent
    $suffix = ''
    if ($Comma)
    {
        $suffix = ','
    }

    if ($Node.Kind -eq 'object' -or $Node.Kind -eq 'array')
    {
        $open = '{'
        $close = '}'
        $count = 0
        if ($Node.Kind -eq 'array')
        {
            $open = '['
            $close = ']'
            $count = $Node.Items.Count
        }
        else
        {
            $count = $Node.Properties.Count
        }

        if ($count -eq 0 -and $Node.TrailingComments.Count -eq 0)
        {
            $Lines.Add($pad + $open + $close + $suffix)
            return
        }

        $Lines.Add($pad + $open)
        Write-JsoncChildren -Node $Node -Lines $Lines -Indent ($Indent + 4)
        $Lines.Add($pad + $close + $suffix)
        return
    }

    $Lines.Add($pad + (Format-JsoncScalar $Node) + $suffix)
}

function Write-JsoncProperty
{
    param($Property, $Lines, [int]$Indent, [switch]$Comma)

    foreach ($comment in $Property.Comments)
    {
        Add-JsoncCommentLine -Lines $Lines -Comment $comment -Indent $Indent
    }

    $value = $Property.Value
    $pad = ' ' * $Indent
    $name = Write-JsoncString -Value ([string]$Property.Name)
    $suffix = ''
    if ($Comma)
    {
        $suffix = ','
    }

    $valueHasComments = $value.Comments.Count -gt 0
    if ($valueHasComments -or $value.Kind -eq 'object' -or $value.Kind -eq 'array')
    {
        if (-not $valueHasComments -and ($value.Kind -eq 'object' -or $value.Kind -eq 'array'))
        {
            $open = '{'
            $close = '}'
            $count = $value.Properties.Count
            if ($value.Kind -eq 'array')
            {
                $open = '['
                $close = ']'
                $count = $value.Items.Count
            }

            if ($count -eq 0 -and $value.TrailingComments.Count -eq 0)
            {
                $Lines.Add($pad + $name + ': ' + $open + $close + $suffix)
                return
            }

            $Lines.Add($pad + $name + ': ' + $open)
            Write-JsoncChildren -Node $value -Lines $Lines -Indent ($Indent + 4)
            $Lines.Add($pad + $close + $suffix)
            return
        }

        $Lines.Add($pad + $name + ':')
        Write-JsoncNode -Node $value -Lines $Lines -Indent ($Indent + 4) -Comma:$Comma
        return
    }

    $Lines.Add($pad + $name + ': ' + (Format-JsoncScalar $value) + $suffix)
}

function Write-JsoncDocument
{
    [CmdletBinding()]
    param($Node)

    $lines = New-Object System.Collections.Generic.List[string]
    Write-JsoncNode -Node $Node -Lines $lines -Indent 0
    foreach ($comment in $Node.AfterComments)
    {
        Add-JsoncCommentLine -Lines $lines -Comment $comment -Indent 0
    }

    $text = [string]::Join("`r`n", $lines.ToArray())
    if (-not $text.EndsWith("`r`n"))
    {
        $text += "`r`n"
    }

    return $text
}

function New-JsoncCommentList
{
    return (New-Object System.Collections.Generic.List[string])
}

function New-JsoncString
{
    param([AllowEmptyString()][string]$Value)
    return @{
        Kind             = 'string'
        Value            = $Value
        Comments         = (New-JsoncCommentList)
        TrailingComments = (New-JsoncCommentList)
        AfterComments    = (New-JsoncCommentList)
    }
}

function New-JsoncBool
{
    param([bool]$Value)
    return @{
        Kind             = 'bool'
        Value            = $Value
        Comments         = (New-JsoncCommentList)
        TrailingComments = (New-JsoncCommentList)
        AfterComments    = (New-JsoncCommentList)
    }
}

function New-JsoncObject
{
    return @{
        Kind             = 'object'
        Properties       = (New-Object System.Collections.Generic.List[object])
        Comments         = (New-JsoncCommentList)
        TrailingComments = (New-JsoncCommentList)
        AfterComments    = (New-JsoncCommentList)
    }
}

function New-JsoncArray
{
    return @{
        Kind             = 'array'
        Items            = (New-Object System.Collections.Generic.List[object])
        Comments         = (New-JsoncCommentList)
        TrailingComments = (New-JsoncCommentList)
        AfterComments    = (New-JsoncCommentList)
    }
}

function Get-JsoncProperty
{
    param($Object, [string]$Name)
    if ($null -eq $Object -or $Object.Kind -ne 'object')
    {
        return $null
    }

    foreach ($property in $Object.Properties)
    {
        if ($property.Name -eq $Name)
        {
            return $property
        }
    }

    return $null
}

function Get-JsoncPropertyValue
{
    param($Object, [string]$Name)
    $property = Get-JsoncProperty -Object $Object -Name $Name
    if ($null -eq $property)
    {
        return $null
    }

    return $property.Value
}

function Get-JsoncStringValue
{
    param($Node)
    if ($null -eq $Node -or $Node.Kind -ne 'string')
    {
        return ''
    }

    return [string]$Node.Value
}

function Set-JsoncProperty
{
    param($Object, [string]$Name, $ValueNode)
    $property = Get-JsoncProperty -Object $Object -Name $Name
    if ($null -ne $property)
    {
        $property.Value = $ValueNode
        return
    }

    $Object.Properties.Add(@{
            Name     = $Name
            Comments = (New-JsoncCommentList)
            Value    = $ValueNode
        })
}

function Remove-JsoncProperty
{
    param($Object, [string]$Name)
    if ($null -eq $Object -or $Object.Kind -ne 'object')
    {
        return
    }

    $kept = New-Object System.Collections.Generic.List[object]
    foreach ($property in $Object.Properties)
    {
        if ($property.Name -ne $Name)
        {
            $kept.Add($property)
        }
    }

    $Object.Properties = $kept
}

function Convert-TerminalSettingsJson
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Json)

    $root = ConvertFrom-JsoncDocument -Text $Json
    if ($null -eq $root -or $root.Kind -ne 'object')
    {
        throw 'Windows Terminal settings must be a JSON object.'
    }

    $profiles = Get-JsoncPropertyValue -Object $root -Name 'profiles'
    if ($null -eq $profiles -or $profiles.Kind -ne 'object')
    {
        $profiles = New-JsoncObject
        Set-JsoncProperty -Object $root -Name 'profiles' -ValueNode $profiles
    }

    $defaults = Get-JsoncPropertyValue -Object $profiles -Name 'defaults'
    if ($null -eq $defaults -or $defaults.Kind -ne 'object')
    {
        $defaults = New-JsoncObject
        Set-JsoncProperty -Object $profiles -Name 'defaults' -ValueNode $defaults
    }

    Remove-JsoncProperty -Object $defaults -Name 'fontFace'
    $font = Get-JsoncPropertyValue -Object $defaults -Name 'font'
    if ($null -eq $font -or $font.Kind -ne 'object')
    {
        $font = New-JsoncObject
        Set-JsoncProperty -Object $defaults -Name 'font' -ValueNode $font
    }

    Set-JsoncProperty -Object $font -Name 'face' -ValueNode (New-JsoncString $script:DefaultFontFace)

    $list = Get-JsoncPropertyValue -Object $profiles -Name 'list'
    if ($null -eq $list -or $list.Kind -ne 'array')
    {
        $list = New-JsoncArray
        Set-JsoncProperty -Object $profiles -Name 'list' -ValueNode $list
    }

    $bestIndex = -1
    $bestRank = 99
    for ($index = 0; $index -lt $list.Items.Count; $index++)
    {
        $item = $list.Items[$index]
        $name = Get-JsoncStringValue (Get-JsoncPropertyValue -Object $item -Name 'name')
        $commandLine = Get-JsoncStringValue (Get-JsoncPropertyValue -Object $item -Name 'commandline')
        $source = Get-JsoncStringValue (Get-JsoncPropertyValue -Object $item -Name 'source')
        $rank = Get-PowerShellProfileRank -Name $name -CommandLine $commandLine -Source $source
        if ($rank -ge 0 -and $rank -lt $bestRank)
        {
            $bestRank = $rank
            $bestIndex = $index
        }
    }

    if ($bestIndex -lt 0)
    {
        $created = New-JsoncObject
        Set-JsoncProperty -Object $created -Name 'guid' -ValueNode (New-JsoncString $script:PowerShellProfileGuid)
        Set-JsoncProperty -Object $created -Name 'hidden' -ValueNode (New-JsoncBool $false)
        Set-JsoncProperty -Object $created -Name 'name' -ValueNode (New-JsoncString 'PowerShell')
        Set-JsoncProperty -Object $created -Name 'source' -ValueNode (New-JsoncString $script:PowerShellProfileSource)
        $list.Items.Insert(0, $created)
        $chosen = $created
    }
    else
    {
        $chosen = $list.Items[$bestIndex]
        if ($bestIndex -ne 0)
        {
            $list.Items.RemoveAt($bestIndex)
            $list.Items.Insert(0, $chosen)
        }
    }

    $guid = Get-JsoncStringValue (Get-JsoncPropertyValue -Object $chosen -Name 'guid')
    if ([string]::IsNullOrWhiteSpace($guid))
    {
        $guid = $script:PowerShellProfileGuid
        Set-JsoncProperty -Object $chosen -Name 'guid' -ValueNode (New-JsoncString $guid)
    }

    Set-JsoncProperty -Object $chosen -Name 'hidden' -ValueNode (New-JsoncBool $false)
    Set-JsoncProperty -Object $root -Name 'defaultProfile' -ValueNode (New-JsoncString $guid)

    for ($itemIndex = 0; $itemIndex -lt $list.Items.Count; $itemIndex++)
    {
        $item = $list.Items[$itemIndex]
        Remove-JsoncProperty -Object $item -Name 'font'
        Remove-JsoncProperty -Object $item -Name 'fontFace'
    }

    return (Write-JsoncDocument -Node $root)
}

function Test-TerminalSettingsText
{
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Json)

    if ([string]::IsNullOrWhiteSpace($Json))
    {
        return $false
    }

    try
    {
        $updated = Convert-TerminalSettingsJson -Json $Json
        $currentFacts = Get-TerminalSettingsFacts -Json $Json
        $updatedFacts = Get-TerminalSettingsFacts -Json $updated
        return ($currentFacts -eq $updatedFacts)
    }
    catch
    {
        return $false
    }
}

function Get-TerminalSettingsFacts
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Json)

    $documentOptions = [System.Text.Json.JsonDocumentOptions]::new()
    $documentOptions.CommentHandling = [System.Text.Json.JsonCommentHandling]::Skip
    $documentOptions.AllowTrailingCommas = $true
    $nodeOptions = [System.Text.Json.Nodes.JsonNodeOptions]::new()
    $root = [System.Text.Json.Nodes.JsonNode]::Parse($Json, $nodeOptions, $documentOptions).AsObject()
    $profiles = $root['profiles'].AsObject()
    $defaults = $profiles['defaults'].AsObject()
    $face = ''
    if ($defaults.ContainsKey('font') -and $null -ne $defaults['font'])
    {
        $face = Get-JsonObjectString -Object $defaults['font'] -Name 'face'
    }

    $list = $profiles['list'].AsArray()
    $firstName = ''
    $firstGuid = ''
    $firstSource = ''
    $firstCommand = ''
    $firstHidden = ''
    $profileFontCount = 0
    if ($list.Count -gt 0)
    {
        $firstName = Get-JsonObjectString -Object $list[0] -Name 'name'
        $firstGuid = Get-JsonObjectString -Object $list[0] -Name 'guid'
        $firstSource = Get-JsonObjectString -Object $list[0] -Name 'source'
        $firstCommand = Get-JsonObjectString -Object $list[0] -Name 'commandline'
        $firstObject = $list[0].AsObject()
        if ($firstObject.ContainsKey('hidden'))
        {
            $firstHidden = $firstObject['hidden'].ToString().ToLowerInvariant()
        }
        foreach ($item in @($list))
        {
            $itemObject = $item.AsObject()
            if ($itemObject.ContainsKey('font') -or $itemObject.ContainsKey('fontFace'))
            {
                $profileFontCount++
            }
        }
    }

    $defaultProfile = Get-JsonObjectString -Object $root -Name 'defaultProfile'
    $defaultFontFace = ''
    if ($defaults.ContainsKey('fontFace'))
    {
        $defaultFontFace = Get-JsonObjectString -Object $defaults -Name 'fontFace'
    }

    return ('face={0};defaultFontFace={1};first={2};guid={3};source={4};command={5};hidden={6};defaultProfile={7};profileFonts={8}' -f $face, $defaultFontFace, $firstName, $firstGuid, $firstSource, $firstCommand, $firstHidden, $defaultProfile, $profileFontCount)
}

function Get-PwshProfilePath
{
    [CmdletBinding()]
    param()

    $pwshCmd = Get-Command -Name pwsh -ErrorAction SilentlyContinue
    if ($pwshCmd)
    {
        $output = & $pwshCmd.Source -NoProfile -NonInteractive -Command '$PROFILE.CurrentUserCurrentHost'
        if ($LASTEXITCODE -eq 0 -and $output)
        {
            $path = @($output)[-1]
            if ($path)
            {
                return $path.ToString().Trim()
            }
        }
    }

    return (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Microsoft.PowerShell_profile.ps1')
}

function Test-PwshProfileContent
{
    [CmdletBinding()]
    param()

    $path = Get-PwshProfilePath
    if (-not (Test-Path -LiteralPath $path))
    {
        return $false
    }

    $current = [System.IO.File]::ReadAllText($path)
    $desired = Get-ShellProfileText
    return ((ConvertTo-NormalizedProfileText $current) -eq (ConvertTo-NormalizedProfileText $desired))
}

function Set-PwshProfileContent
{
    [CmdletBinding()]
    param()

    $path = Get-PwshProfilePath
    $desired = Get-ShellProfileText
    if (Test-PwshProfileContent)
    {
        return
    }

    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory))
    {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($path, $desired, $encoding)
}

function Test-TerminalIconsInstalled
{
    [CmdletBinding()]
    param()

    $pwshCmd = Get-Command -Name pwsh -ErrorAction SilentlyContinue
    if (-not $pwshCmd)
    {
        return $false
    }

    $output = & $pwshCmd.Source -NoProfile -NonInteractive -Command "if (Get-Module -ListAvailable -Name Terminal-Icons) { 'present' } else { 'missing' }"
    if ($LASTEXITCODE -ne 0)
    {
        return $false
    }

    return ((@($output) -join "`n") -match '(?m)^present$')
}

function Install-TerminalIconsModule
{
    [CmdletBinding()]
    param()

    if (Test-TerminalIconsInstalled)
    {
        return
    }

    $pwshCmd = Get-Command -Name pwsh -ErrorAction SilentlyContinue
    if (-not $pwshCmd)
    {
        throw 'pwsh is not on PATH. Install Microsoft.PowerShell and run this again.'
    }

    $runner = Join-Path ([System.IO.Path]::GetTempPath()) ('Install-TerminalIcons-' + [guid]::NewGuid().ToString('n') + '.ps1')
    $code = @'
$ErrorActionPreference = "Stop"
$ConfirmPreference = "None"
if (Get-Module -ListAvailable -Name Terminal-Icons) { return }
$nuget = @(Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge [version]"2.8.5.201" })
if ($nuget.Count -eq 0) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
}
$repo = Get-PSRepository -Name PSGallery -ErrorAction Stop
$previousPolicy = [string]$repo.InstallationPolicy
$changedPolicy = $false
try {
    if ($previousPolicy -ne "Trusted") {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        $changedPolicy = $true
    }
    Install-Module -Name Terminal-Icons -Repository PSGallery -Scope CurrentUser -Force -AllowClobber
    if (-not (Get-Module -ListAvailable -Name Terminal-Icons)) {
        throw "Terminal-Icons is not installed"
    }
}
finally {
    if ($changedPolicy) {
        Set-PSRepository -Name PSGallery -InstallationPolicy $previousPolicy
    }
}
'@
    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($runner, $code, $encoding)
    try
    {
        & $pwshCmd.Source -NoProfile -NonInteractive -File $runner
        if ($LASTEXITCODE -ne 0)
        {
            throw "Install-Module Terminal-Icons failed with exit $LASTEXITCODE"
        }
    }
    finally
    {
        Remove-Item -LiteralPath $runner -Force -ErrorAction SilentlyContinue
    }
}

function Get-UserFontDirectory
{
    [CmdletBinding()]
    param()

    return (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts')
}

function Test-DepartureMonoFontsInstalled
{
    [CmdletBinding()]
    param()

    $directory = Get-UserFontDirectory
    $registryPath = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    foreach ($font in $script:DepartureMonoFonts)
    {
        $destination = Join-Path $directory $font.File
        if (-not (Test-Path -LiteralPath $destination))
        {
            return $false
        }

        $registryName = Get-UserFontRegistryValueName -Family $font.Family -FileName $font.File
        $current = $null
        if (Test-Path -LiteralPath $registryPath)
        {
            $property = Get-ItemProperty -LiteralPath $registryPath -Name $registryName -ErrorAction SilentlyContinue
            if ($property)
            {
                $current = $property.$registryName
            }
        }
        if ($current -ne $destination)
        {
            return $false
        }
    }

    return $true
}

function Install-UserFontFile
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$Family
    )

    $directory = Get-UserFontDirectory
    if (-not (Test-Path -LiteralPath $directory))
    {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $fileName = [System.IO.Path]::GetFileName($SourcePath)
    $destination = Join-Path $directory $fileName
    $copy = $true
    if (Test-Path -LiteralPath $destination)
    {
        $sourceHash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
        $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        if ($sourceHash -eq $destinationHash)
        {
            $copy = $false
        }
    }
    if ($copy)
    {
        Copy-Item -LiteralPath $SourcePath -Destination $destination -Force
    }

    $registryPath = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    if (-not (Test-Path -LiteralPath $registryPath))
    {
        New-Item -Path $registryPath -Force | Out-Null
    }

    $registryName = Get-UserFontRegistryValueName -Family $Family -FileName $fileName
    $current = $null
    $property = Get-ItemProperty -LiteralPath $registryPath -Name $registryName -ErrorAction SilentlyContinue
    if ($property)
    {
        $current = $property.$registryName
    }
    if ($current -ne $destination)
    {
        New-ItemProperty -LiteralPath $registryPath -Name $registryName -Value $destination -PropertyType String -Force | Out-Null
    }

    return $destination
}

function Add-UserFontResource
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Paths)

    if (-not ('Win32FontChange.Native' -as [type]))
    {
        Add-Type -Namespace Win32FontChange -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("gdi32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int AddFontResource(string lpFileName);
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern System.IntPtr SendMessage(System.IntPtr hWnd, uint Msg, System.IntPtr wParam, System.IntPtr lParam);
'@
    }

    foreach ($path in $Paths)
    {
        [void][Win32FontChange.Native]::AddFontResource($path)
    }

    $broadcast = [IntPtr]0xffff
    [void][Win32FontChange.Native]::SendMessage($broadcast, [uint32]0x001D, [IntPtr]::Zero, [IntPtr]::Zero)
}

function Install-DepartureMonoFonts
{
    [CmdletBinding()]
    param()

    if (Test-DepartureMonoFontsInstalled)
    {
        return
    }

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('DepartureMono-' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $previousProgress = $ProgressPreference
    try
    {
        $ProgressPreference = 'SilentlyContinue'
        $zip = Join-Path $tempRoot 'DepartureMono.zip'
        Invoke-WebRequest -Uri $script:FontZipUri -OutFile $zip -UseBasicParsing
        $extract = Join-Path $tempRoot 'extract'
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $installed = New-Object System.Collections.Generic.List[string]
        foreach ($font in $script:DepartureMonoFonts)
        {
            $source = Join-Path $extract $font.File
            if (-not (Test-Path -LiteralPath $source))
            {
                throw "Departure Mono archive is missing $($font.File)"
            }

            $installed.Add((Install-UserFontFile -SourcePath $source -Family $font.Family))
        }

        Add-UserFontResource -Paths $installed.ToArray()
    }
    finally
    {
        $ProgressPreference = $previousProgress
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-DepartureMonoFontsInstalled))
    {
        throw 'Departure Mono fonts are not registered for the current user.'
    }
}

function Get-ExistingWindowsTerminalSettingsPaths
{
    [CmdletBinding()]
    param()

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json')
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in $candidates)
    {
        if (Test-Path -LiteralPath $candidate)
        {
            $found.Add($candidate)
        }
    }

    return $found.ToArray()
}

function Get-WindowsTerminalSettingsWritePaths
{
    [CmdletBinding()]
    param()

    $existing = @(Get-ExistingWindowsTerminalSettingsPaths)
    if ($existing.Count -gt 0)
    {
        return $existing
    }

    $packageRoot = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe'
    if (Test-Path -LiteralPath $packageRoot)
    {
        return @((Join-Path $packageRoot 'LocalState\settings.json'))
    }

    return @((Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json'))
}

function Get-EmptyTerminalSettingsJson
{
    [CmdletBinding()]
    param()

    return @'
{
  "$schema": "https://aka.ms/terminal-profiles-schema",
  "profiles": {
    "defaults": {},
    "list": []
  }
}
'@
}

function Test-WindowsTerminalSettings
{
    [CmdletBinding()]
    param()

    $paths = @(Get-ExistingWindowsTerminalSettingsPaths)
    if ($paths.Count -eq 0)
    {
        return $false
    }

    foreach ($path in $paths)
    {
        $json = [System.IO.File]::ReadAllText($path)
        if (-not (Test-TerminalSettingsText -Json $json))
        {
            return $false
        }
    }

    return $true
}

function Set-WindowsTerminalSettings
{
    [CmdletBinding()]
    param()

    $encoding = New-Object System.Text.UTF8Encoding $false
    foreach ($path in @(Get-WindowsTerminalSettingsWritePaths))
    {
        $json = Get-EmptyTerminalSettingsJson
        if (Test-Path -LiteralPath $path)
        {
            $json = [System.IO.File]::ReadAllText($path)
        }
        if (Test-TerminalSettingsText -Json $json)
        {
            continue
        }

        $updated = Convert-TerminalSettingsJson -Json $json
        $directory = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $directory))
        {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        [System.IO.File]::WriteAllText($path, $updated, $encoding)
    }

    if (-not (Test-WindowsTerminalSettings))
    {
        throw 'Windows Terminal settings do not have Departure Mono and PowerShell first.'
    }
}

function Get-ShellProfileFacts
{
    [CmdletBinding()]
    param()

    return @{
        Profile  = [bool](Test-PwshProfileContent)
        Icons    = [bool](Test-TerminalIconsInstalled)
        Fonts    = [bool](Test-DepartureMonoFontsInstalled)
        Terminal = [bool](Test-WindowsTerminalSettings)
    }
}

function Format-ShellProfileFacts
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Facts)

    $profileState = if ($Facts.Profile) { 'match' } else { 'missing' }
    $iconsState = if ($Facts.Icons) { 'present' } else { 'missing' }
    $fontsState = if ($Facts.Fonts) { 'installed' } else { 'missing' }
    $terminalState = if ($Facts.Terminal) { 'ready' } else { 'missing' }
    return ('profile={0};icons={1};fonts={2};terminal={3}' -f $profileState, $iconsState, $fontsState, $terminalState)
}

function Get-ShellProfileReport
{
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSVersion.Major -lt 7)
    {
        $result = Invoke-ShellProfileOnPwsh -Command 'Get'
        return @{ Result = $result }
    }

    return @{ Result = (Format-ShellProfileFacts -Facts (Get-ShellProfileFacts)) }
}

function Test-ShellProfile
{
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSVersion.Major -lt 7)
    {
        $code = Invoke-ShellProfileOnPwsh -Command 'Test'
        if ($code -eq 0)
        {
            return $true
        }
        if ($code -eq 1)
        {
            return $false
        }

        throw "Test-ShellProfile failed in pwsh with exit $code"
    }

    try
    {
        $facts = Get-ShellProfileFacts
        return ($facts.Profile -and $facts.Icons -and $facts.Fonts -and $facts.Terminal)
    }
    catch
    {
        return $false
    }
}

function Set-ShellProfile
{
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSVersion.Major -lt 7)
    {
        $code = Invoke-ShellProfileOnPwsh -Command 'Set'
        if ($code -ne 0)
        {
            throw "Set-ShellProfile failed in pwsh with exit $code"
        }

        return
    }

    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($step in @(
            { Set-PwshProfileContent }
            { Install-TerminalIconsModule }
            { Install-DepartureMonoFonts }
            { Set-WindowsTerminalSettings }
        ))
    {
        try
        {
            & $step
        }
        catch
        {
            $errors.Add($_.Exception.Message)
        }
    }

    if ($errors.Count -gt 0)
    {
        throw ($errors -join ' ')
    }
}

function Test-ShellProfileLibraryFile
{
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf))
    {
        return $false
    }

    $head = [System.IO.File]::ReadAllText($Path)
    return ($head -match 'function Invoke-ShellProfileOnPwsh')
}

function Save-ShellProfileRelaunchFile
{
    [CmdletBinding()]
    param()

    $path = $script:ShellProfileFile
    if (Test-ShellProfileLibraryFile -Path $path)
    {
        return $path
    }

    $definition = $script:ShellProfileDefinition
    if ([string]::IsNullOrWhiteSpace($definition) -or $definition -notmatch 'function Invoke-ShellProfileOnPwsh')
    {
        throw 'Shell profile script path is not available to relaunch under pwsh.'
    }

    $directory = Join-Path ([System.IO.Path]::GetTempPath()) ('shell-profile-' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $file = Join-Path $directory 'ShellProfile.ps1'
    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($file, $definition, $encoding)
    $script:ShellProfileFile = $file
    $script:ShellProfileRelaunchTemp = $directory
    return $file
}

function Invoke-ShellProfileOnPwsh
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Command)

    $pwshCmd = Get-Command -Name pwsh -ErrorAction Stop
    $createdTemp = $false
    $path = $script:ShellProfileFile
    if (-not (Test-ShellProfileLibraryFile -Path $path))
    {
        $path = Save-ShellProfileRelaunchFile
        $createdTemp = $true
    }

    $previous = [Environment]::GetEnvironmentVariable('SHELL_PROFILE_COMMAND')
    try
    {
        [Environment]::SetEnvironmentVariable('SHELL_PROFILE_COMMAND', $Command)
        $output = & $pwshCmd.Source -NoProfile -NonInteractive -File $path
        $code = $LASTEXITCODE
    }
    finally
    {
        [Environment]::SetEnvironmentVariable('SHELL_PROFILE_COMMAND', $previous)
        if ($createdTemp -and -not [string]::IsNullOrWhiteSpace($script:ShellProfileRelaunchTemp))
        {
            Remove-Item -LiteralPath $script:ShellProfileRelaunchTemp -Recurse -Force -ErrorAction SilentlyContinue
            $script:ShellProfileRelaunchTemp = $null
            $script:ShellProfileFile = $null
        }
    }

    if ($Command -eq 'Get')
    {
        if ($code -ne 0)
        {
            throw "Get-ShellProfileReport failed in pwsh with exit $code"
        }

        return ((@($output) | Select-Object -Last 1).ToString())
    }

    return $code
}

$shellCommand = [Environment]::GetEnvironmentVariable('SHELL_PROFILE_COMMAND')
if (($MyInvocation.InvocationName -ne '.') -and $shellCommand)
{
    [Environment]::SetEnvironmentVariable('SHELL_PROFILE_COMMAND', $null)
    if ($shellCommand -eq 'Test')
    {
        if (Test-ShellProfile) { exit 0 } else { exit 1 }
    }
    if ($shellCommand -eq 'Set')
    {
        if ([Environment]::GetEnvironmentVariable('SHELL_PROFILE_SET_PROBE') -eq '1')
        {
            $probeOut = [Environment]::GetEnvironmentVariable('SHELL_PROFILE_SET_PROBE_OUT')
            if (-not [string]::IsNullOrWhiteSpace($probeOut))
            {
                $encoding = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($probeOut, 'set-relaunched')
            }

            exit 0
        }

        Set-ShellProfile
        exit 0
    }
    if ($shellCommand -eq 'Get')
    {
        $report = Get-ShellProfileReport
        Write-Output $report.Result
        exit 0
    }
    if ($shellCommand -eq 'Text')
    {
        $textPath = [Environment]::GetEnvironmentVariable('SHELL_PROFILE_OUT')
        if ([string]::IsNullOrWhiteSpace($textPath))
        {
            throw 'SHELL_PROFILE_OUT is required for the Text command.'
        }

        $encoding = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($textPath, (Get-ShellProfileText), $encoding)
        exit 0
    }

    Write-Error "Unknown shell profile command: $shellCommand"
    exit 2
}
