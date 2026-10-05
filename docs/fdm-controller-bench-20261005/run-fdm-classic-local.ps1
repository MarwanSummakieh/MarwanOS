param()
$ErrorActionPreference = 'Stop'
$taskAppFolder = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../out/fdm-classic/test-app'))
$taskExe = Join-Path $taskAppFolder 'FDM.exe'
if (-not (Test-Path -LiteralPath $taskExe)) {
    throw 'The local FDM Classic build is missing. See docs/fdm-classic-local-build-20261005.md.'
}
$taskPreviousTestMode = $env:FDM_LOCAL_TEST
$taskPreviousControllerMode = $env:FDM_CONTROLLER_UI
try {
    $env:FDM_LOCAL_TEST = '1'
    $env:FDM_CONTROLLER_UI = '1'
    # Preserve the test environment instead of letting FDM relaunch itself.
    Start-Process -FilePath $taskExe -ArgumentList '-nelvcheck' -WorkingDirectory $taskAppFolder -WindowStyle Normal
} finally {
    if ($null -eq $taskPreviousTestMode) { Remove-Item Env:FDM_LOCAL_TEST -ErrorAction SilentlyContinue }
    else { $env:FDM_LOCAL_TEST = $taskPreviousTestMode }
    if ($null -eq $taskPreviousControllerMode) { Remove-Item Env:FDM_CONTROLLER_UI -ErrorAction SilentlyContinue }
    else { $env:FDM_CONTROLLER_UI = $taskPreviousControllerMode }
}
