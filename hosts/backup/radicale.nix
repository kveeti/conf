{ config, lib, pkgs, ... }:

let
  ports = config.homelab.ports;
  state = "/var/lib/radicale";
  authFile = config.age.secrets.radicale-users.path;
  python = pkgs.python3.withPackages (packages: with packages; [ python-dateutil vobject ]);
  birthdayCalendar = pkgs.stdenv.mkDerivation {
    pname = "radicale-birthday-calendar";
    version = "535ae54ef6464b1aba825af794ecc4c4dbf3d3c3";
    src = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/iBigQ/radicale-birthday-calendar/535ae54ef6464b1aba825af794ecc4c4dbf3d3c3/create_birthday_calendar.py";
      hash = "sha256-NDWl0Fu10eQ8wGjGEQGoRc9KhmCkNATVeJLEj2lwsv4=";
    };
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/create_birthday_calendar.py
      makeWrapper ${python}/bin/python $out/bin/create_birthday_calendar \
        --add-flags "$out/bin/create_birthday_calendar.py"
    '';
  };
  hook = pkgs.writeShellScript "radicale-hook" ''
    ${pkgs.git}/bin/git status --porcelain | ${pkgs.gawk}/bin/awk '{print $2}' | ${birthdayCalendar}/bin/create_birthday_calendar || true
    ${pkgs.git}/bin/git add -A
    ${pkgs.git}/bin/git commit -m "Changes by Radicale hook" || true
  '';
in {
  imports = [ ../../modules/services/restic-backups.nix ];

  services.radicale = {
    enable = true;
    settings = {
      server.hosts = [ "127.0.0.1:5232" ];
      storage = {
        filesystem_folder = state;
        type = "multifilesystem";
        hook = "${hook}";
      };
      auth = {
        type = "htpasswd";
        htpasswd_filename = "/run/credentials/radicale.service/users";
        htpasswd_encryption = "bcrypt";
      };
    };
  };

  services.nginx.virtualHosts."dav.internal.veetik.com" = {
    onlySSL = true;
    useACMEHost = "internal.veetik.com";
    listen = [{ addr = "0.0.0.0"; port = ports.https; ssl = true; }];
    locations."/".proxyPass = "http://127.0.0.1:5232";
  };

  systemd.services.radicale = {
    serviceConfig = {
      StateDirectory = lib.mkForce "radicale";
      LoadCredential = [ "users:${authFile}" ];
    };
  };

  homelab.backups = {
    serverUrl = "https://backup.internal.veetik.com:8000";
    instances.radicale = {
      passwordFile = config.age.secrets.restic-radicale-password.path;
      paths = [ state ];
      preBackupScript = ''
        exec 9<${state}/.Radicale.lock
        flock --exclusive 9
      '';
      restoreDirectory = state;
      preRestoreScript = ''
        systemctl stop radicale.service
      '';
      postRestoreScript = ''
        systemctl start radicale.service
      '';
    };
  };
}
