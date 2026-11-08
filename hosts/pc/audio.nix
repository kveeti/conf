{
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.avahi.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    raopOpenFirewall = true;
    extraConfig.client.easyeffects-threads = {
      "context.properties.rules" = [
        {
          matches = [ { "application.process.binary" = "~.*easyeffects.*"; } ];
          actions.update-props."context.data-loops" = [
            { "thread.name" = "ee-output"; "loop.class" = [ "data.rt" ]; }
            { "thread.name" = "ee-input"; "loop.class" = [ "data.rt" ]; }
          ];
        }
      ];
      "filter.rules" = [
        {
          matches = [ { "node.name" = "~ee_soe_.*"; } ];
          actions.update-props."node.loop.name" = "ee-output";
        }
        {
          matches = [ { "node.name" = "~ee_sie_.*"; } ];
          actions.update-props."node.loop.name" = "ee-input";
        }
      ];
    };
    extraConfig.pipewire.music = {
      "context.modules" = [
        {
          name = "libpipewire-module-loopback";
          args = {
            "node.description" = "Music";
            "audio.position" = [ "FL" "FR" ];
            "capture.props" = {
              "node.name" = "music_sink";
              "media.class" = "Audio/Sink";
              "node.virtual" = true;
              "priority.session" = 0;
            };
            "playback.props" = {
              "node.name" = "Music";
              "application.name" = "Music";
              "media.name" = "Music";
              "node.passive" = true;
            };
          };
        }
      ];
    };
    extraConfig.pipewire-pulse.music = {
      "stream.rules" = [
        {
          matches = [ { "application.name" = "spotify"; } ];
          actions.update-props."target.object" = "music_sink";
        }
      ];
    };
    extraConfig.pipewire.raop = {
      "context.modules" = [
        {
          name = "libpipewire-module-raop-discover";
          args."stream.rules" = [
            {
              matches = [ { "raop.ip" = "~.*"; } ];
              actions."create-stream"."stream.props"."priority.session" = 1;
            }
          ];
        }
      ];
    };
    wireplumber.extraConfig."soundblaster-output-latency" = {
      "monitor.alsa.rules" = [
        {
          matches = [
            {
              "node.name" = "alsa_output.usb-Creative_Technology_Ltd_Sound_Blaster_Play__3_YDSB1730133002380J-00.analog-stereo";
            }
          ];
          actions.update-props."node.force-quantum" = 64;
        }
      ];
    };
    wireplumber.extraConfig."disable-bluetooth-mics" = {
      "monitor.bluez.properties" = {
        "bluez5.roles" = [ "a2dp_sink" "a2dp_source" "bap_sink" ];
      };
    };
  };
}
