$ErrorActionPreference = "Stop"

$Agents = Join-Path $HOME ".openclaw\workspace\AGENTS.md"
$Dist = Join-Path $env:APPDATA "npm\node_modules\openclaw\dist"

Write-Host "=== AGENTS: skill/tool instructions ==="
if (Test-Path -LiteralPath $Agents) {
    Select-String -LiteralPath $Agents -Pattern 'SKILL\.md|read.*skill|skill.*read|before.*tool|before.*using' -CaseSensitive:$false |
        Select-Object -First 30 |
        ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line.Trim() }
} else {
    Write-Host "AGENTS.md not found: $Agents"
}

Write-Host ""
Write-Host "=== OpenClaw: likely pre-AGENTS skill instructions ==="
if (-not (Test-Path -LiteralPath $Dist)) { throw "OpenClaw dist not found: $Dist" }

$Patterns = @('SKILL\.md','read.{0,60}skill','skill.{0,60}read','before.{0,60}skill')
$Matches = Get-ChildItem -LiteralPath $Dist -Filter "*.js" -File -Recurse |
    Select-String -Pattern $Patterns -CaseSensitive:$false |
    Select-Object -First 60

if (-not $Matches) {
    Write-Host "No likely matches found."
    exit 0
}

$Matches | ForEach-Object {
    $Rel = $_.Path.Replace($Dist + "\", "")
    "{0}:{1}: {2}" -f $Rel, $_.LineNumber, $_.Line.Trim()
}
