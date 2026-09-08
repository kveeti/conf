{ config, adminKeys, inventory, lib, pkgs, ... }:

let
  name = "minecraft";
  stateRoot = "/var/lib/microvms/${name}";
  host = inventory.hosts.${name};
  network = inventory.networks.${host.network};
  bridge = "br-${network.interface}";
  secretDir = "${stateRoot}/secrets";
in {
  system.activationScripts.minecraft-files = {
    deps = [ "agenix" ];
    text = ''
      install -d -m 0755 ${stateRoot}/ssh
      install -d -m 0711 ${secretDir}
      install -m 0400 ${config.age.secrets.telemetry-pass.path} ${secretDir}/telemetry-pass
    '';
  };

  systemd.network.networks."60-vm-minecraft" = {
    matchConfig.Name = "vm-minecraft";
    networkConfig.Bridge = bridge;
  };

  microvm.vms.minecraft = {
    specialArgs = { inherit adminKeys inventory; };
    config = { config, ... }: {
      imports = [
        ../../../modules/profiles/microvm.nix
        ./backup
      ];

      networking.hostName = host.hostname;

      microvm = {
        mem = lib.mkForce 8192;
        vcpu = lib.mkForce 8;
        interfaces = [{
          type = "tap";
          id = "vm-minecraft";
          mac = "02:00:00:66:00:07";
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
        volumes = [{
          image = "${stateRoot}/home.img";
          mountPoint = "/home";
          size = 131072;
        }];
      };

      systemd.tmpfiles.rules = [ "d /home/veeti 0700 veeti users -" ];

      systemd.network = {
        enable = true;
        networks."10-ethernet" = {
          matchConfig.Type = "ether";
          address = [ "${host.ipv4}/${lib.last (lib.splitString "/" network.cidr4)}" ];
          routes = [{ Gateway = network.router4; }];
          networkConfig.DHCP = "no";
        };
      };

      networking.firewall.allowedTCPPorts = [ config.homelab.ports.game ];

      environment.systemPackages = with pkgs; [
        jdk25_headless
        tmux
        unzip
        zip
      ];
    };
  };
}
