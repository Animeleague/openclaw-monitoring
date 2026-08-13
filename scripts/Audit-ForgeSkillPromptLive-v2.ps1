$ErrorActionPreference = "Stop"

$Target = "$env:APPDATA\npm\node_modules\openclaw\dist\system-prompt-config-BeuaroSf.js"
$Sessions = "$HOME\.openclaw\agents\main\agent\codex-home\sessions"

$OldExact = 'Scan <available_skills>. If one clearly applies, read its SKILL.md at exact <location> with `${params.readToolName}`, then follow it.'
$NewMarker = 'reuse them rather than reading the file again'

function Read-SharedText([string]$Path) {
    $fs = [System.IO.File]::Open($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite)
    try {
        $sr = New-Object System.IO.StreamReader($fs)
        try { return $sr.ReadToEnd() }
        finally { $sr.Dispose() }
    }
    finally { $fs.Dispose() }
}

Write-Host "=== RUNTIME FILE ==="
$Runtime = Read-SharedText $Target
"Exact old prompt present: " + $Runtime.Contains($OldExact)
"New patch marker present: " + $Runtime.Contains($NewMarker)

Write-Host ""
Write-Host "=== LATEST CODEX ROLLOUT ==="
$Latest = Get-ChildItem -Path $Sessions -Recurse -Filter '*.jsonl' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $Latest) { throw "No rollout JSONL found under $Sessions" }
"File: " + $Latest.FullName
"Modified: " + $Latest.LastWriteTime
$Rollout = Read-SharedText $Latest.FullName
"Exact old prompt present: " + $Rollout.Contains($OldExact)
"New patch marker present: " + $Rollout.Contains($NewMarker)

Write-Host ""
Write-Host "=== POSSIBLE PER-TURN SKILL RULES ==="
Get-ChildItem "$env:APPDATA\npm\node_modules\openclaw\dist" -Filter '*.js' -File |
    Select-String -Pattern 'each turn|every turn|new turn|per turn|skill.*turn|turn.*skill|read.*SKILL\.md' -CaseSensitive:$false |
    Select-Object -First 40 |
    ForEach-Object {
        $line = $_.Line.Trim()
        if ($line.Length -gt 320) { $line = $line.Substring(0,320) + "..." }
        "{0}:{1}: {2}" -f ([IO.Path]::GetFileName($_.Path)),$_.LineNumber,$line
    }
