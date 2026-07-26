{ config, pkgs, lib, secrets, serviceDnsRecords ? [], ... }:
let
  IF_WAN = "enp1s0f0";
  IF_LAN = "enp1s0f1";
  IF_IFB = "ifb-wan";
  UPLOAD_CAP_MBITS = 600;
  DOWNLOAD_CAP_MBITS = 600;
  SIX_RD = "6rd-*";

  inventory = import ./inventory.nix;
  hosts = inventory.hosts;

  serviceLocalData = map (record:
    ''"${record.name}. IN A ${record.address}"''
  ) serviceDnsRecords;
in
{
  imports = [ ./ddns.nix ./observability.nix ./unifi-vm.nix ];

  config.nix.settings.experimental-features = [ "nix-command" "flakes" ];
  config.nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "mongodb-ce"
    "unifi-controller"
    "unifi-controller-bleeding-edge"
  ];
  config.nixpkgs.overlays = [
    (import ./overlays/mongodb-ce-7.nix)
    (import ./overlays/unifi-bleeding-edge.nix)
  ];

  config.boot.loader.systemd-boot.enable = true;
  config.boot.loader.efi.canTouchEfiVariables = true;

  config.time.timeZone = "Europe/Helsinki";
  config.i18n.defaultLocale = "en_US.UTF-8";
  config.i18n.extraLocaleSettings = {
    LC_ADDRESS = "fi_FI.UTF-8";
    LC_IDENTIFICATION = "fi_FI.UTF-8";
    LC_MEASUREMENT = "fi_FI.UTF-8";
    LC_MONETARY = "fi_FI.UTF-8";
    LC_NAME = "fi_FI.UTF-8";
    LC_NUMERIC = "fi_FI.UTF-8";
    LC_PAPER = "fi_FI.UTF-8";
    LC_TELEPHONE = "fi_FI.UTF-8";
    LC_TIME = "fi_FI.UTF-8";
  };
  config.console.keyMap = "fi";
  config.services.xserver.xkb = {
    layout = "fi";
    variant = "";
  };

  config.networking.hostName = "router";

  config.services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
      ChallengeResponseAuthentication = false;
      X11Forwarding = false;
    };
    hostKeys = [{
      type = "ed25519";
      path = "/etc/ssh/ssh_host_ed25519_key";
    }];
  };

  config.users.users = {
    root = {
      openssh.authorizedKeys.keys = secrets.keys.admins;
      hashedPasswordFile = config.age.secrets.password.path;
    };

    veeti = {
      openssh.authorizedKeys.keys = secrets.keys.admins;
      extraGroups = [ "wheel" ];
      createHome = true;
      useDefaultShell = true;
      isNormalUser = true;
      hashedPasswordFile = config.age.secrets.password.path;
    };
  };
  config.security.sudo.wheelNeedsPassword = false;

  config.environment.systemPackages = with pkgs; [
    iproute2
    tcpdump
    ethtool
    bridge-utils
    wireguard-tools
    speedtest-cli
    btop
    vim
    igmpproxy
  ];

  config.boot.kernelModules = [ "ifb" ];

  config.boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;

    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.tcp_max_syn_backlog" = 2048;
    "net.ipv4.tcp_synack_retries" = 2;
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;

    "net.netfilter.nf_conntrack_tcp_timeout_syn_sent" = 120;
    "net.netfilter.nf_conntrack_tcp_timeout_syn_recv" = 60;
    "net.netfilter.nf_conntrack_tcp_timeout_fin_wait" = 120;
    "net.netfilter.nf_conntrack_tcp_timeout_time_wait" = 120;
    "net.netfilter.nf_conntrack_tcp_timeout_close_wait" = 60;
    "net.netfilter.nf_conntrack_tcp_timeout_last_ack" = 30;
    "net.netfilter.nf_conntrack_generic_timeout" = 600;
    "net.netfilter.nf_conntrack_icmp_timeout" = 30;
    "net.netfilter.nf_conntrack_buckets" = 65536;
    "net.netfilter.nf_conntrack_max" = 1048576;
    "net.netfilter.nf_conntrack_tcp_timeout_established" = 7440;

    "net.core.rmem_max" = 134217728;
    "net.core.wmem_max" = 134217728;
    "net.ipv4.tcp_rmem" = "4096 87380 134217728";
    "net.ipv4.tcp_wmem" = "4096 65536 134217728";
  };

  config.networking.useNetworkd = true;
  config.age.secrets.wg_privkey = {
    mode = "640";
    owner = "systemd-network";
    group = "systemd-network";
  };
  config.age.secrets.wg_mac_pubkey = {
    mode = "640";
    owner = "systemd-network";
    group = "systemd-network";
  };
  config.age.secrets.wg_mac_presharedkey = {
    mode = "640";
    owner = "systemd-network";
    group = "systemd-network";
  };
  config.age.secrets.wg_ip_pubkey = {
    mode = "640";
    owner = "systemd-network";
    group = "systemd-network";
  };
  config.age.secrets.wg_ip_presharedkey = {
    mode = "640";
    owner = "systemd-network";
    group = "systemd-network";
  };

  config.systemd.network = {
    enable = true;
    networks = {
      "10-wan" = {
        matchConfig.Name = IF_WAN;
        networkConfig.DHCP = "ipv4";
        linkConfig.RequiredForOnline = "routable";
        dhcpV4Config.Use6RD = true;
      };

      "10-lan" = {
        matchConfig.Name = IF_LAN;
        linkConfig.RequiredForOnline = "routable";
        networkConfig.LinkLocalAddressing = false;
        vlan = [
          "vlan5"
          "vlan10"
          "vlan20"
          "vlan30"
          "vlan40"
          "vlan70"
          "vlan71"
          "vlan72"
          "vlan73"
          "vlan111"
          "vlan999"
        ];
      };

      "30-wg0" = {
         matchConfig.Name = "wg0";
         address = ["10.255.255.1/24"];
         networkConfig.IPMasquerade = "ipv4";
      };

      "40-vlan5" = {
        matchConfig.Name = "vlan5";
        address = ["192.168.5.1/24"];
        networkConfig.IPv4Forwarding = true;
      };
      "40-vlan10" = {
        matchConfig.Name = "vlan10";
        address = ["192.168.10.1/24" "fd00:10::1/64"];
        networkConfig = {
          IPv4Forwarding = true;
          DHCPPrefixDelegation = true;
          IPv6SendRA = true;
          DNS = [ "fd00:10::1" ];
        };
        ipv6SendRAConfig.EmitDNS = true;
        ipv6Prefixes = [{
          Prefix = inventory.networks.trusted.cidr6;
          AddressAutoconfiguration = true;
          OnLink = true;
        }];
        dhcpV6Config.UseDNS = false;
      };
      "40-vlan20" = {
        matchConfig.Name = "vlan20";
        address = ["192.168.20.1/24"];
        networkConfig.IPv4Forwarding = true;
      };
      "40-vlan30" = {
        matchConfig.Name = "vlan30";
        address = ["192.168.30.1/24"];
        networkConfig.IPv4Forwarding = true;
      };
      "40-vlan40" = {
        matchConfig.Name = "vlan40";
        address = ["192.168.40.1/24"];
        networkConfig.IPv4Forwarding = true;
      };
      "40-vlan70" = {
        matchConfig.Name = "vlan70";
        address = ["192.168.70.1/30"];
        networkConfig.IPv4Forwarding = true;
      };
      "40-vlan71" = {
        matchConfig.Name = "vlan71";
        address = ["192.168.71.1/30"];
        networkConfig.IPv4Forwarding = true;
      };
      "40-vlan72" = {
        matchConfig.Name = "vlan72";
        address = ["192.168.72.1/30"];
        networkConfig.IPv4Forwarding = true;
      };
      "40-vlan73" = {
        matchConfig.Name = "vlan73";
        address = ["192.168.73.1/30"];
        networkConfig.IPv4Forwarding = true;
      };
      "40-vlan111" = {
        matchConfig.Name = "vlan111";
        address = ["192.168.111.1/24"];
        networkConfig.IPv4Forwarding = true;
      };
      "40-vlan999" = {
        matchConfig.Name = "vlan999";
        address = ["192.168.99.1/24"];
        networkConfig.IPv4Forwarding = true;
      };
      "50-unifi-interface" = {
        matchConfig.Name = "vm-unifi";
        networkConfig = {
          DHCP = "no";
          IPv4Forwarding = true;
          LinkLocalAddressing = false;
        };
        address = [ "192.168.100.1/24" ];
      };
    };
    netdevs = {
      "30-wg0" = {
        netdevConfig = {
          Kind = "wireguard";
          Name = "wg0";
          MTUBytes = "1300";
        };
        wireguardConfig = {
          PrivateKeyFile = config.age.secrets.wg_privkey.path;
          ListenPort = 49002;
        };
        wireguardPeers = [
          {
            PublicKey = "/rfA2gDMRx9m3fCG5g7Oo6ir2jZFvJP9WvfTFqix7Ew=";
            PresharedKeyFile = config.age.secrets.wg_mac_presharedkey.path;
            AllowedIPs = [ "10.255.255.2/32" ];
          }
          {
            PublicKey = "XcTHMvTMJUCP87GphFxEYEL6vc6Fuq//93BLRWUqbng=";
            PresharedKeyFile = config.age.secrets.wg_ip_presharedkey.path;
            AllowedIPs = [ "10.255.255.3/32" ];
          }
        ];
      };

      "40-vlan5-management" = {
        netdevConfig = {
          Kind = "vlan";
          Name = "vlan5";
        };
        vlanConfig.Id = 5;
      };
      "40-vlan10-trusted" = {
        netdevConfig = {
          Kind = "vlan";
          Name = "vlan10";
        };
        vlanConfig.Id = 10;
      };
      "40-vlan20-iot" = {
        netdevConfig = {
          Kind = "vlan";
          Name = "vlan20";
        };
        vlanConfig.Id = 20;
      };
      "40-vlan30-untrusted" = {
        netdevConfig = {
          Kind = "vlan";
          Name = "vlan30";
        };
        vlanConfig.Id = 30;
      };
      "40-vlan40-servers" = {
        netdevConfig = {
          Kind = "vlan";
          Name = "vlan40";
        };
        vlanConfig.Id = 40;
      };
      "40-vlan70-nginx-public" = {
        netdevConfig = {
          Kind = "vlan";
          Name = "vlan70";
        };
        vlanConfig.Id = 70;
      };
      "40-vlan71-tasks" = {
        netdevConfig = {
          Kind = "vlan";
          Name = "vlan71";
        };
        vlanConfig.Id = 71;
      };
      "40-vlan72-bm" = {
        netdevConfig = {
          Kind = "vlan";
          Name = "vlan72";
        };
        vlanConfig.Id = 72;
      };
      "40-vlan73-modi" = {
        netdevConfig = {
          Kind = "vlan";
          Name = "vlan73";
        };
        vlanConfig.Id = 73;
      };
      "40-vlan111" = {
        netdevConfig = {
          Kind = "vlan";
          Name = "vlan111";
        };
        vlanConfig.Id = 111;
      };
      "40-vlan999-dev" = {
        netdevConfig = {
          Kind = "vlan";
          Name = "vlan999";
        };
        vlanConfig.Id = 999;
      };
    };
  };

  config.systemd.services.ethtool-optimize = {
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      for iface in ${IF_WAN} ${IF_LAN}; do
        ${pkgs.ethtool}/bin/ethtool -K $iface tso on gso on gro on
        ${pkgs.ethtool}/bin/ethtool -G $iface rx 4096 tx 4096
        ${pkgs.ethtool}/bin/ethtool -C $iface rx-usecs 1 tx-usecs 0
      done
    '';
  };

  config.systemd.services.sqm = {
    description = "WAN smart queue management";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.iproute2}/bin/ip link add ${IF_IFB} type ifb 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip link set ${IF_IFB} up

      ${pkgs.iproute2}/bin/tc qdisc replace dev ${IF_WAN} root handle 1: htb default 10
      ${pkgs.iproute2}/bin/tc class replace dev ${IF_WAN} parent 1: classid 1:10 htb rate ${toString UPLOAD_CAP_MBITS}mbit ceil ${toString UPLOAD_CAP_MBITS}mbit
      ${pkgs.iproute2}/bin/tc qdisc replace dev ${IF_WAN} parent 1:10 handle 10: fq_codel

      ${pkgs.iproute2}/bin/tc qdisc replace dev ${IF_WAN} handle ffff: ingress
      ${pkgs.iproute2}/bin/tc filter replace dev ${IF_WAN} parent ffff: protocol all pref 1 u32 match u32 0 0 action mirred egress redirect dev ${IF_IFB}
      ${pkgs.iproute2}/bin/tc qdisc replace dev ${IF_IFB} root handle 1: htb default 10
      ${pkgs.iproute2}/bin/tc class replace dev ${IF_IFB} parent 1: classid 1:10 htb rate ${toString DOWNLOAD_CAP_MBITS}mbit ceil ${toString DOWNLOAD_CAP_MBITS}mbit
      ${pkgs.iproute2}/bin/tc qdisc replace dev ${IF_IFB} parent 1:10 handle 10: fq_codel
    '';
    preStop = ''
      ${pkgs.iproute2}/bin/tc qdisc del dev ${IF_WAN} root 2>/dev/null || true
      ${pkgs.iproute2}/bin/tc qdisc del dev ${IF_WAN} ingress 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip link del ${IF_IFB} 2>/dev/null || true
    '';
  };

  config.networking.firewall.enable = false; # if enabled, adds its own nftables rules
  config.networking.nftables.enable = true;
  config.networking.nftables.checkRuleset = true;
  config.networking.nftables.ruleset = ''
    table inet filter {
      chain rpfilter {
        type filter hook prerouting priority mangle + 10; policy drop;
        meta nfproto ipv4 udp sport . udp dport { 68 . 67, 67 . 68 } accept
        iifname "${IF_IFB}" fib saddr . mark oifname "${IF_WAN}" accept
        fib saddr . mark . iif oif exists accept
      }

      chain input {
        type filter hook input priority filter; policy drop;

        ct state vmap { invalid : drop, established : accept, related : accept }
        iifname "lo" accept
        meta l4proto ipv6-icmp accept

        ip saddr { 192.168.5.1, 192.168.10.1, 192.168.20.1, 192.168.30.1, 192.168.40.1, 192.168.70.1, 192.168.71.1, 192.168.72.1, 192.168.73.1, 192.168.111.1, 192.168.99.1, 10.255.255.1 } counter drop
        ip6 saddr { ::1 } counter drop

        iifname "wg0" accept comment "connected wireguard clients"
        iifname { "${IF_WAN}", "${IF_IFB}" } udp dport 49002 accept comment "wireguard handshaking"

        iifname { "${IF_WAN}", "${IF_IFB}" } counter drop
        iifname "${SIX_RD}" counter drop

        iifname "vlan10" tcp dport 22 accept comment "vlan10 ssh"
        iifname { "vlan5", "vlan10", "vlan20", "vlan30", "vlan40", "vlan111" } udp dport 67 accept comment "vlan dhcp"
        iifname { "vlan5", "vlan10", "vlan20", "vlan30", "vlan40", "vlan999" } meta l4proto { tcp, udp } th dport 53 accept comment "vlan dns except vlan111"

        iifname { "vlan10", "vlan20", "vlan40" } udp dport 5353 accept comment "avahi mdns"
        meta l4proto igmp accept comment "allow igmp for multicast routing"
        iifname { "vlan10", "vlan20" } udp dport { 319, 320 } accept comment "AirPlay PTP sync"

        iifname "vm-unifi" meta l4proto { tcp, udp } th dport { 8080, 8443, 10001, 3478 } accept

        icmp type echo-request accept
      }

      chain forward {
        type filter hook forward priority 0; policy drop;

        iifname "vlan70" ip saddr != ${hosts.nginxPublic.ipv4} counter drop comment "anti-spoof nginx-public"
        iifname "vlan71" ip saddr != ${hosts.tasks.ipv4} counter drop comment "anti-spoof tasks"
        iifname "vlan72" ip saddr != ${hosts.bm.ipv4} counter drop comment "anti-spoof bm"
        iifname "vlan73" ip saddr != ${hosts.modi.ipv4} counter drop comment "anti-spoof modi"

        ct state vmap { invalid : drop, established : accept, related : accept }

        iifname { "wg0", "vlan10" } accept
        iifname { "wg0", "vlan5", "vlan10", "vlan20", "vlan30", "vlan40", "vlan70", "vlan71", "vlan72", "vlan73", "vlan999" } oifname "${IF_WAN}" accept comment "everyone gets to the WWW except vlan111"

        tcp flags syn tcp option maxseg size set rt mtu
        iifname { "vlan10" } oifname "${SIX_RD}" accept
        meta l4proto ipv6-icmp accept
        iifname "${SIX_RD}" ct state { new, untracked } counter drop

        iifname "vlan40" oifname "vlan40" accept
        iifname "vlan40" oifname "vlan20" ip daddr ${hosts.homeAssistant.ipv4} accept comment "home assistant prometheus metrics scrape"

        iifname "vlan70" oifname "vlan40" ip saddr ${hosts.nginxPublic.ipv4} ip daddr ${hosts.backup.ipv4} tcp dport { 8428, 9428 } accept comment "nginx-public -> backup host observability"
        iifname "vlan71" oifname "vlan40" ip saddr ${hosts.tasks.ipv4} ip daddr ${hosts.backup.ipv4} tcp dport { 8000, 8428, 9428 } accept comment "tasks -> backup host rest-server + observability"
        iifname "vlan72" oifname "vlan40" ip saddr ${hosts.bm.ipv4} ip daddr ${hosts.backup.ipv4} tcp dport { 8000, 8428, 9428 } accept comment "bm -> backup host rest-server + observability"
        iifname "vlan73" oifname "vlan40" ip saddr ${hosts.modi.ipv4} ip daddr ${hosts.backup.ipv4} tcp dport { 8000, 8428, 9428 } accept comment "modi -> backup host rest-server + observability"
        iifname "vlan20" oifname "vlan40" ip saddr ${hosts.homeAssistant.ipv4} ip daddr ${hosts.backup.ipv4} tcp dport { 8000, 8428, 9428 } accept comment "home assistant -> backup host rest-server + observability"

        iifname "vlan70" oifname "vlan71" ip saddr ${hosts.nginxPublic.ipv4} ip daddr ${hosts.tasks.ipv4} tcp dport 8000 accept comment "nginx-public -> tasks backend"
        iifname "vlan70" oifname "vlan72" ip saddr ${hosts.nginxPublic.ipv4} ip daddr ${hosts.bm.ipv4} tcp dport 8000 accept comment "nginx-public -> bm backend"

        iifname "vlan40" oifname "vlan70" ip saddr ${hosts.backup.ipv4} ip daddr ${hosts.nginxPublic.ipv4} tcp dport 443 accept comment "backup host blackbox probes -> nginx-public"

        iifname "vlan20" oifname "vlan111" ether saddr ${hosts.appleTv.mac} ip saddr ${hosts.appleTv.ipv4} ip daddr ${hosts.jellyfin.ipv4} tcp dport 443 counter accept comment "Apple TV -> Jellyfin"

        iifname "vlan20" oifname "vlan10" udp dport 5353 accept comment "mdns reflection"
        ip daddr 224.0.1.129 udp dport { 319, 320 } accept comment "AirPlay PTP multicast routing"
        iifname "vlan20" oifname "vlan10" udp dport { 319, 320 } accept comment "AirPlay PTP return"

        iifname "vlan111" ip saddr 192.168.111.0/24 ip daddr "${secrets.vlan111OutboundAllowedIP}" udp dport 49800 counter accept
        iifname "vlan111" ip saddr 192.168.111.0/24 ip daddr ${hosts.vlan111Service.ipv4} meta l4proto { tcp, udp } th dport 5000 counter accept

        ip daddr ${hosts.nginxPublic.ipv4} ct status dnat meta l4proto { tcp, udp } th dport { 80, 443 } counter accept comment "port forwards"

        # unifi controller
        # https://help.ui.com/hc/en-us/articles/218506997-Required-Ports-Reference
        # protocol | port  | direction | usage
        # ---------|-------|-----------|---------------------------
        # udp      | 3478  | both      | STUN for remote access
        # udp      | 10001 | ingress   | Device discovery during adoption
        # tcp      | 8080  | ingress   | Device and application communication
        # tcp      | 8443  | ingress   | Application GUI/API (on UniFi Console)
        #
        iifname "vlan5" oifname "vm-unifi" udp dport { 3478, 10001, 1900 } counter accept
        iifname "vlan5" oifname "vm-unifi" tcp dport { 8080, 8443 } counter accept
        iifname "vm-unifi" oifname "vlan5" udp dport { 3478, 10001, 1900 } counter accept
        iifname "vm-unifi" oifname "vlan5" tcp dport { 8080, 8443 } counter accept
        iifname { "vlan5", "vlan10" } tcp dport { 8443 } counter accept
      }
    }

    table inet nat {
      chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;

        iifname "vlan5" ip daddr 192.168.5.1 udp dport { 3478, 10001, 1900 } counter dnat to ${hosts.unifiController.ipv4}
        iifname "vlan5" ip daddr 192.168.5.1 tcp dport { 8080, 8443 } counter dnat to ${hosts.unifiController.ipv4}
        iifname { "vlan5", "vlan10" } ip daddr 192.168.5.1 tcp dport 443 counter dnat to ${hosts.unifiController.ipv4}:8443

        fib daddr type local meta l4proto { tcp, udp } th dport { 80, 443 } ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } counter dnat to ${hosts.nginxPublic.ipv4}
        meta nfproto ipv4 iifname "${IF_WAN}" meta l4proto { tcp, udp } th dport { 80, 443 } counter dnat to ${hosts.nginxPublic.ipv4}

        iifname { "vlan10", "vlan20", "vlan30", "vlan999" } meta l4proto { tcp, udp } th dport 53 counter redirect to 53
      }

      chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        oifname ${IF_WAN} masquerade
      }
    }
  '';

#  config.services.suricata = {
#    enable = true;
#    # By default, NixOS runs suricata-update to fetch the Emerging Threats (ET) Open ruleset
#
#    settings = {
#      app-layer.protocols = {
#        modbus = {
#          enabled = "yes";
#          "detection-enabled" = "yes";
#        };
#        dnp3 = {
#          enabled = "yes";
#          detection-enabled = "yes";
#        };
#        enip = {
#          enabled = "yes";
#          detection-enabled = "yes";
#        };
#      };
#
#      vars = {
#        address-groups = {
#          # Encompasses your VLANs (192.168.0.0/16) and WireGuard (10.255.255.0/24)
#          HOME_NET = "[192.168.0.0/16, 10.255.255.0/24, fd00::/8, fe80::/10]";
#          EXTERNAL_NET = "!$HOME_NET";
#        };
#      };
#
#      af-packet = [
#        {
#          interface = IF_WAN;
#          cluster-id = 99;
#          cluster-type = "cluster_flow";
#          defrag = "yes";
#        }
#        {
#          interface = IF_LAN;
#          cluster-id = 98;
#          cluster-type = "cluster_flow";
#          defrag = "yes";
#        }
#        {
#          interface = "wg0";
#          cluster-id = 97;
#          cluster-type = "cluster_flow";
#          defrag = "yes";
#        }
#      ];
#
#      outputs = [
#        {
#          fast = {
#            enabled = true;
#            filename = "fast.log";
#            append = "yes";
#          };
#        }
#        {
#          eve-log = {
#            enabled = true;
#            filetype = "regular";
#            filename = "eve.json";
#            types = [
#              { alert = { payload = "yes"; payload-buffer-size = 4096; payload-printable = "yes"; packet = "yes"; }; }
#              "dns"
#              "tls"
#              "flow"
#            ];
#          };
#        }
#      ];
#    };
#  };

#  config.services.logrotate = {
#    enable = true;
#    settings = {
#      "suricata" = {
#        files = [ 
#          "/var/log/suricata/*.log" 
#          "/var/log/suricata/*.json" 
#        ];
#        frequency = "daily";
#        rotate = 7;
#        compress = true;
#        delaycompress = true;
#        missingok = true;
#        notifempty = true;
#        postrotate = ''
#          # Send SIGHUP to Suricata to close and reopen log files
#          ${pkgs.systemd}/bin/systemctl kill -s HUP suricata.service >/dev/null 2>&1 || true
#        '';
#      };
#    };
#  };

  config.environment.etc."igmpproxy.conf".text = ''
    quickleave

    phyint vlan10 upstream ratelimit 0 threshold 1
            altnet 192.168.10.0/24

    phyint vlan20 downstream ratelimit 0 threshold 1
            altnet 192.168.20.0/24

    phyint wg0 disabled
    phyint vlan5 disabled
    phyint vlan30 disabled
    phyint vlan40 disabled
    phyint vlan70 disabled
    phyint vlan71 disabled
    phyint vlan72 disabled
    phyint vlan73 disabled
    phyint vlan111 disabled
    phyint vlan999 disabled
    phyint vm-unifi disabled
    phyint lo disabled
  '';
  
  config.systemd.services.igmpproxy = {
    description = "IGMP Proxy for AirPlay PTP";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.igmpproxy}/bin/igmpproxy -n /etc/igmpproxy.conf";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  config.services.resolved.enable = false;
  config.services.unbound = {
    enable = true;
    checkconf = true;
    resolveLocalQueries = true;
    enableRootTrustAnchor = true;
    settings = {
      forward-zone = [
        {
          name = ".";
          forward-addr = [
            "9.9.9.9@853#dns.quad9.net"
            "149.112.112.112@853#dns.quad9.net"
          ];
          forward-tls-upstream = "yes";
        }
      ];
      server = {
        #verbosity = "2";
        #log-queries = "yes";
        #log-replies = "yes";
        #log-servfail = "yes";
        #log-local-actions = "yes";
        verbosity = "0";
        log-queries = "no";
        log-replies = "no";
        log-servfail = "no";
        log-local-actions = "no";

        module-config = ''"respip validator iterator"'';
        interface = [
          "127.0.0.1"
          "10.255.255.1"
          "192.168.5.1"
          "192.168.10.1"
          "192.168.20.1"
          "192.168.30.1"
          "192.168.40.1"
          "192.168.99.1"
          "::0"
        ];
        access-control = [
          "127.0.0.1 allow"
          "10.255.255.0/24 allow"
          "192.168.5.0/24 allow"
          "192.168.10.0/24 allow"
          "192.168.20.0/24 allow"
          "192.168.30.0/24 allow"
          "192.168.40.0/24 allow"
          "192.168.99.0/24 allow"
          "::1 allow"
          "fe80::/10 allow"
          "fd00::/8 allow"
        ];
        port = "53";
        do-ip4 = "yes";
        do-ip6 = "yes";
        do-udp = "yes";
        do-tcp = "yes";

        interface-automatic = "yes";

        hide-identity = "yes";
        hide-version = "yes";
        harden-glue = "yes";
        harden-dnssec-stripped = "yes";
        use-caps-for-id = "yes";
        harden-below-nxdomain = "yes";
        harden-referral-path = "yes";
        qname-minimisation = "yes";
        num-threads = "2";

        prefetch = "yes";
        prefetch-key = "yes";
        neg-cache-size = "4m";
        cache-max-negative-ttl = "300";
        msg-cache-size = "50m";
        rrset-cache-size = "100m";
        key-cache-size = "4m";
        cache-min-ttl = 300;
        cache-max-ttl = 86400;
        aggressive-nsec = "yes";

        serve-expired = "yes";
        serve-expired-ttl = "120";
        serve-expired-client-timeout = "1800";
        serve-expired-reply-ttl = "30";

        so-reuseport = "yes";
        minimal-responses = "yes";
        rrset-roundrobin = "yes";
        so-rcvbuf = "1m";

        local-zone = [
          ''"internal.veetik.com." static''
          ''"dev-internal.veetik.com." redirect''
          ''"media.lan." redirect''
          ''"jellyfin.media.lan." static''
          ''"veetik.com." typetransparent''
        ];
        local-data = [
          ''"ui.internal.veetik.com. IN A ${hosts.router.ipv4}"''
          ''"ha.internal.veetik.com. IN A ${hosts.homeAssistant.ipv4}"''
          ''"z2m.internal.veetik.com. IN A ${hosts.homeAssistant.ipv4}"''

          ''"printer.internal.veetik.com. IN A ${hosts.printer.ipv4}"''

          ''"grafana.internal.veetik.com. IN A ${hosts.backup.ipv4}"''

          ''"dev.internal.veetik.com. IN A ${hosts.dev.ipv4}"''
          ''"dev-internal.veetik.com. IN A ${hosts.dev.ipv4}"''

          ''"media.lan. IN A ${hosts.media.ipv4}"''
          ''"jellyfin.media.lan. IN A ${hosts.jellyfin.ipv4}"''
        ] ++ serviceLocalData;
      };
      rpz = [
        {
          name = "hagezi_pro";
          url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/rpz/pro.txt";
        }
      ];
      # Unix socket, no TLS: a TCP control port needs a runtime-only server-key-file that breaks checkconf.
      remote-control = {
        control-enable = true;
        control-interface = "/run/unbound/unbound.ctl";
        control-use-cert = false;
      };
    };
  };

  config.services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false;
    settings = {
      port = 0;

      interface = [ "vlan5" "vlan10" "vlan20" "vlan30" "vlan40" "vlan111" ];
      dhcp-range = [
        "set:vlan5,   192.168.5.2,    192.168.5.254,  24h"
        "set:vlan10,  192.168.10.200, 192.168.10.254, 24h"
        "set:vlan20,  192.168.20.10,  192.168.20.254, 24h"
        "set:vlan30,  192.168.30.2,   192.168.30.254, 24h"
        "set:vlan40,  192.168.40.200, 192.168.40.254, 24h"
        "set:vlan111, 192.168.111.8,  192.168.111.8,  24h"
      ];
      dhcp-option = [
        "tag:vlan5,   option:router,     192.168.5.1"
        "tag:vlan5,   option:dns-server, 192.168.5.1"

        "tag:vlan10,  option:router,     192.168.10.1"
        "tag:vlan10,  option:dns-server, 192.168.10.1"

        "tag:vlan20,  option:router,     192.168.20.1"
        "tag:vlan20,  option:dns-server, 192.168.20.1"

        "tag:vlan30,  option:router,     192.168.30.1"
        "tag:vlan30,  option:dns-server, 192.168.30.1"

        "tag:vlan40,  option:router,     192.168.40.1"
        "tag:vlan40,  option:dns-server, 192.168.40.1"

        "tag:vlan111, option:router,     192.168.111.1"
        "tag:vlan111, option:dns-server, 1.1.1.1,1.0.0.1,9.9.9.9,149.112.112.112"
      ];
      dhcp-host = [
        "${hosts.slzb.mac}, ${hosts.slzb.hostname}, ${hosts.slzb.ipv4}"
        "${hosts.appleTv.mac}, ${hosts.appleTv.hostname}, ${hosts.appleTv.ipv4}"
        "${hosts.atx.mac}, ${hosts.atx.hostname}, ${hosts.atx.ipv4}"
        "${hosts.backup.mac}, ${hosts.backup.hostname}, ${hosts.backup.ipv4}"
      ];
    };
  };

  config.homelab.cloudflare-ddns = {
    enable = true;
    environmentFile = config.age.secrets.cloudflare_ddns_env.path;
    interval = "*:0/1";
  };
  config.systemd.services.cloudflare-ddns.after = [ "unbound.service" ];
  config.systemd.services.cloudflare-ddns.wants = [ "unbound.service" ];

  config.services.avahi = {
    enable = true;
    reflector = true;
    allowInterfaces = [
      "vlan10"
      "vlan20"
      "vlan40"
    ];
    extraConfig = ''
      reflect-filters=_airplay._tcp.local,_raop._tcp.local,_ipp._tcp.local,_ipps._tcp.local,_printer._tcp.local
    '';
    ipv4 = true;
    ipv6 = false;
    publish = {
      enable = false;
      addresses = false;
      workstation = false;
    };
  };

  config.system.stateVersion = "25.05";
}
