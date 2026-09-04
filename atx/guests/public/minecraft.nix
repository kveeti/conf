{ config, ... }:

let
  vmName = "minecraft";
  stateRoot = "/var/lib/microvms/${vmName}";
in {
  homelab.microvms.${vmName} = {
    inherit stateRoot;

    secrets = [{ name = "telemetry-pass"; mode = "0400"; }];

    shares.ssh-host = {
      owner = "root"; group = "root"; mode = "0755";
      path = "/run/ssh-host"; hostPath = "${stateRoot}/ssh";
    };

    vm = {
      specialArgs = { inherit (config._module.args) keys guestIps publicGateways; };
      config = { pkgs, lib, keys, guestIps, publicGateways, ... }: {
        imports = [ ../_common.nix ];

        networking.hostName = "minecraft";

        microvm = {
          mem = lib.mkForce 8192;
          vcpu = lib.mkForce 8;
          interfaces = [{
            type = "tap";
            id = "vm-minecraft";
            mac = "02:00:00:66:00:07";
          }];
          volumes = [{
            image = "${stateRoot}/home.img";
            mountPoint = "/home";
            size = 131072;
          }];
        };

        systemd.tmpfiles.rules = [
          "d /home/veeti 0700 veeti users -"
        ];

        systemd.network.enable = true;
        systemd.network.networks."10-eth" = {
          matchConfig.Type = "ether";
          address = [ "${guestIps.minecraft}/30" ];
          routes = [{ Gateway = publicGateways.minecraft; }];
          networkConfig.DHCP = "no";
        };

        networking.firewall = {
          enable = true;
          allowedTCPPorts = [ 22 25565 ];
        };

        environment.systemPackages = [ pkgs.jdk25_headless pkgs.tmux pkgs.ghostty.terminfo pkgs.zip pkgs.unzip ];
      };
    };
  };
}
