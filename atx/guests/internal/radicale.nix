{ config, pkgs, lib, withSharedVhost, ... }:

let
  domain = "dav.internal.veetik.com";

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

  dir = "/var/lib/radicale";
in {
  config.age.secrets.radicale-users.mode = "0400";
  config.age.secrets.radicale-users.owner = "radicale";

  config.homelab.volumes.radicale.owner = "radicale";

  config.homelab.backups.instances.radicale = {
    paths = [ dir ];
    after = [ "var-lib-radicale.mount" ];
    before = [ "radicale.service" "radicale-init-git.service" ];
    hasData = ''[ -n "$(ls -A ${dir} 2>/dev/null)" ]'';
    restore = ''
      restic restore --tag radicale latest --target / --include ${dir}
      chown -R radicale:radicale ${dir}
    '';
  };

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

  config.systemd.services.radicale-init-git = {
    description = "Initialize git repo in radicale storage dir";
    wantedBy = [ "radicale.service" ];
    before   = [ "radicale.service" ];
    after    = [ "var-lib-radicale.mount" ];
    serviceConfig = {
      Type = "oneshot";
      User = "radicale";
      Group = "radicale";
    };
    path = [ pkgs.git ];
    script = ''
      cd /var/lib/radicale
      if [ ! -d .git ]; then
        git init -q
        git config user.email "radicale@internal.veetik.com"
        git config user.name "Radicale"
        git add -A
        git commit -q --allow-empty -m "Initial commit" || true
      fi
    '';
  };

  config.services.nginx.virtualHosts.${domain} = withSharedVhost {
    locations."/".proxyPass = "http://127.0.0.1:20005";
  };

}
