{ config, pkgs, lib, ... }:

let
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    python-dateutil
    vobject
  ]);

  radicale-birthday-script = pkgs.stdenv.mkDerivation rec {
    pname = "radicale-birthday-calendar";
    version = "535ae54ef6464b1aba825af794ecc4c4dbf3d3c3";

    src = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/iBigQ/radicale-birthday-calendar/${version}/create_birthday_calendar.py";
      hash = "sha256-NDWl0Fu10eQ8wGjGEQGoRc9KhmCkNATVeJLEj2lwsv4=";
    };

    dontUnpack = true;

    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/create_birthday_calendar.py
      makeWrapper ${pythonEnv}/bin/python $out/bin/create_birthday_calendar \
        --add-flags "$out/bin/create_birthday_calendar.py"
    '';
  };

  radicale-hook-script = pkgs.writeShellScript "radicale-hook" ''
    ${pkgs.git}/bin/git status --porcelain | ${pkgs.gawk}/bin/awk '{print $2}' | ${radicale-birthday-script}/bin/create_birthday_calendar || true
    ${pkgs.git}/bin/git add -A
    ${pkgs.git}/bin/git commit -m "Changes by Radicale hook" || true
  '';

in {

  config.age.secrets.radicale-users.mode = "0400";
  config.age.secrets.radicale-users.owner = "radicale";

  config.services.radicale = {
    enable = true;
    settings = {
      server.hosts = [ "127.0.0.1:20005" ];
      storage.filesystem_folder = "/var/lib/radicale";
      storage.type = "multifilesystem";
      storage.hook = "${radicale-hook-script}";
      auth = {
        type = "htpasswd";
        htpasswd_filename = config.age.secrets.radicale-users.path;
        htpasswd_encryption = "bcrypt";
      };
    };
  };

  config.services.nginx.virtualHosts."dav.internal.veetik.com" = {
    useACMEHost = "internal.veetik.com";
    forceSSL = true;
    quic = true;
    locations."/".proxyPass = "http://127.0.0.1:20005";
  };

}
