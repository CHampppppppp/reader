$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Run this script on Windows 11 x64.' }
$root = Split-Path $PSScriptRoot -Parent
dotnet publish (Join-Path $root 'Sources/Reader.Windows/Reader.Windows.csproj') -c Release -r win-x64 --self-contained true -o (Join-Path $root 'build')
if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
Write-Host 'Built windows/build/Qingdu.Windows.exe. Default launch uses the offline fixture; --website opens WeRead.'
