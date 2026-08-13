param(
    [string]$OpenClawRoot = "$HOME\.openclaw"
)

$ErrorActionPreference = "Stop"

$Out = Join-Path $HOME "Downloads\forge-pre-optimisation-checkpoint.txt"

function Add-Line([string]$Text = "") {
    Add-Content -LiteralPath $Out -Value $Text -Encoding UTF8
}

function Add-Section([string]$Title) {
    Add-Line
    Add-Line ("=" * 100)
    Add-Line $Title
    Add-Line ("=" * 100)
}

function Get-SharedText([string]$Path) {
    $fs = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )
    try {
        $sr = New-Object System.IO.StreamReader($fs)
        try { return $sr.ReadToEnd() }
        finally { $sr.Dispose() }
    }
    finally { $fs.Dispose() }
}

function Get-Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "<missing>" }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Find-MarkerFiles([string]$Marker, [string[]]$Roots) {
    $Found = @()
    foreach ($Root in $Roots) {
        if (-not (Test-Path -LiteralPath $Root -PathType Container)) { continue }
        $Found += @(
            Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "*.js" -ErrorAction SilentlyContinue |
            Select-String -SimpleMatch -Pattern $Marker -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Path -Unique
        )
    }
    return @($Found | Select-Object -Unique)
}

Remove-Item -LiteralPath $Out -Force -ErrorAction SilentlyContinue

Add-Line "FORGE PRE-OPTIMISATION CHECKPOINT"
Add-Line ("Generated: " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz"))
Add-Line "READ ONLY - this script does not modify OpenClaw, Forge, AGENTS.md, config, sessions or patches."

$GlobalDist = Join-Path $env:APPDATA "npm\node_modules\openclaw\dist"
$ProjectRoot = Join-Path $OpenClawRoot "npm\projects"
$CodexHome = Join-Path $OpenClawRoot "agents\main\agent\codex-home"
$Agents = Join-Path $OpenClawRoot "workspace\AGENTS.md"
$OpenClawConfig = Join-Path $OpenClawRoot "openclaw.json"
$CodexConfig = Join-Path $CodexHome "config.toml"

$SearchRoots = @($GlobalDist, $ProjectRoot) | Where-Object {
    Test-Path -LiteralPath $_ -PathType Container
}

Add-Section "1. VERSIONS / PATHS"
try {
    Add-Line ("openclaw --version: " + ((& openclaw --version 2>$null | Out-String).Trim()))
}
catch {
    Add-Line ("openclaw --version failed: " + $_.Exception.Message)
}
Add-Line ("OpenClaw root : " + $OpenClawRoot)
Add-Line ("Global dist   : " + $GlobalDist)
Add-Line ("Project root  : " + $ProjectRoot)
Add-Line ("Codex home    : " + $CodexHome)
Add-Line ("AGENTS.md     : " + $Agents)
Add-Line ("openclaw.json : " + $OpenClawConfig)
Add-Line ("Codex config  : " + $CodexConfig)

Add-Section "2. KNOWN FORGE / CODEX PATCH MARKERS"

$Markers = @(
    "FORGE_CODEX_STABLE_TOOL_CATALOG_V2",
    "FORGE_CODEX_TRANSIENT_LUNA_V1",
    "FORGE_CODEX_DUAL_WARM_THREADS_V2",
    "FORGE_CODEX_DUAL_WARM_THREADS_V2_1",
    "FORGE_CODEX_TURN_PAYLOAD_DIAG_V1",
    "FORGE_CODEX_DURABLE_REGISTRATION_PROOF_V1",
    "FORGE_CODEX_IMAGE_STABILITY_V1_1",
    "FORGE_CURRENT_TURN_IMAGE_DEDUPE_V1",
    "FORGE_CONTEXT_HISTORY_V1",
    "FORGE_CONTEXT_HISTORY_V2",
    "FORGE_CODEX_NATIVE_AUTOCOMPACT_HEADROOM_V1",
    "FORGE_CODEX_NATIVE_AUTOCOMPACT_HEADROOM_V1_1"
)

foreach ($Marker in $Markers) {
    $Files = @(Find-MarkerFiles -Marker $Marker -Roots $SearchRoots)
    Add-Line
    Add-Line ("MARKER: " + $Marker)
    Add-Line ("COUNT : " + $Files.Count)
    if ($Files.Count -eq 0) {
        Add-Line "  NOT FOUND"
        continue
    }
    foreach ($File in $Files) {
        Add-Line ("  " + $File)
        Add-Line ("    SHA256: " + (Get-Sha256 $File))
    }
}

Add-Section "3. BOOTSTRAP TOOL-EFFICIENCY PROMPT"

$BootstrapNeedles = @(
    "For native skill carry-over purposes",
    "reuse them rather than reading the file again",
    "Do not retry a tool that has already reported a persistent configuration",
    "Do not repeat the same informational tool call when a usable result"
)

$PromptFiles = @()
if (Test-Path -LiteralPath $GlobalDist -PathType Container) {
    $PromptFiles = @(
        Get-ChildItem -LiteralPath $GlobalDist -Recurse -File -Filter "*.js" -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $Text = Get-SharedText $_.FullName
                foreach ($Needle in $BootstrapNeedles) {
                    if ($Text.Contains($Needle)) { return $true }
                }
                return $false
            }
            catch { return $false }
        }
    )
}

if ($PromptFiles.Count -eq 0) {
    Add-Line "No bootstrap/tool-efficiency prompt markers found."
}
else {
    foreach ($File in $PromptFiles) {
        Add-Line ("FILE: " + $File.FullName)
        Add-Line ("SHA256: " + (Get-Sha256 $File.FullName))
        $Text = Get-SharedText $File.FullName
        foreach ($Needle in $BootstrapNeedles) {
            Add-Line ("  " + $Needle + " = " + $Text.Contains($Needle))
        }
    }
}

Add-Section "4. AGENTS.MD CHECKPOINT"

if (-not (Test-Path -LiteralPath $Agents -PathType Leaf)) {
    Add-Line "AGENTS.md not found."
}
else {
    $AText = Get-SharedText $Agents
    Add-Line ("SHA256: " + (Get-Sha256 $Agents))
    Add-Line ("Chars : " + $AText.Length)

    $AgentRules = @(
        "Start with the single routed KB file for the question and a focused search.",
        "Retrieve only the relevant passage (normally no more than about 20 lines).",
        "Never read an entire KB file into context for a normal lookup.",
        "Consult additional KB files or expand the passage only if the first bounded result is insufficient to answer safely.",
        "DO NOT BE LAZY.",
        "Never mention the knowledge base (kb)"
    )

    foreach ($Rule in $AgentRules) {
        Add-Line ("  " + $Rule + " = " + $AText.Contains($Rule))
    }
}

Add-Section "5. NATIVE AUTO-COMPACTION CONFIG"

if (-not (Test-Path -LiteralPath $CodexConfig -PathType Leaf)) {
    Add-Line "Codex config.toml not found."
}
else {
    Add-Line ("SHA256: " + (Get-Sha256 $CodexConfig))
    $Matches = @(Select-String -LiteralPath $CodexConfig -Pattern '^\s*model_auto_compact_token_limit\s*=' -ErrorAction SilentlyContinue)
    if ($Matches.Count -eq 0) {
        Add-Line "model_auto_compact_token_limit = <unset>"
    }
    else {
        foreach ($M in $Matches) {
            Add-Line ("line " + $M.LineNumber + ": " + $M.Line.Trim())
        }
    }
}

Add-Section "6. FORGE MONITOR PLUGIN INSTALL"

$ForgeProjects = @()
if (Test-Path -LiteralPath $ProjectRoot -PathType Container) {
    $ForgeProjects = @(
        Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Filter "package.json" -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $J = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
                $J.name -eq "@animeleague/forge-discord-monitor"
            }
            catch { $false }
        }
    )
}

if ($ForgeProjects.Count -eq 0) {
    Add-Line "Installed Forge monitor package not found under .openclaw\npm\projects."
}
else {
    foreach ($Pkg in $ForgeProjects) {
        try {
            $J = Get-Content -LiteralPath $Pkg.FullName -Raw | ConvertFrom-Json
            Add-Line ("Package: " + $Pkg.FullName)
            Add-Line ("Version: " + $J.version)
            Add-Line ("SHA256 : " + (Get-Sha256 $Pkg.FullName))
        }
        catch {
            Add-Line ("Could not parse " + $Pkg.FullName)
        }
    }
}

Add-Section "7. MASS-MENTION SAFEGUARD CONFIG"

if (-not (Test-Path -LiteralPath $OpenClawConfig -PathType Leaf)) {
    Add-Line "openclaw.json not found."
}
else {
    Add-Line ("openclaw.json SHA256: " + (Get-Sha256 $OpenClawConfig))
    try {
        $Cfg = Get-Content -LiteralPath $OpenClawConfig -Raw | ConvertFrom-Json
        $Entry = $Cfg.plugins.entries.'forge-discord-monitor'
        if ($null -eq $Entry) {
            $Entry = $Cfg.plugins.entries.'@animeleague/forge-discord-monitor'
        }
        if ($null -eq $Entry) {
            Add-Line "Forge monitor plugin config entry not found by expected key."
        }
        else {
            $Value = $Entry.config.allowMassMention
            if ($null -eq $Value) {
                Add-Line "allowMassMention = <unset> (expected fail-closed default false in plugin)"
            }
            else {
                Add-Line ("allowMassMention = " + [string]$Value)
            }
        }
    }
    catch {
        Add-Line ("Could not parse openclaw.json: " + $_.Exception.Message)
    }
}

Add-Section "8. SUMMARY"
Add-Line "Upload this TXT to Rook before applying any further OpenClaw optimisation."
Add-Line "It is intentionally diagnostic only; absence of a marker is evidence to investigate, not permission to reapply a patch blindly."

Write-Host ""
Write-Host "READ ONLY - nothing changed." -ForegroundColor Green
Write-Host "Checkpoint written to:"
Write-Host "  $Out"
