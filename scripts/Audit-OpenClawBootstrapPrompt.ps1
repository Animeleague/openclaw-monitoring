$ErrorActionPreference = "Stop"

$Target = "$env:APPDATA\npm\node_modules\openclaw\dist\system-prompt-config-BeuaroSf.js"
$Out = "$HOME\Downloads\openclaw-bootstrap-prompt-audit.txt"

if (-not (Test-Path -LiteralPath $Target)) {
    throw "Target not found: $Target"
}

$Lines = Get-Content -LiteralPath $Target
$Matches = for ($i = 0; $i -lt $Lines.Count; $i++) {
    $Line = $Lines[$i]
    if ($Line -match 'AGENTS|SKILL|available_skills|tool|memory|context|session|reply|message|channel|room|identity|system prompt|startup|bootstrap|must|never|do not|before|after|current turn|every turn|each turn') {
        "{0}: {1}" -f ($i + 1), $Line.TrimEnd()
    }
}

@(
    "OpenClaw bootstrap prompt audit"
    "Target: $Target"
    "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    ""
    $Matches
) | Set-Content -LiteralPath $Out -Encoding UTF8

Write-Host "Wrote:"
Write-Host "  $Out"
Write-Host ""
Write-Host "Lines captured: $($Matches.Count)"
Write-Host ""
Write-Host "Paste/upload that txt here."
