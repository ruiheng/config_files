[CmdletBinding()]
param(
    [string]$VmrunPath,
    [string]$LogPath = "C:\Scripts\vmware-shutdown-suspend.log",
    [int]$SoftTimeoutSeconds = 300,
    [int]$HardTimeoutSeconds = 900
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)

    $parent = Split-Path -Parent $LogPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    "$(Get-Date -Format s) $Message" | Out-File -FilePath $LogPath -Append -Encoding utf8
}

function Resolve-VmrunPath {
    if ($VmrunPath) {
        if (Test-Path -LiteralPath $VmrunPath -PathType Leaf) {
            return $VmrunPath
        }
        throw "vmrun.exe not found: $VmrunPath"
    }

    $candidates = @(
        "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe",
        "C:\Program Files\VMware\VMware Workstation\vmrun.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    $command = Get-Command "vmrun.exe" -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw "vmrun.exe not found"
}

function ConvertTo-NativeArgument {
    param([string]$Argument)

    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }

    $result = '"'
    $backslashes = 0
    foreach ($char in $Argument.ToCharArray()) {
        if ($char -eq '\') {
            $backslashes += 1
            continue
        }

        if ($char -eq '"') {
            $result += '\' * (($backslashes * 2) + 1)
            $result += '"'
            $backslashes = 0
            continue
        }

        if ($backslashes -gt 0) {
            $result += '\' * $backslashes
            $backslashes = 0
        }
        $result += $char
    }

    if ($backslashes -gt 0) {
        $result += '\' * ($backslashes * 2)
    }

    $result += '"'
    return $result
}

function ConvertTo-NativeArgumentList {
    param([string[]]$Arguments)

    return (($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join " ")
}

function Invoke-Vmrun {
    param(
        [string]$Vmrun,
        [string[]]$Arguments,
        [int]$TimeoutSeconds
    )

    $outputFile = [IO.Path]::GetTempFileName()
    $errorFile = [IO.Path]::GetTempFileName()

    try {
        $argumentList = ConvertTo-NativeArgumentList $Arguments
        $process = Start-Process -FilePath $Vmrun `
            -ArgumentList $argumentList `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $outputFile `
            -RedirectStandardError $errorFile

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try {
                Stop-Process -Id $process.Id -Force
            } catch {
                Write-Log "Failed to stop timed-out vmrun process $($process.Id): $($_.Exception.Message)"
            }
            return [pscustomobject]@{
                ExitCode = -1
                Output = "Timed out after $TimeoutSeconds seconds"
            }
        }

        $stdout = Get-Content -LiteralPath $outputFile -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content -LiteralPath $errorFile -Raw -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = (($stdout, $stderr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine
        }
    } finally {
        Remove-Item -LiteralPath $outputFile, $errorFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-RunningVmPaths {
    param([string]$Vmrun)

    $result = Invoke-Vmrun -Vmrun $Vmrun -Arguments @("list") -TimeoutSeconds 60
    if ($result.ExitCode -ne 0) {
        throw "vmrun list failed with exit code $($result.ExitCode): $($result.Output)"
    }

    $lines = $result.Output -split "\r?\n"
    foreach ($line in $lines | Select-Object -Skip 1) {
        $path = $line.Trim()
        if ($path) {
            $path
        }
    }
}

$vmrun = Resolve-VmrunPath
Write-Log "VMware shutdown suspend started. vmrun=$vmrun"

try {
    $runningVms = @(Get-RunningVmPaths -Vmrun $vmrun)
} catch {
    Write-Log "Failed to list running VMs: $($_.Exception.Message)"
    exit 1
}

if ($runningVms.Count -eq 0) {
    Write-Log "No running VMs found."
    exit 0
}

$failed = 0
foreach ($vmx in $runningVms) {
    Write-Log "Soft suspend started: $vmx"
    $soft = Invoke-Vmrun -Vmrun $vmrun -Arguments @("suspend", $vmx, "soft") -TimeoutSeconds $SoftTimeoutSeconds

    if ($soft.Output) {
        Write-Log "Soft suspend output for $vmx`: $($soft.Output)"
    }

    if ($soft.ExitCode -eq 0) {
        Write-Log "Soft suspend finished: $vmx"
        continue
    }

    Write-Log "Soft suspend failed for $vmx with exit code $($soft.ExitCode). Trying hard suspend."
    $hard = Invoke-Vmrun -Vmrun $vmrun -Arguments @("suspend", $vmx, "hard") -TimeoutSeconds $HardTimeoutSeconds

    if ($hard.Output) {
        Write-Log "Hard suspend output for $vmx`: $($hard.Output)"
    }

    if ($hard.ExitCode -eq 0) {
        Write-Log "Hard suspend finished: $vmx"
    } else {
        $failed += 1
        Write-Log "Hard suspend failed for $vmx with exit code $($hard.ExitCode)"
    }
}

Write-Log "VMware shutdown suspend finished. failures=$failed"
exit $failed
