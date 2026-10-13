{ config, lib, pkgs, keys, ... }:

let
  homeDir = "/home/veeti/pi-agent-home";
  workspaceDir = "${homeDir}/workspace";
  guestAddress = "10.203.0.2";
  hostAddress = "10.203.0.1";
in {
  systemd.tmpfiles.rules = [
    "d ${homeDir} 0700 veeti users -"
    "d ${workspaceDir} 0700 veeti users -"
  ];

  # A private bridge with only the guest attached. Internet egress is routed
  # through the host with NAT and the destination restrictions below.
  systemd.network.enable = true;
  # NetworkManager manages the PC's uplink; don't make activation wait for the
  # isolated VM bridge (which has no carrier until the VM starts).
  systemd.network.wait-online.enable = false;
  systemd.network.netdevs."10-br-pi-agent" = {
    netdevConfig = {
      Name = "br-pi-agent";
      Kind = "bridge";
    };
  };
  systemd.network.networks = {
    "30-pi-agent-tap" = {
      matchConfig.Name = "vm-pi-agent";
      networkConfig = {
        Bridge = "br-pi-agent";
        DHCP = "no";
        LinkLocalAddressing = "no";
      };
    };
    "40-pi-agent-bridge" = {
      matchConfig.Name = "br-pi-agent";
      address = [ "${hostAddress}/30" ];
      networkConfig = {
        DHCP = "no";
        LinkLocalAddressing = "no";
        ConfigureWithoutCarrier = true;
      };
    };
  };

  # IPv4-only egress; guest access to host/LAN services remains blocked.
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 0;
  };

  networking.firewall.filterForward = true;
  networking.firewall.extraForwardRules = ''
    iifname "br-pi-agent" ip saddr ${guestAddress} oifname { "enp10s0", "wlp9s0" } accept
  '';
  networking.firewall.extraInputRules = ''
    iifname "br-pi-agent" ip saddr ${guestAddress} ip daddr ${hostAddress} tcp dport 8080 accept
  '';

  # An independent early input chain prevents global host firewall allowances
  # (such as SSH) from granting the guest access to other host services.
  # Only reply-direction traffic is exempt, so host -> guest SSH still works.
  networking.nftables.tables.pi-agent-isolation = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority -10; policy accept;
        iifname "br-pi-agent" ct state established ct direction reply accept
        iifname "br-pi-agent" ip saddr ${guestAddress} ip daddr ${hostAddress} tcp dport 8080 accept
        iifname "br-pi-agent" drop
      }
      set non_public_ipv4 {
        type ipv4_addr; flags interval;
        elements = {
          0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8,
          169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24,
          192.0.2.0/24, 192.168.0.0/16, 198.18.0.0/15,
          198.51.100.0/24, 203.0.113.0/24, 224.0.0.0/4, 240.0.0.0/4
        }
      }
      chain forward {
        type filter hook forward priority -10; policy accept;
        iifname "br-pi-agent" ip daddr @non_public_ipv4 drop
        iifname "br-pi-agent" ip saddr ${guestAddress} oifname { "enp10s0", "wlp9s0" } accept
        iifname "br-pi-agent" drop
        oifname "br-pi-agent" ip daddr ${guestAddress} ct state established ct direction reply accept
        oifname "br-pi-agent" drop
      }
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ip saddr ${guestAddress} oifname { "enp10s0", "wlp9s0" } masquerade
      }
    '';
  };

  # llama-server remains bound to 127.0.0.1:8080. This narrowly-scoped proxy
  # makes it reachable only on the guest-facing bridge address.
  systemd.services.pi-agent-llama-proxy = {
    description = "Expose the local llama.cpp API to the isolated pi-agent VM";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "systemd-networkd.service" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      ExecStartPre = ''
        ${pkgs.bash}/bin/bash -c 'for i in {1..30}; do if ${pkgs.iproute2}/bin/ip -4 -o addr show dev br-pi-agent | ${pkgs.gnugrep}/bin/grep -q "${hostAddress}/30"; then exit 0; fi; sleep 1; done; exit 1'
      '';
      ExecStart = "${pkgs.socat}/bin/socat TCP4-LISTEN:8080,bind=${hostAddress},reuseaddr,fork TCP4:127.0.0.1:8080";
      Restart = "on-failure";
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
    };
  };

  microvm.vms.pi-agent = {
    autostart = false;
    config = { pkgs, ... }: {
      imports = [
        ({ lib, ... }: {
          boot.loader.grub.enable = false;
          boot.loader.systemd-boot.enable = false;

          microvm = {
            hypervisor = "cloud-hypervisor";
            mem = 4096;
            vcpu = 4;
            volumes = [{
              image = "/var/lib/microvms/pi-agent/ssh-host.img";
              mountPoint = "/var/lib/ssh-host";
              size = 32;
            }];
            shares = [
              {
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
                tag = "ro-store";
                proto = "virtiofs";
              }
              {
                source = homeDir;
                mountPoint = "/home/veeti";
                tag = "agent-home";
                proto = "virtiofs";
              }
            ];
            interfaces = [{
              type = "tap";
              id = "vm-pi-agent";
              mac = "02:00:00:20:30:02";
            }];
          };

          networking = {
            hostName = "pi-agent";
            useDHCP = false;
            useNetworkd = true;
            nameservers = lib.mkForce [ "1.1.1.1" "9.9.9.9" ];
            firewall.enable = true;
            nftables.enable = true;
          };

          systemd.network.enable = true;
          systemd.network.networks."10-ethernet" = {
            matchConfig.MACAddress = "02:00:00:20:30:02";
            address = [ "${guestAddress}/30" ];
            routes = [{ Gateway = hostAddress; }];
            networkConfig = {
              DNS = [ "1.1.1.1" "9.9.9.9" ];
              IPv6AcceptRA = false;
              DHCP = "no";
              LinkLocalAddressing = "no";
            };
          };

          services.getty.autologinUser = "veeti";
          services.openssh = {
            enable = true;
            openFirewall = false;
            hostKeys = [{
              type = "ed25519";
              path = "/var/lib/ssh-host/ssh_host_ed25519_key";
            }];
            settings = {
              AllowUsers = [ "veeti" ];
              PermitRootLogin = "no";
              PasswordAuthentication = false;
              KbdInteractiveAuthentication = false;
            };
          };
          systemd.services.sshd-keygen.unitConfig.RequiresMountsFor = "/var/lib/ssh-host";
          networking.firewall.extraInputRules = ''
            ip saddr ${hostAddress} tcp dport 22 accept
          '';

          systemd.services.pi-agent-llama-local = {
            description = "Forward guest localhost llama API to the isolated host proxy";
            wantedBy = [ "multi-user.target" ];
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            serviceConfig = {
              ExecStart = "${pkgs.socat}/bin/socat TCP4-LISTEN:8080,bind=127.0.0.1,reuseaddr,fork TCP4:${hostAddress}:8080";
              Restart = "on-failure";
              DynamicUser = true;
              NoNewPrivileges = true;
              PrivateTmp = true;
              ProtectHome = true;
              ProtectSystem = "strict";
            };
          };

          users.users.veeti = {
            isNormalUser = true;
            uid = 1000;
            home = "/home/veeti";
            createHome = false;
            shell = pkgs.bashInteractive;
            openssh.authorizedKeys.keys = keys.admins;
          };

          environment.systemPackages = with pkgs; [
            (callPackage ./pi-coding-agent.nix {})
            nodejs
            pnpm
            ghostty.terminfo
            git
            socat
            ripgrep
            fd
          ];

          system.stateVersion = "26.05";
        })
      ];
    };
  };
}
