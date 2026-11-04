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
│   └── rofi/           # Application launcher
├── .env.example        # Environment variables template
├── .gitignore
├── .p10k.zsh           # Powerlevel10k Zsh theme
├── .xprofile           # Fcitx environment for graphical sessions
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

## OpenWhispr

OpenWhispr starts through XDG autostart and is also available from the
application launcher. Both entries use the CUDA-aware launch wrapper. The
microphone module on the main Polybar launches the same wrapper when clicked;
its icon is gray while OpenWhispr is stopped, teal while idle, and red only
while OpenWhispr is recording.

The active host profile uses Whisper Base with CUDA. OpenWhispr application and
runtime state under `~/.config/open-whispr`—including databases, recordings,
models, sessions, and credentials—remains machine-local and is intentionally
not tracked here.

## Screenshots

`Mod+P` freezes the current desktop, lets you select a region, and copies the
PNG to the X11 clipboard. If an open dropdown prevents region selection, the
same shortcut copies the focused monitor with the dropdown visible. Chromium's
native dropdown closes on `Mod+P`; double-tap `Super` after opening it to copy
the focused monitor immediately. You can also press `Mod+Shift+P` before opening
it; a brief notification confirms the shortcut, and the focused monitor is
copied five seconds later. The helper uses GTK instead of Ubuntu's packaged
`xclip` because `xclip` 0.13 can hang applications while serving large images.
It requires `scrot`, `python3-xlib`, `python3-gi`, `gir1.2-gtk-3.0`, and
`libnotify-bin`.

## Notes

- Copy `.env.example` to `.env` and configure as needed
- `.p10k.zsh` contains Powerlevel10k Zsh theme configuration
