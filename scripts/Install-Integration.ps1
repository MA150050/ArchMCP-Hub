#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [ValidateSet('revit', 'rhino', '3dsmax', '3ds-max', 'autocad', 'sketchup')] [string] $HostId,
    [Parameter(Mandatory = $true)] [string] $HostVersion,
    [string] $InstallPath = '',
    [string] $AgentName = 'OpenCode',
    [ValidateSet('Install', 'Repair', 'Verify', 'Uninstall')] [string] $Action = 'Install',
    [switch] $NonInteractive
)
$ErrorActionPreference = 'Stop'

trap {
    Write-Host ''
    Write-Host "[ERROR] Dispatcher failed: $($_.Exception.Message)" -ForegroundColor Red
    if (-not $NonInteractive) {
        Write-Host ''
        Read-Host 'Press Enter to close this window'
    }
    exit 1
}

$normalizedId = $HostId.ToLowerInvariant().Replace('-', '')
$scriptMap = @{
    'revit'    = 'Install-Revit-OpenCode.ps1'
    'rhino'    = 'Install-Rhino-MCP.ps1'
    '3dsmax'   = 'Install-3dsMax-MCP.ps1'
    'autocad'  = 'Install-AutoCAD-MCP.ps1'
    'sketchup' = 'Install-SketchUp-MCP.ps1'
}

$targetScript = Join-Path $PSScriptRoot $scriptMap[$normalizedId]
if (-not (Test-Path -LiteralPath $targetScript -PathType Leaf)) {
    throw "Integration script not found: $targetScript"
}

$invokeParams = @{
    HostVersion = $HostVersion
    AgentName   = $AgentName
    Action      = $Action
}
if ($normalizedId -ne 'revit') {
    $invokeParams['InstallPath'] = $InstallPath
}
if ($NonInteractive) {
    $invokeParams['NonInteractive'] = $true
}

& $targetScript @invokeParams
exit $LASTEXITCODE
