{ config, pkgs-unstable, ... }:

{
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

    lovelaceConfig.views = [{
      title = "Home";
      sections = [
        {
          type = "grid";
          cards = [
            { type = "heading"; heading_style = "title"; heading = "Main"; }
            { type = "tile"; entity = "light.living_room_lights"; name = "Living room"; vertical = false; features_position = "bottom"; }
            { type = "tile"; entity = "light.kitchen_ceiling_light"; name = "Kitchen"; vertical = false; features_position = "bottom"; }
            { type = "tile"; entity = "light.bedroom_light_left"; name = "Bedtable"; vertical = false; icon_tap_action.action = "toggle"; features_position = "bottom"; }
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

    config = {
      homeassistant = {
        name = "Home";
        time_zone = "Europe/Helsinki";
        unit_system = "metric";
      };
      http = {
        server_host = "127.0.0.1";
        server_port = config.homelab.ports.homeAssistant;
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
      prometheus.namespace = "hass";

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
            "light.living_room_light_desk" = { state = "on"; brightness = 255; color_temp_kelvin = 3000; };
            "light.living_room_light_behind_tv" = { state = "on"; brightness = 255; color_temp_kelvin = 3000; };
            "light.living_room_light_hole" = { state = "on"; brightness = 255; color_temp_kelvin = 3000; };
          };
        }
        {
          id = "living_room_2";
          name = "Living room 2";
          entities = {
            "light.living_room_light_desk" = { state = "on"; brightness = 128; color_temp_kelvin = 2700; };
            "light.living_room_light_behind_tv" = { state = "on"; brightness = 128; color_temp_kelvin = 2700; };
            "light.living_room_light_hole" = { state = "on"; brightness = 128; color_temp_kelvin = 2700; };
          };
        }
        {
          id = "living_room_3";
          name = "Living room 3";
          entities = {
            "light.living_room_light_desk" = { state = "on"; brightness = 38; color_temp_kelvin = 2200; };
            "light.living_room_light_behind_tv" = { state = "on"; brightness = 38; color_temp_kelvin = 2200; };
            "light.living_room_light_hole" = { state = "on"; brightness = 38; color_temp_kelvin = 2200; };
          };
        }
        {
          id = "living_room_red_1";
          name = "Living room red 1";
          entities = {
            "light.living_room_light_desk" = { state = "on"; brightness = 255; rgb_color = [ 255 0 0 ]; };
            "light.living_room_light_behind_tv" = { state = "on"; brightness = 255; rgb_color = [ 255 0 0 ]; };
            "light.living_room_light_hole" = { state = "on"; brightness = 255; rgb_color = [ 255 0 0 ]; };
          };
        }
        {
          id = "living_room_red_2";
          name = "Living room red 2";
          entities = {
            "light.living_room_light_desk" = { state = "on"; brightness = 128; rgb_color = [ 255 0 0 ]; };
            "light.living_room_light_behind_tv" = { state = "on"; brightness = 128; rgb_color = [ 255 0 0 ]; };
            "light.living_room_light_hole" = { state = "on"; brightness = 128; rgb_color = [ 255 0 0 ]; };
          };
        }
        {
          id = "living_room_red_3";
          name = "Living room red 3";
          entities = {
            "light.living_room_light_desk" = { state = "on"; brightness = 38; rgb_color = [ 255 0 0 ]; };
            "light.living_room_light_behind_tv" = { state = "on"; brightness = 38; rgb_color = [ 255 0 0 ]; };
            "light.living_room_light_hole" = { state = "on"; brightness = 38; rgb_color = [ 255 0 0 ]; };
          };
        }
        {
          id = "lights_off";
          name = "lights off";
          entities."light.all_lights".state = "off";
        }
      ];

      automation = [
        {
          alias = "Switches - scenes";
          mode = "queued";
          trigger = builtins.concatMap (topic:
            map (action: {
              platform = "mqtt";
              inherit topic;
              value_template = "{{ value_json.action }}";
              payload = action;
              id = action;
            }) [ "up_press_release" "down_press_release" "off_press_release" "on_press_release" "up_hold" "down_hold" "off_hold" ]
          ) [ "zigbee2mqtt/living_room_switch" "zigbee2mqtt/hallway_switch" ];
          action = [{
            choose = [
              { conditions = "{{ trigger.id == 'up_hold' }}"; sequence = [{ service = "scene.turn_on"; target.entity_id = "scene.living_room_red_1"; }]; }
              { conditions = "{{ trigger.id == 'down_hold' }}"; sequence = [{ service = "scene.turn_on"; target.entity_id = "scene.living_room_red_2"; }]; }
              { conditions = "{{ trigger.id == 'off_hold' }}"; sequence = [{ service = "scene.turn_on"; target.entity_id = "scene.living_room_red_3"; }]; }
              { conditions = "{{ trigger.id == 'up_press_release' }}"; sequence = [{ service = "scene.turn_on"; target.entity_id = "scene.living_room_1"; }]; }
              { conditions = "{{ trigger.id == 'down_press_release' }}"; sequence = [{ service = "scene.turn_on"; target.entity_id = "scene.living_room_2"; }]; }
              { conditions = "{{ trigger.id == 'off_press_release' }}"; sequence = [{ service = "scene.turn_on"; target.entity_id = "scene.living_room_3"; }]; }
              { conditions = "{{ trigger.id == 'on_press_release' }}"; sequence = [{ service = "light.turn_off"; target.entity_id = "light.all_lights"; }]; }
            ];
          }];
        }
        {
          alias = "Bathroom motion lights";
          mode = "restart";
          trigger = [
            { platform = "state"; entity_id = "binary_sensor.bathroom_motion_occupancy"; to = "on"; id = "on"; }
            { platform = "state"; entity_id = "binary_sensor.bathroom_motion_occupancy"; to = "off"; id = "off"; }
          ];
          variables = {
            lr_on = "{{ is_state('light.living_room_light_desk','on') or is_state('light.living_room_light_behind_tv','on') or is_state('light.living_room_light_hole','on') }}";
            lr_bri = "{{ [state_attr('light.living_room_light_desk','brightness') or 0, state_attr('light.living_room_light_behind_tv','brightness') or 0, state_attr('light.living_room_light_hole','brightness') or 0] | max }}";
            lr_red = ''
              {% set ns = namespace(red=false) %}
              {% for entity_id in ['light.living_room_light_desk', 'light.living_room_light_behind_tv', 'light.living_room_light_hole'] %}
                {% set rgb = state_attr(entity_id, 'rgb_color') %}
                {% if is_state(entity_id, 'on') and state_attr(entity_id, 'color_mode') in ['hs', 'xy', 'rgb', 'rgbw', 'rgbww'] and rgb and rgb[0] > 200 and rgb[1] < 80 and rgb[2] < 80 %}
                  {% set ns.red = true %}
                {% endif %}
              {% endfor %}
              {{ ns.red }}
            '';
            lr_temp = "{{ state_attr('light.living_room_light_desk','color_temp_kelvin') or state_attr('light.living_room_light_behind_tv','color_temp_kelvin') or state_attr('light.living_room_light_hole','color_temp_kelvin') or 3000 }}";
            night = "{{ now().hour >= 23 or now().hour < 6 }}";
          };
          action = [{
            choose = [
              {
                conditions = "{{ trigger.id == 'off' }}";
                sequence = [
                  { delay = "{{ '00:02:00' if night else '00:05:00' }}"; }
                  { service = "light.turn_off"; target.entity_id = "light.bathroom_lights"; }
                ];
              }
              { conditions = "{{ lr_red | bool }}"; sequence = [{ service = "light.turn_on"; target.entity_id = "light.bathroom_lights"; data = { brightness = "{{ lr_bri }}"; rgb_color = [ 255 0 0 ]; }; }]; }
              { conditions = "{{ lr_on and lr_bri > 191 }}"; sequence = [{ service = "light.turn_on"; target.entity_id = "light.bathroom_lights"; data = { brightness_pct = 100; color_temp_kelvin = 3000; }; }]; }
              { conditions = "{{ lr_on }}"; sequence = [{ service = "light.turn_on"; target.entity_id = "light.bathroom_lights"; data = { brightness = "{{ lr_bri }}"; color_temp_kelvin = "{{ lr_temp }}"; }; }]; }
              { conditions = "{{ night }}"; sequence = [{ service = "light.turn_on"; target.entity_id = "light.bathroom_lights"; data = { brightness_pct = 8; color_temp_kelvin = 2200; }; }]; }
            ];
            default = [{ service = "light.turn_on"; target.entity_id = "light.bathroom_lights"; data = { brightness_pct = 100; color_temp_kelvin = 3000; }; }];
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
            {
              service = "light.turn_on";
              target.entity_id = [ "light.living_room_light_desk" "light.living_room_light_behind_tv" "light.living_room_light_hole" "light.bedroom_light_left" ];
              data = { brightness = 1; color_temp_kelvin = 2200; };
            }
            { delay = "00:00:02"; }
            {
              service = "light.turn_on";
              target.entity_id = [ "light.living_room_light_desk" "light.living_room_light_behind_tv" "light.living_room_light_hole" "light.bedroom_light_left" ];
              data = { brightness = 255; color_temp_kelvin = 4000; transition = 1800; };
            }
            {
              service = "input_select.select_option";
              target.entity_id = "input_select.wake_up_lights";
              data.option = "Off";
            }
          ];
        }
      ];
    };
  };

  systemd.services.home-assistant.after = [ "mosquitto.service" ];
}
