# for GIT
if [ -r "$HOME/.git-completion.sh" ]; then
    source "$HOME/.git-completion.sh"
fi
PS1='[\u@\h \W$(__git_ps1 " (%s)")]\$ '

export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    if command -v node >/dev/null 2>&1 && node --version >/dev/null 2>&1 \
        && command -v npm >/dev/null 2>&1 && npm --version >/dev/null 2>&1; then
        source "$NVM_DIR/nvm.sh" --no-use
    else
        source "$NVM_DIR/nvm.sh"
    fi
fi

# Clean PATH after all tool initializers have run.
config_files_clean_path() {
    local entry existing duplicate
    local -a original_path clean_path
    local IFS=:

    read -ra original_path <<< "$PATH"
    clean_path=("$HOME/.local/bin")
    for entry in "${original_path[@]}"; do
        case "$entry" in
            ""|/usr/local/games|/usr/games)
                continue
                ;;
        esac

        duplicate=0
        for existing in "${clean_path[@]}"; do
            if [[ "$entry" == "$existing" ]]; then
                duplicate=1
                break
            fi
        done
        if [[ $duplicate -eq 0 ]]; then
            clean_path+=("$entry")
        fi
    done

    PATH="${clean_path[*]}"
    export PATH
}
config_files_clean_path
unset -f config_files_clean_path
