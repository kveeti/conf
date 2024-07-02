#/bin/bash

# install yay
cd ~
git clone https://aur.archlinux.org/yay.git
cd yay
echo y | makepkg -si
cd ~
rm -rf ./yay

# aur packages
echo y | LANG=C yay -S --answerdiff None --answerclean None --noconfirm --needed \
  tofi \
  minecraft-launcher \
  downgrade

# dotfiles
DOTS="${HOME}/.dots"
rm -rf "${DOTS}"

cd "${HOME}"

git clone --branch dots_arch --single-branch --bare https://github.com/veeti-k/conf "${DOTS}"
function dots {
   /usr/bin/git --git-dir="${DOTS}" --work-tree="${HOME}" $@
}
dots checkout
if [ $? = 0 ]; then
	echo "checked out config";
else
	echo "backing up pre-existing files";
	mkdir -p .config-backup
	dots checkout 2>&1 | grep -E "\s+\." | awk {'print $1'} | xargs -I{} mv {} .config-backup/{}
fi;
dots checkout
dots config status.showUntrackedFiles no
