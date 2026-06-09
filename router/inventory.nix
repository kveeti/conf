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

    public = {
      interface = "vlan66";
      vlan = 66;
      cidr4 = "192.168.66.0/24";
      router4 = "192.168.66.1";
    };

    vlan111 = {
      interface = "vlan111";
      vlan = 111;
      cidr4 = "192.168.111.0/24";
      router4 = "192.168.111.1";
    };

    wireguard = {
      interface = "wg0";
      cidr4 = "10.255.255.0/24";
      router4 = "10.255.255.1";
    };

    unifiContainer = {
      interface = "ve-unifi";
      cidr4 = "192.168.100.0/24";
      router4 = "192.168.100.1";
    };
  };

  hosts = {
    router = {
      network = "management";
      ipv4 = "192.168.5.1";
    };

    homeAssistant = {
      hostname = "ha";
      mac = "BC:24:11:62:37:5C";
      network = "iot";
      ipv4 = "192.168.20.2";
    };

    slzb = {
      hostname = "slzb";
      mac = "68:25:DD:49:0D:13";
      network = "iot";
      ipv4 = "192.168.20.3";
    };

    nixServicesInternal = {
      hostname = "nix-services-internal";
      network = "servers";
      ipv4 = "192.168.40.206";
    };

    vlan111Service = {
      network = "servers";
      ipv4 = "192.168.40.221";
    };

    servicesPublic = {
      hostname = "public";
      mac = "bc:24:11:89:dd:7e";
      network = "public";
      ipv4 = "192.168.66.2";
    };

    dev = {
      hostname = "dev";
      mac = "bc:24:11:55:42:a1";
      network = "public";
      ipv4 = "192.168.66.3";
    };

    vlan111Device = {
      network = "vlan111";
      ipv4 = "192.168.111.8";
    };

    unifiController = {
      network = "unifiContainer";
      ipv4 = "192.168.100.2";
    };
  };
}
