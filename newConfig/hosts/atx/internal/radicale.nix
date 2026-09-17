{ config, pkgs, withSharedVhost, ... }:

let
  domain = "dav.internal.veetik.com";
  port = config.homelab.ports.radicale;
  state = "/var/lib/radicale";

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
  age.secrets.radicale-users = {
    owner = "radicale";
    mode = "0400";
  };

  homelab.volumes.radicale.owner = "radicale";

  homelab.backups.instances.radicale = {
    repository = "internal";
    username = "internal";
    tag = "radicale";
    restPasswordFile = "/run/secrets/restic-internal-rest-pass";
    encryptionPasswordFile = "/run/secrets/restic-internal-encryption-pass";
    paths = [ state ];
    after = [ "var-lib-radicale.mount" ];
    before = [ "radicale.service" "radicale-init-git.service" ];
    requiredBy = [ "radicale.service" "radicale-init-git.service" ];
    restoreMarker = "${state}/.restore-in-progress";
    hasData = ''[ -n "$(ls -A ${state} 2>/dev/null)" ]'';
    restore = ''
      restic restore --tag radicale latest --target / --include ${state}
      chown -R radicale:radicale ${state}
    '';
  };

  services.radicale = {
    enable = true;
    settings = {
      server.hosts = [ "127.0.0.1:${toString port}" ];
      storage = {
        filesystem_folder = state;
        type = "multifilesystem";
        hook = "${hook}";
      };
      auth = {
        type = "htpasswd";
        htpasswd_filename = config.age.secrets.radicale-users.path;
        htpasswd_encryption = "bcrypt";
      };
    };
  };

  systemd.services.radicale-init-git = {
    description = "Initialize git in Radicale storage";
    wantedBy = [ "radicale.service" ];
    before = [ "radicale.service" ];
    after = [ "var-lib-radicale.mount" ];
    path = [ pkgs.git ];
    serviceConfig = {
      Type = "oneshot";
      User = "radicale";
      Group = "radicale";
    };
    script = ''
      cd ${state}
      if [ ! -d .git ]; then
        git init -q
        git config user.email "radicale@internal.veetik.com"
        git config user.name "Radicale"
        git add -A
        git commit -q --allow-empty -m "Initial commit" || true
      fi
    '';
  };

  services.nginx.virtualHosts.${domain} = withSharedVhost {
    locations."/".proxyPass = "http://127.0.0.1:${toString port}";
  };
}
