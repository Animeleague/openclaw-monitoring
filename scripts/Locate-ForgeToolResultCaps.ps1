$ErrorActionPreference = 'Stop'

$Root = Join-Path $env:APPDATA 'npm\node_modules\openclaw\dist'
$Out  = Join-Path $HOME 'Downloads\forge-tool-result-caps-source.txt'

$ExactFiles = @(
    'tool-result-truncation-C9VgnqCa.js',
    'tool-result-middleware-B8t-_qCu.js',
    'attempt.model-diagnostic-events-Dg8sP6iR.js',
    'run-attempt-V636cwT5.js'
)

$Patterns = @(
    'DEFAULT_MAX_LIVE_TOOL_RESULT_CHARS',
    'resolveLiveToolResultMaxChars',
    'truncateToolResultMessage',
    'capToolResultForPersistence',
    'resolveMaxToolResultChars',
    'installSessionToolResultGuard(',
    'maxToolResultChars',
    'createAgentToolResultMiddlewareRunner',
    'resolveTranscriptPolicy',
    'toolResultMax',
    'toolResult'
)

$Lines = New-Object System.Collections.Generic.List[string]
$Lines.Add('FORGE TOOL RESULT CAP / MIDDLEWARE AUDIT - READ ONLY')
$Lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$Lines.Add("Root: $Root")
$Lines.Add('NO FILES ARE MODIFIED.')
$Lines.Add('')

foreach ($Name in $ExactFiles) {
    $Path = Join-Path $Root $Name
    $Lines.Add(('=' * 100))
    $Lines.Add("FILE: $Path")

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $Lines.Add('MISSING')
        $Lines.Add('')
        continue
    }

    $Lines.Add("SHA256: $((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash)")
    $Content = @(Get-Content -LiteralPath $Path)
    $Lines.Add("LINES: $($Content.Count)")
    $Lines.Add('')

    if ($Name -eq 'tool-result-truncation-C9VgnqCa.js' -or
        $Name -eq 'tool-result-middleware-B8t-_qCu.js') {
        $Lines.Add('--- FULL FILE ---')
        for ($i = 1; $i -le $Content.Count; $i++) {
            $Lines.Add(('{0,7}: {1}' -f $i, $Content[$i - 1]))
        }
        $Lines.Add('')
        continue
    }

    foreach ($Pattern in $Patterns) {
        $Hits = @(Select-String -LiteralPath $Path -SimpleMatch -Pattern $Pattern -ErrorAction SilentlyContinue)
        if (-not $Hits) { continue }

        $Lines.Add("--- PATTERN: $Pattern | HITS: $($Hits.Count) ---")
        foreach ($Hit in ($Hits | Select-Object -First 12)) {
            $Start = [Math]::Max(1, $Hit.LineNumber - 35)
            $End   = [Math]::Min($Content.Count, $Hit.LineNumber + 55)
            $Lines.Add("MATCH line $($Hit.LineNumber): $($Hit.Line.Trim())")
            for ($i = $Start; $i -le $End; $i++) {
                $Lines.Add(('{0,7}: {1}' -f $i, $Content[$i - 1]))
            }
            $Lines.Add('')
        }
    }
}

$Lines.Add('')
$Lines.Add(('=' * 100))
$Lines.Add('CONFIG / SCHEMA SEARCH')
$Lines.Add(('=' * 100))

$SchemaPatterns = @(
    'maxToolResultChars',
    'liveToolResult',
    'toolResultMax',
    'toolResultLimit',
    'toolResult'
)

$Files = @(Get-ChildItem -LiteralPath $Root -Filter '*.js' -File -Recurse)
foreach ($Pattern in $SchemaPatterns) {
    $Hits = @(
        Select-String -Path $Files.FullName -SimpleMatch -Pattern $Pattern -ErrorAction SilentlyContinue |
        Select-Object Path, LineNumber, Line
    )
    $Lines.Add('')
    $Lines.Add("PATTERN: $Pattern | TOTAL HITS: $($Hits.Count)")
    foreach ($Hit in ($Hits | Select-Object -First 40)) {
        $Lines.Add("$($Hit.Path):$($Hit.LineNumber): $($Hit.Line.Trim())")
    }
}

$Lines | Set-Content -LiteralPath $Out -Encoding UTF8

Write-Host ''
Write-Host 'READ ONLY - no OpenClaw files changed.' -ForegroundColor Green
Write-Host "Output: $Out"
