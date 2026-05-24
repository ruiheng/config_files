[CmdletBinding()]
param(
    [string]$InstallDir = "C:\Scripts",
    [int]$MaxWaitSeconds = 1800,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$scriptName = "Suspend-VMwareRunningVMs.ps1"
$sourceScript = Join-Path $PSScriptRoot $scriptName
$targetScript = Join-Path $InstallDir $scriptName
$shutdownScriptDir = "$env:SystemRoot\System32\GroupPolicy\Machine\Scripts\Shutdown"
$scriptsIni = "$env:SystemRoot\System32\GroupPolicy\Machine\Scripts\scripts.ini"
$groupPolicyScriptsBaseKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Shutdown\0"
$groupPolicyStateBaseKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Shutdown\0"
$systemPolicyKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

function Write-Step {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this installer from an elevated PowerShell session."
    }
}

function Ensure-Directory {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path) {
        return
    }

    if ($DryRun) {
        Write-Step "Would create directory: $Path"
        return
    }

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Write-Utf16File {
    param(
        [string]$Path,
        [string]$Content
    )

    if ($DryRun) {
        Write-Step "Would write file: $Path"
        return
    }

    [IO.File]::WriteAllText($Path, $Content, [Text.Encoding]::Unicode)
}

function Set-RegistryString {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Value
    )

    if ($DryRun) {
        Write-Step "Would set registry string: $Path $Name=$Value"
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType String -Force | Out-Null
}

function Set-RegistryDword {
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value
    )

    if ($DryRun) {
        Write-Step "Would set registry dword: $Path $Name=$Value"
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

function Get-ShutdownScriptIndex {
    param(
        [string]$BaseKey,
        [string]$ScriptPath
    )

    $max = -1

    if (-not (Test-Path -LiteralPath $BaseKey)) {
        return 0
    }

    foreach ($key in Get-ChildItem -LiteralPath $BaseKey -ErrorAction SilentlyContinue) {
        if ($key.PSChildName -notmatch "^\d+$") {
            continue
        }

        $index = [int]$key.PSChildName
        if ($index -gt $max) {
            $max = $index
        }

        $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        if ($props.Script -eq "powershell.exe" -and $props.Parameters -like "*$ScriptPath*") {
            return $index
        }
    }

    return $max + 1
}

function Install-ScriptsIniEntry {
    param(
        [string]$ScriptPath,
        [int]$Index
    )

    $cmdLine = "$($Index)CmdLine=powershell.exe"
    $parameters = "$($Index)Parameters=-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

    if (-not (Test-Path -LiteralPath $scriptsIni)) {
        Write-Utf16File $scriptsIni ("[Shutdown]" + [Environment]::NewLine + $cmdLine + [Environment]::NewLine + $parameters + [Environment]::NewLine)
        return
    }

    $lines = @(Get-Content -LiteralPath $scriptsIni)
    $out = New-Object System.Collections.Generic.List[string]
    $inShutdown = $false
    $foundShutdown = $false
    $wroteCmdLine = $false
    $wroteParameters = $false

    foreach ($line in $lines) {
        if ($line -match "^\s*\[(.+)\]\s*$") {
            if ($inShutdown) {
                if (-not $wroteCmdLine) { $out.Add($cmdLine) }
                if (-not $wroteParameters) { $out.Add($parameters) }
            }
            $inShutdown = $Matches[1] -ieq "Shutdown"
            if ($inShutdown) { $foundShutdown = $true }
            $out.Add($line)
            continue
        }

        if ($inShutdown -and $line -match "^\s*$($Index)CmdLine\s*=") {
            $out.Add($cmdLine)
            $wroteCmdLine = $true
            continue
        }

        if ($inShutdown -and $line -match "^\s*$($Index)Parameters\s*=") {
            $out.Add($parameters)
            $wroteParameters = $true
            continue
        }

        $out.Add($line)
    }

    if ($inShutdown) {
        if (-not $wroteCmdLine) { $out.Add($cmdLine) }
        if (-not $wroteParameters) { $out.Add($parameters) }
    }

    if (-not $foundShutdown) {
        if ($out.Count -gt 0 -and $out[$out.Count - 1] -ne "") {
            $out.Add("")
        }
        $out.Add("[Shutdown]")
        $out.Add($cmdLine)
        $out.Add($parameters)
    }

    Write-Utf16File $scriptsIni (($out -join [Environment]::NewLine) + [Environment]::NewLine)
}

function Install-ShutdownScriptRegistry {
    param(
        [string]$ScriptPath,
        [int]$Index
    )

    foreach ($baseKey in @($groupPolicyScriptsBaseKey, $groupPolicyStateBaseKey)) {
        Set-RegistryString $baseKey "DisplayName" "Local Group Policy"
        Set-RegistryString $baseKey "FileSysPath" "$env:SystemRoot\System32\GroupPolicy\Machine"
        Set-RegistryString $baseKey "GPO-ID" "LocalGPO"
        Set-RegistryString $baseKey "GPOName" "Local Group Policy"
        Set-RegistryString $baseKey "PSScriptOrder" "1"
        Set-RegistryDword $baseKey "SOM-ID" 0

        $scriptKey = Join-Path $baseKey ([string]$Index)
        Set-RegistryString $scriptKey "Script" "powershell.exe"
        Set-RegistryString $scriptKey "Parameters" "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        Set-RegistryDword $scriptKey "IsPowershell" 0
        Set-RegistryDword $scriptKey "ExecTime" 0
    }
}

if (-not (Test-Path -LiteralPath $sourceScript -PathType Leaf)) {
    throw "Source script not found: $sourceScript"
}

if (-not $DryRun) {
    Assert-Admin
}

Write-Step "Installing VMware shutdown suspend script..."
Ensure-Directory $InstallDir
Ensure-Directory $shutdownScriptDir

if ($DryRun) {
    Write-Step "Would copy: $sourceScript -> $targetScript"
} else {
    Copy-Item -LiteralPath $sourceScript -Destination $targetScript -Force
}

$scriptIndex = Get-ShutdownScriptIndex $groupPolicyScriptsBaseKey $targetScript
Install-ScriptsIniEntry $targetScript $scriptIndex
Install-ShutdownScriptRegistry $targetScript $scriptIndex

Set-RegistryDword $systemPolicyKey "MaxGPOScriptWait" $MaxWaitSeconds

Write-Step "Installed script: $targetScript"
Write-Step "Registered shutdown script via Local Group Policy at index $scriptIndex."
Write-Step "Set MaxGPOScriptWait=$MaxWaitSeconds seconds."
Write-Step "Log file will be: C:\Scripts\vmware-shutdown-suspend.log"
