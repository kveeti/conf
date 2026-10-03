{
  description = "Radicale container image";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/a5cc6f2c37bf518436dc8d1c288ccd0c43c2f4c4";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          python = pkgs.python3.withPackages (packages: with packages; [
            python-dateutil
            vobject
          ]);

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

          iniFormat = pkgs.formats.ini {
            listToValue = pkgs.lib.concatMapStringsSep ", " (pkgs.lib.generators.mkValueStringDefault {});
          };

          config = iniFormat.generate "radicale.conf" {
            server.hosts = [ "0.0.0.0:5232" ];
            auth = {
              type = "htpasswd";
              htpasswd_filename = "/run/secrets/radicale-users";
              htpasswd_encryption = "bcrypt";
            };
            storage = {
              type = "multifilesystem";
              filesystem_folder = "/var/lib/radicale";
              inherit hook;
            };
          };

          runtime = pkgs.runCommand "radicale-runtime" {} ''
            mkdir -p $out/etc/radicale $out/lib/radicale
            ln -s ${config} $out/etc/radicale/config
            ln -s ${hook} $out/lib/radicale/hook
          '';

          entrypoint = pkgs.writeShellScriptBin "radicale-entrypoint" ''
            set -eu

            state=/var/lib/radicale

            if [ ! -d "$state/.git" ]; then
              ${pkgs.git}/bin/git -C "$state" init -q
              ${pkgs.git}/bin/git -C "$state" config user.email "radicale@internal.veetik.com"
              ${pkgs.git}/bin/git -C "$state" config user.name "Radicale"
              ${pkgs.git}/bin/git -C "$state" add -A
              ${pkgs.git}/bin/git -C "$state" commit -q --allow-empty -m "Initial commit" || true
            fi

            ${pkgs.git}/bin/git -C "$state" config user.email "radicale@internal.veetik.com"
            ${pkgs.git}/bin/git -C "$state" config user.name "Radicale"

            exec ${pkgs.radicale}/bin/radicale -C ${config}
          '';

          image = pkgs.dockerTools.buildLayeredImage {
            name = "veetik/radicale-and-friends";
            tag = "latest";
            contents = [
              entrypoint
              runtime
              pkgs.radicale
              pkgs.git
              pkgs.gawk
              pkgs.bash
              birthdayCalendar
              python
            ];
            extraCommands = "mkdir -p var/lib/radicale";
            fakeRootCommands = ''
              chown 1000:1000 var/lib/radicale
            '';
            config = {
              Entrypoint = [ "${entrypoint}/bin/radicale-entrypoint" ];
              Env = [
                "HOME=/var/lib/radicale"
                "PATH=${pkgs.lib.makeBinPath [ pkgs.git pkgs.gawk ]}"
              ];
              ExposedPorts = { "5232/tcp" = {}; };
              User = "1000:1000";
              WorkingDir = "/var/lib/radicale";
            };
          };
        in {
          dockerImage = image;
          default = image;
        });
    };
}
