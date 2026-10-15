# Builds Starfield.scr into .\dist. Requires the .NET 8 SDK.
#   .\build.ps1                      self-contained single file (~70 MB, runs anywhere)
#   .\build.ps1 -FrameworkDependent  small, needs the .NET 8 Desktop Runtime on the target PC
# The WebView2 Runtime must be installed on the target PC (preinstalled on Windows 11).
param([switch]$FrameworkDependent)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$sc = if ($FrameworkDependent) { 'false' } else { 'true' }
dotnet publish Starfield.csproj -c Release -r win-x64 --self-contained $sc `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o dist

Move-Item -Force dist\Starfield.exe dist\Starfield.scr
Write-Host "Built dist\Starfield.scr"
Write-Host "Install: right-click Starfield.scr > Install, or copy to C:\Windows\System32"
