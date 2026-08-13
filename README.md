# OpenClaw Monitoring

Read-only diagnostics and source-locating helpers used for Animeleague's Forge/OpenClaw performance, cache, prompt-growth and session investigations.

## Scope

This repository is for monitoring/audit tooling. Production Forge monitor logic lives in `Animeleague/forge-discord-monitor`; OpenClaw core patches live in `Animeleague/openclaw`.

The scripts here should be read-only unless their header explicitly says otherwise. Patch/deploy scripts and abandoned runtime experiments are intentionally not mixed into this repository.

## Current audit set

- `Audit-ForgeNativeTurnGrowthV1-FIXED2.ps1` — per-turn native Codex token/session growth with attribution of actual user text, Conversation Info, channel metadata, wrappers, assistant/reasoning/tool payloads.
- `Audit-ForgePostFixSessionV1.ps1` — post-fix session audit.
- `Audit-ForgeCodexThreadTransition.ps1` — native thread transition and payload/fingerprint audit.
- `Audit-ForgeCodexCompactionPayload.ps1` — compaction payload inspection.
- `Audit-ForgeCodexFreshThreadBootstrap.ps1` — fresh-thread bootstrap cost inspection.
- `Audit-ForgeToolResultCapImpact-PS51-v2.ps1` — PowerShell 5.1-compatible tool-result cap impact audit.
- `Audit-OpenClawBootstrapPrompt.ps1` — bootstrap prompt inspection.
- `Audit-ForgeSkillPromptLive-v2.ps1` — live skill prompt audit.
- `Audit-ForgeSkillReadInstructions.ps1` — skill-read instruction audit.
- `Audit-ForgeSkillReadsAfterV2.ps1` — post-v2 skill-read audit.
- `Audit-ForgeGifToolChain.ps1` — GIF/tool-chain investigation.
- `Inspect-ForgeOldNativeThreadTail.ps1` — inspect tail of older native thread state.
- `Locate-ForgeToolResultCaps.ps1` — locate OpenClaw tool-result truncation/middleware code.
- `Locate-ForgeToolHistoryPipeline.ps1` — locate tool-history persistence/rendering pipeline.
- `Locate-ForgePromptPolicySources.ps1` — locate prompt-policy sources.
- `Locate-ForgeDiscordRendererSource.ps1` — locate Discord renderer/source paths.
- `Locate-ForgeAgentsInjection.ps1` — locate AGENTS/bootstrap injection paths.
- `Locate-CodexPerTurnSkillRule.ps1` — locate per-turn Codex skill rule sources.
- `Locate-ForgeRenderedPrompt.ps1` — locate rendered prompt construction.
- `Locate-ForgeGifNativeToolChain.ps1` — locate native GIF/tool chain.

## Deliberately excluded

Intermediate broken/older revisions such as `Audit-ForgeNativeTurnGrowthV1.ps1`, `...-FIXED.ps1`, older tool-result-cap audit revisions, and patch scripts that actively modify OpenClaw are not treated as canonical monitoring tools.

The experimental `fix/codex-transient-runtime-context` OpenClaw branch is also not production state; that approach was rolled back and is retained only as historical branch evidence.
