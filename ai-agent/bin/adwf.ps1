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
  Bash-backed commands require Git Bash, MSYS2, or WSL bash in PATH until migrated natively.
"@ | Write-Output
}

function Require-Command($Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "Missing required command: $Name"
    }
    return $cmd.Source
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

function Invoke-BashScript($ScriptName, [string[]]$RemainingArgs) {
    $bash = Require-Command "bash"
    $script = Join-Path $WorkflowScripts $ScriptName
    if (-not (Test-Path -LiteralPath $script)) {
        throw "Missing workflow script: $script"
    }
    & $bash $script @RemainingArgs
    exit $LASTEXITCODE
}

if (-not $AdwfArgs -or $AdwfArgs.Count -eq 0) {
    Show-Usage
    exit 2
}

$command = $AdwfArgs[0]
$remaining = if ($AdwfArgs.Count -gt 1) { $AdwfArgs[1..($AdwfArgs.Count - 1)] } else { @() }

$normalized = $command -replace '\.sh$', '' -replace '\.js$', ''

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
        Invoke-BashScript "agent-deck-workflow-init-permissions.sh" $remaining
    }
    "agent-deck-workflow-init-permissions" {
        Invoke-BashScript "agent-deck-workflow-init-permissions.sh" $remaining
    }
    "send-and-wake" {
        Invoke-BashScript "adwf-send-and-wake.sh" $remaining
    }
    "adwf-send-and-wake" {
        Invoke-BashScript "adwf-send-and-wake.sh" $remaining
    }
    default {
        $scriptName = "$normalized.sh"
        Invoke-BashScript $scriptName $remaining
    }
}
