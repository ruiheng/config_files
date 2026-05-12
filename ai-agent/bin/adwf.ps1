[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AdwfArgs
)

$ErrorActionPreference = "Stop"

function Resolve-SelfPath {
    $path = $PSCommandPath
    $item = Get-Item -LiteralPath $path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        $target = $item.Target
        if ($target -is [array]) {
            $target = $target[0]
        }
        if ($target) {
            if ([IO.Path]::IsPathRooted($target)) {
                return $target
            }
            return Join-Path (Split-Path -Parent $path) $target
        }
    }
    return $path
}

$SelfPath = Resolve-SelfPath
$SelfDir = Split-Path -Parent $SelfPath
$AiAgentRoot = Split-Path -Parent $SelfDir
$WorkflowScripts = Join-Path $AiAgentRoot "skills\agent-deck-workflow\scripts"

function Show-Usage {
    @"
Usage:
  adwf <command> [args...]

Commands:
  resolve-tool-command
  acquire-active-task-lock
  send-delegate-with-active-task-lock
  prepare-workspaces
  prepare-planner-workspace
  planner-closeout-batch
  archive-and-remove-planner-group-sessions
  archive-and-remove-task-sessions
  closeout-health-gate
  ensure-planner-scoped-session
  ensure-supervised-planner-session
  prune-task-branches
  notify-workflow-event
  init-permissions
  send-and-wake

Notes:
  Skills should call this stable adwf entrypoint instead of direct .sh/.ps1 paths.
  Commands with Node implementations run natively on Windows/Linux/macOS.
  Legacy Bash-backed commands still require Git Bash/MSYS2 on native Windows until migrated.
"@ | Write-Output
}

function Require-Command($Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "Missing required command: $Name"
    }
    return $cmd.Source
}

function Test-Executable($Path) {
    return ($Path -and (Test-Path -LiteralPath $Path -PathType Leaf))
}

function Resolve-BashCommand {
    $candidates = @()
    $allowWslBash = $false
    if ($env:ADWF_BASH) {
        $candidates += $env:ADWF_BASH
        $allowWslBash = $true
    }

    if ($IsWindows -or $env:OS -eq "Windows_NT") {
        $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
        $candidates += @(
            (Join-Path $env:ProgramFiles "Git\bin\bash.exe"),
            (Join-Path $env:ProgramFiles "Git\usr\bin\bash.exe"),
            (Join-Path $env:LocalAppData "Programs\Git\bin\bash.exe"),
            (Join-Path $env:LocalAppData "Programs\Git\usr\bin\bash.exe"),
            "C:\msys64\usr\bin\bash.exe",
            "C:\msys64\mingw64\bin\bash.exe"
        )
        if ($programFilesX86) {
            $candidates += @(
                (Join-Path $programFilesX86 "Git\bin\bash.exe"),
                (Join-Path $programFilesX86 "Git\usr\bin\bash.exe")
            )
        }
    }

    $pathBashes = Get-Command -All bash -ErrorAction SilentlyContinue | ForEach-Object { $_.Source }
    $candidates += $pathBashes

    $seen = @{}
    foreach ($candidate in $candidates) {
        if (-not (Test-Executable $candidate)) { continue }
        $resolvedPath = (Resolve-Path -LiteralPath $candidate).Path
        if (($IsWindows -or $env:OS -eq "Windows_NT") -and -not $allowWslBash) {
            if ($resolvedPath -match "\\Windows\\System32\\bash\.exe$" -or $resolvedPath -match "\\Microsoft\\WindowsApps\\bash\.exe$") {
                continue
            }
        }

        $key = $resolvedPath.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        try {
            & $candidate --version *> $null
            if ($LASTEXITCODE -eq 0) {
                return $candidate
            }
        } catch {
            continue
        }
    }

    throw "Missing usable Git Bash/MSYS2 bash. Install Git Bash/MSYS2, or set ADWF_BASH to a specific bash executable."
}

function ConvertTo-BashPath($Bash, $Path) {
    if (-not ($IsWindows -or $env:OS -eq "Windows_NT")) {
        return $Path
    }

    $converted = & $Bash -lc 'if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; elif command -v wslpath >/dev/null 2>&1; then wslpath -u "$1"; else printf "%s\n" "$1"; fi' "adwf-path" $Path
    if ($LASTEXITCODE -ne 0 -or -not $converted) {
        throw "Failed to convert Windows path for bash: $Path"
    }
    return $converted[0]
}

function Invoke-NodeScript($ScriptName, [string[]]$RemainingArgs) {
    $node = Require-Command "node"
    $script = Join-Path $WorkflowScripts $ScriptName
    if (-not (Test-Path -LiteralPath $script)) {
        throw "Missing workflow script: $script"
    }
    & $node $script @RemainingArgs
    exit $LASTEXITCODE
}

function Invoke-WorkflowScript($CommandName, [string[]]$RemainingArgs) {
    $nodeScript = "$CommandName.js"
    $nodePath = Join-Path $WorkflowScripts $nodeScript
    if (Test-Path -LiteralPath $nodePath) {
        Invoke-NodeScript $nodeScript $RemainingArgs
    }

    $bashScript = "$CommandName.sh"
    $bashPath = Join-Path $WorkflowScripts $bashScript
    if (Test-Path -LiteralPath $bashPath) {
        Invoke-BashScript $bashScript $RemainingArgs
    }

    throw "Unknown workflow command: $CommandName"
}

function Invoke-BashScript($ScriptName, [string[]]$RemainingArgs) {
    $bash = Resolve-BashCommand
    $script = Join-Path $WorkflowScripts $ScriptName
    if (-not (Test-Path -LiteralPath $script)) {
        throw "Missing workflow script: $script"
    }
    $bashScript = ConvertTo-BashPath $bash $script
    & $bash $bashScript @RemainingArgs
    exit $LASTEXITCODE
}

if (-not $AdwfArgs -or $AdwfArgs.Count -eq 0) {
    Show-Usage
    exit 2
}

$command = $AdwfArgs[0]
$remaining = if ($AdwfArgs.Count -gt 1) { $AdwfArgs[1..($AdwfArgs.Count - 1)] } else { @() }

$normalized = $command -replace '\.sh$', '' -replace '\.js$', ''

try {
    switch ($normalized) {
        { $_ -in @("-h", "--help", "help") } {
            Show-Usage
            exit 0
        }
        "resolve-tool-command" {
            $configPath = Join-Path $AiAgentRoot "config\tool-profiles.toml"
            Invoke-NodeScript "resolve-tool-command.js" (@("--config", $configPath) + $remaining)
        }
        "init-permissions" {
            Invoke-WorkflowScript "agent-deck-workflow-init-permissions" $remaining
        }
        "agent-deck-workflow-init-permissions" {
            Invoke-WorkflowScript "agent-deck-workflow-init-permissions" $remaining
        }
        "send-and-wake" {
            Invoke-WorkflowScript "adwf-send-and-wake" $remaining
        }
        "adwf-send-and-wake" {
            Invoke-WorkflowScript "adwf-send-and-wake" $remaining
        }
        default {
            Invoke-WorkflowScript $normalized $remaining
        }
    }
} catch {
    Write-Host "[ERR] $($_.Exception.Message)"
    exit 1
}
