# Systemd user units

## Install cliphist service

```bash
mkdir -p ~/.config/systemd/user
ln -s /home/ruiheng/config_files/nvim/systemd/user/cliphist.service ~/.config/systemd/user/cliphist.service
systemctl --user daemon-reload
systemctl --user enable --now cliphist.service
```
