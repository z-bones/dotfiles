.PHONY: install packages tools symlinks android encrypt decrypt update help

DOTFILES_DIR := $(HOME)/.dotfiles

help:
	@echo "Dotfiles Management"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  install   - Full installation (packages, tools, symlinks)"
	@echo "  packages  - Install system packages only"
	@echo "  tools     - Install development tools only"
	@echo "  symlinks  - Create config symlinks only"
	@echo "  android   - Set up the Android dev toolbox (JDK, SDK, emulator)"
	@echo "  encrypt   - Encrypt secrets (SSH keys, GPG, etc.)"
	@echo "  decrypt   - Decrypt and install secrets"
	@echo "  update    - Pull latest changes and re-symlink"

install:
	@./install.sh

packages:
	@source ./scripts/packages.sh

tools:
	@source ./scripts/tools.sh

symlinks:
	@source ./scripts/symlinks.sh

android:
	@./scripts/android.sh setup

encrypt:
	@./scripts/secrets.sh encrypt

decrypt:
	@./scripts/secrets.sh decrypt

update:
	@git pull --ff-only
	@source ./scripts/symlinks.sh
	@echo "Updated and re-linked!"
