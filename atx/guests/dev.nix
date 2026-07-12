{ config, ... }:

let
  vmName = "dev";
  stateRoot = "/var/lib/microvms/${vmName}";
in {
  homelab.microvms.${vmName} = {
    inherit stateRoot;

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
          ./_common.nix
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

        # persistent /home: project trees, deps and agent state survive rebuilds/reboots
        microvm.volumes = [{
          image = "${stateRoot}/home.img";
          mountPoint = "/home";
          size = 102400; # 100 GiB
        }];

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
          allowedTCPPorts = [ 22 ];
          # dev is the only host on vlan999, router-fenced to just the Mac (vlan10) /
          # wireguard, so a broad dev-server range is safe to leave open here.
          allowedTCPPortRanges = [ { from = 3000; to = 9999; } ];
        };

        environment.systemPackages = with pkgs; [
          git gh gnumake gcc
          nodejs_22 go python3 cargo rustc
          ripgrep fd fzf jq curl tmux direnv
          (pkgs.callPackage ../../mac/pi-coding-agent.nix { })
        ];

        programs.mosh = {
          enable = true;
          openFirewall = true;
        };

        # shared tmux config (prefix, vi copy-mode, OSC 52 clipboard) from the mac flake
        environment.etc."tmux.conf".source = "${mac}/tmux.conf";

        # zsh for parity with the mac shell; full aliases/functions stay mac-side
        programs.zsh.enable = true;
        users.defaultUserShell = pkgs.zsh;
        environment.shellAliases.e = "nvim";
      };
    };
  };
}
