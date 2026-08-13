$ErrorActionPreference = 'Stop'

$Out = Join-Path $HOME 'Downloads\forge-tool-result-cap-impact.txt'

function Get-TextChars($Message) {
    if ($null -eq $Message -or [string]$Message.role -ne 'toolResult') { return 0 }
    $Total = 0
    if ($Message.content -is [System.Collections.IEnumerable] -and -not ($Message.content -is [string])) {
        foreach ($Block in $Message.content) {
            if ($null -ne $Block -and $null -ne $Block.text) {
                $Total += ([string]$Block.text).Length
            }
        }
    } elseif ($Message.content -is [string]) {
        $Total += ([string]$Message.content).Length
    }
    return $Total
}

function Get-ToolName($Message) {
    foreach ($Name in @($Message.toolName, $Message.name, $Message.tool_name)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Name)) { return [string]$Name }
    }
    return 'unknown'
}

$Lines = New-Object System.Collections.Generic.List[string]
$Lines.Add('FORGE TOOL RESULT CAP IMPACT - READ ONLY')
$Lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$Lines.Add('NO FILES ARE MODIFIED.')
$Lines.Add('')

$Lines.Add('=== CURRENT CONFIG ===')
$ConfigCandidates = @(
    (Join-Path $HOME '.openclaw\openclaw.json'),
    (Join-Path $HOME '.openclaw\config.json')
)

$ConfigFound = $false
foreach ($ConfigPath in $ConfigCandidates) {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { continue }
    $ConfigFound = $true
    $Lines.Add("Config: $ConfigPath")
    try {
        $Cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        $DefaultCap = $Cfg.agents.defaults.contextLimits.toolResultMaxChars
        if ($null -eq $DefaultCap) { $Lines.Add('agents.defaults.contextLimits.toolResultMaxChars = <unset>') } else { $Lines.Add("agents.defaults.contextLimits.toolResultMaxChars = $DefaultCap") }
        if ($Cfg.agents.list) {
            foreach ($Agent in $Cfg.agents.list) {
                $Id = if ($Agent.id) { [string]$Agent.id } else { '<unknown>' }
                $Cap = $Agent.contextLimits.toolResultMaxChars
                if ($null -ne $Cap) { $Lines.Add("agents.list[$Id].contextLimits.toolResultMaxChars = $Cap") }
            }
        }
    } catch {
        $Lines.Add("Config parse error: $($_.Exception.Message)")
    }
}
if (-not $ConfigFound) { $Lines.Add('No known config file found.') }
$Lines.Add('')

$Lines.Add('=== CANONICAL SESSION ===')
$SessionDirs = @(
    (Join-Path $HOME '.openclaw\agents\main\sessions'),
    (Join-Path $HOME '.openclaw\sessions')
) | Where-Object { Test-Path -LiteralPath $_ -PathType Container }

$Candidates = @()
foreach ($Dir in $SessionDirs) {
    $Candidates += Get-ChildItem -LiteralPath $Dir -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*.trajectory.jsonl' }
}

if (-not $Candidates) {
    $Lines.Add('No canonical session JSONL candidates found.')
    $Lines | Set-Content -LiteralPath $Out -Encoding UTF8
    Write-Host "READ ONLY - output: $Out"
    exit 0
}

$Session = $Candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Lines.Add("Canonical candidates found: $($Candidates.Count)")
$Lines.Add("Selected newest: $($Session.FullName)")
$Lines.Add("LastWriteTime: $($Session.LastWriteTime)")
$Lines.Add("Bytes: $($Session.Length)")
$Lines.Add('')

$Results = New-Object System.Collections.Generic.List[object]
$LineNo = 0
Get-Content -LiteralPath $Session.FullName | ForEach-Object {
    $LineNo++
    if ([string]::IsNullOrWhiteSpace($_)) { return }
    try { $J = $_ | ConvertFrom-Json } catch { return }
    $M = $null
    if ($null -ne $J.message) { $M = $J.message }
    elseif ([string]$J.role -eq 'toolResult') { $M = $J }
    if ($null -eq $M -or [string]$M.role -ne 'toolResult') { return }
    $Chars = Get-TextChars $M
    $DetailsAggregatedChars = 0
    $FullOutputPath = $null
    $SpillTruncated = $false
    if ($null -ne $M.details) {
        if ($null -ne $M.details.aggregated) { $DetailsAggregatedChars = ([string]$M.details.aggregated).Length }
        if ($null -ne $M.details.fullOutputPath) { $FullOutputPath = [string]$M.details.fullOutputPath }
        if ($M.details.spillTruncated -eq $true) { $SpillTruncated = $true }
    }
    $Results.Add([pscustomobject]@{
        Line = $LineNo
        Tool = Get-ToolName $M
        TextChars = $Chars
        AggregatedChars = $DetailsAggregatedChars
        HasFullOutputPath = -not [string]::IsNullOrWhiteSpace($FullOutputPath)
        FullOutputExists = if (-not [string]::IsNullOrWhiteSpace($FullOutputPath)) { Test-Path -LiteralPath $FullOutputPath -PathType Leaf } else { $false }
        SpillTruncated = $SpillTruncated
    })
}

$TotalText = ($Results | Measure-Object TextChars -Sum).Sum
$TotalAggregated = ($Results | Measure-Object AggregatedChars -Sum).Sum
$Lines.Add("Tool results: $($Results.Count)")
$Lines.Add("Tool-result text chars: $TotalText")
$Lines.Add("details.aggregated chars: $TotalAggregated")
$Lines.Add("Results with fullOutputPath: $(($Results | Where-Object HasFullOutputPath).Count)")
$Lines.Add("fullOutputPath currently exists: $(($Results | Where-Object FullOutputExists).Count)")
$Lines.Add("spillTruncated=true: $(($Results | Where-Object SpillTruncated).Count)")
$Lines.Add('')

$Lines.Add('=== SIMULATED PER-RESULT CAPS ===')
foreach ($Cap in @(2000, 4000, 6000, 8000, 12000, 16000)) {
    $After = 0L
    $Affected = 0
    foreach ($R in $Results) {
        $After += [Math]::Min([long]$R.TextChars, [long]$Cap)
        if ($R.TextChars -gt $Cap) { $Affected++ }
    }
    $Saved = [long]$TotalText - $After
    $Pct = if ($TotalText -gt 0) { [Math]::Round(($Saved * 100.0) / $TotalText, 1) } else { 0 }
    $Lines.Add(('{0,6} chars => affected={1,4}  text_after={2,10}  saved={3,10} ({4}%)' -f $Cap,$Affected,$After,$Saved,$Pct))
}
$Lines.Add('')

$Lines.Add('=== BY TOOL ===')
$Groups = $Results | Group-Object Tool | ForEach-Object {
    [pscustomobject]@{
        Tool = $_.Name
        Count = $_.Count
        TextChars = ($_.Group | Measure-Object TextChars -Sum).Sum
        Over4K = ($_.Group | Where-Object { $_.TextChars -gt 4000 }).Count
        Over6K = ($_.Group | Where-Object { $_.TextChars -gt 6000 }).Count
        FullOutputPaths = ($_.Group | Where-Object HasFullOutputPath).Count
    }
} | Sort-Object TextChars -Descending
foreach ($G in $Groups) {
    $Lines.Add(('{0,-24} count={1,4} chars={2,10} >4K={3,3} >6K={4,3} spill={5,3}' -f $G.Tool,$G.Count,$G.TextChars,$G.Over4K,$G.Over6K,$G.FullOutputPaths))
}
$Lines.Add('')

$Lines.Add('=== TOP 25 LARGEST RESULTS ===')
foreach ($R in ($Results | Sort-Object TextChars -Descending | Select-Object -First 25)) {
    $Lines.Add(('line={0,5} tool={1,-22} text={2,8} aggregated={3,8} spill={4} exists={5}' -f $R.Line,$R.Tool,$R.TextChars,$R.AggregatedChars,$R.HasFullOutputPath,$R.FullOutputExists))
}

$Lines.Add('')
$Lines.Add('NOTE: Simulation caps text content only. OpenClaw may also sanitize/cap details separately.')
$Lines.Add('NOTE: This script does not alter config, session JSONL, spill files, or OpenClaw source.')
$Lines | Set-Content -LiteralPath $Out -Encoding UTF8
Write-Host ''
Write-Host 'READ ONLY - no files changed.' -ForegroundColor Green
Write-Host "Session: $($Session.FullName)"
Write-Host "Tool results: $($Results.Count)"
Write-Host "Output: $Out"
