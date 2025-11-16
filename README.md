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
git clone <your-repo-url> dotfiles
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

## Notes

- Copy `.env.example` to `.env` and configure as needed
- `.p10k.zsh` contains Powerlevel10k Zsh theme configuration
