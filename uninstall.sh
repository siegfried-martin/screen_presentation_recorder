#!/usr/bin/env bash
# uninstall.sh: remove Record Presentation for the current user.
# Keeps your recordings (~/Videos/Presentations) and the OBS "Presentation"
# profile/scene collection; delete those by hand if you want them gone.
set -uo pipefail

systemctl --user disable --now caption-worker.path 2>/dev/null
systemctl --user stop caption-worker.service 2>/dev/null
rm -f ~/.local/bin/{presentation-record,presentation-record-dialog,caption-video,caption-worker} \
  ~/.local/share/applications/presentation-record.desktop \
  ~/.local/share/icons/hicolor/scalable/apps/presentation-record.svg \
  ~/.config/systemd/user/caption-worker.{service,path}
rm -rf ~/.local/state/presentation-record
systemctl --user daemon-reload
echo "Removed. Recordings and the OBS Presentation profile were kept."
echo "WhisperX can be removed with: uv tool uninstall whisperx"
