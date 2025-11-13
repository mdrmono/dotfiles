# Dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Directory Structure

```
.
├── .config/
│   ├── alacritty/
│   ├── calibre/
│   ├── Code/
│   ├── doom/
│   ├── fcitx5/
│   ├── i3/
│   ├── polybar/
│   └── rofi/
├── .env.example
├── .p10k.zsh
└── scripts/
    └── util/
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
