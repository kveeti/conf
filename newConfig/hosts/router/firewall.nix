{ config, inventory, lib, vlan111OutboundAllowedIP, ... }:

let
  wan = inventory.router.wanInterface;
  ifb = inventory.router.ifbInterface;
  sixRd = inventory.router.sixRdInterface;
  hosts = inventory.hosts;
  networks = inventory.networks;
  ports = config.homelab.ports;
  backupPorts = hosts.backup.ports;
  unifiPorts = hosts.unifi.ports;
  policy = inventory.router;
  wireguardPeers = import ./wireguard-peers.nix;

  interfaceSet = names:
    lib.concatMapStringsSep ", " (name: ''"${networks.${name}.interface}"'') names;

  dhcpNetworkNames = builtins.attrNames (lib.filterAttrs (_: network: network ? dhcp) networks);
  dhcpInterfaces = interfaceSet dhcpNetworkNames;
  dnsInterfaces = interfaceSet (builtins.filter (name: name != "wireguard") policy.dnsNetworks);
  internetInterfaces = interfaceSet policy.internetNetworks;
  mdnsInterfaces = interfaceSet policy.mdnsNetworks;
  dnsRedirectInterfaces = interfaceSet policy.dnsRedirectNetworks;

  routerAddressSet = lib.concatMapStringsSep ", " (network: network.router4)
    (builtins.attrValues (lib.filterAttrs (name: _: name != "unifi") networks));

  portForwards = [
    {
      name = "web";
      destination = hosts.public.ipv4;
      protocol = "tcp";
      ports = [ hosts.public.ports.http hosts.public.ports.https ];
    }
    {
      name = "minecraft";
      destination = hosts.minecraft.ipv4;
      protocol = "tcp";
      ports = [ 25565 ];
    }
  ];

  portMatch = forward:
    let
      values = map toString forward.ports;
    in if builtins.length values == 1
      then builtins.head values
      else "{ ${lib.concatStringsSep ", " values} }";

  portForwardFilterRules = lib.concatMapStringsSep "\n" (forward: ''
    ip daddr ${forward.destination} ct status dnat \
      ${forward.protocol} dport ${portMatch forward} \
      counter accept comment "${forward.name} port forward"
  '') portForwards;

  portForwardNatRules = lib.concatMapStringsSep "\n" (forward: ''
    fib daddr type local \
      ${forward.protocol} dport ${portMatch forward} \
      ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } \
      counter dnat to ${forward.destination}

    meta nfproto ipv4 iifname "${wan}" \
      ${forward.protocol} dport ${portMatch forward} \
      counter dnat to ${forward.destination}
  '') portForwards;
in {
  networking.firewall.enable = false;
  networking.nftables = {
    enable = true;
    checkRuleset = true;
    ruleset = ''
      table inet filter {
        chain rpfilter {
          type filter hook prerouting priority mangle + 10; policy drop;
          meta nfproto ipv4 udp sport . udp dport { 68 . 67, 67 . 68 } accept
          iifname "${ifb}" fib saddr . mark oifname "${wan}" accept
          fib saddr . mark . iif oif exists accept
        }

        chain input {
          type filter hook input priority filter; policy drop;

          ct state vmap { invalid : drop, established : accept, related : accept }
          iifname "lo" accept
          meta l4proto ipv6-icmp accept

          ip saddr { ${routerAddressSet} } counter drop
          ip6 saddr { ::1 } counter drop

          iifname "${networks.wireguard.interface}" \
            meta l4proto { tcp, udp } th dport ${toString ports.dns} \
            accept comment "wireguard clients -> DNS"

          iifname "${networks.wireguard.interface}" \
            ip saddr ${wireguardPeers.mac.ipv4} \
            tcp dport ${toString ports.ssh} \
            accept comment "Mac wireguard -> SSH"

          iifname { "${wan}", "${ifb}" } \
            udp dport ${toString ports.wireguard} \
            accept comment "wireguard handshaking"

          iifname { "${wan}", "${ifb}" } counter drop
          iifname "${sixRd}" counter drop

          iifname "${networks.trusted.interface}" \
            tcp dport ${toString ports.ssh} \
            accept comment "trusted SSH"

          iifname { ${dhcpInterfaces} } \
            udp dport ${toString ports.dhcp} \
            accept comment "DHCP"

          iifname { ${dnsInterfaces} } \
            meta l4proto { tcp, udp } th dport ${toString ports.dns} \
            accept comment "DNS"

          iifname { "${networks.trusted.interface}", "${networks.iot.interface}" } \
            udp dport { 319, 320 } \
            accept comment "AirPlay PTP sync"

          iifname { ${mdnsInterfaces} } \
            udp dport ${toString ports.mdns} \
            accept comment "mDNS reflection"

          iifname "${networks.unifi.interface}" \
            meta l4proto { tcp, udp } th dport {
              ${toString unifiPorts.inform},
              ${toString unifiPorts.web},
              ${toString unifiPorts.discovery},
              ${toString unifiPorts.stun}
            } accept

          icmp type echo-request accept
        }

        chain forward {
          type filter hook forward priority filter; policy drop;

          iifname "${networks.dmz.interface}" \
            ip saddr != { ${hosts.public.ipv4}, ${hosts.public.adminIpv4} } \
            counter drop comment "public host anti-spoof"

          iifname "${networks.minecraft.interface}" \
            ip saddr != ${hosts.minecraft.ipv4} \
            counter drop comment "minecraft anti-spoof"

          # Adjust both SYN and SYN-ACK packets before any early accept.
          tcp flags syn tcp option maxseg size set rt mtu
          ct state vmap { invalid : drop, established : accept, related : accept }

          iifname { "${networks.wireguard.interface}", "${networks.trusted.interface}" } accept
          iifname { ${internetInterfaces} } \
            oifname "${wan}" \
            accept comment "internet access except media"

          iifname "${networks.trusted.interface}" oifname "${sixRd}" accept
          meta l4proto ipv6-icmp accept
          iifname "${sixRd}" ct state { new, untracked } counter drop

          iifname "${networks.servers.interface}" oifname "${networks.servers.interface}" accept
          iifname "${networks.dmz.interface}" \
            oifname "${networks.servers.interface}" \
            ip saddr ${hosts.public.ipv4} ip daddr ${hosts.backup.ipv4} \
            tcp dport {
              ${toString backupPorts.restic},
              ${toString backupPorts.metricsIngress},
              ${toString backupPorts.logsIngress}
            } accept comment "public -> backup"

          iifname "${networks.minecraft.interface}" \
            oifname "${networks.servers.interface}" \
            ip saddr ${hosts.minecraft.ipv4} ip daddr ${hosts.backup.ipv4} \
            tcp dport {
              ${toString backupPorts.metricsIngress},
              ${toString backupPorts.logsIngress}
            } accept comment "minecraft -> backup"

          iifname "${networks.iot.interface}" \
            oifname "${networks.servers.interface}" \
            ip saddr ${hosts.home-assistant.ipv4} ip daddr ${hosts.backup.ipv4} \
            tcp dport {
              ${toString backupPorts.restic},
              ${toString backupPorts.metricsIngress},
              ${toString backupPorts.logsIngress}
            } accept comment "home assistant -> backup"

          iifname "${networks.servers.interface}" \
            ip saddr ${hosts.atx-internal.ipv4} \
            oifname "${networks.dmz.interface}" \
            ip daddr ${hosts.public.ipv4} tcp dport ${toString hosts.public.ports.https} \
            accept comment "internal apps -> public identity"

          iifname "${networks.servers.interface}" \
            oifname "${networks.dmz.interface}" \
            ip saddr ${hosts.backup.ipv4} ip daddr ${hosts.public.ipv4} \
            tcp dport ${toString hosts.public.ports.https} \
            accept comment "backup -> public probes"

          iifname "${networks.iot.interface}" \
            oifname "${networks.media.interface}" \
            ether saddr ${hosts.apple-tv.mac} \
            ip saddr ${hosts.apple-tv.ipv4} ip daddr ${hosts.jellyfin.ipv4} \
            tcp dport ${toString hosts.jellyfin.ports.https} \
            counter accept comment "Apple TV -> Jellyfin"

          iifname "${networks.media.interface}" \
            ip saddr ${networks.media.cidr4} ip daddr "${vlan111OutboundAllowedIP}" \
            udp dport 49800 \
            counter accept comment "media VPN transport"

          ${portForwardFilterRules}

          iifname { "${networks.trusted.interface}", "${networks.iot.interface}" } \
            udp dport { ${toString ports.mdns}, 319, 320 } \
            accept comment "reflected multicast"

          iifname "${networks.management.interface}" \
            oifname "${networks.unifi.interface}" \
            udp dport { ${toString unifiPorts.stun}, ${toString unifiPorts.discovery}, ${toString unifiPorts.ssdp} } \
            counter accept

          iifname "${networks.management.interface}" \
            oifname "${networks.unifi.interface}" \
            tcp dport { ${toString unifiPorts.inform}, ${toString unifiPorts.web} } \
            counter accept

          iifname "${networks.unifi.interface}" \
            oifname "${networks.management.interface}" \
            udp dport { ${toString unifiPorts.stun}, ${toString unifiPorts.discovery}, ${toString unifiPorts.ssdp} } \
            counter accept

          iifname "${networks.unifi.interface}" \
            oifname "${networks.management.interface}" \
            tcp dport { ${toString unifiPorts.inform}, ${toString unifiPorts.web} } \
            counter accept
        }
      }

      table inet nat {
        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;

          iifname "${networks.management.interface}" \
            ip daddr ${networks.management.router4} \
            udp dport { ${toString unifiPorts.stun}, ${toString unifiPorts.discovery}, ${toString unifiPorts.ssdp} } \
            counter dnat to ${hosts.unifi.ipv4}

          iifname "${networks.management.interface}" \
            ip daddr ${networks.management.router4} \
            tcp dport { ${toString unifiPorts.inform}, ${toString unifiPorts.web} } \
            counter dnat to ${hosts.unifi.ipv4}

          iifname { "${networks.management.interface}", "${networks.trusted.interface}" } \
            ip daddr ${networks.management.router4} \
            tcp dport ${toString ports.unifiHttps} \
            counter dnat to ${hosts.unifi.ipv4}:${toString unifiPorts.web}

          ${portForwardNatRules}

          iifname { ${dnsRedirectInterfaces} } \
            meta l4proto { tcp, udp } th dport ${toString ports.dns} \
            counter redirect to ${toString ports.dns}
        }

        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          oifname "${wan}" masquerade
        }
      }
    '';
  };
}
