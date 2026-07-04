# Systemd user units

## Install clipboard services

```bash
mkdir -p ~/.config/systemd/user
ln -sf /home/ruiheng/config_files/systemd/user/cliphist.service ~/.config/systemd/user/cliphist.service
ln -sf /home/ruiheng/config_files/systemd/user/x11-wayland-clipboard-bridge.service ~/.config/systemd/user/x11-wayland-clipboard-bridge.service
systemctl --user daemon-reload
systemctl --user disable --now clipboard-sync.service
systemctl --user enable --now cliphist.service
systemctl --user enable --now x11-wayland-clipboard-bridge.service
```
