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

# font config
mkdir -p .config/fontconfig/fonts.conf
> .config/fontconfig/fonts.conf
cat << EOF > .config/fontconfig/fonts.conf
<?xml version='1.0'?>
<!DOCTYPE fontconfig SYSTEM 'fonts.dtd'>
<fontconfig>
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Noto Sans</family>
      <family>Noto Color Emoji</family>
      <family>Noto Emoji</family>
      <family>DejaVu Sans</family>
    </prefer>
  </alias>

  <alias>
   <family>serif</family>
   <prefer>
     <family>Noto Serif</family>
     <family>Noto Color Emoji</family>
     <family>Noto Emoji</family>
     <family>DejaVu Serif</family>
   </prefer>
  </alias>

  <alias>
    <family>monospace</family>
    <prefer>
      <family>JetBrainsMono Nerd Font</family>
      <family>Noto Color Emoji</family>
      <family>Noto Emoji</family>
      <family>DejaVu Sans Mono</family>
    </prefer>
  </alias>

  <match target="font">
    <edit name="antialias" mode="assign">
      <bool>true</bool>
    </edit>
  </match>

  <match target="font">
    <edit name="rgba" mode="assign">
      <const>rgb</const>
    </edit>
  </match>

  <match target="font">
    <edit name="hinting" mode="assign">
      <bool>true</bool>
    </edit>
    <edit name="hintstyle" mode="assign">
      <const>hintslight</const>
    </edit>
  </match>

  <match target="font">
    <edit name="size" mode="assign">
      <double>15</double>
    </edit>
  </match>

</fontconfig>
EOF

