<#
Purpose:
    Run scripts\validate.sql against a database and exit with its result:
    0 when every check matches the baseline, non-zero otherwise.

Usage (from the repository root):
    scripts\validate.ps1 -DatabaseName DataWarehouse_Test
    scripts\validate.ps1 -DatabaseName DataWarehouse_Test -Server .\SQLEXPRESS

DatabaseName is required and has no default, like the SQLCMD scripts.
#>
param(
    [Parameter(Mandatory = $true)] [string] $DatabaseName,
    [string] $Server = '.\SQLEXPRESS'
)

$sql = Join-Path $PSScriptRoot 'validate.sql'

# The value has no drive letter, so it can be passed unquoted (see README).
sqlcmd -S $Server -E -C -b -W -s '|' -v "DatabaseName=$DatabaseName" -i $sql
exit $LASTEXITCODE
