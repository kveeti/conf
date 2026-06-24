{ pkgs, ... }:

let
  pname = "helium";
  version = "0.13.5.1";

  src = pkgs.fetchurl {
    url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-x86_64.AppImage";
    hash = "sha256-VAncL78nyXRRNUPZ2c0QudxFrfxy7tXE2NFN4teeezk=";
  };

  appimageContents = pkgs.appimageTools.extractType2 {
    inherit pname version src;
  };

  helium-unwrapped = pkgs.appimageTools.wrapType2 {
    inherit pname version src;

    # libva.so.2 isn't bundled in the AppImage's FHS env; without it Chromium's
    # GPU process can't dlopen VAAPI and silently falls back to software decode.
    # nixpkgs' libva is patched to find the iHD driver in /run/opengl-driver.
    extraPkgs = pkgs: with pkgs; [ libnotify libsecret libva ];

    extraInstallCommands = ''
      install -Dm444 ${appimageContents}/helium.desktop -t $out/share/applications/
      install -Dm444 ${appimageContents}/helium.png \
        $out/share/icons/hicolor/256x256/apps/helium.png
    '';
  };

  helium = pkgs.symlinkJoin {
    name = "helium-${version}";
    paths = [ helium-unwrapped ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm $out/bin/helium
      makeWrapper ${helium-unwrapped}/bin/helium $out/bin/helium \
        --add-flags "--enable-features=VaapiVideoDecodeLinuxGL,VaapiIgnoreDriverChecks --ignore-gpu-blocklist"
    '';
  };
in
{
  environment.systemPackages = [ helium ];
}
