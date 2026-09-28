$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'build-windows.ps1')
$root = Split-Path $PSScriptRoot -Parent
$id = [Guid]::NewGuid().ToString('N')
$stdout = Join-Path $root "build/windows-test-$id.stdout.log"
$stderr = Join-Path $root "build/windows-test-$id.stderr.log"
$process = Start-Process -FilePath (Join-Path $root 'build/windows/Qingdu.Windows.exe') -ArgumentList '--self-test' -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
if (-not $process.WaitForExit(45000)) {
    $process.Kill()
    throw "Prototype test timed out. Logs: $stdout and $stderr"
}
$process.WaitForExit()
Get-Content $stdout
Get-Content $stderr
if ($process.ExitCode -ne 0) { throw "Prototype tests failed (exit $($process.ExitCode))." }
