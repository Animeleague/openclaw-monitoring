# Audit-ForgePostFixSessionV1.ps1
# READ-ONLY audit collector for Forge/OpenClaw/Codex session health.
# Does not modify configs, sessions, rollouts, bindings, or logs.

$ErrorActionPreference = 'Stop'

$UserProfile = [Environment]::GetFolderPath('UserProfile')
$OpenClaw = Join-Path $UserProfile '.openclaw'
$CodexHome = Join-Path $OpenClaw 'agents\main\agent\codex-home'
$RolloutRoot = Join-Path $CodexHome 'sessions'
$LogDir = Join-Path $OpenClaw 'logs'
$TodayLog = Join-Path $LogDir 'forge-discord-monitor-2026-08-11.jsonl'
$CanonicalSessionId = '34ca7ff3-27c9-4300-a591-066ab7aa423a'
$PostFixUtc = [datetime]::Parse('2026-08-11T02:42:50Z').ToUniversalTime()
$CapacityUtc = [datetime]::Parse('2026-08-11T01:22:00Z').ToUniversalTime()
$KnownCanonicalBytesAtUpload = 9317067

$Out = Join-Path ([Environment]::GetFolderPath('Desktop')) 'forge-postfix-session-audit-2026-08-11.txt'

function Write-Line([string]$Text = '') {
    Add-Content -LiteralPath $Out -Value $Text -Encoding UTF8
}

function Write-Section([string]$Title) {
    Write-Line
    Write-Line ('=' * 110)
    Write-Line $Title
    Write-Line ('=' * 110)
}

function Get-SharedLines([string]$Path) {
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $sr = New-Object System.IO.StreamReader($fs)
        try {
            while (($line = $sr.ReadLine()) -ne $null) { $line }
        } finally { $sr.Dispose() }
    } finally { $fs.Dispose() }
}

function Get-TextFromMessagePayload($Payload) {
    if ($null -eq $Payload -or $null -eq $Payload.content) { return '' }
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($item in $Payload.content) {
        if ($null -ne $item.text) { [void]$parts.Add([string]$item.text) }
        elseif ($null -ne $item.input_text) { [void]$parts.Add([string]$item.input_text) }
    }
    return ($parts -join "`n")
}

function Marker-Flags([string]$Text) {
    [pscustomobject]@{
        AssembledContext = $Text.Contains('OpenClaw assembled context for this turn:')
        ConversationContext = $Text.Contains('<conversation_context>')
        RuntimeContext = $Text.Contains('OpenClaw runtime context for this turn:')
        ConversationInfo = $Text.Contains('Conversation info (untrusted metadata):')
        PreviousMessages = $Text.Contains('Previous messages from this Discord channel')
        CurrentUserRequest = $Text.Contains('Current user request:')
    }
}

Remove-Item -LiteralPath $Out -Force -ErrorAction SilentlyContinue
Write-Line 'FORGE POST-FIX SESSION / USAGE AUDIT V1'
Write-Line ('Generated local: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz'))
Write-Line ('Post-fix baseline UTC: ' + $PostFixUtc.ToString('o'))
Write-Line 'READ-ONLY. No OpenClaw/Codex/session/config files are modified.'

Write-Section '1. CURRENT CONFIG'
$config = Join-Path $CodexHome 'config.toml'
if (Test-Path -LiteralPath $config) {
    Write-Line ('Codex config: ' + $config)
    $compactLines = Select-String -LiteralPath $config -Pattern 'model_auto_compact_token_limit' -ErrorAction SilentlyContinue
    if ($compactLines) { foreach ($m in $compactLines) { Write-Line ('  ' + $m.Line.Trim()) } }
    else { Write-Line '  model_auto_compact_token_limit: not present' }
} else { Write-Line ('Codex config not found: ' + $config) }

Write-Section '2. CANONICAL OPENCLAW GLOBAL SESSION'
$canonical = Get-ChildItem -LiteralPath $OpenClaw -Recurse -File -Filter ($CanonicalSessionId + '*.jsonl') -ErrorAction SilentlyContinue |
    Where-Object { $PSItem.FullName -notlike '*codex-home*sessions*' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($canonical) {
    $lineCount = 0
    foreach ($line in Get-SharedLines $canonical.FullName) { $lineCount++ }
    Write-Line ('Path      : ' + $canonical.FullName)
    Write-Line ('Bytes     : ' + $canonical.Length)
    Write-Line ('MiB       : ' + [math]::Round($canonical.Length / 1MB, 2))
    Write-Line ('Lines     : ' + $lineCount)
    Write-Line ('LastWrite : ' + $canonical.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
    Write-Line ('Delta bytes vs uploaded 9,317,067-byte snapshot: ' + ($canonical.Length - $KnownCanonicalBytesAtUpload))
} else { Write-Line 'Canonical session file not found by session ID.' }

Write-Section '3. MONITOR USAGE / FAILURES — AUG 11'
$monitorEvents = New-Object System.Collections.Generic.List[object]
if (Test-Path -LiteralPath $TodayLog) {
    foreach ($line in Get-SharedLines $TodayLog) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $j = $line | ConvertFrom-Json
            if ($j.eventType -in @('turn-usage','model-usage')) { [void]$monitorEvents.Add($j) }
        } catch {}
    }

    $turns = @($monitorEvents | Where-Object { $PSItem.eventType -eq 'turn-usage' })
    $successful = @($turns | Where-Object { $null -ne $PSItem.usage -and $null -ne $PSItem.model })
    $failed = @($turns | Where-Object { $null -eq $PSItem.usage -or $null -eq $PSItem.model })
    $post = @($successful | Where-Object {
        try { ([datetime]::Parse([string]$PSItem.timestamp)).ToUniversalTime() -ge $PostFixUtc } catch { $false }
    })

    Write-Line ('Monitor file : ' + $TodayLog)
    Write-Line ('Turn-usage events total : ' + $turns.Count)
    Write-Line ('Successful turns        : ' + $successful.Count)
    Write-Line ('Failed/null-usage turns : ' + $failed.Count)
    Write-Line ('Successful turns post-fix: ' + $post.Count)

    foreach ($model in @('gpt-5.6-luna','gpt-5.6-sol')) {
        $m = @($post | Where-Object { $PSItem.model -eq $model } | Sort-Object timestamp)
        Write-Line
        Write-Line ('POST-FIX MODEL: ' + $model)
        Write-Line ('  turns: ' + $m.Count)
        if ($m.Count -gt 0) {
            $contexts = @($m | Where-Object { $null -ne $PSItem.contextUsedTokens } | ForEach-Object { [double]$PSItem.contextUsedTokens })
            $sumInput = ($m | ForEach-Object { if ($PSItem.usage) { [double]$PSItem.usage.input } else { 0 } } | Measure-Object -Sum).Sum
            $sumCache = ($m | ForEach-Object { if ($PSItem.usage -and $null -ne $PSItem.usage.cacheRead) { [double]$PSItem.usage.cacheRead } else { 0 } } | Measure-Object -Sum).Sum
            $sumOutput = ($m | ForEach-Object { if ($PSItem.usage) { [double]$PSItem.usage.output } else { 0 } } | Measure-Object -Sum).Sum
            $sumDuration = ($m | ForEach-Object { if ($null -ne $PSItem.durationMs) { [double]$PSItem.durationMs } else { 0 } } | Measure-Object -Sum).Sum
            Write-Line ('  provider input tokens total : ' + [long]$sumInput)
            Write-Line ('  cache-read tokens total     : ' + [long]$sumCache)
            Write-Line ('  output tokens total         : ' + [long]$sumOutput)
            if ($contexts.Count -gt 0) {
                Write-Line ('  first contextUsedTokens     : ' + [long]$contexts[0])
                Write-Line ('  last contextUsedTokens      : ' + [long]$contexts[-1])
                Write-Line ('  net context delta           : ' + [long]($contexts[-1] - $contexts[0]))
                Write-Line ('  min / max context           : ' + [long](($contexts | Measure-Object -Minimum).Minimum) + ' / ' + [long](($contexts | Measure-Object -Maximum).Maximum))
            }
            Write-Line ('  mean turn duration ms       : ' + [math]::Round($sumDuration / $m.Count, 0))
            Write-Line '  per-turn context sequence:'
            foreach ($e in $m) {
                $uInput = if ($e.usage) { $e.usage.input } else { $null }
                $uCache = if ($e.usage) { $e.usage.cacheRead } else { $null }
                $uOut = if ($e.usage) { $e.usage.output } else { $null }
                Write-Line ('    ' + $e.timestamp + ' ctx=' + $e.contextUsedTokens + ' input=' + $uInput + ' cache=' + $uCache + ' out=' + $uOut + ' ms=' + $e.durationMs + ' fallback=' + $e.fallbackUsed)
            }
        }
    }

    Write-Line
    Write-Line 'FAILED / NULL-USAGE TURN EVENTS:'
    foreach ($e in $failed) {
        Write-Line ('  ' + $e.timestamp + ' channel=' + $e.channelId + ' message=' + $e.messageId + ' provider=' + $e.provider + ' model=' + $e.model + ' duration=' + $e.durationMs)
    }

    Write-Line
    Write-Line 'CAPACITY-WINDOW EVENTS (01:20Z–01:25Z / 02:20–02:25 BST):'
    $capStart = $CapacityUtc.AddMinutes(-2)
    $capEnd = $CapacityUtc.AddMinutes(3)
    foreach ($e in @($monitorEvents | Where-Object {
        try {
            $t = ([datetime]::Parse([string]$PSItem.timestamp)).ToUniversalTime()
            $t -ge $capStart -and $t -le $capEnd
        } catch { $false }
    } | Sort-Object timestamp)) {
        $usageFlag = if($e.usage){'yes'}else{'null'}
        Write-Line ('  ' + $e.eventType + ' ' + $e.timestamp + ' channel=' + $e.channelId + ' model=' + $e.model + ' ctx=' + $e.contextUsedTokens + ' usage=' + $usageFlag + ' duration=' + $e.durationMs)
    }
} else { Write-Line ('Monitor log missing: ' + $TodayLog) }

Write-Section '4. NATIVE CODEX ROLLOUT INVENTORY — AUG 11'
$dayDir = Join-Path $RolloutRoot '2026\08\11'
$rollouts = @()
if (Test-Path -LiteralPath $dayDir) { $rollouts = @(Get-ChildItem -LiteralPath $dayDir -File -Filter 'rollout-*.jsonl' | Sort-Object LastWriteTime) }
Write-Line ('Rollout count: ' + $rollouts.Count)

$rolloutSummaries = New-Object System.Collections.Generic.List[object]
foreach ($file in $rollouts) {
    $models = New-Object System.Collections.Generic.HashSet[string]
    $lastTokens = $null
    $maxTokens = 0L
    $compactions = 0
    $userMessages = 0
    $userChars = 0L
    $assembledCount = 0
    $convContextCount = 0
    $runtimeContextCount = 0
    $conversationInfoCount = 0
    $previousMessagesCount = 0
    $postFixUser = New-Object System.Collections.Generic.List[object]
    $biggestUsers = New-Object System.Collections.Generic.List[object]
    $lineNo = 0

    foreach ($line in Get-SharedLines $file.FullName) {
        $lineNo++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $j = $line | ConvertFrom-Json } catch { continue }
        if ($null -ne $j.payload -and $null -ne $j.payload.model) {
            $ms = [string]$j.payload.model
            if ($ms -like 'gpt-5.6-*') { [void]$models.Add($ms) }
        }
        if ($j.type -eq 'event_msg' -and $j.payload.type -eq 'token_count' -and $null -ne $j.payload.info.last_token_usage) {
            $lt = [long]$j.payload.info.last_token_usage.total_tokens
            $lastTokens = $lt
            if ($lt -gt $maxTokens) { $maxTokens = $lt }
        }
        if ($j.type -eq 'compacted') { $compactions++ }
        if ($j.type -eq 'response_item' -and $j.payload.type -eq 'message' -and $j.payload.role -eq 'user') {
            $text = Get-TextFromMessagePayload $j.payload
            $len = $text.Length
            $flags = Marker-Flags $text
            $userMessages++
            $userChars += $len
            if ($flags.AssembledContext) { $assembledCount++ }
            if ($flags.ConversationContext) { $convContextCount++ }
            if ($flags.RuntimeContext) { $runtimeContextCount++ }
            if ($flags.ConversationInfo) { $conversationInfoCount++ }
            if ($flags.PreviousMessages) { $previousMessagesCount++ }
            $ts = $null
            try { $ts = ([datetime]::Parse([string]$j.timestamp)).ToUniversalTime() } catch {}
            $row = [pscustomobject]@{
                Line=$lineNo; Timestamp=$j.timestamp; Chars=$len
                Assembled=$flags.AssembledContext; ConvContext=$flags.ConversationContext
                Runtime=$flags.RuntimeContext; Info=$flags.ConversationInfo; Previous=$flags.PreviousMessages
            }
            [void]$biggestUsers.Add($row)
            if ($null -ne $ts -and $ts -ge $PostFixUtc) { [void]$postFixUser.Add($row) }
        }
    }

    $summary = [pscustomobject]@{
        File=$file.Name; Path=$file.FullName; Bytes=$file.Length
        MiB=[math]::Round($file.Length/1MB,2); LastWrite=$file.LastWriteTime
        Models=(@($models) -join ','); LastTokens=$lastTokens; MaxTokens=$maxTokens
        Compactions=$compactions; UserMessages=$userMessages; UserChars=$userChars
        Assembled=$assembledCount; ConvContext=$convContextCount; Runtime=$runtimeContextCount
        ConversationInfo=$conversationInfoCount; PreviousMessages=$previousMessagesCount
        PostFixUser=@($postFixUser)
        BiggestUsers=@($biggestUsers | Sort-Object Chars -Descending | Select-Object -First 10)
    }
    [void]$rolloutSummaries.Add($summary)

    Write-Line
    Write-Line ('FILE: ' + $summary.File)
    Write-Line ('  MiB=' + $summary.MiB + ' LastWrite=' + $summary.LastWrite.ToString('yyyy-MM-dd HH:mm:ss') + ' Models=' + $summary.Models)
    Write-Line ('  LastTokens=' + $summary.LastTokens + ' MaxTokens=' + $summary.MaxTokens + ' Compactions=' + $summary.Compactions)
    Write-Line ('  UserMessages=' + $summary.UserMessages + ' UserChars=' + $summary.UserChars)
    Write-Line ('  Markers: assembled=' + $summary.Assembled + ' conversation_context=' + $summary.ConvContext + ' runtime_context=' + $summary.Runtime + ' conversation_info=' + $summary.ConversationInfo + ' previous_messages=' + $summary.PreviousMessages)
}

Write-Section '5. POST-FIX NATIVE USER-HISTORY HYGIENE'
$postRows = @()
foreach ($s in $rolloutSummaries) {
    foreach ($r in $s.PostFixUser) {
        $postRows += [pscustomobject]@{
            File=$s.File; Line=$r.Line; Timestamp=$r.Timestamp; Chars=$r.Chars
            Assembled=$r.Assembled; ConvContext=$r.ConvContext; Runtime=$r.Runtime
            Info=$r.Info; Previous=$r.Previous
        }
    }
}
$postRows = @($postRows | Sort-Object Timestamp)
Write-Line ('Post-fix native role=user records: ' + $postRows.Count)
if ($postRows.Count -gt 0) {
    $chars = @($postRows | ForEach-Object { [double]$PSItem.Chars })
    $sortedChars = @($chars | Sort-Object)
    $medianIndex = [math]::Floor(($sortedChars.Count - 1) / 2)
    Write-Line ('Chars min / median-ish / max: ' + [long](($chars | Measure-Object -Minimum).Minimum) + ' / ' + [long]$sortedChars[$medianIndex] + ' / ' + [long](($chars | Measure-Object -Maximum).Maximum))
    Write-Line ('Records containing OpenClaw assembled context: ' + @($postRows | Where-Object Assembled).Count)
    Write-Line ('Records containing <conversation_context>      : ' + @($postRows | Where-Object ConvContext).Count)
    Write-Line ('Records containing runtime-context wrapper    : ' + @($postRows | Where-Object Runtime).Count)
    Write-Line ('Records containing Conversation info metadata : ' + @($postRows | Where-Object Info).Count)
    Write-Line ('Records containing previous-channel messages : ' + @($postRows | Where-Object Previous).Count)
    Write-Line
    Write-Line 'Largest 25 post-fix user records (content NOT printed):'
    foreach ($r in @($postRows | Sort-Object Chars -Descending | Select-Object -First 25)) {
        Write-Line ('  ' + $r.Timestamp + ' chars=' + $r.Chars + ' assembled=' + $r.Assembled + ' conv=' + $r.ConvContext + ' runtime=' + $r.Runtime + ' info=' + $r.Info + ' prev=' + $r.Previous + ' file=' + $r.File + ':' + $r.Line)
    }
}

Write-Section '6. COMPACTION CHECKPOINT HYGIENE'
foreach ($file in $rollouts) {
    $lineNo = 0
    foreach ($line in Get-SharedLines $file.FullName) {
        $lineNo++
        if ($line -notmatch '"type"\s*:\s*"compacted"') { continue }
        try { $j = $line | ConvertFrom-Json } catch { continue }
        if ($j.type -ne 'compacted') { continue }
        $rh = @($j.payload.replacement_history)
        $roleUser = 0
        $userChars = 0L
        $assembled = 0
        $conv = 0
        $runtime = 0
        $info = 0
        foreach ($item in $rh) {
            if ($item.type -eq 'message' -and $item.role -eq 'user') {
                $roleUser++
                $text = Get-TextFromMessagePayload $item
                $userChars += $text.Length
                $f = Marker-Flags $text
                if ($f.AssembledContext) { $assembled++ }
                if ($f.ConversationContext) { $conv++ }
                if ($f.RuntimeContext) { $runtime++ }
                if ($f.ConversationInfo) { $info++ }
            }
        }
        Write-Line ('Compacted event: ' + $file.Name + ':' + $lineNo + ' ts=' + $j.timestamp)
        Write-Line ('  replacement_history items=' + $rh.Count + ' role=user=' + $roleUser + ' userChars=' + $userChars)
        Write-Line ('  retained markers: assembled=' + $assembled + ' conversation_context=' + $conv + ' runtime_context=' + $runtime + ' conversation_info=' + $info)
    }
}

Write-Section '7. QUICK VERDICT INPUTS'
if ($postRows.Count -gt 0) {
    $maxPost = [long](($postRows | Measure-Object Chars -Maximum).Maximum)
    $avgPost = [math]::Round((($postRows | Measure-Object Chars -Average).Average),0)
    Write-Line ('Post-fix native user record avg chars: ' + $avgPost)
    Write-Line ('Post-fix native user record max chars: ' + $maxPost)
    Write-Line ('Post-fix giant assembled-context records: ' + @($postRows | Where-Object Assembled).Count)
}
Write-Line
Write-Line 'END OF READ-ONLY AUDIT'
Write-Host ""
Write-Host "Audit complete:"
Write-Host $Out
Write-Host ""
Write-Host "Upload that TXT file to Rook."
