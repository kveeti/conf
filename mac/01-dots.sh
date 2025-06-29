#!/bin/zsh

set -euo pipefail

DOTS="${HOME}/.dots"
rm -rf "${DOTS}"

cd "${HOME}"

git clone --branch dots_mac --single-branch --bare https://github.com/kveeti/conf "${DOTS}"
function dots {
   /usr/bin/git --git-dir="${DOTS}" --work-tree="${HOME}" $@
}
dots checkout
if [ $? = 0 ]; then
	echo "checked out config";
else
	echo "backing up pre-existing files";
	mkdir -p .config-backup
	dots checkout 2>&1 | grep -E "\s+\." | awk '{print $1}' | xargs -I{} bash -c 'rsync -R {} .config-backup/ && rm -r {}'
fi;
dots checkout
dots config status.showUntrackedFiles no
