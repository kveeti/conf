{ config, inventory, pkgs, ... }:

let
  wan = "wan0";
  lan = "lan0";
  ifb = "ifb-wan";
  router = inventory.hosts.router;
  networks = inventory.networks;
  ports = config.homelab.ports;

  address4 = network:
    "${network.router4}/${builtins.elemAt (builtins.match ".*/(.*)" network.cidr4) 0}";
in {
  age.secrets = {
    wg_privkey = {
      mode = "0640";
      owner = "systemd-network";
      group = "systemd-network";
    };
    wg_mac_presharedkey = {
      mode = "0640";
      owner = "systemd-network";
      group = "systemd-network";
    };
    wg_ip_presharedkey = {
      mode = "0640";
      owner = "systemd-network";
      group = "systemd-network";
    };
  };

  boot = {
    kernelModules = [ "ifb" ];
    kernel.sysctl = {
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
      "net.netfilter.nf_conntrack_buckets" = 65536;
      "net.netfilter.nf_conntrack_max" = 1048576;
      "net.netfilter.nf_conntrack_tcp_timeout_established" = 7440;
      "net.core.rmem_max" = 134217728;
      "net.core.wmem_max" = 134217728;
      "net.ipv4.tcp_rmem" = "4096 87380 134217728";
      "net.ipv4.tcp_wmem" = "4096 65536 134217728";
    };
  };

  systemd.services = {
    router-interface-names = {
      description = "Assign stable router interface names";
      wantedBy = [ "network-pre.target" ];
      before = [ "network-pre.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        config=/etc/router-interfaces
        if [[ ! -f "$config" ]]; then
          echo "Missing $config" >&2
          exit 1
        fi

        rename_interface() {
          role="$1"
          target="$2"
          mac=$(${pkgs.gawk}/bin/awk -v role="$role" '$1 == role { print $2 }' "$config")

          if [[ -z "$mac" ]]; then
            echo "Missing $role MAC address in $config" >&2
            exit 1
          fi

          for path in /sys/class/net/*; do
            interface="''${path##*/}"
            if [[ "$(cat "$path/address")" == "$mac" ]]; then
              if [[ "$interface" != "$target" ]]; then
                ${pkgs.iproute2}/bin/ip link set dev "$interface" down
                ${pkgs.iproute2}/bin/ip link set dev "$interface" name "$target"
              fi
              return
            fi
          done

          echo "Could not find $role interface with MAC $mac" >&2
          exit 1
        }

        rename_interface wan ${wan}
        rename_interface lan ${lan}
      '';
    };

    ethtool-optimize = {
      description = "Tune router network interfaces";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      path = [ pkgs.ethtool ];
      serviceConfig.Type = "oneshot";
      script = ''
        for interface in ${wan} ${lan}; do
          ethtool -K "$interface" tso on gso on gro on || true
          ethtool -G "$interface" rx 4096 tx 4096 || true
          ethtool -C "$interface" rx-usecs 1 tx-usecs 0 || true
        done
      '';
    };

    sqm = {
      description = "WAN smart queue management";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.iproute2}/bin/ip link add ${ifb} type ifb 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip link set ${ifb} up

        ${pkgs.iproute2}/bin/tc qdisc replace dev ${wan} root handle 1: htb default 10
        ${pkgs.iproute2}/bin/tc class replace dev ${wan} parent 1: classid 1:10 htb rate ${toString router.wan.uploadMbit}mbit ceil ${toString router.wan.uploadMbit}mbit
        ${pkgs.iproute2}/bin/tc qdisc replace dev ${wan} parent 1:10 handle 10: fq_codel

        ${pkgs.iproute2}/bin/tc qdisc replace dev ${wan} handle ffff: ingress
        ${pkgs.iproute2}/bin/tc filter replace dev ${wan} parent ffff: protocol all pref 1 u32 match u32 0 0 action mirred egress redirect dev ${ifb}
        ${pkgs.iproute2}/bin/tc qdisc replace dev ${ifb} root handle 1: htb default 10
        ${pkgs.iproute2}/bin/tc class replace dev ${ifb} parent 1: classid 1:10 htb rate ${toString router.wan.downloadMbit}mbit ceil ${toString router.wan.downloadMbit}mbit
        ${pkgs.iproute2}/bin/tc qdisc replace dev ${ifb} parent 1:10 handle 10: fq_codel
      '';
      preStop = ''
        ${pkgs.iproute2}/bin/tc qdisc del dev ${wan} root 2>/dev/null || true
        ${pkgs.iproute2}/bin/tc qdisc del dev ${wan} ingress 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip link del ${ifb} 2>/dev/null || true
      '';
    };
  };

  systemd.network = {
    enable = true;

    networks = {
      "10-wan" = {
        matchConfig.Name = wan;
        linkConfig.RequiredForOnline = "routable";
        networkConfig.DHCP = "ipv4";
        dhcpV4Config.Use6RD = true;
      };

      "10-lan" = {
        matchConfig.Name = lan;
        linkConfig.RequiredForOnline = "carrier";
        networkConfig.LinkLocalAddressing = false;
        vlan = [
          networks.management.interface
          networks.trusted.interface
          networks.iot.interface
          networks.untrusted.interface
          networks.servers.interface
          networks.dmz.interface
          networks.minecraft.interface
          networks.media.interface
          networks.dev.interface
        ];
      };

      "30-wireguard" = {
        matchConfig.Name = networks.wireguard.interface;
        address = [ (address4 networks.wireguard) ];
        networkConfig.IPv4Forwarding = true;
      };

      "40-management" = {
        matchConfig.Name = networks.management.interface;
        address = [ (address4 networks.management) ];
        networkConfig.IPv4Forwarding = true;
      };

      "40-trusted" = {
        matchConfig.Name = networks.trusted.interface;
        address = [ (address4 networks.trusted) "${networks.trusted.router6}/64" ];
        networkConfig = {
          IPv4Forwarding = true;
          DHCPPrefixDelegation = true;
          IPv6SendRA = true;
          DNS = [ networks.trusted.router6 ];
        };
        ipv6SendRAConfig.EmitDNS = true;
        ipv6Prefixes = [{
          Prefix = networks.trusted.cidr6;
          AddressAutoconfiguration = true;
          OnLink = true;
        }];
        dhcpV6Config.UseDNS = false;
      };

      "40-iot" = {
        matchConfig.Name = networks.iot.interface;
        address = [ (address4 networks.iot) ];
        networkConfig.IPv4Forwarding = true;
      };

      "40-untrusted" = {
        matchConfig.Name = networks.untrusted.interface;
        address = [ (address4 networks.untrusted) ];
        networkConfig.IPv4Forwarding = true;
      };

      "40-servers" = {
        matchConfig.Name = networks.servers.interface;
        address = [ (address4 networks.servers) ];
        networkConfig.IPv4Forwarding = true;
      };

      "40-dmz" = {
        matchConfig.Name = networks.dmz.interface;
        address = [ (address4 networks.dmz) ];
        networkConfig.IPv4Forwarding = true;
      };

      "40-minecraft" = {
        matchConfig.Name = networks.minecraft.interface;
        address = [ (address4 networks.minecraft) ];
        networkConfig.IPv4Forwarding = true;
      };

      "40-media" = {
        matchConfig.Name = networks.media.interface;
        address = [ (address4 networks.media) ];
        networkConfig.IPv4Forwarding = true;
      };

      "40-dev" = {
        matchConfig.Name = networks.dev.interface;
        address = [ (address4 networks.dev) ];
        networkConfig.IPv4Forwarding = true;
      };
    };

    netdevs = {
      "30-wireguard" = {
        netdevConfig = {
          Kind = "wireguard";
          Name = networks.wireguard.interface;
          MTUBytes = "1300";
        };
        wireguardConfig = {
          PrivateKeyFile = config.age.secrets.wg_privkey.path;
          ListenPort = ports.wireguard;
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

      "40-management" = {
        netdevConfig = { Kind = "vlan"; Name = networks.management.interface; };
        vlanConfig.Id = networks.management.vlan;
      };
      "40-trusted" = {
        netdevConfig = { Kind = "vlan"; Name = networks.trusted.interface; };
        vlanConfig.Id = networks.trusted.vlan;
      };
      "40-iot" = {
        netdevConfig = { Kind = "vlan"; Name = networks.iot.interface; };
        vlanConfig.Id = networks.iot.vlan;
      };
      "40-untrusted" = {
        netdevConfig = { Kind = "vlan"; Name = networks.untrusted.interface; };
        vlanConfig.Id = networks.untrusted.vlan;
      };
      "40-servers" = {
        netdevConfig = { Kind = "vlan"; Name = networks.servers.interface; };
        vlanConfig.Id = networks.servers.vlan;
      };
      "40-dmz" = {
        netdevConfig = { Kind = "vlan"; Name = networks.dmz.interface; };
        vlanConfig.Id = networks.dmz.vlan;
      };
      "40-minecraft" = {
        netdevConfig = { Kind = "vlan"; Name = networks.minecraft.interface; };
        vlanConfig.Id = networks.minecraft.vlan;
      };
      "40-media" = {
        netdevConfig = { Kind = "vlan"; Name = networks.media.interface; };
        vlanConfig.Id = networks.media.vlan;
      };
      "40-dev" = {
        netdevConfig = { Kind = "vlan"; Name = networks.dev.interface; };
        vlanConfig.Id = networks.dev.vlan;
      };
    };
  };
}
