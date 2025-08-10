param(
  [Parameter(Mandatory = $true)]
  [string]$TunnelToken
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$installDir = 'C:\cloudflared'
$exePath    = "$installDir\cloudflared.exe"

Write-Host "Creating $installDir"
New-Item -ItemType Directory -Path $installDir -Force | Out-Null

Write-Host "Downloading cloudflared.exe"
Invoke-WebRequest `
  -Uri 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe' `
  -OutFile $exePath -UseBasicParsing

Write-Host "Installing cloudflared Windows service"
& $exePath service install $TunnelToken
if ($LASTEXITCODE) { throw "cloudflared install failed with exit code $LASTEXITCODE" }

Write-Host "Cloudflared service status:"
& $exePath service status
