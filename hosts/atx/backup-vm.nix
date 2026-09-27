{ config, adminKeys, inventory, lib, ... }:

let
  name = "backup-vm";
  stateRoot = "/var/lib/microvms/${name}";
  host = inventory.hosts.${name};
  network = inventory.networks.${host.network};
  secretDir = "${stateRoot}/secrets";
in {
  system.activationScripts.backup-vm-files = {
    deps = [ "agenix" ];
    text = ''
      install -d -m 0755 ${stateRoot}/ssh
      install -d -m 0711 ${secretDir}
      install -m 0400 ${config.age.secrets.telemetry-pass.path} ${secretDir}/telemetry-pass
    '';
  };

  systemd.network.networks."60-vm-backup" = {
    matchConfig.Name = "vm-backup";
    networkConfig.Bridge = "br-${network.interface}";
  };

  microvm.vms.backup-vm = {
    specialArgs = { inherit adminKeys inventory; };
    config = { pkgs, ... }: {
      imports = [ ../../modules/profiles/microvm.nix ];

      networking.hostName = host.hostname;
      networking.nftables.enable = true;
      networking.firewall.extraInputRules = ''
        ip saddr { ${inventory.hosts.public.kubeIpv4}, ${inventory.hosts.backup.kubeIpv4} } tcp dport ${toString host.ports.s3} accept
      '';

      users.groups.garage = {};
      users.users.garage = {
        isSystemUser = true;
        group = "garage";
      };

      services.garage = {
        enable = true;
        package = pkgs.garage;
        settings = {
          replication_factor = 1;
          rpc_bind_addr = "127.0.0.1:3901";
          rpc_public_addr = "127.0.0.1:3901";
          rpc_secret_file = "/var/lib/garage/rpc-secret";
          s3_api = {
            s3_region = "garage";
            api_bind_addr = "${host.ipv4}:${toString host.ports.s3}";
          };
        };
      };

      systemd.services.garage = {
        unitConfig.RequiresMountsFor = "/var/lib/garage";
        serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = "garage";
          Group = "garage";
        };
        preStart = ''
          if [ ! -e /var/lib/garage/rpc-secret ]; then
            umask 077
            ${pkgs.openssl}/bin/openssl rand -hex 32 > /var/lib/garage/rpc-secret
          fi
        '';
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
            image = "${stateRoot}/garage.img";
            mountPoint = "/var/lib/garage";
            label = "garage-data";
            size = 262144;
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
