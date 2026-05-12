[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Interactive,
    [string]$BinDir
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $PSCommandPath
function Resolve-KnownFolder($EnvName, $FolderName) {
    $envValue = [Environment]::GetEnvironmentVariable($EnvName)
    if (-not [string]::IsNullOrWhiteSpace($envValue)) {
        return $envValue
    }
    return [Environment]::GetFolderPath($FolderName)
}

$HomeDir = Resolve-KnownFolder "USERPROFILE" "UserProfile"
$LocalAppData = Resolve-KnownFolder "LOCALAPPDATA" "LocalApplicationData"

$script:Linked = 0
$script:Skipped = 0
$script:Failed = 0
$script:BackedUp = 0
$script:PathChanged = $false
$script:CodexCliCommand = "codext"

function Write-Info($Message) { Write-Host "[INFO] $Message" }
function Write-Ok($Message) { Write-Host "[OK] $Message" }
function Write-Skip($Message) { Write-Host "[SKIP] $Message" }
function Write-Err($Message) { Write-Host "[ERR] $Message" }
function Write-Dry($Message) { Write-Host "[DRY RUN] $Message" }

function Test-LinkPath($Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Resolve-ExistingPath($Path) {
    try {
        return (Get-Item -LiteralPath $Path -Force).Target
    } catch {
        return $null
    }
}

function New-LinkPath($Source, $TargetPath, $Type) {
    try {
        New-Item -ItemType SymbolicLink -Path $TargetPath -Target $Source -Force | Out-Null
        Write-Ok "Linked $Type`: $TargetPath -> $Source"
        return $true
    } catch {
        Write-Info "Symlink unavailable; trying fallback: $TargetPath :: $($_.Exception.Message)"
    }

    if ($Type -eq "Directory") {
        try {
            New-Item -ItemType Junction -Path $TargetPath -Target $Source -Force | Out-Null
            Write-Ok "Linked Directory (junction): $TargetPath -> $Source"
            return $true
        } catch {
            Write-Err "Failed to create junction: $TargetPath :: $($_.Exception.Message)"
            return $false
        }
    }

    try {
        New-Item -ItemType HardLink -Path $TargetPath -Target $Source -Force | Out-Null
        Write-Ok "Linked File (hardlink): $TargetPath -> $Source"
        return $true
    } catch {
        Write-Err "Failed to create hardlink: $TargetPath :: $($_.Exception.Message)"
        return $false
    }
}

function Backup-ItemPath($Path) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backup = "$Path.backup.$stamp"

    if ($DryRun) {
        Write-Dry "Would backup: $Path -> $backup"
        return $true
    }

    try {
        Move-Item -LiteralPath $Path -Destination $backup
        $script:BackedUp += 1
        Write-Info "Backed up: $Path -> $backup"
        return $true
    } catch {
        Write-Err "Failed to backup: $Path :: $($_.Exception.Message)"
        $script:Failed += 1
        return $false
    }
}

function Read-ConflictAction($Path) {
    if (-not $Interactive) { return "skip" }

    Write-Host ""
    Write-Skip "Target already exists: $Path"
    $answer = Read-Host "[PROMPT] [s]kip, [b]ackup & replace, [f]orce replace, [c]ancel"
    switch -Regex ($answer) {
        "^(|s|skip)$" { return "skip" }
        "^(b|backup)$" { return "backup" }
        "^(f|force)$" { return "force" }
        "^(c|cancel)$" { return "cancel" }
        default { return "skip" }
    }
}

function Remove-ExistingPath($Path) {
    if ($DryRun) {
        Write-Dry "Would remove existing path: $Path"
        return $true
    }

    try {
        Remove-Item -LiteralPath $Path -Force -Recurse
        Write-Info "Removed: $Path"
        return $true
    } catch {
        Write-Err "Failed to remove: $Path :: $($_.Exception.Message)"
        $script:Failed += 1
        return $false
    }
}

function Ensure-Directory($Path) {
    if (Test-Path -LiteralPath $Path) { return }
    if ($DryRun) {
        Write-Dry "Would create directory: $Path"
        return
    }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Write-Info "Created directory: $Path"
}

function Link-ItemPath($RelativeSource, $TargetPath) {
    $source = Join-Path $ScriptDir $RelativeSource
    if (-not (Test-Path -LiteralPath $source)) {
        Write-Err "Source does not exist: $source"
        $script:Failed += 1
        return
    }

    $targetParent = Split-Path -Parent $TargetPath
    if ($targetParent) { Ensure-Directory $targetParent }

    if (Test-Path -LiteralPath $TargetPath) {
        if (Test-LinkPath $TargetPath) {
            $existingTarget = Resolve-ExistingPath $TargetPath
            if ($existingTarget -and ((Resolve-Path -LiteralPath $existingTarget).Path -eq (Resolve-Path -LiteralPath $source).Path)) {
                Write-Skip "Already linked: $TargetPath"
                $script:Skipped += 1
                return
            }
        }

        if ($Force) {
            if (-not (Backup-ItemPath $TargetPath)) { return }
        } else {
            $action = Read-ConflictAction $TargetPath
            if ($action -eq "cancel") { throw "Installation cancelled by user" }
            if ($action -eq "skip") {
                Write-Skip "Exists: $TargetPath"
                $script:Skipped += 1
                return
            }
            if ($action -eq "backup") {
                if (-not (Backup-ItemPath $TargetPath)) { return }
            }
            if ($action -eq "force") {
                if (-not (Remove-ExistingPath $TargetPath)) { return }
            }
        }
    }

    if ($DryRun) {
        Write-Dry "Would link: $TargetPath -> $source"
        $script:Linked += 1
        return
    }

    try {
        $sourceItem = Get-Item -LiteralPath $source -Force
        $type = if ($sourceItem.PSIsContainer) { "Directory" } else { "File" }
        if (New-LinkPath $source $TargetPath $type) {
            $script:Linked += 1
        } else {
            $script:Failed += 1
        }
    } catch {
        Write-Err "Failed to link: $TargetPath :: $($_.Exception.Message)"
        $script:Failed += 1
    }
}

function Link-ManagedFile($RelativeSource, $TargetPath) {
    $source = Join-Path $ScriptDir $RelativeSource
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        Write-Err "Source does not exist: $source"
        $script:Failed += 1
        return
    }

    $targetParent = Split-Path -Parent $TargetPath
    if ($targetParent) { Ensure-Directory $targetParent }

    if (Test-Path -LiteralPath $TargetPath) {
        $sameContent = $false
        try {
            $sameContent = (Get-FileHash -Algorithm SHA256 -LiteralPath $TargetPath).Hash -eq (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
        } catch {
            $sameContent = $false
        }

        if ($sameContent) {
            Write-Skip "Already current: $TargetPath"
            $script:Skipped += 1
            return
        }

        if (-not (Backup-ItemPath $TargetPath)) { return }
    }

    if ($DryRun) {
        Write-Dry "Would link managed file: $TargetPath -> $source"
        $script:Linked += 1
        return
    }

    if (New-LinkPath $source $TargetPath "File") {
        $script:Linked += 1
    } else {
        $script:Failed += 1
    }
}

function Ensure-JsonObjectProperty($Object, $Name) {
    $prop = $Object.PSObject.Properties[$Name]
    if (-not $prop) {
        $value = [pscustomobject]@{}
        Add-Member -InputObject $Object -MemberType NoteProperty -Name $Name -Value $value
        return $value
    }
    return $prop.Value
}

function Set-JsonProperty($Object, $Name, $Value) {
    if ($Object.PSObject.Properties[$Name]) {
        $Object.PSObject.Properties[$Name].Value = $Value
    } else {
        Add-Member -InputObject $Object -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Remove-JsonProperty($Object, $Name) {
    if ($Object.PSObject.Properties[$Name]) {
        $Object.PSObject.Properties.Remove($Name)
    }
}

function Configure-GeminiSettings($TargetPath) {
    $source = Join-Path $ScriptDir "ai-agent\gemini\settings.json"
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        Write-Err "Source does not exist: $source"
        $script:Failed += 1
        return
    }

    if ($DryRun) {
        Write-Dry "Would merge Gemini settings: $TargetPath"
        return
    }

    Ensure-Directory (Split-Path -Parent $TargetPath)
    $defaults = Get-Content -LiteralPath $source -Raw | ConvertFrom-Json
    $settings = [pscustomobject]@{}

    if (Test-Path -LiteralPath $TargetPath) {
        try {
            $settings = Get-Content -LiteralPath $TargetPath -Raw | ConvertFrom-Json
            if (-not $settings) { $settings = [pscustomobject]@{} }
        } catch {
            if (-not (Backup-ItemPath $TargetPath)) { return }
            $settings = [pscustomobject]@{}
        }
    }

    $general = Ensure-JsonObjectProperty $settings "general"
    Set-JsonProperty $general "enableAutoUpdate" $false

    $security = Ensure-JsonObjectProperty $settings "security"
    Set-JsonProperty $security "enablePermanentToolApproval" $true
    Set-JsonProperty $security "disableAlwaysAllow" $false

    $mcpServers = Ensure-JsonObjectProperty $settings "mcpServers"
    Remove-JsonProperty $mcpServers "workflow_mailbox"
    Remove-JsonProperty $mcpServers "agent_mailbox"

    foreach ($defaultServer in $defaults.mcpServers.PSObject.Properties) {
        if ($defaultServer.Name -eq "agent-mailbox") {
            Set-JsonProperty $mcpServers $defaultServer.Name $defaultServer.Value
        } elseif (-not $mcpServers.PSObject.Properties[$defaultServer.Name]) {
            Add-Member -InputObject $mcpServers -MemberType NoteProperty -Name $defaultServer.Name -Value $defaultServer.Value
        }
    }

    $settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $TargetPath -Encoding UTF8
    Write-Ok "Merged Gemini settings: $TargetPath"
}

function Install-Skills($ToolName, $TargetDir) {
    Write-Info "Installing $ToolName skills..."
    Ensure-Directory $TargetDir

    $sourceSkills = Join-Path $ScriptDir "ai-agent\skills"
    Get-ChildItem -LiteralPath $sourceSkills -Directory | ForEach-Object {
        Link-ItemPath "ai-agent\skills\$($_.Name)" (Join-Path $TargetDir $_.Name)
    }
}

function Test-Command($Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Resolve-InstallBinDir {
    if ($BinDir) {
        return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BinDir)
    }

    $defaultBin = Join-Path $HomeDir ".local\bin"
    if (-not $Interactive) {
        return $defaultBin
    }

    $answer = Read-Host "[PROMPT] Install command shims directory [$defaultBin]"
    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $defaultBin
    }
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($answer)
}

function Ensure-UserPathEntry($Path) {
    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()
    if ($userPath) {
        $parts = $userPath -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    $alreadyUser = $false
    foreach ($part in $parts) {
        if ($part.TrimEnd("\") -ieq $fullPath.TrimEnd("\")) {
            $alreadyUser = $true
            break
        }
    }

    $currentParts = $env:Path -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $alreadyCurrent = $false
    foreach ($part in $currentParts) {
        if ($part.TrimEnd("\") -ieq $fullPath.TrimEnd("\")) {
            $alreadyCurrent = $true
            break
        }
    }

    if ($alreadyUser) {
        Write-Ok "Command shim directory already in User PATH: $fullPath"
    } elseif ($DryRun) {
        Write-Dry "Would add to User PATH: $fullPath"
    } else {
        $newParts = @($parts + $fullPath)
        $newPath = $newParts -join ";"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        $savedPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if (-not (($savedPath -split ";") | Where-Object { $_.TrimEnd("\") -ieq $fullPath.TrimEnd("\") })) {
            Set-ItemProperty -Path "HKCU:\Environment" -Name "Path" -Value $newPath
            $savedPath = [Environment]::GetEnvironmentVariable("Path", "User")
        }
        if (-not (($savedPath -split ";") | Where-Object { $_.TrimEnd("\") -ieq $fullPath.TrimEnd("\") })) {
            Write-Err "Failed to persist User PATH entry: $fullPath"
            $script:Failed += 1
            return
        }
        $script:PathChanged = $true
        Write-Ok "Added to User PATH: $fullPath"
    }

    if (-not $alreadyCurrent) {
        $env:Path = "$fullPath;$env:Path"
        if (-not $DryRun) {
            Write-Info "Added to current process PATH: $fullPath"
        }
    }
}

function Ensure-Jq {
    if (Test-Command "jq") {
        Write-Ok "Found: jq"
        return
    }

    if ($DryRun) {
        Write-Dry "Would install missing jq with: winget install --id jqlang.jq -e --source winget --accept-package-agreements --accept-source-agreements"
        return
    }

    if (-not (Test-Command "winget")) {
        Write-Skip "Missing: jq; winget not found, install jq manually"
        return
    }

    Write-Info "jq not found; installing with winget..."
    winget install --id jqlang.jq -e --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0 -and (Test-Command "jq")) {
        Write-Ok "Installed: jq"
        return
    }

    Write-Skip "jq install attempted but jq is still not available in PATH; open a new terminal or install manually"
}

function Ensure-Codext {
    Write-Info "Checking codext..."

    if (Test-Command "codext") {
        $script:CodexCliCommand = "codext"
        Write-Ok "Found: codext"
        return
    }

    if (-not (Test-Command "npm")) {
        Write-Err "codext requires npm"
        $script:Failed += 1
        return
    }

    if ($DryRun) {
        Write-Dry "Would run: npm install -g @loongphy/codext"
        $script:CodexCliCommand = "codext"
        return
    }

    Write-Info "Running: npm install -g @loongphy/codext"
    npm install -g "@loongphy/codext"
    if ($LASTEXITCODE -eq 0 -and (Test-Command "codext")) {
        $script:CodexCliCommand = "codext"
        Write-Ok "Installed: codext"
        return
    }

    Write-Err "Command still unavailable after install: codext"
    $script:Failed += 1
}

function Ensure-TomlStringKey($File, $Section, $Key, $Value) {
    if ($DryRun) {
        Write-Dry "Would ensure [$Section] $Key in: $File"
        return
    }

    Ensure-Directory (Split-Path -Parent $File)
    $lines = @()
    if (Test-Path -LiteralPath $File) {
        $lines = @(Get-Content -LiteralPath $File)
    }

    $out = New-Object System.Collections.Generic.List[string]
    $inSection = $false
    $foundSection = $false
    $foundKey = $false
    $entry = "$Key = `"$Value`""
    $sectionHeader = "[$Section]"

    foreach ($line in $lines) {
        if ($line -match "^\s*\[$([Regex]::Escape($Section))\]\s*$") {
            $inSection = $true
            $foundSection = $true
            $out.Add($line)
            continue
        }

        if ($inSection -and $line -match "^\s*\[") {
            if (-not $foundKey) { $out.Add($entry) }
            $inSection = $false
        }

        if ($inSection -and $line -match "^\s*$([Regex]::Escape($Key))\s*=") {
            $out.Add($entry)
            $foundKey = $true
            continue
        }

        $out.Add($line)
    }

    if ($foundSection -and $inSection -and -not $foundKey) {
        $out.Add($entry)
    }

    if (-not $foundSection) {
        if ($out.Count -gt 0 -and $out[$out.Count - 1] -ne "") {
            $out.Add("")
        }
        $out.Add($sectionHeader)
        $out.Add($entry)
    }

    Set-Content -LiteralPath $File -Value $out -Encoding UTF8
    Write-Ok "Ensured [$Section] $Key in: $File"
}

function Configure-AgentDeckCodex {
    $agentDeckConfig = Join-Path $HomeDir ".agent-deck\config.toml"
    Ensure-TomlStringKey $agentDeckConfig "codex" "command" "codext"
}

function Show-Prerequisites {
    Write-Info "Checking AI workflow commands..."
    foreach ($cmd in @("git", "node", "npm", "bash", "codex", "codext", "claude", "gemini")) {
        if (Test-Command $cmd) {
            Write-Ok "Found: $cmd"
        } else {
            Write-Skip "Missing: $cmd"
        }
    }
    if ((Test-Command "pwsh") -or (Test-Command "powershell.exe")) {
        Write-Ok "Found: PowerShell runtime for adwf.cmd"
    } else {
        Write-Err "Missing PowerShell runtime: pwsh or powershell.exe"
        $script:Failed += 1
    }
    Ensure-Jq
    foreach ($cmd in @("agent-mailbox", "agent-deck")) {
        if (Test-Command $cmd) {
            Write-Ok "Found: $cmd"
        } else {
            Write-Skip "Missing: $cmd; AI workflow automation will be incomplete until this is installed"
        }
    }
}

function Invoke-LoggedCommand($Command, [string[]]$Arguments, $DryRunText) {
    if ($DryRun) {
        Write-Dry $DryRunText
        return $true
    }

    & $Command @Arguments
    if ($LASTEXITCODE -eq 0) {
        return $true
    }
    return $false
}

function Invoke-BestEffortCommand($Command, [string[]]$Arguments, $DryRunText) {
    if ($DryRun) {
        Write-Dry $DryRunText
        return
    }

    & $Command @Arguments | Out-Null
}

function Configure-AgentMailboxMcp {
    if (-not (Test-Command "agent-mailbox")) {
        Write-Skip "Skipping agent_mailbox MCP config (agent-mailbox not found)"
        return
    }

    Write-Info "Configuring agent_mailbox MCP servers..."

    if (Test-Command $script:CodexCliCommand) {
        Invoke-BestEffortCommand $script:CodexCliCommand @("mcp", "remove", "workflow_mailbox") "Would run: $script:CodexCliCommand mcp remove workflow_mailbox"
        Invoke-BestEffortCommand $script:CodexCliCommand @("mcp", "remove", "agent_mailbox") "Would run: $script:CodexCliCommand mcp remove agent_mailbox"
        if (Invoke-LoggedCommand $script:CodexCliCommand @("mcp", "add", "agent_mailbox", "--", "agent-mailbox", "mcp") "Would run: $script:CodexCliCommand mcp add agent_mailbox -- agent-mailbox mcp") {
            Write-Ok "Configured Codex MCP: agent_mailbox"
        } else {
            Write-Skip "Failed to configure Codex MCP: agent_mailbox"
        }
    } else {
        Write-Skip "Skipping Codex MCP config ($script:CodexCliCommand not found)"
    }

    if (Test-Command "claude") {
        if (Invoke-LoggedCommand "claude" @("mcp", "add", "-s", "user", "agent_mailbox", "--", "agent-mailbox", "mcp") "Would run: claude mcp add -s user agent_mailbox -- agent-mailbox mcp") {
            Write-Ok "Configured Claude MCP: agent_mailbox"
        } else {
            Write-Skip "Failed to configure Claude MCP: agent_mailbox"
        }
    } else {
        Write-Skip "Skipping Claude MCP config (claude not found)"
    }

    if (Test-Command "gemini") {
        Invoke-BestEffortCommand "gemini" @("mcp", "remove", "workflow_mailbox") "Would run: gemini mcp remove workflow_mailbox"
        Invoke-BestEffortCommand "gemini" @("mcp", "remove", "agent_mailbox") "Would run: gemini mcp remove agent_mailbox"
        Invoke-BestEffortCommand "gemini" @("mcp", "remove", "agent-mailbox") "Would run: gemini mcp remove agent-mailbox"
        if (Invoke-LoggedCommand "gemini" @("mcp", "add", "-s", "user", "agent_mailbox", "agent-mailbox", "mcp") "Would run: gemini mcp add -s user agent_mailbox agent-mailbox mcp") {
            Write-Ok "Configured Gemini MCP: agent_mailbox"
        } else {
            Write-Skip "Failed to configure Gemini MCP: agent_mailbox"
        }
    } else {
        Write-Skip "Skipping Gemini MCP config (gemini not found)"
    }
}

function Install-AiAgent($CommandBinDir) {
    $configHome = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HomeDir ".config" }

    Link-ItemPath "ai-agent" (Join-Path $configHome "ai-agent")

    $claudeDir = Join-Path $HomeDir ".claude"
    Link-ItemPath "ai-agent\CLAUDE.md" (Join-Path $claudeDir "CLAUDE.md")
    Link-ItemPath "ai-agent\modules" (Join-Path $claudeDir "modules")
    Link-ItemPath "ai-agent\claude\statusline-command.sh" (Join-Path $claudeDir "statusline-command.sh")
    Install-Skills "Claude Code" (Join-Path $claudeDir "skills")

    $codexDir = Join-Path $HomeDir ".codex"
    Link-ItemPath "ai-agent\AGENTS.md" (Join-Path $codexDir "AGENTS.md")
    Link-ItemPath "ai-agent\modules" (Join-Path $codexDir "modules")
    Link-ItemPath "ai-agent\codex\rules\agent-deck-workflow.rules" (Join-Path $codexDir "rules\agent-deck-workflow.rules")
    Install-Skills "Codex" (Join-Path $codexDir "skills")

    $geminiDir = Join-Path $HomeDir ".gemini"
    Link-ItemPath "ai-agent\GEMINI.md" (Join-Path $geminiDir "GEMINI.md")
    Configure-GeminiSettings (Join-Path $geminiDir "settings.json")
    Link-ItemPath "ai-agent\modules" (Join-Path $geminiDir "modules")
    Link-ManagedFile "ai-agent\gemini\policies\agent-deck-workflow.toml" (Join-Path $geminiDir "policies\agent-deck-workflow.toml")

    $agentsSkills = Join-Path $HomeDir ".agents\skills"
    if (Test-Path -LiteralPath $agentsSkills) {
        Install-Skills "Gemini CLI shared" $agentsSkills
    } else {
        Install-Skills "Gemini CLI" (Join-Path $geminiDir "skills")
    }

    Link-ManagedFile "ai-agent\bin\adwf.ps1" (Join-Path $CommandBinDir "adwf.ps1")
    Link-ManagedFile "ai-agent\bin\adwf.cmd" (Join-Path $CommandBinDir "adwf.cmd")
    Ensure-UserPathEntry $CommandBinDir
    Ensure-Codext
    Configure-AgentDeckCodex
    Configure-AgentMailboxMcp
}

Write-Info "========================================"
Write-Info "  Config Files Installation Script"
Write-Info "  OS detected: Windows"
if ($DryRun) { Write-Info "  MODE: DRY RUN" }
elseif ($Force) { Write-Info "  MODE: FORCE" }
elseif ($Interactive) { Write-Info "  MODE: INTERACTIVE" }
Write-Info "========================================"
Write-Host ""
Write-Info "Source directory: $ScriptDir"
Write-Info "Target home: $HomeDir"
$CommandBinDir = Resolve-InstallBinDir
Write-Info "Command shim directory: $CommandBinDir"

Link-ItemPath "gitconfig.win" (Join-Path $HomeDir ".gitconfig")
Link-ItemPath "gitignore" (Join-Path $HomeDir ".gitignore")

$nvimDir = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME "nvim" } else { Join-Path $LocalAppData "nvim" }
Link-ItemPath "nvim" $nvimDir

Install-AiAgent $CommandBinDir
Show-Prerequisites

Write-Host ""
Write-Info "========================================"
Write-Info "  Installation Summary"
Write-Info "========================================"
Write-Host "  Linked:   $script:Linked"
Write-Host "  Skipped:  $script:Skipped"
Write-Host "  Backed up: $script:BackedUp"
Write-Host "  Failed:   $script:Failed"
if ($script:PathChanged) {
    Write-Info "Open a new terminal for the updated User PATH to apply everywhere."
}

if ($script:Failed -gt 0) {
    exit 1
}
