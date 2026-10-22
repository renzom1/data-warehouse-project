<#
Purpose:
    Run one analysis script and save its output, so that every number in
    analysis/findings.md can be traced to a file in analysis/output/.

    Steps:
        1. Run scripts\validate.ps1. If the database does not match the
           baseline, stop: the analysis is not run on unvalidated data.
        2. Run the analysis script and write its output to
           analysis/output/<script name>.txt (UTF-8).
        3. Fail if the output contains MISMATCH (a control-total
           reconciliation in the script did not tie out).

Usage (from the repository root):
    scripts\run_analysis.ps1 -Script analysis\01_revenue_trends.sql -DatabaseName DataWarehouse_Test

DatabaseName is required and has no default, like the SQLCMD scripts.
#>
param(
    [Parameter(Mandatory = $true)] [string] $Script,
    [Parameter(Mandatory = $true)] [string] $DatabaseName,
    [string] $Server = '.\SQLEXPRESS'
)

$root = Split-Path $PSScriptRoot -Parent
$scriptPath = Resolve-Path $Script -ErrorAction Stop
$outDir = Join-Path $root 'analysis\output'
$outFile = Join-Path $outDir ([IO.Path]::GetFileNameWithoutExtension($scriptPath) + '.txt')

& (Join-Path $PSScriptRoot 'validate.ps1') -DatabaseName $DatabaseName -Server $Server | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Validation failed on $DatabaseName. Run scripts\validate.ps1 -DatabaseName $DatabaseName to see the mismatches."
    exit 1
}

New-Item -ItemType Directory -Force $outDir | Out-Null

sqlcmd -S $Server -E -C -b -W -s '|' -f 65001 -v "DatabaseName=$DatabaseName" -i $scriptPath -o $outFile
if ($LASTEXITCODE -ne 0) {
    Write-Error "sqlcmd failed for $Script. See $outFile."
    exit $LASTEXITCODE
}

$mismatches = Select-String -Path $outFile -Pattern 'MISMATCH' -SimpleMatch
if ($mismatches) {
    $mismatches | ForEach-Object { Write-Host $_.Line }
    Write-Error "Reconciliation MISMATCH in $outFile."
    exit 2
}

Write-Host "OK: validation passed, output saved to $outFile"
exit 0
