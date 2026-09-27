{ config, adminKeys, inventory, lib, ... }:

let
  name = "control3";
  stateRoot = "/var/lib/microvms/${name}";
  host = inventory.hosts.${name};
  network = inventory.networks.${host.network};
  secretDir = "${stateRoot}/secrets";
in {
  system.activationScripts.control3-files = {
    deps = [ "agenix" ];
    text = ''
      install -d -m 0755 ${stateRoot}/ssh
      install -d -m 0711 ${secretDir}
      install -m 0400 ${config.age.secrets.telemetry-pass.path} ${secretDir}/telemetry-pass
    '';
  };

  systemd.network.networks."60-vm-control3" = {
    matchConfig.Name = "vm-control3";
    networkConfig.Bridge = "br-${network.interface}";
  };

  microvm.vms.control3 = {
    specialArgs = { inherit adminKeys inventory; };
    config = { config, ... }: {
      imports = [
        ../../modules/profiles/microvm.nix
        ../../modules/services/k3s-server.nix
      ];

      networking.hostName = host.hostname;

      services.k3s = {
        serverAddr = "https://${inventory.hosts.public.kubeIpv4}:6443";
        tokenFile = "/var/lib/rancher/k3s/join-token";
        nodeTaint = [ "node-role.kubernetes.io/control-plane=true:NoSchedule" ];
      };

      systemd.services.k3s.unitConfig.ConditionPathExists = config.services.k3s.tokenFile;

      microvm = {
        mem = lib.mkForce 2048;
        interfaces = [{
          type = "tap";
          id = "vm-control3";
          mac = "02:00:00:32:00:07";
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
          image = "${stateRoot}/state.img";
          mountPoint = "/var/lib/rancher/k3s";
          size = 16384;
        }];
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
