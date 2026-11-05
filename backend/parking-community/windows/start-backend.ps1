# Keep the backend alive if Python exits; Ctrl+C still stops this supervisor.
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$log = Join-Path $PSScriptRoot 'backend.log'
$mutex = New-Object System.Threading.Mutex($false, 'Global\GorillaParkingBackendSupervisor')
$ownsMutex = $false
try {
    try { $ownsMutex = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { Write-Host 'Backend supervisor is already running.'; exit 0 }
    $python = (Get-Command python.exe -ErrorAction Stop).Source
    $delay = 5
    while ($true) {
        # Never start a second server over an existing listener.
        if (Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue) {
            Start-Sleep -Seconds 10
            continue
        }
        if ((Test-Path $log) -and (Get-Item $log).Length -gt 10MB) {
            Move-Item -Force $log ($log + '.previous')
        }
        $started = Get-Date
        Add-Content $log ($started.ToString('s') + ' Supervisor starting backend.')
        & $python -u (Join-Path $root 'run_local.py') --wait-for-config 2>&1 | ForEach-Object {
            Add-Content $log ((Get-Date).ToString('s') + ' ' + "$_")
        }
        $code = $LASTEXITCODE
        if (((Get-Date) - $started).TotalSeconds -ge 300) { $delay = 5 }
        Add-Content $log ((Get-Date).ToString('s') + " Backend exited (code $code); retry in $delay seconds.")
        Start-Sleep -Seconds $delay
        $delay = [Math]::Min(60, $delay * 2)
    }
} finally {
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
