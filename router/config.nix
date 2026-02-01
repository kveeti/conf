{ config, pkgs, lib, secrets, ... }:
let
  IF_WAN = "enp1s0f0";
  IF_LAN = "enp1s0f1";
in
{
  imports = [ ./ddns.nix ];

  config.nix.settings.experimental-features = [ "nix-command" "flakes" ];
  config.nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "unifi-controller"
    "unifi-controller-bleeding-edge"
  ];
  config.nixpkgs.overlays = [
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
  ];

  config.boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = 1;
    "net.ipv6.conf.all.forwarding" = 0;
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
          "vlan111"
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
        address = ["192.168.10.1/24"];
        networkConfig.IPv4Forwarding = true;
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
      "40-vlan111" = {
        matchConfig.Name = "vlan111";
        address = ["192.168.111.1/24"];
        networkConfig.IPv4Forwarding = true;
      };
      "50-container-interfaces" = {
        matchConfig.Name = "ve-*";
        networkConfig.DHCPServer = "no";
        address = ["192.168.100.1/24"];
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
          # mac
          {
            PublicKey = "/rfA2gDMRx9m3fCG5g7Oo6ir2jZFvJP9WvfTFqix7Ew=";
            PresharedKeyFile = config.age.secrets.wg_mac_presharedkey.path;
            AllowedIPs = [ "10.255.255.2/32" ];
          }
          # ip
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
      "40-vlan111" = {
        netdevConfig = {
          Kind = "vlan";
          Name = "vlan111";
        };
        vlanConfig.Id = 111;
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

  config.networking.firewall.enable = false; # if enabled, adds its own nftables rules
  config.networking.nftables.enable = true;
  config.networking.nftables.checkRuleset = true;
  config.networking.nftables.ruleset = ''
    table inet filter {
      chain rpfilter {
        type filter hook prerouting priority mangle + 10; policy drop;
        meta nfproto ipv4 udp sport . udp dport { 68 . 67, 67 . 68 } accept
        fib saddr . mark . iif oif exists accept
      }

      chain input {
        type filter hook input priority filter; policy drop;

        ct state vmap { invalid : drop, established : accept, related : accept }
        iifname "lo" accept

        ip saddr { 192.168.5.1, 192.168.10.1, 192.168.20.1, 192.168.30.1, 192.168.40.1, 192.168.111.1, 10.255.255.1 } counter drop
        ip6 saddr { ::1, fe80::/10 } counter drop

        iifname "wg0" accept comment "connected wireguard clients"
        iifname "${IF_WAN}" udp dport 49002 accept comment "wireguard handshaking"

        iifname "${IF_WAN}" counter drop

        iifname "vlan10" tcp dport 22 accept comment "vlan10 ssh"
        iifname { "vlan5", "vlan10", "vlan20", "vlan30", "vlan40", "vlan111" } udp dport 67 accept comment "vlan dhcp"
        iifname { "vlan5", "vlan10", "vlan20", "vlan30", "vlan40" } meta l4proto { tcp, udp } th dport 53 accept comment "vlan dns except vlan111"
        iifname { "vlan10", "vlan20" } udp dport 5353 accept comment "avahi mdns"
        iifname "ve-unifi" meta l4proto { tcp, udp } th dport { 8080, 8443, 10001, 3478 } accept

        icmp type echo-request accept
      }

      chain forward {
        type filter hook forward priority 0; policy drop;

        ct state vmap { invalid : drop, established : accept, related : accept }

        iifname { "wg0", "vlan10" } accept
        iifname "vlan40" oifname "vlan40" accept
        iifname "vlan40" oifname "vlan20" ip daddr 192.168.20.2 accept comment "home assistant prometheus metrics scrape"
        iifname "vlan20" oifname "vlan10" udp dport 5353 accept comment "mdns reflection"

        iifname { "wg0", "vlan5", "vlan10", "vlan20", "vlan30", "vlan40" } oifname "${IF_WAN}" accept comment "everyone gets to the WWW except vlan111"

        iifname "vlan111" ip saddr 192.168.111.0/24 ip daddr "${secrets.vlan111OutboundAllowedIP}" udp dport 49800 counter accept
        iifname "vlan111" ip saddr 192.168.111.0/24 ip daddr 192.168.40.221 meta l4proto { tcp, udp } th dport 5000 counter accept

        ip daddr 192.168.40.20 ct status dnat meta l4proto { tcp, udp } th dport { 80, 443 } counter accept comment "port forwards"
        ip daddr 192.168.40.20 ct status dnat meta l4proto { tcp, udp } th dport 7777 counter accept comment "port forwards"
        ip daddr 192.168.40.20 ct status dnat tcp dport 8888 counter accept comment "port forwards"
        ip daddr 192.168.40.20 ct status dnat udp dport 9987 counter accept comment "port forwards"

        # unifi controller
        # https://help.ui.com/hc/en-us/articles/218506997-Required-Ports-Reference
        # protocol | port  | direction | usage
        # ---------|-------|-----------|---------------------------
        # udp      | 3478  | both      | STUN for remote access
        # udp      | 10001 | ingress   | Device discovery during adoption
        # tcp      | 8080  | ingress   | Device and application communication
        # tcp      | 8443  | ingress   | Application GUI/API (on UniFi Console)
        #
        iifname "vlan5" oifname "ve-unifi" udp dport { 3478, 10001, 1900 } counter accept
        iifname "vlan5" oifname "ve-unifi" tcp dport { 8080, 8443 } counter accept
        iifname "ve-unifi" oifname "vlan5" udp dport { 3478, 10001, 1900 } counter accept
        iifname "ve-unifi" oifname "vlan5" tcp dport { 8080, 8443 } counter accept
        iifname { "vlan5", "vlan10" } tcp dport { 8443 } counter accept
      }
    }

    table ip nat {
      chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;

        # unifi controller
        iifname "vlan5" ip daddr 192.168.5.1 udp dport { 3478, 10001, 1900 } counter dnat to 192.168.100.2
        iifname "vlan5" ip daddr 192.168.5.1 tcp dport { 8080, 8443 } counter dnat to 192.168.100.2
        iifname { "vlan5", "vlan10" } ip daddr 192.168.5.1 tcp dport 443 counter dnat to 192.168.100.2:8443

        # public http traffic to 192.168.40.20
        fib daddr type local meta l4proto { tcp, udp } th dport { 80, 443 } ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } counter dnat to 192.168.40.20
        iifname "${IF_WAN}" meta l4proto { tcp, udp } th dport { 80, 443 } counter dnat to 192.168.40.20

        # satisfactory server to 192.168.40.20
        fib daddr type local meta l4proto { tcp, udp } th dport 7777 ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } counter dnat to 192.168.40.20
        iifname "${IF_WAN}" meta l4proto { tcp, udp } th dport 7777 counter dnat to 192.168.40.20
        fib daddr type local meta l4proto tcp th dport 8888 ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } counter dnat to 192.168.40.20
        iifname "${IF_WAN}" meta l4proto tcp th dport 8888 counter dnat to 192.168.40.20

        # teamspeak server to 192.168.40.20
        fib daddr type local udp dport 9987 ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } counter dnat to 192.168.40.20
        iifname "${IF_WAN}" udp dport 9987 counter dnat to 192.168.40.20

        # dns through router, except vlan40, vlan111
        iifname { "vlan10", "vlan20", "vlan30" } meta l4proto { tcp, udp } th dport 53 counter redirect to 53
      }

      chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        oifname ${IF_WAN} masquerade
      }
    }
  '';

  # dns
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
        ];
        access-control = [
          "127.0.0.1 allow"
          "10.255.255.0/24 allow"
          "192.168.5.0/24 allow"
          "192.168.10.0/24 allow"
          "192.168.20.0/24 allow"
          "192.168.30.0/24 allow"
          "192.168.40.0/24 allow"
        ];
        port = "53";
        do-ip4 = "yes";
        do-ip6 = "no";
        do-udp = "yes";
        do-tcp = "yes";

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
          ''"home.lan." static''
          ''"veetik.com." typetransparent''
        ];
        local-data = [
          ''"ui.internal.veetik.com. IN A 192.168.5.1"''
          ''"ha.internal.veetik.com. IN A 192.168.20.2"''

          ''"px1.internal.veetik.com. IN A 192.168.40.101"''
          ''"px2.internal.veetik.com. IN A 192.168.40.102"''

          ''"dav.internal.veetik.com. IN A 192.168.40.10"''
          ''"git.internal.veetik.com. IN A 192.168.40.10"''
          ''"pass.internal.veetik.com. IN A 192.168.40.10"''
          ''"rss.internal.veetik.com. IN A 192.168.40.10"''
          ''"sso.internal.veetik.com. IN A 192.168.40.10"''
          ''"ldap.internal.veetik.com. IN A 192.168.40.10"''

          ''"o11s.internal.veetik.com. IN A 192.168.40.5"''
          ''"o11s-metrics.internal.veetik.com. IN A 192.168.40.5"''

          ''"111.home.lan IN A 192.168.111.8"''
          ''"112.home.lan IN A 192.168.111.8"''
          ''"113.home.lan IN A 192.168.111.8"''
          ''"114.home.lan IN A 192.168.111.8"''
          ''"115.home.lan IN A 192.168.111.8"''
          ''"116.home.lan IN A 192.168.111.8"''
          ''"117.home.lan IN A 192.168.111.8"''
          ''"118.home.lan IN A 192.168.111.8"''
          ''"119.home.lan IN A 192.168.111.8"''
          ''"120.home.lan IN A 192.168.111.8"''

          ''"authadmin.veetik.com. IN A 192.168.40.7"''
        ];
      };
      # blocklists
      rpz = [
        {
          name = "hagezi_pro";
          url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/rpz/pro.txt";
        }
      ];
      remote-control = {
        control-enable = false;
      };
    };
  };

  # dhcp
  config.services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false;
    settings = {
      # no dns, only dhcp
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
        "BC:24:11:62:37:5C, ha,                192.168.20.2"
        "68:25:DD:49:0D:13, slzb,              192.168.20.3"
        "BC:24:11:C5:E2:F5, backup,            192.168.40.5"
        "BC:24:11:BD:EC:96, services-internal, 192.168.40.10"
        "BC:24:11:28:D5:91, services-public,   192.168.40.20"
      ];
    };
  };

  config.services.cloudflare-ddns = {
    enable = true;
    environmentFile = config.age.secrets.cloudflare_ddns_env.path;
    interval = "*:0/1";
  };
  config.systemd.services.cloudflare-ddns.after = [ "unbound.service" ];
  config.systemd.services.cloudflare-ddns.wants = [ "unbound.service" ];

  config.services.avahi = {
    enable = true;
    reflector = true;
    interfaces = [
      "vlan10"
      "vlan20"
    ];
    allowInterfaces = [
      "vlan10"
      "vlan20"
    ];
    ipv4 = true;
    ipv6 = false;
    publish = {
      enable = false;
      addresses = false;
      workstation = false;
    };
  };

  # unifi controller
  config.systemd.tmpfiles.rules = [
    "d /var/lib/unifi-container 0755 unifi unifi -"
  ];
  config.users.users.unifi = {
    isSystemUser = true;
    group = "unifi";
  };
  config.users.groups.unifi = {};
  config.containers.unifi = {
    autoStart = true;
    privateNetwork = true;
    localAddress = "192.168.100.2";
    hostAddress = "192.168.100.1";
    
    bindMounts = {
      "/var/lib/unifi" = {
        hostPath = "/var/lib/unifi-container";
        isReadOnly = false;
      };
    };

    specialArgs = { hostPkgs = pkgs; };
    config = { config, pkgs, hostPkgs, ... }: {
      nixpkgs.config.allowUnfree = true;
      services.unifi = {
        enable = true;
        openFirewall = true;
        unifiPackage = hostPkgs.unifi-bleeding-edge;
        initialJavaHeapSize = 512;  # = -Xms512m
        maximumJavaHeapSize = 1024; # = -Xmx1024m
      };

      nixpkgs.config.permittedInsecurePackages = [
        # Acknowledge MongoDB CVE-2025-11979 (https://nvd.nist.gov/vuln/detail/CVE-2025-11979)
        "mongodb-7.0.25"
      ];

      services.resolved.enable = true;
      networking = {
        firewall.allowedTCPPorts = [ 8080 8443 ];
        firewall.allowedUDPPorts = [ 3478 10001 ];
        useHostResolvConf = lib.mkForce false;
        defaultGateway = "192.168.100.1";
      };

      system.stateVersion = "25.05";
    };
  };

  config.system.stateVersion = "25.05";
}

