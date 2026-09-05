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

    dev = {
      interface = "vlan999";
      vlan = 999;
      cidr4 = "192.168.99.0/24";
      router4 = "192.168.99.1";
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

    publicMinecraft = {
      interface = "vlan76";
      vlan = 76;
      cidr4 = "192.168.76.0/30";
      router4 = "192.168.76.1";
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

    unifiNetwork = {
      interface = "vm-unifi";
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
      network = "iot";
      ipv4 = "192.168.20.4";
    };

    slzb = {
      hostname = "slzb";
      mac = "68:25:DD:49:0D:13";
      network = "iot";
      ipv4 = "192.168.20.3";
    };

    appleTv = {
      hostname = "appletv";
      mac = "c0:95:6d:51:fb:32";
      network = "iot";
      ipv4 = "192.168.20.2";
    };

    atx = {
      hostname = "atx";
      mac = "c8:7f:54:65:d1:b8";
      network = "servers";
      ipv4 = "192.168.40.10";
    };

    atxInternal = {
      hostname = "atx-internal";
      network = "servers";
      ipv4 = "192.168.40.11";
    };

    dev = {
      hostname = "dev";
      network = "dev";
      ipv4 = "192.168.99.10";
    };

    backup = {
      hostname = "backup";
      mac = "e8:6a:64:e5:e5:56";
      network = "servers";
      ipv4 = "192.168.40.9";
    };

    vlan111Service = {
      network = "servers";
      ipv4 = "192.168.40.221";
    };

    printer = {
      hostname = "printer";
      network = "servers";
      ipv4 = "192.168.40.12";
    };

    public = {
      hostname = "public";
      mac = "e8:6a:64:99:a8:76";
      network = "dmz";
      ipv4 = "192.168.66.2";
      adminIpv4 = "192.168.66.3";
    };

    minecraft = {
      hostname = "minecraft";
      network = "publicMinecraft";
      ipv4 = "192.168.76.2";
    };

    media = {
      network = "vlan111";
      ipv4 = "192.168.111.10";
    };

    jellyfin = {
      network = "vlan111";
      ipv4 = "192.168.111.11";
    };

    unifiController = {
      network = "unifiNetwork";
      ipv4 = "192.168.100.2";
    };
  };
}
