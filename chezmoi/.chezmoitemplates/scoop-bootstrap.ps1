{{ template "refresh-path.ps1" . -}}
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host 'scoop が見つからないためインストールします...'
    Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
}
