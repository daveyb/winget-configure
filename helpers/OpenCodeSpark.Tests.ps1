#Requires -Version 7
$ErrorActionPreference = 'Stop'

$helper = Join-Path $PSScriptRoot 'OpenCodeSpark.ps1'
. $helper

function Assert-True
{
    param([bool]$Condition, [string]$Label)
    if (-not $Condition)
    {
        throw $Label
    }
}

function Assert-Equal
{
    param($Actual, $Expected, [string]$Label)
    if ($Actual -ne $Expected)
    {
        throw ("{0}. Expected [{1}] actual [{2}]" -f $Label, $Expected, $Actual)
    }
}

$launcherPath = Join-Path ([System.IO.Path]::GetTempPath()) ('opencode-spark-' + [guid]::NewGuid().ToString('n') + '.ps1')
$encoding = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($launcherPath, (Get-OpenCodeSparkLauncherText), $encoding)
try
{
    . $launcherPath

    function Format-OpenCodeSparkLaunch {
        param([string[]]$Argument)
        $launch = @(Get-OpenCodeSparkArgument -Argument $Argument)
        foreach ($item in $launch) {
            if ($item -isnot [string]) {
                throw 'launch argument is not a string'
            }
        }
        return ($launch -join '|')
    }

    Assert-Equal (Format-OpenCodeSparkLaunch) '--auto' 'no arguments'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('--version')) '--auto|--version' 'version flag stays on the default command'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('run')) 'run|--auto' 'run with no message'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('run', 'hello')) 'run|--auto|hello' 'run receives auto after the subcommand'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('--print-logs', 'run', 'hello')) '--print-logs|run|--auto|hello' 'run after a global flag still receives auto'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('-m', 'spark/x')) '--auto|-m|spark/x' 'tui model flag keeps a leading auto'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('C:\src')) '--auto|C:\src' 'project path keeps a leading auto'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('models')) 'models' 'models is unchanged'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('--print-logs', 'models')) '--print-logs|models' 'models after a global flag is unchanged'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('--auto', 'run')) '--auto|run' 'existing auto is kept'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('run', '--no-auto')) 'run|--no-auto' 'no-auto is kept'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('--no-auto')) '--no-auto' 'no-auto alone is kept'
}
finally
{
    Remove-Item -LiteralPath $launcherPath -Force -ErrorAction SilentlyContinue
}

$executableSuffix = 'opencode-cli\1.19.3-x64\opencode.exe'
Assert-True ((Get-OpenCodeSparkExecutablePath).EndsWith($executableSuffix)) 'executable path uses the pinned folder'
Assert-True ((Get-OpenCodeSparkLauncherText).Contains($executableSuffix)) 'launcher starts that same executable'
Assert-True (Test-OpenCodeSparkHashEqual -Actual 'e4ce9117f55fc068414513789f8c7d1049f855d7518bb4e350b9170a3a20d8c3' -Expected 'E4CE9117F55FC068414513789F8C7D1049F855D7518BB4E350B9170A3A20D8C3') 'zip hash compare ignores case'
Assert-True (-not (Test-OpenCodeSparkHashEqual -Actual '0000000000000000000000000000000000000000000000000000000000000000' -Expected 'E4CE9117F55FC068414513789F8C7D1049F855D7518BB4E350B9170A3A20D8C3')) 'zip hash compare rejects a different hash'
Assert-True (Test-OpenCodeSparkVersionOutput "1.19.3`r`n") 'version output accepts 1.19.3'
Assert-True (-not (Test-OpenCodeSparkVersionOutput '1.19.1')) 'version output rejects 1.19.1'

Set-StrictMode -Version Latest
$helperText = [System.IO.File]::ReadAllText($helper)
$dscGet = [scriptblock]::Create($helperText + "`nreturn (Get-OpenCodeSparkReport)`n")
$dscReport = & $dscGet
Assert-True ($null -ne $dscReport -and $dscReport.Result -match '^launcher=(present|missing);shim=(present|missing);path=(present|missing);opencode=(present|missing)$') 'strict scriptblock get returns facts'
Assert-True ($dscReport.Result -notmatch 'LITELLM|secret|pass://') 'report does not include a secret'

Write-Output 'OpenCodeSpark tests passed'
