{ config, inventory, ... }:

let
  hosts = inventory.hosts;
  networks = inventory.networks;
  atxInternal = hosts.atx-internal.ipv4;
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
        interface = [
          "127.0.0.1"
          networks.wireguard.router4
          networks.management.router4
          networks.trusted.router4
          networks.iot.router4
          networks.untrusted.router4
          networks.servers.router4
          networks.dev.router4
          "::1"
          networks.trusted.router6
        ];
        access-control = [
          "127.0.0.1 allow"
          "${networks.wireguard.cidr4} allow"
          "${networks.management.cidr4} allow"
          "${networks.trusted.cidr4} allow"
          "${networks.iot.cidr4} allow"
          "${networks.untrusted.cidr4} allow"
          "${networks.servers.cidr4} allow"
          "${networks.dev.cidr4} allow"
          "::1 allow"
          "fe80::/10 allow"
          "${networks.trusted.cidr6} allow"
        ];
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
          ''"auth.veetik.com." static''
          ''"auth2.veetik.com." static''
        ];

        local-data = [
          ''"ui.internal.veetik.com. IN A ${hosts.router.ipv4}"''
          ''"auth.veetik.com. IN A ${hosts.public.ipv4}"''
          ''"auth2.veetik.com. IN A ${hosts.public.ipv4}"''
          ''"authadmin.veetik.com. IN A ${hosts.public.adminIpv4}"''
          ''"mc.veetik.com. IN CNAME oul-1.veetik.com."''
          ''"ha.internal.veetik.com. IN A ${hosts.home-assistant.ipv4}"''
          ''"z2m.internal.veetik.com. IN A ${hosts.home-assistant.ipv4}"''
          ''"printer.internal.veetik.com. IN A ${hosts.printer.ipv4}"''
          ''"backup.internal.veetik.com. IN A ${hosts.backup.ipv4}"''
          ''"grafana.internal.veetik.com. IN A ${hosts.backup.ipv4}"''
          ''"dev.internal.veetik.com. IN A ${hosts.dev.ipv4}"''
          ''"dev-internal.veetik.com. IN A ${hosts.dev.ipv4}"''
          ''"media.lan. IN A ${hosts.media.ipv4}"''
          ''"jellyfin.media.lan. IN A ${hosts.jellyfin.ipv4}"''
          ''"dav.internal.veetik.com. IN A ${atxInternal}"''
          ''"food.internal.veetik.com. IN A ${atxInternal}"''
          ''"weather.internal.veetik.com. IN A ${atxInternal}"''
          ''"p.internal.veetik.com. IN A ${atxInternal}"''
          ''"rss.internal.veetik.com. IN A ${atxInternal}"''
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
      interface = [
        networks.management.interface
        networks.trusted.interface
        networks.iot.interface
        networks.untrusted.interface
        networks.servers.interface
        networks.dmz.interface
        networks.media.interface
      ];
      dhcp-range = [
        "set:management,192.168.5.2,192.168.5.254,24h"
        "set:trusted,192.168.10.200,192.168.10.254,24h"
        "set:iot,192.168.20.10,192.168.20.254,24h"
        "set:untrusted,192.168.30.2,192.168.30.254,24h"
        "set:servers,192.168.40.200,192.168.40.254,24h"
        "set:dmz,192.168.66.3,192.168.66.3,255.255.255.248,24h"
        "set:media,192.168.111.8,192.168.111.8,24h"
      ];
      dhcp-option = [
        "tag:management,option:router,${networks.management.router4}"
        "tag:management,option:dns-server,${networks.management.router4}"
        "tag:trusted,option:router,${networks.trusted.router4}"
        "tag:trusted,option:dns-server,${networks.trusted.router4}"
        "tag:iot,option:router,${networks.iot.router4}"
        "tag:iot,option:dns-server,${networks.iot.router4}"
        "tag:untrusted,option:router,${networks.untrusted.router4}"
        "tag:untrusted,option:dns-server,${networks.untrusted.router4}"
        "tag:servers,option:router,${networks.servers.router4}"
        "tag:servers,option:dns-server,${networks.servers.router4}"
        "tag:dmz,option:router,${networks.dmz.router4}"
        "tag:dmz,option:dns-server,1.1.1.1,1.0.0.1"
        "tag:media,option:router,${networks.media.router4}"
        "tag:media,option:dns-server,1.1.1.1,1.0.0.1,9.9.9.9,149.112.112.112"
      ];
      dhcp-host = [
        "${hosts.slzb-06.mac},${hosts.slzb-06.hostname},${hosts.slzb-06.ipv4}"
        "${hosts.apple-tv.mac},${hosts.apple-tv.hostname},${hosts.apple-tv.ipv4}"
        "${hosts.atx.mac},${hosts.atx.hostname},${hosts.atx.ipv4}"
        "${hosts.backup.mac},${hosts.backup.hostname},${hosts.backup.ipv4}"
        "${hosts.public.mac},${hosts.public.hostname},${hosts.public.adminIpv4}"
      ];
    };
  };

  services.avahi = {
    enable = true;
    reflector = true;
    allowInterfaces = [
      networks.trusted.interface
      networks.iot.interface
      networks.untrusted.interface
      networks.servers.interface
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
}
