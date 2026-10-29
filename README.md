# Screen Presentation Recorder

One-click screen + mic recording for GNOME on Wayland, with transcripts and
captions made in the background by [WhisperX](https://github.com/m-bain/whisperX).
It runs on a laptop with no dedicated GPU.

Click the dock icon, pick your options, record, click it again to stop:

- **Recording:** Audio only, Video only, or Both
- **Screen:** any connected monitor (GNOME's share picker is skipped), or "Pick a window…"
- **Transcription:** None or Transcript. A transcript makes `.srt`/`.vtt` captions,
  a plain `.txt` transcript and a copy of the video with a caption track

There's a 3-2-1 countdown that disappears before recording starts, and Do Not
Disturb stays on while you record, so notification popups don't end up in the
video. Transcription is queued and runs at idle priority after you stop, so
it doesn't slow down the recording or your other work.

## Requirements

- GNOME on Wayland (tested on Ubuntu 26.04, GNOME 50, OBS 32.1)
- libadwaita 1.7 or newer (Ubuntu 25.10+) for the options dialog
- These packages:

  ```sh
  sudo apt install obs-studio ffmpeg python3-gi gir1.2-adw-1 libnotify-bin psmisc
  ```

- [uv](https://docs.astral.sh/uv/), which runs the main script and installs WhisperX:

  ```sh
  curl -LsSf https://astral.sh/uv/install.sh | sh
  ```

- WhisperX, needed only for transcripts. It's a few GB with the CPU build of PyTorch:

  ```sh
  uv tool install whisperx --python 3.12 --torch-backend cpu
  ```

  The first transcription downloads the `large-v3-turbo` model (about 1.6 GB) into
  `~/.cache/huggingface`.

## Install

```sh
git clone https://github.com/siegfried-martin/screen_presentation_recorder.git
cd screen_presentation_recorder
./install.sh
```

Then find **Record Presentation** in Activities, start it once, and right-click its
dock icon → **Pin to Dash**.

The installer is user-level only, so it never needs sudo. It does the following:

| What | Where |
|---|---|
| Scripts | `~/.local/bin/` |
| Launcher + icon | `~/.local/share/applications/`, `~/.local/share/icons/` |
| Transcription worker (systemd user units) | `~/.config/systemd/user/caption-worker.{path,service}` |
| OBS profile + scene collection "Presentation" | `~/.config/obs-studio/basic/` |
| obs-websocket enabled with a random password | `~/.config/obs-studio/plugin_config/obs-websocket/config.json` |
| Settings | `~/.config/presentation-record/config.env` |
| Recordings | `~/Videos/Presentations/` (configurable, see [Settings](#settings)) |

Your other OBS profiles and scene collections are left alone. The script starts OBS
with `--profile Presentation --collection Presentation`. Before changing an existing
file, the installer saves a copy as `FILE.bak-YYYYMMDD`. Quit OBS before installing.

### Video encoder

The installer picks a hardware encoder if it finds one, so recording doesn't
overload the CPU:

- `vaapi` for AMD and Intel GPUs (tested with an AMD Radeon 860M)
- `nvenc` for NVIDIA
- `x264` (software) otherwise

To override the choice, run `./install.sh --encoder vaapi|nvenc|x264`.

## Settings

All settings are in one file, `~/.config/presentation-record/config.env`. The
installer creates it from [`config.env.example`](config.env.example) and doesn't
overwrite it on later installs.

| Setting | Default | When it applies |
|---|---|---|
| `RECORDINGS_DIR` | `$HOME/Videos/Presentations` | Re-run `./install.sh`, so the worker watches the new folder |
| `ENCODER` | `auto` | Re-run `./install.sh` |
| `FPS` | `15` | Next recording |
| `MAX_RESOLUTION` | `1920x1200` | Next recording. Bigger screens are scaled down to fit |
| `COUNTDOWN` | `3` | Next recording. Seconds before recording starts; `0` = no countdown |
| `DO_NOT_DISTURB` | `true` | Next recording. Hides notification popups while recording |
| `WHISPER_MODEL` | `large-v3-turbo` | Next transcript. `small` or `medium` are faster on slow machines |
| `WHISPER_LANGUAGE` | `en` | Next transcript. The language spoken in the recording |

You can also set the folder and encoder when installing; both are saved to the file:

```sh
./install.sh --dir ~/Documents/Talks --encoder x264
```

## Usage

- **Start:** click the dock icon, choose options, then **Start Recording** (or press Enter).
- **Stop:** click the dock icon again, or use **Stop Recording** in the OBS tray
  icon. Both work.
- **Recordings folder:** right-click the dock icon → **Open Recordings Folder**.

For a recording named `2026-10-26_19-25-54.mp4`, transcription produces:

| File | What it is |
|---|---|
| `….srt`, `….vtt` | Captions |
| `….txt` | Plain transcript |
| `….captioned.mp4` | The video with a caption track you can turn on and off. VLC, mpv and most desktop players show it; browsers and Google Drive don't |

Audio-only recordings are `.m4a` files and get the `.srt`/`.vtt`/`.txt` only.
A desktop notification tells you when the transcript is ready.

### Sharing on Google Drive / in a browser

Browsers and the Drive previewer ignore caption tracks inside the MP4. You have two
options:

1. **Toggleable captions:** upload the video, open it in Drive and go to ⋮ →
   **Manage caption tracks** → upload the `.srt` file.
2. **Always-visible captions:** burn them into the picture. This works in every player:

   ```sh
   caption-video --remux --burn ~/Videos/Presentations/2026-10-26_19-25-54.mp4
   # → 2026-10-26_19-25-54.burned.mp4
   ```

### Fixing transcript mistakes

Edit the `.srt` in any text editor. Then rebuild the captioned and burned videos
without transcribing again:

```sh
caption-video --remux [--burn] FILE.mp4
```

## Standalone tools

`caption-video` works on any video or audio file, not only recordings made with
this project:

```
caption-video [--burn] [--remux] [--lang CODE] [--model NAME] FILE
```

- `--lang` and `--model` default to `WHISPER_LANGUAGE` and `WHISPER_MODEL` from the
  settings file (`en` and `large-v3-turbo`). Any WhisperX/faster-whisper model name works.

To queue a file for the background worker instead of running it in your terminal,
create a request file next to it in the recordings folder:

```sh
echo '{"transcription": "transcript"}' > ~/Videos/Presentations/NAME.request.json
```

## How it works

```
dock icon ─▶ presentation-record ─▶ presentation-record-dialog (GTK/libadwaita)
                   │
                   ├─ audio: ffmpeg (mic + computer sound) ─▶ NAME.m4a
                   └─ video/both: OBS via obs-websocket ────▶ NAME.mp4
                   │
            "--watch" helper notices the recording stopped (dock click or OBS tray),
            closes OBS, restores notifications, writes NAME.request.json
                   │
caption-worker.path (watches the folder) ─▶ caption-worker.service
   (Nice=19, idle CPU + IO scheduling) ─▶ caption-video ─▶ WhisperX ─▶ .srt/.txt/.captioned.mp4
```

- **Skipping GNOME's screen picker.** The script writes a screen-share "restore
  token" for the chosen monitor into the xdg-desktop-portal permission store. This
  is the same entry GNOME saves when you tick a screen in its picker. OBS is started
  in a systemd scope named after its app ID, so the portal accepts the token.
- **Frame rate, size and folder.** These are set over websocket at the start of
  each recording, from the settings file. The canvas is the monitor's own resolution,
  scaled down to fit `MAX_RESOLUTION`.
- **Logs.**
  - Recording: `~/.local/state/presentation-record/recorder.log`
  - Transcription: `journalctl --user -u caption-worker`
  - A failed transcription leaves `NAME.caption-failed.log` next to the recording.
    Delete that log to retry.

## Uninstall

```sh
./uninstall.sh
```

This removes the scripts, launcher, icon and systemd units. It keeps your
recordings, your settings file and the OBS "Presentation" profile. To remove WhisperX as well, run
`uv tool uninstall whisperx`.

## Limitations

- GNOME/Mutter only. The monitor list and the restore tokens use GNOME-specific D-Bus APIs.
- Transcription runs on the CPU. With `large-v3-turbo`, expect roughly real time
  or slower on a laptop.
- One audio track: mic and computer sound are mixed together.

## License

[MIT](LICENSE)
