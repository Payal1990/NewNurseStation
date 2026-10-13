<#
  Publish & deploy the Nurse Station (Razor) app to IIS.
  Run on a machine that has the .NET 8 SDK installed.

  Examples:
    # First deploy (copies everything, including web.config):
    .\publish.ps1 -DeployPath "C:\inetpub\NurseStation" -AppPool "NurseStation"

    # Later deploys (keeps the server's web.config + appsettings.Production.json):
    .\publish.ps1 -DeployPath "C:\inetpub\NurseStation" -AppPool "NurseStation"

  Notes:
    * web.config and appsettings.Production.json on the server are PRESERVED after the
      first deploy, so your live connection string / Legacy URL / SSO secret are never
      overwritten by a redeploy.
    * Needs the .NET 8 "ASP.NET Core Hosting Bundle" on the target IIS server (see README).
#>
param(
  [Parameter(Mandatory = $true)][string]$DeployPath,   # IIS physical path for the app
  [string]$AppPool = "",                               # IIS app-pool name (optional but recommended)
  [string]$Configuration = "Release",
  [string]$PublishDir = "$PSScriptRoot\publish"
)

$ErrorActionPreference = "Stop"
$proj = Join-Path $PSScriptRoot "NurseStationRazor.csproj"

Write-Host "1/5  Publishing ($Configuration)..." -ForegroundColor Cyan
dotnet publish $proj -c $Configuration -o $PublishDir --nologo
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed." }

New-Item -ItemType Directory -Force -Path $DeployPath | Out-Null

# Take the app offline so its DLLs aren't locked while we copy.
Write-Host "2/5  Taking app offline..." -ForegroundColor Cyan
$offline = Join-Path $DeployPath "app_offline.htm"
Set-Content -Path $offline -Value "<h1>Updating, back in a moment...</h1>" -Encoding utf8

if ($AppPool) {
  try { Import-Module WebAdministration -ErrorAction Stop; Stop-WebAppPool -Name $AppPool -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 } catch {}
}

# Preserve server-managed files: keep an existing web.config / appsettings.Production.json,
# never wipe the stdout logs folder, and leave the offline marker alone until the end.
$exclude = @("app_offline.htm")
if (Test-Path (Join-Path $DeployPath "web.config"))                   { $exclude += "web.config" }
if (Test-Path (Join-Path $DeployPath "appsettings.Production.json"))  { $exclude += "appsettings.Production.json" }

Write-Host "3/5  Copying to $DeployPath (preserving: $($exclude -join ', '))..." -ForegroundColor Cyan
robocopy $PublishDir $DeployPath /MIR /XF $exclude /XD logs /NFL /NDL /NJH /NJS /NP
if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)." }
$global:LASTEXITCODE = 0

New-Item -ItemType Directory -Force -Path (Join-Path $DeployPath "logs") | Out-Null

Write-Host "4/5  Bringing app back online..." -ForegroundColor Cyan
if ($AppPool) { try { Start-WebAppPool -Name $AppPool } catch {} }
Remove-Item $offline -ErrorAction SilentlyContinue

Write-Host "5/5  Done. Deployed to $DeployPath" -ForegroundColor Green
