function ConvertFrom-PackageLine
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $pattern = '^\s*(?:-\s+)?(?<Id>[^\s#]+)(?:\s+source:\s*(?<Source>[^\s#]+))?(?:\s+#\s*(?<Comment>.*))?\s*$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success)
    {
        $payload = $Text.Trim()
        if ($payload.StartsWith('- '))
        {
            $payload = $payload.Substring(2).Trim()
        }
        $bad = $payload
        $parts = @($payload -split '\s+' | Where-Object { -not [string]::IsNullOrEmpty($_) })
        if ($parts.Count -ge 2 -and $parts[1] -cne 'source:')
        {
            $bad = $parts[1]
        }
        throw "Invalid package line token: $bad"
    }

    $id = $match.Groups['Id'].Value
    $source = 'winget'
    $sourceGroup = $match.Groups['Source']
    if ($sourceGroup.Success -and -not [string]::IsNullOrEmpty($sourceGroup.Value))
    {
        $sourceToken = $sourceGroup.Value
        if (($sourceToken -cne 'winget') -and ($sourceToken -cne 'msstore'))
        {
            throw "Invalid package source: $sourceToken"
        }
        $source = $sourceToken
    }

    $comment = ''
    $commentGroup = $match.Groups['Comment']
    if ($commentGroup.Success)
    {
        $comment = $commentGroup.Value.Trim()
    }

    return @{
        Id      = $id
        Source  = $source
        Comment = $comment
    }
}
