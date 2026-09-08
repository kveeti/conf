{
  networks = {
    management = {
      dhcp = {
        start = "192.168.5.2";
        end = "192.168.5.254";
        lease = "24h";
      };
      interface = "vlan5";
      vlan = 5;
      cidr4 = "192.168.5.0/24";
      router4 = "192.168.5.1";
    };

    trusted = {
      dhcp = {
        start = "192.168.10.200";
        end = "192.168.10.254";
        lease = "24h";
      };
      interface = "vlan10";
      vlan = 10;
      cidr4 = "192.168.10.0/24";
      router4 = "192.168.10.1";
      cidr6 = "fd00:10::/64";
      router6 = "fd00:10::1";
    };

    iot = {
      dhcp = {
        start = "192.168.20.10";
        end = "192.168.20.254";
        lease = "24h";
      };
      interface = "vlan20";
      vlan = 20;
      cidr4 = "192.168.20.0/24";
      router4 = "192.168.20.1";
    };

    untrusted = {
      dhcp = {
        start = "192.168.30.2";
        end = "192.168.30.254";
        lease = "24h";
      };
      interface = "vlan30";
      vlan = 30;
      cidr4 = "192.168.30.0/24";
      router4 = "192.168.30.1";
    };

    servers = {
      dhcp = {
        start = "192.168.40.200";
        end = "192.168.40.254";
        lease = "24h";
      };
      interface = "vlan40";
      vlan = 40;
      cidr4 = "192.168.40.0/24";
      router4 = "192.168.40.1";
    };

    dmz = {
      dhcp = {
        start = "192.168.66.3";
        end = "192.168.66.3";
        lease = "24h";
        netmask = "255.255.255.248";
        dns = [ "1.1.1.1" "1.0.0.1" ];
      };
      interface = "vlan66";
      vlan = 66;
      cidr4 = "192.168.66.0/29";
      router4 = "192.168.66.1";
    };

    minecraft = {
      interface = "vlan76";
      vlan = 76;
      cidr4 = "192.168.76.0/30";
      router4 = "192.168.76.1";
    };

    media = {
      dhcp = {
        start = "192.168.111.8";
        end = "192.168.111.8";
        lease = "24h";
        dns = [ "1.1.1.1" "1.0.0.1" "9.9.9.9" "149.112.112.112" ];
      };
      interface = "vlan111";
      vlan = 111;
      cidr4 = "192.168.111.0/24";
      router4 = "192.168.111.1";
    };

    dev = {
      interface = "vlan999";
      vlan = 999;
      cidr4 = "192.168.99.0/24";
      router4 = "192.168.99.1";
    };

    wireguard = {
      interface = "wg0";
      cidr4 = "10.255.255.0/24";
      router4 = "10.255.255.1";
    };

    unifi = {
      interface = "vm-unifi";
      cidr4 = "192.168.100.0/24";
      router4 = "192.168.100.1";
    };
  };

  # Router policy groups are explicit: adding a VLAN does not grant it access.
  router = {
    wanInterface = "wan0";
    lanInterface = "lan0";
    ifbInterface = "ifb-wan";
    sixRdInterface = "6rd-*";
    dnsNetworks = [ "wireguard" "management" "trusted" "iot" "untrusted" "servers" "dev" ];
    internetNetworks = [ "wireguard" "management" "trusted" "iot" "untrusted" "servers" "dmz" "minecraft" "dev" ];
    mdnsNetworks = [ "trusted" "iot" "untrusted" "servers" ];
    dnsRedirectNetworks = [ "trusted" "iot" "untrusted" "dev" ];
  };

  hosts = {
    router = {
      hostname = "router";
      network = "management";
      ipv4 = "192.168.5.1";
      ports = {
        ssh = 22;
        dns = 53;
        dhcp = 67;
        unifiHttps = 443;
        wireguard = 49002;
        mdns = 5353;
        vmagent = 8429;
        nodeExporter = 9100;
        blackboxExporter = 9115;
        unifiExporter = 9130;
        unboundExporter = 9167;
        wireguardExporter = 9586;
        smartctlExporter = 9633;
      };
    };

    atx = {
      dhcpReservation = true;
      hostname = "atx";
      interface = "enxc87f5465d1b8";
      mac = "c8:7f:54:65:d1:b8";
      network = "servers";
      ipv4 = "192.168.40.10";
      ports = {
        ssh = 22;
        initrdSsh = 2222;
        vmagent = 8429;
        nodeExporter = 9100;
        smartctlExporter = 9633;
      };
    };

    atx-internal = {
      hostname = "internal";
      network = "servers";
      ipv4 = "192.168.40.11";
      ports = {
        ssh = 22;
        http = 80;
        netbiosName = 137;
        netbiosDatagram = 138;
        netbios = 139;
        https = 443;
        smb = 445;
        oauth2Rss = 4180;
        oauth2Paperless = 4181;
        nginxStatus = 8050;
        vmagent = 8429;
        syncthingGui = 8384;
        nodeExporter = 9100;
        nginxExporter = 9113;
        postgresqlExporter = 9187;
        rss = 20000;
        radicale = 20005;
        weather = 20006;
        paperless = 20007;
        food = 20008;
        syncthingDiscovery = 21027;
        syncthingTransfer = 22000;
      };
    };

    backup = {
      dhcpReservation = true;
      hostname = "backup";
      mac = "e8:6a:64:e5:e5:56";
      network = "servers";
      ipv4 = "192.168.40.9";
      ports = {
        ssh = 22;
        https = 443;
        initrdSsh = 2222;
        grafana = 3000;
        restic = 8000;
        restServer = 8001;
        metricsIngress = 8428;
        vmagent = 8429;
        nodeExporter = 9100;
        blackboxExporter = 9115;
        logsIngress = 9428;
        smartctlExporter = 9633;
        victoriametrics = 18428;
        victorialogs = 19428;
      };
    };

    public = {
      hostname = "public";
      mac = "e8:6a:64:99:a8:76";
      network = "dmz";
      ipv4 = "192.168.66.2";
      adminIpv4 = "192.168.66.3";
      dhcpReservation = true;
      dhcpAddress = "adminIpv4";
      ports = {
        ssh = 22;
        http = 80;
        https = 443;
        authentikRadius = 1812;
        initrdSsh = 2222;
        authentikLdap = 3389;
        authentikLdaps = 6636;
        tasks = 8001;
        bm = 8002;
        money = 8003;
        nginxStatus = 8050;
        keycloak = 8080;
        authentik = 8081;
        vmagent = 8429;
        keycloakManagement = 9000;
        nodeExporter = 9100;
        nginxExporter = 9113;
        postgresqlExporter = 9187;
        authentikMetrics = 9300;
        authentikHttps = 9443;
        smartctlExporter = 9633;
        authentikDebug = 9900;
        authentikDebugPython = 9901;
        mongo = 27017;
      };
    };

    home-assistant = {
      hostname = "ha";
      network = "iot";
      ipv4 = "192.168.20.4";
    };

    slzb-06 = {
      dhcpReservation = true;
      hostname = "slzb";
      mac = "68:25:DD:49:0D:13";
      network = "iot";
      ipv4 = "192.168.20.3";
    };

    apple-tv = {
      dhcpReservation = true;
      hostname = "appletv";
      mac = "c0:95:6d:51:fb:32";
      network = "iot";
      ipv4 = "192.168.20.2";
    };

    dev = {
      hostname = "dev";
      network = "dev";
      ipv4 = "192.168.99.10";
    };

    printer = {
      hostname = "printer";
      network = "servers";
      ipv4 = "192.168.40.12";
    };

    minecraft = {
      hostname = "minecraft";
      network = "minecraft";
      ipv4 = "192.168.76.2";
      ports = {
        ssh = 22;
        vmagent = 8429;
        nodeExporter = 9100;
        game = 25565;
      };
    };

    media = {
      network = "media";
      ipv4 = "192.168.111.10";
    };

    jellyfin = {
      network = "media";
      ipv4 = "192.168.111.11";
      ports.https = 443;
    };

    unifi = {
      hostname = "unifi";
      network = "unifi";
      ipv4 = "192.168.100.2";
      ports = {
        ssdp = 1900;
        stun = 3478;
        inform = 8080;
        web = 8443;
        discovery = 10001;
        mongo = 27117;
      };
    };
  };
}
