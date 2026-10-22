<#
Purpose:
    Claude Code Stop hook. Before the agent ends its turn, checks that every
    analysis script has an up-to-date saved output:

        analysis/0N_<topic>.sql  ->  analysis/output/0N_<topic>.txt

    An output is stale when it is missing or older than its script. Then the
    numbers in findings.md may not come from the current script, so the hook
    asks the agent to run scripts\run_analysis.ps1 first (definition of done,
    step 3). It does not query the database.

    If the agent was already sent back once in this turn (stop_hook_active),
    the hook does not block again, to avoid a loop when the run cannot be done
    (for example, SQL Server is down); it only warns the author.

Configured in .claude/settings.json (event: Stop).
#>

$raw = [Console]::In.ReadToEnd()
try { $payload = $raw | ConvertFrom-Json } catch { $payload = $null }

$root = $env:CLAUDE_PROJECT_DIR
if (-not $root) { $root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }

$analysisDir = Join-Path $root 'analysis'
$outputDir = Join-Path $analysisDir 'output'

$stale = @()
Get-ChildItem -Path $analysisDir -Filter '*.sql' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d{2}_.+\.sql$' } |
    ForEach-Object {
        $out = Join-Path $outputDir ($_.BaseName + '.txt')
        if (-not (Test-Path $out)) {
            $stale += "$($_.Name) (no saved output)"
        } elseif ($_.LastWriteTime -gt (Get-Item $out).LastWriteTime) {
            $stale += "$($_.Name) (changed after its output was saved)"
        }
    }

if ($stale.Count -eq 0) { exit 0 }

$list = $stale -join '; '

if ($payload -and $payload.stop_hook_active) {
    @{ systemMessage = "Warning: analysis outputs are still out of date: $list. The numbers in findings.md may not match the current scripts." } |
        ConvertTo-Json -Compress
    exit 0
}

@{
    decision = 'block'
    reason   = "Analysis outputs are out of date: $list. Run scripts\run_analysis.ps1 -Script analysis\<script>.sql -DatabaseName DataWarehouse_Test for each one and check that it passes before finishing (CLAUDE.md, definition of done, step 3). If it cannot be run, say so explicitly to the author."
} | ConvertTo-Json -Compress
exit 0
