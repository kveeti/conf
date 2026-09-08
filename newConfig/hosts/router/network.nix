{ inventory, lib, pkgs, ... }:

let
  wan = inventory.router.wanInterface;
  lan = inventory.router.lanInterface;
  networks = inventory.networks;

  vlanDefinitions = lib.filterAttrs (_: network: network ? vlan) networks;

  address4 = network:
    "${network.router4}/${lib.last (lib.splitString "/" network.cidr4)}";

  mkVlanDevice = name: network:
    lib.nameValuePair "40-${name}" {
      netdevConfig = {
        Kind = "vlan";
        Name = network.interface;
      };
      vlanConfig.Id = network.vlan;
    };

  mkVlanNetwork = name: network:
    lib.nameValuePair "40-${name}" ({
      matchConfig.Name = network.interface;
      address = [ (address4 network) ];
      networkConfig.IPv4Forwarding = true;
    } // lib.optionalAttrs (network ? cidr6) {
      address = [
        (address4 network)
        "${network.router6}/${lib.last (lib.splitString "/" network.cidr6)}"
      ];
      networkConfig = {
        IPv4Forwarding = true;
        DHCPPrefixDelegation = true;
        IPv6SendRA = true;
        DNS = [ network.router6 ];
      };
      ipv6SendRAConfig.EmitDNS = true;
      ipv6Prefixes = [{
        Prefix = network.cidr6;
        AddressAutoconfiguration = true;
        OnLink = true;
      }];
      dhcpV6Config.UseDNS = false;
    });

  vlanDevices = lib.mapAttrs' mkVlanDevice vlanDefinitions;
  vlanNetworks = lib.mapAttrs' mkVlanNetwork vlanDefinitions;
  vlanInterfaces = map (network: network.interface) (builtins.attrValues vlanDefinitions);
in {
  boot.kernel.sysctl = {
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
          ethtool -K "$interface" tso on gso on gro on
          ethtool -G "$interface" rx 4096 tx 4096
          ethtool -C "$interface" rx-usecs 1 tx-usecs 0
        done
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
        vlan = vlanInterfaces;
      };
    } // vlanNetworks;

    netdevs = vlanDevices;
  };
}
