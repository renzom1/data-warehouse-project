<#
Purpose:
    Claude Code PreToolUse hook. Blocks two kinds of tool calls before they run:

        1. Any sqlcmd / validate.ps1 / run_analysis.ps1 call that targets the
           author's original database DataWarehouse (not DataWarehouse_Test).
           CLAUDE.md: never write to it, reload it or drop it.
        2. Any edit of the source files under datasets/ (Edit/Write tools, or a
           shell command that writes, moves or deletes there). Decision 6 shows
           that a change to a source CSV changes the warehouse; it needs the
           author's explicit decision.

    Exit code 2 blocks the call and sends the message on stderr to Claude.
    Exit code 0 lets it through.

Configured in .claude/settings.json (matcher: Bash|PowerShell|Edit|Write|NotebookEdit).
#>

$raw = [Console]::In.ReadToEnd()
try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

$tool = $payload.tool_name
$toolInput = $payload.tool_input

function Block([string] $message) {
    [Console]::Error.WriteLine($message)
    exit 2
}

if ($tool -in @('Bash', 'PowerShell')) {
    $command = [string] $toolInput.command

    # DataWarehouse not followed by a word character, so DataWarehouse_Test passes.
    $targetsOriginal = $command -match '(?i)\bDataWarehouse(?![\w])'
    $runsSql = $command -match '(?i)\b(sqlcmd|Invoke-Sqlcmd|validate\.ps1|run_analysis\.ps1)\b'
    if ($targetsOriginal -and $runsSql) {
        Block 'Blocked by scripts/hooks/guard.ps1: this command targets the original DataWarehouse database. All work runs on DataWarehouse_Test (CLAUDE.md, "Databases"). If the author explicitly asked for this, ask them to run it themselves.'
    }

    $touchesDatasets = $command -match '(?i)datasets[\\/]'
    $writes = $command -match '(?i)(Set-Content|Add-Content|Out-File|Clear-Content|Remove-Item|Move-Item|Rename-Item|Copy-Item|New-Item|\brm\b|\bmv\b|\bcp\b|\bdel\b|>)'
    if ($touchesDatasets -and $writes) {
        Block 'Blocked by scripts/hooks/guard.ps1: this command may modify the source files in datasets/. Source CSVs are only changed by an explicit decision of the author (see decision 6). Ask the author first.'
    }
}

if ($tool -in @('Edit', 'Write', 'NotebookEdit')) {
    $path = [string] $toolInput.file_path
    if (-not $path) { $path = [string] $toolInput.notebook_path }
    if ($path -match '(?i)(^|[\\/])datasets[\\/]') {
        Block 'Blocked by scripts/hooks/guard.ps1: files in datasets/ are the source data and are not edited by the agent. A change here changes the warehouse (see decision 6). Ask the author first.'
    }
}

exit 0
