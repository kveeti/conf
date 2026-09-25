{ config, inventory, lib, ... }:

let
  hosts = inventory.hosts;
  networks = inventory.networks;
  policy = inventory.router;

  dnsNetworks = map (name: networks.${name}) policy.dnsNetworks;
  dnsInterfaces = [ "127.0.0.1" ] ++ map (network: network.router4) dnsNetworks ++ [ "::0" ];
  dnsAccessControls =
    [ "127.0.0.1 allow" ]
    ++ map (network: "${network.cidr4} allow") dnsNetworks
    ++ [ "::1 allow" "fe80::/10 allow" "fd00::/8 allow" ];

  dhcpNetworks = builtins.attrValues (lib.filterAttrs (_: network: network ? dhcp) networks);
  dhcpReservations = builtins.attrValues (lib.filterAttrs (_: host: host.dhcpReservation or false) hosts);
  dhcpInterfaces = map (network: network.interface) dhcpNetworks;
  dhcpRanges = map (network:
    lib.concatStringsSep "," (
      [ "set:${network.interface}" network.dhcp.start network.dhcp.end ]
      ++ lib.optional (network.dhcp ? netmask) network.dhcp.netmask
      ++ [ network.dhcp.lease ]
    )
  ) dhcpNetworks;
  dhcpOptions = lib.concatMap (network: [
    "tag:${network.interface},option:router,${network.router4}"
    "tag:${network.interface},option:dns-server,${lib.concatStringsSep "," (network.dhcp.dns or [ network.router4 ])}"
  ]) dhcpNetworks;
  dhcpHosts = map (host:
    "${host.mac},${host.hostname},${host.${host.dhcpAddress or "ipv4"}}"
  ) dhcpReservations;

  mdnsInterfaces = map (name: networks.${name}.interface) policy.mdnsNetworks;
in {
  services.resolved.enable = false;

  services.unbound = {
    enable = true;
    checkconf = true;
    resolveLocalQueries = true;
    enableRootTrustAnchor = true;
    settings = {
      forward-zone = [{
        name = ".";
        forward-addr = [
          "9.9.9.9@853#dns.quad9.net"
          "149.112.112.112@853#dns.quad9.net"
        ];
        forward-tls-upstream = "yes";
      }];

      server = {
        verbosity = "0";
        log-queries = "no";
        log-replies = "no";
        log-servfail = "no";
        log-local-actions = "no";
        module-config = ''"respip validator iterator"'';
        interface = dnsInterfaces;
        interface-automatic = "yes";
        access-control = dnsAccessControls;
        port = toString config.homelab.ports.dns;
        do-ip4 = "yes";
        do-ip6 = "yes";
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
          ''"media.lan." redirect''
          ''"jellyfin.media.lan." static''
          ''"veetik.com." typetransparent''
          ''"auth.veetik.com." static''
        ];
        local-data = [
          ''"ui.internal.veetik.com. IN A ${hosts.router.ipv4}"''
          ''"auth.veetik.com. IN A ${hosts.public.ipv4}"''
          ''"authadmin.veetik.com. IN A ${hosts.public.adminIpv4}"''
          ''"mc.veetik.com. IN CNAME oul-1.veetik.com."''
          ''"ha.internal.veetik.com. IN A ${hosts.home-assistant.ipv4}"''
          ''"z2m.internal.veetik.com. IN A ${hosts.home-assistant.ipv4}"''
          ''"backup.internal.veetik.com. IN A ${hosts.backup.ipv4}"''
          ''"grafana.internal.veetik.com. IN A ${hosts.backup.ipv4}"''
          ''"logs.internal.veetik.com. IN A ${hosts.backup.ipv4}"''
          ''"metrics.internal.veetik.com. IN A ${hosts.backup.ipv4}"''
          ''"traces.internal.veetik.com. IN A ${hosts.backup.ipv4}"''
          ''"media.lan. IN A ${hosts.media.ipv4}"''
          ''"jellyfin.media.lan. IN A ${hosts.jellyfin.ipv4}"''
          ''"dav.internal.veetik.com. IN A ${hosts.atx-internal.ipv4}"''
          ''"food.internal.veetik.com. IN A ${hosts.atx-internal.ipv4}"''
          ''"weather.internal.veetik.com. IN A ${hosts.atx-internal.ipv4}"''
          ''"p.internal.veetik.com. IN A ${hosts.atx-internal.ipv4}"''
          ''"rss.internal.veetik.com. IN A ${hosts.atx-internal.ipv4}"''
        ];
      };

      rpz = [{
        name = "hagezi_pro";
        url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/rpz/pro.txt";
      }];

      remote-control = {
        control-enable = true;
        control-interface = "/run/unbound/unbound.ctl";
        control-use-cert = false;
      };
    };
  };

  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false;
    settings = {
      port = 0;
      interface = dhcpInterfaces;
      dhcp-range = dhcpRanges;
      dhcp-option = dhcpOptions;
      dhcp-host = dhcpHosts;

    };
  };

  services.avahi = {
    enable = true;
    reflector = true;
    allowInterfaces = mdnsInterfaces;
    extraConfig = ''
      reflect-filters=_airplay._tcp.local,_raop._tcp.local
    '';
    ipv4 = true;
    ipv6 = false;
    publish = {
      enable = false;
      addresses = false;
      workstation = false;
    };
  };
}
