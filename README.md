# Dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Directory Structure

```
.
├── .config/
│   ├── alacritty/      # Terminal emulator configuration
│   ├── calibre/        # E-book management
│   ├── Code/           # VS Code settings
│   ├── doom/           # Doom Emacs configuration
│   ├── fcitx5/         # Input method framework
│   ├── i3/             # i3 window manager
│   ├── polybar/        # Status bar configuration
│   ├── rofi/           # Application launcher
│   └── systemd/        # User services
├── .env.example        # Environment variables template
├── .gitignore
├── .p10k.zsh           # Powerlevel10k Zsh theme
├── README.md
└── scripts/            # Utility scripts
```

## Installation

```bash
# Install GNU Stow
sudo apt install stow  # Ubuntu/Debian
sudo pacman -S stow    # Arch Linux
brew install stow      # macOS

# Clone and apply dotfiles
cd ~
git clone git@github.com:mdrmono/dotfiles.git dotfiles
cd dotfiles
stow .
```

## Usage

```bash
stow .        # Create symlinks
stow -D .     # Remove symlinks
stow -R .     # Refresh symlinks
stow --adopt . # Adopt existing files into repo
```

## Codex Dictation

The X11 i3 `Mod+Z` binding toggles fully local dictation for a focused Codex
window. It uses the Paseo Parakeet model through Sherpa-ONNX, shows live partial
text while recording, and replaces it with the final transcript on the second
press. It does not use Whisper or a network API, and it does not send desktop
notifications. The workflow also requires Node.js, PipeWire's `pw-record`,
`xdotool`, `xclip`, `flock`, and a user systemd session.

The model and Sherpa native runtime are machine-local prerequisites and are not
stored in this repository. Their default locations are:

- `~/.paseo/models/local-speech/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8`
- `~/.local/share/codex-dictation/sherpa-onnx-linux-x64`

After applying the dotfiles, enable the user services to keep the model warm
and the PipeWire capture ring available:

```bash
systemctl --user daemon-reload
systemctl --user enable --now \
  codex-dictation-capture.service \
  codex-dictation-sherpa.service
```

The capture service continuously retains only the latest 500 ms in memory when
dictation is idle, preserving the first word after `Mod+Z` without writing idle
audio to disk. Polybar always shows the microphone state: gray while idle,
then red immediately after the first press and through final transcription.

## Notes

- Copy `.env.example` to `.env` and configure as needed
- `.p10k.zsh` contains Powerlevel10k Zsh theme configuration
