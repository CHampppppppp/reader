$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'build-windows.ps1')
$root = Split-Path $PSScriptRoot -Parent
$id = [Guid]::NewGuid().ToString('N')
$stdout = Join-Path $root "build/windows-test-$id.stdout.log"
$stderr = Join-Path $root "build/windows-test-$id.stderr.log"
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = Join-Path $root 'build/Qingdu.Windows.exe'
$startInfo.Arguments = '--self-test'
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$process = New-Object System.Diagnostics.Process
$process.StartInfo = $startInfo
try {
    if (-not $process.Start()) { throw 'Prototype test could not start.' }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit(45000)
    if ($timedOut) {
        $process.Kill()
    }
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    [System.IO.File]::WriteAllText($stdout, $stdoutTask.GetAwaiter().GetResult())
    [System.IO.File]::WriteAllText($stderr, $stderrTask.GetAwaiter().GetResult())
    Get-Content $stdout
    Get-Content $stderr
    if ($timedOut) { throw "Prototype test timed out. Logs: $stdout and $stderr" }
    if ($exitCode -ne 0) { throw "Prototype tests failed (exit $exitCode)." }
} finally {
    $process.Dispose()
}
