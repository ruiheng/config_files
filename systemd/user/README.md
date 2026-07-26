# Systemd user units

## Install clipboard services

```bash
./install.sh
systemctl --user daemon-reload
systemctl --user disable --now clipboard-sync.service
systemctl --user enable --now cliphist.service
systemctl --user enable --now x11-wayland-clipboard-bridge.service
```

The installer copies the units to `~/.config/systemd/user` and the bridge executable to `~/.local/bin`. These services are skipped on macOS and WSL.
