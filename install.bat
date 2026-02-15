@echo off
setlocal EnableDelayedExpansion

:: Config Files Installation Script for Windows
:: Creates symbolic links for all configuration files
::
:: Usage: install.bat [OPTIONS]
::
:: Options:
::   --dry-run     Show what would be done without making changes
::   --force       Backup and replace existing files
::   --help        Show this help message

:: =============================================================================
:: Configuration
:: =============================================================================

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: Command line flags
set DRY_RUN=0
set FORCE=0
set INTERACTIVE=0

:: Counters
set /a linked=0
set /a skipped=0
set /a failed=0
set /a backed_up=0

:: Check if running in a terminal that supports ANSI colors
set "USE_COLOR=1"
for /f "tokens=2 delims=[]" %%a in ('ver') do set "WIN_VER=%%a"

:: =============================================================================
:: Command Line Parsing
:: =============================================================================

:parse_args
if "%~1"=="" goto :args_done
if /i "%~1"=="--dry-run" (
    set DRY_RUN=1
    shift
    goto :parse_args
)
if /i "%~1"=="--force" (
    set FORCE=1
    shift
    goto :parse_args
)
if /i "%~1"=="--interactive" (
    set INTERACTIVE=1
    shift
    goto :parse_args
)
if /i "%~1"=="-i" (
    set INTERACTIVE=1
    shift
    goto :parse_args
)
if /i "%~1"=="--help" goto :show_help
if /i "%~1"=="-h" goto :show_help
if /i "%~1"=="/h" goto :show_help
if /i "%~1"=="/?" goto :show_help

echo Unknown option: %~1
goto :show_help

:args_done

:: =============================================================================
:: Helper Functions (as labels with call)
:: =============================================================================

goto :main

:log_info
if %USE_COLOR%==1 (
    echo [INFO] %~1
) else (
    echo [INFO] %~1
)
exit /b 0

:log_ok
if %USE_COLOR%==1 (
    echo [OK] %~1
) else (
    echo [OK] %~1
)
exit /b 0

:log_warn
echo [SKIP] %~1
exit /b 0

:log_error
echo [ERR] %~1
exit /b 0

:log_dry
echo [DRY RUN] %~1
exit /b 0

:: Backup a file/directory before replacing it
:: %1: path to backup
:backup_item
set "item=%~1"
for /f "tokens=2-4 delims=/ " %%a in ('date /t') do (
    for /f "tokens=1-2 delims=: " %%d in ('time /t') do (
        set "TIMESTAMP=%%c%%a%%b_%%d%%e"
    )
)
set "backup_name=%item%.backup.%TIMESTAMP%"

if %DRY_RUN%==1 (
    call :log_dry "Would backup: %item% -> %backup_name%"
    exit /b 0
)

if exist "%item%" (
    move "%item%" "%backup_name%" > nul 2>&1
    if !errorlevel!==0 (
        call :log_info "Backed up: %item% -> %backup_name%"
        set /a backed_up+=1
        exit /b 0
    ) else (
        call :log_error "Failed to backup: %item%"
        exit /b 1
    )
)
exit /b 0

:: Create a symbolic link
:: %1: source (relative to SCRIPT_DIR)
:: %2: target (absolute path)
:link_file
set "src=%SCRIPT_DIR%\%~1"
set "dst=%~2"

:: Check if source exists
if not exist "%src%" (
    call :log_error "Source does not exist: %src%"
    set /a failed+=1
    exit /b 1
)

:: Create parent directory if needed
for %%F in ("%dst%") do set "dst_dir=%%~dpF"
if not exist "%dst_dir%" (
    if %DRY_RUN%==1 (
        call :log_dry "Would create directory: %dst_dir%"
    ) else (
        mkdir "%dst_dir%" 2> nul
        if exist "%dst_dir%" (
            call :log_info "Created directory: %dst_dir%"
        )
    )
)

:: Check if target already exists
if exist "%dst%" (
    :: Check if it's a symlink (junction or symlink)
    dir "%dst%" | findstr "<JUNCTION><SYMLINK><SYMLINKD>" > nul 2>&1
    if !errorlevel!==0 (
        :: It's a symlink - check if it points to the right place
        for /f "tokens=*" %%a in ('dir "%dst%" ^| findstr "<JUNCTION><SYMLINK><SYMLINKD>"') do (
            set "link_info=%%a"
        )

        :: Check if pointing to our source
        echo !link_info! | findstr /i "%src:\=\\%" > nul 2>&1
        if !errorlevel!==0 (
            call :log_warn "Already linked: %dst%"
            set /a skipped+=1
            exit /b 0
        ) else (
            :: Different symlink
            if %FORCE%==1 (
                if %DRY_RUN%==1 (
                    call :log_dry "Would remove symlink: %dst%"
                ) else (
                    rmdir "%dst%" 2> nul || del "%dst%" 2> nul
                    call :log_info "Removed old symlink: %dst%"
                )
            ) else if %INTERACTIVE%==1 (
                call :prompt_user "%dst%"
                set "action=!ERRORLEVEL!"
                if !action!==0 (
                    set /a skipped+=1
                    exit /b 0
                ) else if !action!==1 (
                    call :backup_item "%dst%"
                    if !ERRORLEVEL!==1 (
                        set /a failed+=1
                        exit /b 1
                    )
                ) else if !action!==2 (
                    rmdir "%dst%" 2> nul || del "%dst%" 2> nul
                    call :log_info "Removed: %dst%"
                ) else if !action!==3 (
                    call :log_info "Installation cancelled by user"
                    exit /b 1
                )
            ) else (
                call :log_warn "Different symlink exists: %dst%"
                set /a skipped+=1
                exit /b 0
            )
        )
    ) else (
        :: It's a regular file or directory
        if %FORCE%==1 (
            call :backup_item "%dst%"
            if !ERRORLEVEL!==1 (
                set /a failed+=1
                exit /b 1
            )
            if %DRY_RUN%==1 (
                call :log_dry "Would link: %dst% -> %src%"
                set /a linked+=1
                exit /b 0
            )
        ) else if %INTERACTIVE%==1 (
            call :prompt_user "%dst%"
            set "action=!ERRORLEVEL!"
            if !action!==0 (
                set /a skipped+=1
                exit /b 0
            ) else if !action!==1 (
                call :backup_item "%dst%"
                if !ERRORLEVEL!==1 (
                    set /a failed+=1
                    exit /b 1
                )
            ) else if !action!==2 (
                rmdir /s /q "%dst%" 2> nul || del /f /q "%dst%" 2> nul
                call :log_info "Removed: %dst%"
            ) else if !action!==3 (
                call :log_info "Installation cancelled by user"
                exit /b 1
            )
        ) else (
            call :log_warn "File exists (not a symlink): %dst%"
            set /a skipped+=1
            exit /b 0
        )
    )
)

:: Create the symlink
if %DRY_RUN%==1 (
    call :log_dry "Would link: %dst% -> %src%"
    set /a linked+=1
    exit /b 0
)

:: Determine if source is a directory or file
if exist "%src%\*" (
    :: It's a directory
    mklink /d "%dst%" "%src%" > nul 2>&1
) else (
    :: It's a file
    mklink "%dst%" "%src%" > nul 2>&1
)

if !errorlevel!==0 (
    call :log_ok "Linked: %dst% -> %src%"
    set /a linked+=1
    exit /b 0
) else (
    call :log_error "Failed to link: %dst%"
    call :log_info "Note: Creating symlinks on Windows requires Administrator privileges or Developer Mode"
    set /a failed+=1
    exit /b 1
)

:: Prompt user for action when target exists
:: Returns: 0=skip, 1=backup, 2=replace, 3=cancel
:prompt_user
set "target=%~1"
echo.
call :log_warn "Target already exists: %target%"
:prompt_loop
echo [PROMPT] [s]kip, [b]ackup ^& replace, [f]orce replace, [S]kip all, [B]ackup all, [F]orce all, [c]ancel:
set /p "response="
if /i "%response%"=="s" exit /b 0
if /i "%response%"=="skip" exit /b 0
if "%response%"=="" exit /b 0
if /i "%response%"=="b" exit /b 1
if /i "%response%"=="backup" exit /b 1
if /i "%response%"=="f" exit /b 2
if /i "%response%"=="force" exit /b 2
if /i "%response%"=="S" exit /b 0
if /i "%response%"=="skip all" exit /b 0
if /i "%response%"=="B" exit /b 1
if /i "%response%"=="backup all" exit /b 1
if /i "%response%"=="F" exit /b 2
if /i "%response%"=="force all" exit /b 2
if /i "%response%"=="c" exit /b 3
if /i "%response%"=="cancel" exit /b 3
echo Invalid option. Please try again.
goto :prompt_loop

:: =============================================================================
:: Installation Functions
:: =============================================================================

:install_home_configs
call :log_info "Installing home directory dotfiles..."

:: Git config (Windows version)
call :link_file "gitconfig.ruiheng.win" "%USERPROFILE%\.gitconfig"

exit /b 0

:install_nvim_config
call :log_info "Installing Neovim configuration..."

:: Neovim on Windows uses %LOCALAPPDATA%\nvim
set "NVIM_CONFIG_DIR=%LOCALAPPDATA%\nvim"

:: Also check for XDG_CONFIG_HOME
if defined XDG_CONFIG_HOME (
    set "NVIM_CONFIG_DIR=%XDG_CONFIG_HOME%\nvim"
)

call :link_file "nvim" "%NVIM_CONFIG_DIR%"

exit /b 0

:check_nvim
nvim --version > nul 2>&1
if !errorlevel!==0 (
    for /f "tokens=*" %%a in ('nvim --version ^| findstr "NVIM"') do (
        call :log_info "Found: %%a"
    )
    exit /b 0
) else (
    call :log_warn "Neovim not found in PATH"
    exit /b 1
)

:setup_nvim
call :log_info "Setting up Neovim configuration..."

call :check_nvim
if !errorlevel!==1 (
    call :log_warn "Neovim setup incomplete - Neovim not found"
    echo.
    call :log_info "To install Neovim on Windows:"
    echo.
    echo   # Using winget (Windows 10/11):
    echo   winget install Neovim.Neovim
    echo.
    echo   # Or download from:
    echo   https://github.com/neovim/neovim/releases
    echo.
    exit /b 1
)

:: Check if config is linked
if defined XDG_CONFIG_HOME (
    set "NVIM_CONFIG=%XDG_CONFIG_HOME%\nvim"
) else (
    set "NVIM_CONFIG=%LOCALAPPDATA%\nvim"
)

dir "%NVIM_CONFIG%" | findstr "<SYMLINKD>" > nul 2>&1
if !errorlevel!==0 (
    call :log_ok "Neovim config linked at: %NVIM_CONFIG%"
)

call :log_info "Neovim setup complete."
call :log_info "  - Lazy.nvim will bootstrap itself on first nvim start"
call :log_info "  - All plugins will be automatically installed"
call :log_info "  - Run 'nvim' to complete setup"
exit /b 0

:: =============================================================================
:: Main
:: =============================================================================

:main
call :log_info "========================================"
call :log_info "  Config Files Installation Script"
call :log_info "  OS detected: Windows"
if %DRY_RUN%==1 (
    call :log_info "  MODE: DRY RUN (no changes will be made)"
) else if %FORCE%==1 (
    call :log_info "  MODE: FORCE (existing files will be backed up)"
) else if %INTERACTIVE%==1 (
    call :log_info "  MODE: INTERACTIVE (will prompt on conflicts)"
)
call :log_info "========================================"
echo.

call :log_info "Source directory: %SCRIPT_DIR%"
call :log_info "Target home: %USERPROFILE%"

:: Install configs
call :install_home_configs
call :install_nvim_config

:: Setup Neovim
call :setup_nvim

:: Print summary
echo.
call :log_info "========================================"
call :log_info "  Installation Summary"
call :log_info "========================================"
echo   Linked:   %linked%
echo   Skipped:  %skipped%
if %backed_up% gtr 0 (
    echo   Backed up: %backed_up%
)
echo   Failed:   %failed%
echo.

if %DRY_RUN%==1 (
    call :log_info "Dry run complete. No changes were made."
    call :log_info "Run without --dry-run to apply changes."
    exit /b 0
)

if %failed% gtr 0 (
    call :log_error "Some operations failed. Please review the output above."
    exit /b 1
) else (
    call :log_ok "Installation completed successfully!"
    exit /b 0
)

:show_help
echo Config Files Installation Script for Windows
echo.
echo Usage: install.bat [OPTIONS]
echo.
echo Options:
echo   --dry-run         Show what would be done without making changes
echo   --force           Backup and replace existing files
echo   --interactive, -i Prompt when target exists ^(asks: skip/backup/replace/all^)
echo   --help, -h, /h, /?  Show this help message
echo.
echo Examples:
echo   install.bat                   # Standard installation
echo   install.bat --dry-run         # Preview changes
echo   install.bat --force           # Replace existing configs (backs them up)
echo   install.bat --interactive     # Prompt for each conflict
echo.
echo Note: Creating symlinks on Windows requires Administrator privileges
echo       or Developer Mode enabled in Windows Settings.
exit /b 0
