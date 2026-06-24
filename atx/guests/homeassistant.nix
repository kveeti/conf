{ config, secretPath, secretDerive, ... }:

let
  vmName = "homeassistant";
  stateRoot = "/var/lib/microvms/${vmName}";
in {
  homelab.microvms.${vmName} = {
    inherit stateRoot;
    certDomains = [ "internal.veetik.com" ];

    secrets = [
      { name = "mqtt-password"; value = secretPath config.age.secrets.ha-mqtt-password.path; }
      { name = "z2m-env";       value = secretPath config.age.secrets.ha-z2m-env.path; }
      { name = "prometheus-token"; value = secretPath config.age.secrets.ha-prometheus-token.path; }
      { name = "wg-iot-priv"; }
      { name = "wg-iot-psk"; }
      { name = "restic-ha-encryption-pass"; }
      {
        name = "restic-ha-repo";
        value = secretDerive ''
          printf 'rest:https://ha:%s@backup.internal.veetik.com:8000/ha' \
            "$(cat ${config.age.secrets.restic-ha-rest-pass.path})"
        '';
      }
    ];

    shares.ssh-host = {
      owner = "root"; group = "root"; mode = "0755";
      path = "/run/ssh-host"; hostPath = "${stateRoot}/ssh";
    };

    vm = {
      specialArgs = { inherit (config._module.args) keys guestIps pkgs-unstable; };
      config = { config, pkgs, lib, keys, guestIps, pkgs-unstable, ... }: {
        imports = [
          ./_common.nix
          ../../modules/nixos/homelab-volumes.nix
          ../../modules/nixos/homelab-backups.nix
        ];

        networking.hostName = "homeassistant";

        homelab.metrics.scrapeConfigs = [{
          job_name = "hass";
          metrics_path = "/api/prometheus";
          authorization.credentials_file = "/run/secrets/prometheus-token";
          static_configs = [{ targets = [ "127.0.0.1:8123" ]; }];
        }];

        microvm.mem = lib.mkForce 1024;

        environment.systemPackages = with pkgs; [ wireguard-tools ];

        microvm.interfaces = [{
          type = "tap";
          id = "vm-ha";
          mac = "02:00:00:14:00:01";
        }];

        homelab.volumeSize = 4096;

        homelab.volumes = {
          mosquitto   = { owner = "mosquitto";   mode = "0755"; };
          zigbee2mqtt = { owner = "zigbee2mqtt"; mode = "0700"; };
          hass        = { owner = "hass";        mode = "0700"; };
        };

        homelab.backups = {
          repositoryFile = "/run/secrets/restic-ha-repo";
          passwordFile   = "/run/secrets/restic-ha-encryption-pass";
        };

        homelab.backups.instances.hass = {
          paths = [ "/var/lib/hass" ];
          excludes = [
            "/var/lib/hass/home-assistant_v2.db"
            "/var/lib/hass/home-assistant_v2.db-shm"
            "/var/lib/hass/home-assistant_v2.db-wal"
          ];
          after      = [ "var-lib-hass.mount" ];
          before     = [ "home-assistant.service" ];
          requiredBy = [ "home-assistant.service" ];
          hasData = ''[ -n "$(ls -A /var/lib/hass 2>/dev/null)" ]'';
          restore = ''
            restic restore --tag hass latest --target / --include /var/lib/hass
            chown -R hass:hass /var/lib/hass
          '';
        };

        homelab.backups.instances.zigbee2mqtt = {
          paths = [ "/var/lib/zigbee2mqtt" ];
          after = [ "var-lib-zigbee2mqtt.mount" ];
          hasData = ''[ -n "$(ls -A /var/lib/zigbee2mqtt 2>/dev/null)" ]'';
          restore = ''
            restic restore --tag zigbee2mqtt latest --target / --include /var/lib/zigbee2mqtt
            chown -R zigbee2mqtt:zigbee2mqtt /var/lib/zigbee2mqtt
          '';
        };

        # Pin a static user: z2m's default DynamicUser breaks the bind-mounted
        # persistent state dir (uid changes per boot).
        users.users.zigbee2mqtt = { isSystemUser = true; group = "zigbee2mqtt"; };
        users.groups.zigbee2mqtt = {};
        systemd.services.zigbee2mqtt.serviceConfig = {
          DynamicUser = lib.mkForce false;
          User        = lib.mkForce "zigbee2mqtt";
          Group       = lib.mkForce "zigbee2mqtt";
        };

        systemd.network.enable = true;
        systemd.network.networks."10-eth" = {
          matchConfig.Type = "ether";
          address = [ "${guestIps.homeassistant}/24" ];
          routes = [{ Gateway = "192.168.20.1"; }];
          networkConfig.DHCP = "no";
        };
        networking.nameservers = [ "192.168.20.1" ];

        systemd.network.netdevs."25-wg-iot" = {
          netdevConfig = { Kind = "wireguard"; Name = "wg-iot"; };
          wireguardConfig = {
            PrivateKeyFile = "/run/secrets/wg-iot-priv";
            ListenPort = 51820;
          };
          wireguardPeers = [{
            PublicKey = "1KioECK3czkVCkQP1l7C0EfHrVCjQvvrM/uTf2KG1SM=";
            PresharedKeyFile = "/run/secrets/wg-iot-psk";
            AllowedIPs = [ "10.255.20.2/32" ];
          }];
        };
        systemd.network.networks."25-wg-iot" = {
          matchConfig.Name = "wg-iot";
          address = [ "10.255.20.1/24" ];
          networkConfig = { LinkLocalAddressing = "no"; DHCP = "no"; };
          linkConfig.RequiredForOnline = "yes";
        };

        networking.firewall = {
          enable = true;
          allowedTCPPorts = [ 22 443 ];
          allowedUDPPorts = [ 51820 ];
        };

        services.nginx = {
          enable = true;
          recommendedGzipSettings = true;
          recommendedOptimisation = true;
          recommendedProxySettings = true;
          recommendedTlsSettings = true;
          virtualHosts."ha.internal.veetik.com" = {
            forceSSL = true;
            sslCertificate    = "/run/cert/internal.veetik.com/fullchain.pem";
            sslCertificateKey = "/run/cert/internal.veetik.com/key.pem";
            locations."/" = {
              proxyPass = "http://127.0.0.1:8123";
              proxyWebsockets = true;
            };
          };
          virtualHosts."z2m.internal.veetik.com" = {
            forceSSL = true;
            sslCertificate    = "/run/cert/internal.veetik.com/fullchain.pem";
            sslCertificateKey = "/run/cert/internal.veetik.com/key.pem";
            locations."/" = {
              proxyPass = "http://127.0.0.1:8080";
              proxyWebsockets = true;
            };
          };
        };

        # order after run-secrets.mount: the wg-iot key lives there, else the wg -> mosquitto -> z2m chain never comes up
        systemd.services.systemd-networkd = {
          after = [ "run-secrets.mount" ];
          wants = [ "run-secrets.mount" ];
        };
        systemd.services.mosquitto = {
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
        };

        services.mosquitto = {
          enable = true;
          listeners = [
            {
              address = "127.0.0.1";
              port = 1883;
              settings.allow_anonymous = false;
              users.homeassistant = {
                acl = [ "readwrite #" ];
                passwordFile = "/run/secrets/mqtt-password";
              };
            }
            {
              address = "10.255.20.1";
              port = 1883;
              settings.allow_anonymous = false;
              users.homeassistant = {
                acl = [ "readwrite #" ];
                passwordFile = "/run/secrets/mqtt-password";
              };
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
              port = 8080;
            };
            mqtt = {
              base_topic = "zigbee2mqtt";
              server = "mqtt://127.0.0.1:1883";
              user = "homeassistant";
            };
            serial = {
              port = "tcp://10.255.20.2:6638";
              adapter = "ember";
            };
            advanced.log_level = "info";
          };
        };
        systemd.services.zigbee2mqtt = {
          after    = [ "mosquitto.service" "network-online.target" ];
          wants    = [ "mosquitto.service" "network-online.target" ];
          serviceConfig.EnvironmentFile = "/run/secrets/z2m-env";
          serviceConfig.ExecStartPre = [
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
          serviceConfig.Restart = lib.mkForce "always";
          serviceConfig.RestartSec = 10;
          unitConfig.StartLimitIntervalSec = 0;
        };

        services.home-assistant = {
          enable = true;
          package = pkgs-unstable.home-assistant;
          extraComponents = [
            "frontend" "config" "system_health" "repairs" "diagnostics"
            "file_upload" "image_upload" "backup"
            "ssdp" "zeroconf" "mobile_app"
            "recorder"
            "automation" "scene" "script" "blueprint"
            "person" "sun" "zone"
            "input_boolean" "input_datetime" "input_number" "input_select" "input_text"
            "timer" "counter" "schedule" "tag" "webhook"
            "met" "mqtt" "prometheus"
          ];
          configWritable = false;

          lovelaceConfig = {
            views = [{
              title = "Home";
              sections = [
                {
                  type = "grid";
                  cards = [
                    { type = "heading"; heading_style = "title"; heading = "Main"; }
                    { type = "tile"; entity = "light.living_room_light_desk"; name = "Desk"; vertical = false; features_position = "bottom"; }
                    { type = "tile"; entity = "light.bedroom_light_left"; name = "Bedtable"; vertical = false; icon_tap_action.action = "toggle"; features_position = "bottom"; }
                    { type = "tile"; entity = "light.living_room_light_behind_tv"; name = "TV"; show_entity_picture = false; hide_state = false; vertical = false; features_position = "bottom"; }
                    {
                      type = "tile";
                      entity = "scene.lights_off";
                      name = "All off";
                      icon = "mdi:lightbulb-group-off";
                      color = "primary";
                      show_entity_picture = false;
                      hide_state = true;
                      vertical = false;
                      grid_options = { columns = 12; rows = 1; };
                      tap_action.action = "toggle";
                      features_position = "bottom";
                    }
                    {
                      type = "tile";
                      entity = "scene.living_room_1";
                      name = "1";
                      color = "amber";
                      show_entity_picture = false;
                      hide_state = true;
                      vertical = false;
                      tap_action = { action = "perform-action"; perform_action = "scene.turn_on"; target.entity_id = "scene.living_room_1"; data = {}; };
                      icon_tap_action = { action = "perform-action"; perform_action = "scene.turn_on"; target.entity_id = "scene.living_room_1"; data = {}; };
                      features_position = "bottom";
                    }
                    {
                      type = "tile";
                      entity = "scene.living_room_2";
                      name = "2";
                      icon = "mdi:lightbulb";
                      color = "accent";
                      show_entity_picture = false;
                      hide_state = true;
                      vertical = false;
                      tap_action = { action = "perform-action"; perform_action = "scene.turn_on"; target.entity_id = "scene.living_room_2"; data = {}; };
                      icon_tap_action = { action = "perform-action"; perform_action = "scene.turn_on"; target.entity_id = "scene.living_room_2"; data = {}; };
                      features_position = "bottom";
                    }
                    {
                      type = "tile";
                      entity = "scene.living_room_3";
                      name = "3";
                      color = "deep-orange";
                      hide_state = true;
                      vertical = false;
                      tap_action.action = "toggle";
                      features_position = "bottom";
                    }
                    { type = "tile"; entity = "light.bathroom_lights"; vertical = false; features_position = "bottom"; }
                    { type = "tile"; entity = "sensor.living_room_temp_temperature"; name = "Living room temp"; vertical = false; icon_tap_action.action = "none"; features_position = "bottom"; }
                    { type = "tile"; entity = "sensor.living_room_temp_humidity"; name = "Living room humidity"; vertical = false; features_position = "bottom"; }
                  ];
                }
                {
                  type = "grid";
                  cards = [
                    { type = "heading"; icon = ""; heading_style = "title"; heading = "Homelab"; }
                    { type = "tile"; entity = "sensor.homelab_temp_temperature"; name.type = "entity"; show_entity_picture = false; hide_state = false; vertical = false; features_position = "bottom"; }
                  ];
                }
                {
                  type = "grid";
                  cards = [
                    { type = "heading"; heading = "Automations"; heading_style = "title"; }
                    { type = "tile"; entity = "automation.bathroom_motion_lights"; vertical = false; tap_action.action = "toggle"; features_position = "bottom"; }
                    {
                      type = "vertical-stack";
                      grid_options = { columns = 6; rows = "auto"; };
                      cards = [
                        {
                          type = "conditional";
                          conditions = [{ condition = "state"; entity = "input_select.wake_up_lights"; state_not = "Off"; }];
                          card = {
                            type = "tile";
                            entity = "input_select.wake_up_lights";
                            icon = "mdi:alarm";
                            color = "blue";
                            tap_action = { action = "perform-action"; perform_action = "input_select.select_next"; target.entity_id = "input_select.wake_up_lights"; data.cycle = true; };
                            icon_tap_action.action = "none";
                          };
                        }
                        {
                          type = "conditional";
                          conditions = [{ condition = "state"; entity = "input_select.wake_up_lights"; state = "Off"; }];
                          card = {
                            type = "tile";
                            entity = "input_select.wake_up_lights";
                            icon = "mdi:alarm-off";
                            color = "grey";
                            tap_action = { action = "perform-action"; perform_action = "input_select.select_next"; target.entity_id = "input_select.wake_up_lights"; data.cycle = true; };
                            icon_tap_action.action = "none";
                          };
                        }
                      ];
                    }
                  ];
                }
              ];
            }];
          };

          config = {
            homeassistant = {
              name = "Home";
              time_zone = "Europe/Helsinki";
              unit_system = "metric";
            };
            http = {
              server_host = "127.0.0.1";
              server_port = 8123;
              use_x_forwarded_for = true;
              trusted_proxies = [ "127.0.0.1" ];
            };
            frontend = {};
            config = {};
            system_health = {};
            mobile_app = {};
            ssdp = {};
            zeroconf = {};
            person = {};
            sun = {};
            mqtt = {};
            recorder.purge_keep_days = 3;
            prometheus = {
              namespace = "hass";
            };

            input_select.wake_up_lights = {
              name = "Wake up lights";
              icon = "mdi:alarm";
              options = [ "Off" "at 7" "at 8" "at 9" ];
              initial = "Off";
            };

            scene = [
              {
                id = "living_room_1";
                name = "Living room 1";
                entities = {
                  "light.living_room_light_desk"      = { state = "on"; brightness = 255; color_temp_kelvin = 3000; };
                  "light.living_room_light_behind_tv" = { state = "on"; brightness = 255; color_temp_kelvin = 3000; };
                };
              }
              {
                id = "living_room_2";
                name = "Living room 2";
                entities = {
                  "light.living_room_light_desk"      = { state = "on"; brightness = 128; color_temp_kelvin = 2700; };
                  "light.living_room_light_behind_tv" = { state = "on"; brightness = 128; color_temp_kelvin = 2700; };
                };
              }
              {
                id = "living_room_3";
                name = "Living room 3";
                entities = {
                  "light.living_room_light_desk"      = { state = "on"; brightness = 38; color_temp_kelvin = 2200; };
                  "light.living_room_light_behind_tv" = { state = "on"; brightness = 38; color_temp_kelvin = 2200; };
                };
              }
              {
                id = "lights_off";
                name = "lights off";
                entities."light.all_lights" = { state = "off"; };
              }
            ];

            automation = [
              {
                alias = "Switches - scenes";
                mode = "queued";
                trigger = [
                  { platform = "mqtt"; topic = "zigbee2mqtt/living_room_switch"; }
                  { platform = "mqtt"; topic = "zigbee2mqtt/hallway_switch"; }
                ];
                action = [{
                  choose = [
                    { conditions = "{{ trigger.payload_json.action == 'on_press' }}";
                      sequence = [{ service = "scene.turn_on"; target.entity_id = "scene.living_room_1"; }]; }
                    { conditions = "{{ trigger.payload_json.action == 'up_press' }}";
                      sequence = [{ service = "scene.turn_on"; target.entity_id = "scene.living_room_2"; }]; }
                    { conditions = "{{ trigger.payload_json.action == 'down_press' }}";
                      sequence = [{ service = "scene.turn_on"; target.entity_id = "scene.living_room_3"; }]; }
                    { conditions = "{{ trigger.payload_json.action == 'off_press' }}";
                      sequence = [{ service = "light.turn_off"; target.entity_id = "light.all_lights"; }]; }
                  ];
                }];
              }

              {
                alias = "Bathroom motion lights";
                mode = "restart";
                trigger = [
                  { platform = "state"; entity_id = "binary_sensor.bathroom_motion_occupancy"; to = "on";  id = "on"; }
                  { platform = "state"; entity_id = "binary_sensor.bathroom_motion_occupancy"; to = "off"; id = "off"; }
                ];
                variables = {
                  lr_on   = "{{ is_state('light.living_room_light_desk','on') or is_state('light.living_room_light_behind_tv','on') }}";
                  lr_bri  = "{{ [state_attr('light.living_room_light_desk','brightness') or 0, state_attr('light.living_room_light_behind_tv','brightness') or 0] | max }}";
                  lr_temp = "{{ state_attr('light.living_room_light_desk','color_temp_kelvin') or state_attr('light.living_room_light_behind_tv','color_temp_kelvin') or 3000 }}";
                  night   = "{{ now().hour >= 23 or now().hour < 6 }}";
                };
                action = [{
                  choose = [
                    { conditions = "{{ trigger.id == 'off' }}";
                      sequence = [
                        { delay = "{{ '00:02:00' if night else '00:05:00' }}"; }
                        { service = "light.turn_off"; target.entity_id = "light.bathroom_lights"; data.transition = 0.3; }
                      ]; }
                    { conditions = "{{ lr_on and lr_bri > 191 }}";
                      sequence = [{ service = "light.turn_on"; target.entity_id = "light.bathroom_lights"; data = { brightness_pct = 100; color_temp_kelvin = 3000; transition = 0.3; }; }]; }
                    { conditions = "{{ lr_on }}";
                      sequence = [{ service = "light.turn_on"; target.entity_id = "light.bathroom_lights"; data = { brightness = "{{ lr_bri }}"; color_temp_kelvin = "{{ lr_temp }}"; transition = 0.3; }; }]; }
                    { conditions = "{{ night }}";
                      sequence = [{ service = "light.turn_on"; target.entity_id = "light.bathroom_lights"; data = { brightness_pct = 8; color_temp_kelvin = 2200; transition = 0.3; }; }]; }
                  ];
                  default = [{ service = "light.turn_on"; target.entity_id = "light.bathroom_lights"; data = { brightness_pct = 100; color_temp_kelvin = 3000; transition = 0.3; }; }];
                }];
              }

              {
                alias = "Wake-up lights";
                mode = "single";
                trigger = [
                  { platform = "time"; at = "07:00:00"; id = "at 7"; }
                  { platform = "time"; at = "08:00:00"; id = "at 8"; }
                  { platform = "time"; at = "09:00:00"; id = "at 9"; }
                ];
                condition = [{ condition = "template"; value_template = "{{ states('input_select.wake_up_lights') == trigger.id }}"; }];
                action = [
                  { service = "light.turn_on";
                    target.entity_id = [ "light.living_room_light_desk" "light.living_room_light_behind_tv" "light.bedroom_light_left" ];
                    data = { brightness = 1; color_temp_kelvin = 2200; }; }
                  { delay = "00:00:02"; }
                  { service = "light.turn_on";
                    target.entity_id = [ "light.living_room_light_desk" "light.living_room_light_behind_tv" "light.bedroom_light_left" ];
                    data = { brightness = 255; color_temp_kelvin = 4000; transition = 1800; }; }
                  { service = "input_select.select_option";
                    target.entity_id = "input_select.wake_up_lights";
                    data.option = "Off"; }
                ];
              }
            ];
          };
        };
        systemd.services.home-assistant.after = [ "mosquitto.service" ];
      };
    };
  };
}
