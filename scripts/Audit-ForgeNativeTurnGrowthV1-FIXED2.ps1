# Audit-ForgeNativeTurnGrowthV1.ps1
# READ-ONLY audit of per-turn native Codex session growth for Forge.
# Does NOT modify OpenClaw config, sessions, rollouts, bindings, or logs.

$ErrorActionPreference = 'Stop'

$UserProfile = [Environment]::GetFolderPath('UserProfile')
$OpenClaw = Join-Path $UserProfile '.openclaw'
$CodexHome = Join-Path $OpenClaw 'agents\main\agent\codex-home'
$RolloutRoot = Join-Path $CodexHome 'sessions'
$Now = Get-Date
$DayDir = Join-Path $RolloutRoot (Join-Path $Now.ToString('yyyy') (Join-Path $Now.ToString('MM') $Now.ToString('dd')))
$Out = Join-Path ([Environment]::GetFolderPath('Desktop')) ('forge-native-turn-growth-audit-' + (Get-Date -Format 'yyyy-MM-dd') + '.txt')
$TurnsToShow = 12

function Write-Line([string]$Text = '') {
    Add-Content -LiteralPath $Out -Value $Text -Encoding UTF8
}

function Write-Section([string]$Title) {
    Write-Line
    Write-Line ('=' * 118)
    Write-Line $Title
    Write-Line ('=' * 118)
}

function Get-SharedLines([string]$Path) {
    $fs = [System.IO.File]::Open($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite)
    try {
        $sr = New-Object System.IO.StreamReader($fs)
        try { while (($line = $sr.ReadLine()) -ne $null) { $line } }
        finally { $sr.Dispose() }
    } finally { $fs.Dispose() }
}

function Get-TextFromMessagePayload($Payload) {
    if ($null -eq $Payload -or $null -eq $Payload.content) { return '' }
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Payload.content)) {
        if ($null -ne $item.text) { [void]$parts.Add([string]$item.text) }
        elseif ($null -ne $item.input_text) { [void]$parts.Add([string]$item.input_text) }
        elseif ($null -ne $item.output_text) { [void]$parts.Add([string]$item.output_text) }
    }
    return ($parts -join "`n")
}

function Get-JsonLength($Object) {
    if ($null -eq $Object) { return 0 }
    try { return ([string]($Object | ConvertTo-Json -Compress -Depth 50)).Length }
    catch { return ([string]$Object).Length }
}

function Get-ValueLength($Value) {
    if ($null -eq $Value) { return 0 }
    if ($Value -is [string]) { return ([string]$Value).Length }
    return (Get-JsonLength $Value)
}

function Get-FencedBlockRange([string]$Text, [string]$Marker) {
    $start = $Text.IndexOf($Marker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return [pscustomobject]@{ Start=-1; End=-1; Length=0 } }
    $f1 = $Text.IndexOf('```', $start, [System.StringComparison]::Ordinal)
    if ($f1 -lt 0) { return [pscustomobject]@{ Start=$start; End=$start+$Marker.Length; Length=$Marker.Length } }
    $f2 = $Text.IndexOf('```', $f1+3, [System.StringComparison]::Ordinal)
    if ($f2 -lt 0) { return [pscustomobject]@{ Start=$start; End=$Text.Length; Length=$Text.Length-$start } }
    $end = $f2 + 3
    return [pscustomobject]@{ Start=$start; End=$end; Length=$end-$start }
}

function Get-UserBreakdown([string]$Text) {
    if ($null -eq $Text) { $Text = '' }
    $info = Get-FencedBlockRange $Text 'Conversation info (untrusted metadata):'
    $channel = Get-FencedBlockRange $Text 'Discord channel metadata (untrusted metadata):'

    $prevStart = $Text.IndexOf('Previous messages from this Discord channel', [System.StringComparison]::Ordinal)
    $prevEnd = -1
    if ($prevStart -ge 0) {
        $candidate = $Text.IndexOf('Decide whether help is useful.', $prevStart, [System.StringComparison]::Ordinal)
        if ($candidate -ge 0) { $prevEnd = $candidate }
        elseif ($info.Start -gt $prevStart) { $prevEnd = $info.Start }
        else { $prevEnd = $Text.Length }
    }
    $prevLen = if ($prevStart -ge 0 -and $prevEnd -ge $prevStart) { $prevEnd-$prevStart } else { 0 }

    $actualStart = -1
    $requestMarker = 'Current user request:'
    $requestPos = $Text.IndexOf($requestMarker, [System.StringComparison]::Ordinal)
    if ($requestPos -ge 0) {
        $actualStart = $requestPos + $requestMarker.Length
    } else {
        $lastMetadataEnd = [math]::Max($info.End, $channel.End)
        if ($lastMetadataEnd -gt 0 -and $lastMetadataEnd -lt $Text.Length) { $actualStart = $lastMetadataEnd }
    }

    $actual = ''
    if ($actualStart -ge 0 -and $actualStart -le $Text.Length) {
        $actual = $Text.Substring($actualStart).Trim()
    } elseif ($info.Length -eq 0 -and $channel.Length -eq 0 -and -not $Text.StartsWith('[Forge Discord Monitor', [System.StringComparison]::Ordinal)) {
        $actual = $Text.Trim()
    }

    $actualLen = $actual.Length
    $other = $Text.Length - $actualLen - $info.Length - $channel.Length - $prevLen
    if ($other -lt 0) { $other = 0 }

    $preview = ($actual -replace '\s+', ' ').Trim()
    if ($preview.Length -gt 110) { $preview = $preview.Substring(0,110) + '...' }

    [pscustomobject]@{
        TotalChars=$Text.Length; ActualChars=$actualLen; ConversationInfo=$info.Length
        ChannelMetadata=$channel.Length; PreviousQuoted=$prevLen; OtherWrapper=$other; Preview=$preview
        HasAssembled=$Text.Contains('OpenClaw assembled context for this turn:')
        HasConvContext=$Text.Contains('<conversation_context>')
        HasRuntime=$Text.Contains('OpenClaw runtime context for this turn:')
        HasMonitor=$Text.StartsWith('[Forge Discord Monitor', [System.StringComparison]::Ordinal)
    }
}

function Read-Rollout([System.IO.FileInfo]$File) {
    $records = New-Object System.Collections.Generic.List[object]
    $lineNo = 0
    foreach ($line in Get-SharedLines $File.FullName) {
        $lineNo++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $j = $line | ConvertFrom-Json } catch { continue }
        $payloadType = ''; $role = ''
        if ($null -ne $j.payload) {
            if ($null -ne $j.payload.type) { $payloadType = [string]$j.payload.type }
            if ($null -ne $j.payload.role) { $role = [string]$j.payload.role }
        }
        [void]$records.Add([pscustomobject]@{
            Line=$lineNo; Timestamp=[string]$j.timestamp; Type=[string]$j.type
            PayloadType=$payloadType; Role=$role; Payload=$j.payload
            RawBytes=([System.Text.Encoding]::UTF8.GetByteCount($line)+1)
        })
    }
    return $records.ToArray()
}

function Find-LatestRolloutForModel([string]$Model) {
    if (-not (Test-Path -LiteralPath $DayDir)) { return $null }
    $files = @(Get-ChildItem -LiteralPath $DayDir -File -Filter 'rollout-*.jsonl' | Sort-Object LastWriteTime -Descending)
    foreach ($f in $files) {
        foreach ($line in Get-SharedLines $f.FullName) {
            if ($line.Contains('"' + $Model + '"')) { return $f }
        }
    }
    return $null
}

function Get-EndTokenCount($Group) {
    $last = $null
    foreach ($r in $Group) {
        if ($r.Type -eq 'event_msg' -and $r.PayloadType -eq 'token_count' -and $null -ne $r.Payload.info -and $null -ne $r.Payload.info.last_token_usage) {
            $last = [long]$r.Payload.info.last_token_usage.total_tokens
        }
    }
    return $last
}

function Get-GroupStats($Group, $PreviousEndTokens) {
    $userText=''; $assistantChars=0L; $reasoningChars=0L; $reasoningItems=0
    $toolCalls=0; $toolCallArgChars=0L; $toolOutputs=0; $toolOutputChars=0L
    $otherResponseItems=0; $otherResponsePayloadChars=0L; $rawBytes=0L

    foreach ($r in $Group) {
        $rawBytes += [long]$r.RawBytes
        if ($r.Type -ne 'response_item') { continue }
        $pt = [string]$r.PayloadType

        if ($pt -eq 'message') {
            if ($r.Role -eq 'user' -and [string]::IsNullOrEmpty($userText)) { $userText = Get-TextFromMessagePayload $r.Payload }
            elseif ($r.Role -eq 'assistant') { $assistantChars += (Get-TextFromMessagePayload $r.Payload).Length }
            continue
        }
        if ($pt -eq 'reasoning') {
            $reasoningItems++; $reasoningChars += Get-JsonLength $r.Payload; continue
        }
        if ($pt -match '(call_output|tool_output)$') {
            $toolOutputs++
            if ($null -ne $r.Payload.output) { $toolOutputChars += Get-ValueLength $r.Payload.output }
            elseif ($null -ne $r.Payload.result) { $toolOutputChars += Get-ValueLength $r.Payload.result }
            else { $toolOutputChars += Get-JsonLength $r.Payload }
            continue
        }
        if ($pt -match '(function_call|tool_call|custom_tool_call|web_search_call)$') {
            $toolCalls++
            if ($null -ne $r.Payload.arguments) { $toolCallArgChars += Get-ValueLength $r.Payload.arguments }
            elseif ($null -ne $r.Payload.input) { $toolCallArgChars += Get-ValueLength $r.Payload.input }
            else { $toolCallArgChars += Get-JsonLength $r.Payload }
            continue
        }
        $otherResponseItems++; $otherResponsePayloadChars += Get-JsonLength $r.Payload
    }

    $u = Get-UserBreakdown $userText
    $endTokens = Get-EndTokenCount $Group
    $delta = $null
    if ($null -ne $endTokens -and $null -ne $PreviousEndTokens) { $delta = [long]$endTokens-[long]$PreviousEndTokens }

    [pscustomobject]@{
        StartTimestamp=$Group[0].Timestamp; StartLine=$Group[0].Line; EndLine=$Group[-1].Line
        EndTokens=$endTokens; TokenDelta=$delta; RawBytes=$rawBytes; User=$u
        AssistantChars=$assistantChars; ReasoningItems=$reasoningItems; ReasoningPayloadChars=$reasoningChars
        ToolCalls=$toolCalls; ToolCallArgChars=$toolCallArgChars; ToolOutputs=$toolOutputs; ToolOutputChars=$toolOutputChars
        OtherResponseItems=$otherResponseItems; OtherResponsePayloadChars=$otherResponsePayloadChars
    }
}

function Audit-Model([string]$Model) {
    $file = Find-LatestRolloutForModel $Model
    Write-Section ('MODEL: ' + $Model)
    if ($null -eq $file) { Write-Line 'No rollout found today.'; return }

    Write-Line ('Rollout   : ' + $file.FullName)
    Write-Line ('MiB       : ' + [math]::Round($file.Length/1MB,2))
    Write-Line ('LastWrite : ' + $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
    Write-Line

    $records = @(Read-Rollout $file)
    $userIndices = New-Object System.Collections.Generic.List[int]
    for ($i=0; $i -lt $records.Count; $i++) {
        $r=$records[$i]
        if ($r.Type -eq 'response_item' -and $r.PayloadType -eq 'message' -and $r.Role -eq 'user') { [void]$userIndices.Add($i) }
    }
    if ($userIndices.Count -eq 0) { Write-Line 'No native role=user records found.'; return }

    $allStats = New-Object System.Collections.Generic.List[object]
    $previousEndTokens = $null
    for ($uix=0; $uix -lt $userIndices.Count; $uix++) {
        $start=$userIndices[$uix]; $end=$records.Count-1
        if ($uix+1 -lt $userIndices.Count) { $end=$userIndices[$uix+1]-1 }
        $group=@($records[$start..$end])
        $stats=Get-GroupStats $group $previousEndTokens
        [void]$allStats.Add($stats)
        if ($null -ne $stats.EndTokens) { $previousEndTokens=$stats.EndTokens }
    }

    $shown=@($allStats | Select-Object -Last $TurnsToShow)
    Write-Line ('Native role=user segments total : ' + $allStats.Count)
    Write-Line ('Showing last                  : ' + $shown.Count)
    Write-Line
    Write-Line 'tokenDelta = exact Codex total_tokens change vs previous completed native user segment.'
    Write-Line 'Character/byte categories are attribution evidence, not tokenizer-exact token counts.'
    Write-Line

    $n=0
    foreach ($s in $shown) {
        $n++
        $deltaText = if ($null -eq $s.TokenDelta) { 'n/a' } else { ('{0:+#;-#;0}' -f [long]$s.TokenDelta) }
        $endText = if ($null -eq $s.EndTokens) { 'n/a' } else { [string]$s.EndTokens }
        Write-Line ('TURN ' + $n + '  ts=' + $s.StartTimestamp + '  lines=' + $s.StartLine + '-' + $s.EndLine)
        Write-Line ('  native tokens : end=' + $endText + '  delta=' + $deltaText)
        Write-Line ('  user chars    : total=' + $s.User.TotalChars + ' actual=' + $s.User.ActualChars + ' conversationInfo=' + $s.User.ConversationInfo + ' channelMetadata=' + $s.User.ChannelMetadata + ' previousQuoted=' + $s.User.PreviousQuoted + ' other=' + $s.User.OtherWrapper)
        Write-Line ('  user flags    : monitor=' + $s.User.HasMonitor + ' assembled=' + $s.User.HasAssembled + ' conversation_context=' + $s.User.HasConvContext + ' runtime=' + $s.User.HasRuntime)
        if (-not [string]::IsNullOrWhiteSpace($s.User.Preview)) { Write-Line ('  actual preview: ' + $s.User.Preview) }
        Write-Line ('  assistant     : visibleChars=' + $s.AssistantChars)
        Write-Line ('  reasoning     : items=' + $s.ReasoningItems + ' payloadChars=' + $s.ReasoningPayloadChars)
        Write-Line ('  tools         : calls=' + $s.ToolCalls + ' argChars=' + $s.ToolCallArgChars + ' outputs=' + $s.ToolOutputs + ' outputChars=' + $s.ToolOutputChars)
        Write-Line ('  other native  : responseItems=' + $s.OtherResponseItems + ' payloadChars=' + $s.OtherResponsePayloadChars)
        Write-Line ('  rollout bytes : +' + $s.RawBytes)
        Write-Line
    }

    $ordinary=@($shown | Where-Object { $null -ne $PSItem.TokenDelta -and -not $PSItem.User.HasAssembled -and -not $PSItem.User.HasConvContext })
    if ($ordinary.Count -gt 0) {
        Write-Line 'ORDINARY-TURN SUMMARY (displayed tail only)'
        Write-Line ('  turns                         : ' + $ordinary.Count)
        Write-Line ('  avg native token growth       : ' + [math]::Round((($ordinary | Measure-Object TokenDelta -Average).Average),1))
        Write-Line ('  min / max native token growth : ' + (($ordinary | Measure-Object TokenDelta -Minimum).Minimum) + ' / ' + (($ordinary | Measure-Object TokenDelta -Maximum).Maximum))
        Write-Line ('  avg user total chars           : ' + [math]::Round((($ordinary | ForEach-Object { $PSItem.User.TotalChars } | Measure-Object -Average).Average),1))
        Write-Line ('  avg actual user chars          : ' + [math]::Round((($ordinary | ForEach-Object { $PSItem.User.ActualChars } | Measure-Object -Average).Average),1))
        Write-Line ('  avg metadata+wrapper chars     : ' + [math]::Round((($ordinary | ForEach-Object { $PSItem.User.TotalChars-$PSItem.User.ActualChars } | Measure-Object -Average).Average),1))
        Write-Line ('  avg assistant visible chars    : ' + [math]::Round((($ordinary | Measure-Object AssistantChars -Average).Average),1))
        Write-Line ('  avg reasoning payload chars    : ' + [math]::Round((($ordinary | Measure-Object ReasoningPayloadChars -Average).Average),1))
        Write-Line ('  total tool calls / outputs     : ' + (($ordinary | Measure-Object ToolCalls -Sum).Sum) + ' / ' + (($ordinary | Measure-Object ToolOutputs -Sum).Sum))
        Write-Line ('  total tool arg / output chars  : ' + (($ordinary | Measure-Object ToolCallArgChars -Sum).Sum) + ' / ' + (($ordinary | Measure-Object ToolOutputChars -Sum).Sum))
    }
}

Remove-Item -LiteralPath $Out -Force -ErrorAction SilentlyContinue
Write-Line 'FORGE NATIVE TURN GROWTH AUDIT V1'
Write-Line ('Generated local: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz'))
Write-Line 'READ-ONLY. No OpenClaw/Codex/session/config files are modified.'
Write-Line ('Rollout day directory: ' + $DayDir)
Write-Line ('Turns shown per model: ' + $TurnsToShow)

Audit-Model 'gpt-5.6-sol'
Audit-Model 'gpt-5.6-luna'

Write-Section 'END'
Write-Line 'Upload this TXT file to Rook for interpretation.'
Write-Host ''
Write-Host 'Audit complete:'
Write-Host $Out
Write-Host ''
