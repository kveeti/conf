{ config, adminKeys, inventory, lib, ... }:

let
  name = "backup-vm";
  stateRoot = "/var/lib/microvms/${name}";
  host = inventory.hosts.${name};
  network = inventory.networks.${host.network};
  secretDir = "${stateRoot}/secrets";
  legacyRepositories = [ "auth" "authentik" "bm" "ha" "internal" "modi" ];
  appRepositories = [ "bookmarks" "keycloak" "money" "papra" "radicale" "rss" "tasks" "weather" ];
  passwordNames = lib.concatMap (repository: [
    "restic-${repository}-rest-pass"
    "restic-${repository}-encryption-pass"
  ]) legacyRepositories ++ map (repository: "restic-${repository}-password") appRepositories;
in {
  system.activationScripts.backup-vm-files = {
    deps = [ "agenix" ];
    text = ''
      install -d -m 0755 ${stateRoot}/ssh
      install -d -m 0711 ${secretDir}
      install -m 0400 ${config.age.secrets.telemetry-pass.path} ${secretDir}/telemetry-pass
      install -m 0400 ${config.age.secrets.cloudflare-env-file.path} ${secretDir}/cloudflare-env-file
      ${lib.concatMapStringsSep "\n" (password: ''
        install -m 0400 ${config.age.secrets.${password}.path} ${secretDir}/${password}
      '') passwordNames}
    '';
  };

  systemd.network.networks."60-vm-backup" = {
    matchConfig.Name = "vm-backup";
    networkConfig.Bridge = "br-${network.interface}";
  };

  microvm.vms.backup-vm = {
    specialArgs = { inherit adminKeys inventory; };
    config = { ... }: {
      imports = [
        ../../modules/profiles/microvm.nix
        ../../modules/services/restic-server.nix
      ];

      fileSystems."/run/secrets".neededForBoot = true;
      fileSystems."/var/lib/restic".neededForBoot = true;

      networking.hostName = host.hostname;
      networking.nftables.enable = true;
      networking.firewall.allowedTCPPorts = [ host.ports.restic ];

      homelab.resticServer = {
        enable = true;
        listenAddress = "127.0.0.1:${toString host.ports.restServer}";
        repositories = lib.genAttrs legacyRepositories (repository: {
          clientPasswordFile = "/run/secrets/restic-${repository}-rest-pass";
          encryptionPasswordFile = "/run/secrets/restic-${repository}-encryption-pass";
        }) // lib.genAttrs appRepositories (repository: {
          clientPasswordFile = "/run/secrets/restic-${repository}-password";
          encryptionPasswordFile = "/run/secrets/restic-${repository}-password";
        });
      };

      services.nginx = {
        enable = true;
        recommendedProxySettings = true;
        virtualHosts."restic.internal.veetik.com" = {
          onlySSL = true;
          enableACME = true;
          acmeRoot = null;
          listen = [{ addr = "0.0.0.0"; port = host.ports.restic; ssl = true; }];
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString host.ports.restServer}";
            extraConfig = ''
              client_max_body_size 0;
              proxy_request_buffering off;
            '';
          };
        };
      };

      security.acme = {
        acceptTerms = true;
        defaults = {
          email = "security@veetik.com";
          server = "https://acme-v02.api.letsencrypt.org/directory";
          dnsProvider = "cloudflare";
          dnsResolver = "1.1.1.1";
          environmentFile = "/run/secrets/cloudflare-env-file";
        };
      };

      microvm = {
        mem = lib.mkForce 2048;
        interfaces = [{
          type = "tap";
          id = "vm-backup";
          mac = "02:00:00:32:00:04";
        }];
        shares = [
          {
            source = "${stateRoot}/ssh";
            mountPoint = "/run/ssh-host";
            tag = "ssh-host";
            proto = "virtiofs";
          }
          {
            source = secretDir;
            mountPoint = "/run/secrets";
            tag = "secrets";
            proto = "virtiofs";
            readOnly = true;
          }
        ];
        volumes = [
          {
            image = "${stateRoot}/state.img";
            mountPoint = "/var/lib";
            size = 8192;
          }
          {
            image = "${stateRoot}/restic.img";
            mountPoint = "/var/lib/restic";
            label = "restic-data";
            size = 65536;
          }
        ];
      };

      systemd.network = {
        enable = true;
        networks."10-ethernet" = {
          matchConfig.Type = "ether";
          address = [ "${host.ipv4}/${lib.last (lib.splitString "/" network.cidr4)}" ];
          routes = [{ Gateway = network.router4; }];
          networkConfig = {
            DHCP = "no";
            DNS = [ network.router4 ];
          };
        };
      };
    };
  };
}
