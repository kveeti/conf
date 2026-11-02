{ inventory, lib, pkgs, ... }:

let
  homeNetworks = map (network: network.cidr4) (builtins.attrValues inventory.networks)
    ++ [ "fd00::/8" "fe80::/10" ];
in {
  services.suricata = {
    enable = true;
    enabledSources = [ "et/open" ];
    settings = {
      vars.address-groups.HOME_NET = "[${lib.concatStringsSep "," homeNetworks}]";
      app-layer.protocols = {
        dnp3 = {
          enabled = "yes";
          detection-enabled = true;
          detection-ports.dp = 20000;
        };
        modbus = { enabled = "yes"; detection-enabled = true; };
      };
      af-packet = [
        {
          interface = inventory.router.lanInterface;
          cluster-id = 99;
          cluster-type = "cluster_flow";
          defrag = true;
        }
        {
          interface = inventory.networks.wireguard.interface;
          cluster-id = 98;
          cluster-type = "cluster_flow";
          defrag = true;
        }
      ];
      stats = {
        enable = true;
        interval = "60";
      };
      outputs = [{
        eve-log = {
          enabled = true;
          filetype = "regular";
          filename = "eve.json";
          filemode = "0600";
          types = [
            { alert = { payload = false; packet = false; tagged-packets = false; }; }
            { stats = { totals = true; threads = false; }; }
          ];
        };
      }];
    };
  };

  systemd.services = {
    suricata = {
      wants = [ "network-online.target" "suricata-update.service" ];
      after = [ "network-online.target" "ethtool-optimize.service" ];
      serviceConfig.UMask = "0077";
    };

    suricata-update = {
      serviceConfig.ExecStartPost = "-+${pkgs.systemd}/bin/systemctl kill --kill-whom=main --signal=USR2 suricata.service";
    };
  };

  systemd.timers.suricata-update.wantedBy = [ "timers.target" ];

  services.logrotate.settings.suricata = {
    files = [ "/var/log/suricata/*.log" "/var/log/suricata/*.json" ];
    frequency = "daily";
    rotate = 14;
    compress = true;
    delaycompress = true;
    missingok = true;
    notifempty = true;
    create = "0600 suricata suricata";
    sharedscripts = true;
    postrotate = "${pkgs.systemd}/bin/systemctl kill --kill-whom=main --signal=HUP suricata.service || true";
  };
}
