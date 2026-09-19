{ config, lib, pkgs, pkgs-unstable, ... }:

let
  ports = config.homelab.ports;
  mqttUser = {
    acl = [ "readwrite #" ];
    passwordFile = "/run/secrets/mqtt-password";
  };
in {
  users = {
    groups.zigbee2mqtt = {};
    users.zigbee2mqtt = {
      isSystemUser = true;
      group = "zigbee2mqtt";
    };
  };

  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = "127.0.0.1";
        port = ports.mqtt;
        settings.allow_anonymous = false;
        users.homeassistant = mqttUser;
      }
      {
        address = "10.255.20.1";
        port = ports.mqtt;
        settings.allow_anonymous = false;
        users.homeassistant = mqttUser;
      }
    ];
  };

  services.zigbee2mqtt = {
    enable = true;
    package = pkgs-unstable.zigbee2mqtt;
    settings = {
      homeassistant.enabled = true;
      frontend = {
        enabled = true;
        host = "127.0.0.1";
        port = ports.z2m;
      };
      mqtt = {
        base_topic = "zigbee2mqtt";
        server = "mqtt://127.0.0.1:${toString ports.mqtt}";
        user = "homeassistant";
      };
      serial = {
        port = "tcp://10.255.20.2:6638";
        adapter = "ember";
      };
      advanced.log_level = "info";
    };
  };

  systemd.services = {
    mosquitto = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };
    zigbee2mqtt = {
      after = [ "mosquitto.service" "network-online.target" ];
      wants = [ "mosquitto.service" "network-online.target" ];
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = lib.mkForce "zigbee2mqtt";
        Group = lib.mkForce "zigbee2mqtt";
        EnvironmentFile = "/run/secrets/z2m-env";
        ExecStartPre = [
          "${pkgs.writeShellScript "wait-for-slzb" ''
            set -e
            for i in $(seq 1 60); do
              if (exec 3<>/dev/tcp/10.255.20.2/6638) 2>/dev/null; then
                exec 3<&- 3>&-
                exit 0
              fi
              sleep 1
            done
            echo "SLZB (10.255.20.2:6638) not reachable after 60s" >&2
            exit 1
          ''}"
        ];
        Restart = lib.mkForce "always";
        RestartSec = 10;
      };
    };
  };
}
