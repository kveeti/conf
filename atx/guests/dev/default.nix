{ config, ... }:

let
  vmName = "dev";
  stateRoot = "/var/lib/microvms/${vmName}";
in {
  homelab.microvms.${vmName} = {
    inherit stateRoot;
    certDomains = [ "dev-internal.veetik.com" ];
    secrets = [{ name = "telemetry-pass"; mode = "0400"; }];

    shares = {
      ssh-host = {
        owner = "root"; group = "root"; mode = "0755";
        path = "/run/ssh-host"; hostPath = "${stateRoot}/ssh";
      };
    };

    vm = {
      specialArgs = {
        inherit (config._module.args) keys guestIps mac nixvim;
      };
      config = { config, pkgs, lib, keys, guestIps, mac, nixvim, ... }: {
        imports = [
          ../_common.nix
          nixvim.nixosModules.nixvim
          # shared neovim config, sourced from the mac flake so both stay in sync
          "${mac}/nvim.nix"
        ];

        microvm.mem  = lib.mkForce 8192;
        microvm.vcpu = lib.mkForce 6;

        networking.hostName = "dev";

        microvm.interfaces = [{
          type = "tap";
          id = "vm-dev";
          mac = "02:00:00:3d:00:01";
        }];

        microvm = {
          # project trees, deps and agent state survive rebuilds/reboots
          volumes = [
            {
              image = "${stateRoot}/home.img";
              mountPoint = "/home";
              size = 102400; # 100 GiB
            }
            {
              image = "${stateRoot}/nix-store-overlay.img";
              mountPoint = "/nix/.rw-store";
              size = 40960; # 40 GiB
            }
            {
              # Nix's SQLite database, profiles and daemon state must not live
              # on the guest's temporary root filesystem.
              image = "${stateRoot}/nix-state.img";
              mountPoint = "/nix/var/nix";
              size = 4096; # 4 GiB
            }
          ];
          writableStoreOverlay = "/nix/.rw-store";
        };

        systemd.network.enable = true;
        systemd.network.networks."10-eth" = {
          matchConfig.Type = "ether";
          address = [ "${guestIps.dev}/24" ];
          routes = [{ Gateway = "192.168.99.1"; }];
          networkConfig = { DHCP = "no"; DNS = "192.168.99.1"; };
        };
        services.resolved.enable = true;

        networking.firewall = {
          enable = true;
          allowedTCPPorts = [ 22 443 ];
          # dev is the only host on vlan999, router-fenced to just the Mac (vlan10) /
          # wireguard, so a broad dev-server range is safe to leave open here.
          allowedTCPPortRanges = [ { from = 3000; to = 9999; } ];
        };

        environment.systemPackages = with pkgs; [
          git gh gnumake gcc
          nodejs_22 go python3 cargo rustc
          ripgrep fd fzf jq curl direnv
          ghostty.terminfo

          claude-code
          codex
          (pkgs.callPackage ../../../mac/pi-coding-agent.nix { })

        ];

        systemd.services.dev-url-init = {
          description = "Initialize persistent dev-url routes";
          before = [ "nginx.service" ];
          requiredBy = [ "nginx.service" ];
          unitConfig.RequiresMountsFor = "/home";
          serviceConfig.Type = "oneshot";
          script = ''
            install -d -m 0755 -o veeti -g users /home/veeti/.config
            install -d -m 0755 -o veeti -g users /home/veeti/.config/dev-url
            touch /home/veeti/.config/dev-url/routes.map
            chown veeti:users /home/veeti/.config/dev-url/routes.map
            chmod 0644 /home/veeti/.config/dev-url/routes.map
            install -d -m 0755 /run/dev-url
            install -m 0644 /home/veeti/.config/dev-url/routes.map /run/dev-url/routes.map
          '';
        };

        services.nginx = {
          enable = true;
          recommendedProxySettings = true;
          appendHttpConfig = ''
            map $host $dev_url_port {
              default "";
              include /run/dev-url/routes.map;
            }
          '';
          virtualHosts."dev-projects" = {
            serverName = "*.dev-internal.veetik.com";
            onlySSL = true;
            sslCertificate = "/run/cert/dev-internal.veetik.com/fullchain.pem";
            sslCertificateKey = "/run/cert/dev-internal.veetik.com/key.pem";
            locations."/" = {
              proxyPass = "http://127.0.0.1:$dev_url_port";
              proxyWebsockets = true;
              recommendedProxySettings = false;
              extraConfig = ''
                if ($dev_url_port = "") { return 404; }

                proxy_set_header Host 127.0.0.1:$dev_url_port;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_set_header X-Forwarded-Host $host;
                proxy_set_header X-Forwarded-Server $hostname;
              '';
            };
          };
        };

        programs.mosh = {
          enable = true;
          openFirewall = true;
        };

        # shared tmux config (prefix, vi copy-mode, OSC 52 clipboard) from the mac flake
        environment.etc."tmux.conf".source = "${mac}/tmux.conf";

        # /home is a runtime-mounted microvm volume, so users.*.createHome can run
        # before the real /home exists. Ensure the dev user's home exists after mount.
        # The guest root is a 4 GiB tmpfs. Put client-side temporary files on
        # the persistent /home volume instead, so an abandoned nix shell cannot
        # exhaust the root filesystem.
        environment.variables.TMPDIR = "/home/veeti/.cache/tmp";
        nix.settings.build-dir = "/nix/.rw-store/tmp";

        systemd.tmpfiles.rules = [
          "d /home/veeti 0700 veeti users -"
          "d /home/veeti/.cache/tmp 0700 veeti users -"
          "d /nix/.rw-store/tmp 0755 root root -"
        ];

        # Override systemd's default 10-day /tmp retention. /tmp remains small
        # by design, and stale nix-shell directories can be several GiB.
        environment.etc."tmpfiles.d/tmp.conf".text = ''
          q /tmp 1777 root root 2d
          q /var/tmp 1777 root root 7d
        '';

        # zsh for parity with the mac shell; full aliases/functions stay mac-side
        programs.zsh.enable = true;
        users.defaultUserShell = pkgs.zsh;
        environment.shellAliases.e = "nvim";
      };
    };
  };
}

