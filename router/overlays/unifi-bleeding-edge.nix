final: prev: {
  unifi-bleeding-edge = prev.stdenvNoCC.mkDerivation rec {
    pname = "unifi-controller-bleeding-edge";
    version = "10.2.105";

    src = prev.fetchurl {
      url = "https://dl.ui.com/unifi/${version}/unifi_sysvinit_all.deb";
      hash = "sha256-MBTFxNwrIbx6UKZYCcZ+BjYjSlfdxL60Ogei/ba4O+U=";
    };

    nativeBuildInputs = with prev; [
      dpkg
      autoPatchelfHook
    ];

    buildInputs = with prev; [
      systemd
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -ar usr/lib/unifi/{dl,lib,webapps} $out

      runHook postInstall
    '';

    meta = with prev.lib; {
      homepage = "https://www.ui.com";
      description = "Controller for Ubiquiti UniFi access points (bleeding edge)";
      sourceProvenance = with sourceTypes; [ binaryBytecode ];
      license = licenses.unfree;
      platforms = [ "x86_64-linux" "aarch64-linux" ];
    };
  };
}
