#!/usr/bin/env bash
# install.sh: install Record Presentation for the current user (no sudo needed).
#
#   ./install.sh [--encoder vaapi|nvenc|x264]
#
# Copies the scripts to ~/.local/bin, adds the app launcher, icon and the
# caption-worker systemd user units, and sets up an OBS profile + scene
# collection called "Presentation" and the obs-websocket server.
# Existing OBS files are only changed after a .bak-YYYYMMDD backup.
# Run ./uninstall.sh to remove it again.
set -euo pipefail
cd "$(dirname "$(realpath "$0")")"

BIN=$HOME/.local/bin
APPS=$HOME/.local/share/applications
ICONS=$HOME/.local/share/icons/hicolor/scalable/apps
UNITS=$HOME/.config/systemd/user
OUT_DIR=$HOME/Videos/Presentations
OBS=$HOME/.config/obs-studio
PROFILE=$OBS/basic/profiles/Presentation
SCENES=$OBS/basic/scenes/Presentation.json
WS=$OBS/plugin_config/obs-websocket/config.json
STAMP=$(date +%Y%m%d)

encoder=
while [[ $# -gt 0 ]]; do
  case $1 in
    --encoder) encoder=$2; shift ;;
    -h|--help) sed -n '2,10s/^# \{0,1\}//p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

backup() { [[ -e $1 && ! -e $1.bak-$STAMP ]] && cp -a "$1" "$1.bak-$STAMP" || true; }

# --- dependencies ------------------------------------------------------------
missing=()
for cmd in obs ffmpeg ffprobe notify-send gdbus gsettings fuser systemd-run; do
  command -v "$cmd" >/dev/null || missing+=("$cmd")
done
/usr/bin/python3 -c 'import gi; gi.require_version("Adw", "1"); from gi.repository import Adw; Adw.ToggleGroup' \
  2>/dev/null || missing+=("libadwaita>=1.7 (python3-gi, gir1.2-adw-1)")
if (( ${#missing[@]} )); then
  echo "Missing: ${missing[*]}" >&2
  echo "On Ubuntu: sudo apt install obs-studio ffmpeg python3-gi gir1.2-adw-1 libnotify-bin psmisc" >&2
  exit 1
fi
UV=$(command -v uv || true)
[[ -n $UV ]] || UV=$HOME/.local/bin/uv
if [[ ! -x $UV ]]; then
  echo "uv is missing. Install it with: curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
  exit 1
fi
if pgrep -x obs >/dev/null; then
  echo "Please quit OBS first (it overwrites its config files when it exits)." >&2
  exit 1
fi

# --- encoder -----------------------------------------------------------------
if [[ -z $encoder ]]; then
  encoder=x264
  if command -v nvidia-smi >/dev/null && nvidia-smi -L >/dev/null 2>&1; then
    encoder=nvenc
  elif [[ -e /dev/dri/renderD128 ]] && ffmpeg -nostdin -v error -vaapi_device /dev/dri/renderD128 \
      -f lavfi -i nullsrc=s=256x256:d=0.2 -vf format=nv12,hwupload -c:v h264_vaapi -f null - 2>/dev/null; then
    encoder=vaapi
  fi
fi
case $encoder in
  vaapi) enc_id=ffmpeg_vaapi_tex enc_json='{"rate_control": "CQP", "qp": 22, "keyint_sec": 2, "bf": 0}' ;;
  nvenc) enc_id=obs_nvenc_h264_tex enc_json='{"rate_control": "CQP", "cqp": 22, "keyint_sec": 2, "bf": 0}' ;;
  x264)  enc_id=obs_x264 enc_json='{"rate_control": "CRF", "crf": 22, "preset": "veryfast", "keyint_sec": 2}' ;;
  *) echo "unknown encoder: $encoder (use vaapi, nvenc or x264)" >&2; exit 1 ;;
esac
echo "Video encoder: $encoder ($enc_id)"

# --- scripts, launcher, icon, units ------------------------------------------
mkdir -p "$BIN" "$APPS" "$ICONS" "$UNITS" "$OUT_DIR"
install -m 755 bin/presentation-record-dialog bin/caption-video bin/caption-worker "$BIN/"
# pin uv's absolute path: the dock doesn't always have ~/.local/bin on PATH
sed "1s|.*|#!/usr/bin/env -S $UV run --quiet --script|" bin/presentation-record > "$BIN/presentation-record"
chmod 755 "$BIN/presentation-record"
install -m 644 share/presentation-record.svg "$ICONS/"
sed "s|@BINDIR@|$BIN|; s|@OUT_DIR@|$OUT_DIR|" share/presentation-record.desktop.in > "$APPS/presentation-record.desktop"
install -m 644 systemd/caption-worker.service systemd/caption-worker.path "$UNITS/"
gtk-update-icon-cache -q -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
update-desktop-database -q "$APPS" 2>/dev/null || true
systemctl --user daemon-reload
systemctl --user enable --now caption-worker.path

# --- OBS profile, scene collection, websocket ---------------------------------
mkdir -p "$PROFILE" "$(dirname "$SCENES")" "$(dirname "$WS")"
backup "$PROFILE/basic.ini"
backup "$PROFILE/recordEncoder.json"
sed "s|@OUT_DIR@|$OUT_DIR|; s|@ENCODER@|$enc_id|" obs/basic.ini > "$PROFILE/basic.ini"
echo "$enc_json" > "$PROFILE/recordEncoder.json"
[[ -e $SCENES ]] || cp obs/Presentation.json "$SCENES"

# Skip OBS's first-run wizard on a fresh install.
if [[ ! -e $OBS/global.ini ]]; then
  ver=$(obs --version | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
  IFS=. read -r major minor patch <<<"$ver"
  printf '[General]\nLastVersion=%d\n' $(( (major << 24) | (minor << 16) | ${patch:-0} )) > "$OBS/global.ini"
fi

backup "$WS"
/usr/bin/python3 - "$WS" <<'EOF'
import json, secrets, sys
path = sys.argv[1]
try:
    cfg = json.load(open(path))
except (OSError, ValueError):
    cfg = {}
cfg.setdefault("server_port", 4455)
cfg.setdefault("alerts_enabled", False)
cfg["first_load"] = False
cfg["server_enabled"] = True
if not cfg.get("server_password"):
    cfg["server_password"] = secrets.token_urlsafe(24)
cfg["auth_required"] = True
with open(path, "w") as f:
    json.dump(cfg, f, indent=4)
EOF
chmod 600 "$WS"

cat <<EOF

Installed. Search for "Record Presentation" in Activities, then right-click it
in the dock and choose "Pin to Dash".

Transcription needs WhisperX (a few GB download, CPU only):
  uv tool install whisperx --python 3.12 --torch-backend cpu
EOF
command -v whisperx >/dev/null && echo "(whisperx is already installed)"
exit 0
