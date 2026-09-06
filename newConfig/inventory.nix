{
  networks = {
    management = {
      interface = "vlan5";
      vlan = 5;
      cidr4 = "192.168.5.0/24";
      router4 = "192.168.5.1";
    };

    trusted = {
      interface = "vlan10";
      vlan = 10;
      cidr4 = "192.168.10.0/24";
      router4 = "192.168.10.1";
      cidr6 = "fd00:10::/64";
      router6 = "fd00:10::1";
    };

    iot = {
      interface = "vlan20";
      vlan = 20;
      cidr4 = "192.168.20.0/24";
      router4 = "192.168.20.1";
    };

    untrusted = {
      interface = "vlan30";
      vlan = 30;
      cidr4 = "192.168.30.0/24";
      router4 = "192.168.30.1";
    };

    servers = {
      interface = "vlan40";
      vlan = 40;
      cidr4 = "192.168.40.0/24";
      router4 = "192.168.40.1";
    };

    dmz = {
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

  hosts = {
    router = {
      hostname = "router";
      network = "management";
      ipv4 = "192.168.5.1";
      wan = {
        uploadMbit = 95;
        downloadMbit = 95;
      };
      ports = {
        ssh = 22;
        dns = 53;
        dhcp = 67;
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
      hostname = "atx";
      mac = "c8:7f:54:65:d1:b8";
      network = "servers";
      ipv4 = "192.168.40.10";
    };

    atx-internal = {
      hostname = "atx-internal";
      network = "servers";
      ipv4 = "192.168.40.11";
    };

    backup = {
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
      hostname = "slzb";
      mac = "68:25:DD:49:0D:13";
      network = "iot";
      ipv4 = "192.168.20.3";
    };

    apple-tv = {
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
    };

    media = {
      network = "media";
      ipv4 = "192.168.111.10";
    };

    jellyfin = {
      network = "media";
      ipv4 = "192.168.111.11";
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
