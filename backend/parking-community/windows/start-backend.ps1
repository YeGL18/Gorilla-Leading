# Runs the parking-community backend; output is appended to backend.log.
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
& python run_local.py --wait-for-config 2>&1 | ForEach-Object {
    Add-Content -Path (Join-Path $PSScriptRoot 'backend.log') -Value ((Get-Date).ToString('s') + ' ' + "$_")
}
