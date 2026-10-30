# Shows the current tunnel URL and copies the full app address to the clipboard.
$urlFile = Join-Path $PSScriptRoot 'current-url.txt'
if (Test-Path $urlFile) {
    $url = (Get-Content $urlFile -Raw).Trim()
    $app = $url + '/v1/parking-community'
    Write-Host "目前 tunnel 網址：$url"
    Write-Host "在手機 App『測試伺服器網址』貼上：$app"
    Set-Clipboard $app
    Write-Host '（已複製到剪貼簿）'
} else {
    Write-Host '未找到網址：tunnel 可能仍在啟動（看 tunnel.log），或尚未安裝 cloudflared。'
}
