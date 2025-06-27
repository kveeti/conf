#!/bin/zsh

function formulae {
	brew install --formula \
		zstd \
		pv \
		gpg \
		mpv \
		ffmpeg \
		yt-dlp \
		ripgrep \
		fzf \
		lazygit \
		neovim \
		colima \
		docker \
		docker-compose \
		docker-buildx \
		docker-credential-helper

	# docker caveats
	# might stop working someday, hopefully this helps that day:
	# Compose is a Docker plugin. For Docker to find the plugin, add "cliPluginsExtraDirs" to ~/.docker/config.json:
	# "cliPluginsExtraDirs": [ "/opt/homebrew/lib/docker/cli-plugins" ]

	mkdir -p ~/.docker/cli-plugins
	ln -sfn $(which docker-buildx) ~/.docker/cli-plugins/docker-buildx
	ln -sfn $(which docker-compose) ~/.docker/cli-plugins/docker-compose
}

function casks {
	brew install --cask \
		font-jetbrains-mono-nerd-font \
		brave-browser \
		librewolf \
		keepassxc \
		1password \
		ghostty \
		raycast
}

formulae &
casks &

wait
