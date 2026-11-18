{ config, inventory, pkgs, mkNginxPublic, ... }:

let
  ports = config.homelab.ports;
  domain = "t.veetik.com";
in {
  services.mediamtx = {
    enable = true;
    settings = {
      rtsp = false;
      rtmp = false;
      hls = false;
      srt = false;
      webrtcAddress = "${inventory.hosts.worker.ipv4}:${toString ports.streamHttp}";
      webrtcLocalUDPAddress = ":${toString ports.streamWebrtc}";
      webrtcAdditionalHosts = [ domain ];
      webrtcAllowOrigins = [ "https://${domain}" ];
      authInternalUsers = [
        {
          user = "any";
          ips = [ inventory.hosts.pc.ipv4 ];
          permissions = [{ action = "publish"; path = "live"; }];
        }
        {
          user = "any";
          ips = [ inventory.hosts.worker.ipv4 ];
          permissions = [{ action = "read"; path = "live"; }];
        }
      ];
      paths.live = {};
    };
  };

  services.nginx.virtualHosts.${domain} = mkNginxPublic {
    basicAuthFile = pkgs.writeText "stream-htpasswd" ''
      viewer:$apr1$idM0OCYw$yNRZAv2OdZVasnJhdSqJ5.
    '';
    locations = {
      "= /".return = "302 /live/";
      "/".proxyPass = "http://${inventory.hosts.worker.ipv4}:${toString ports.streamHttp}";
    };
  };

  networking.firewall = {
    allowedUDPPorts = [ ports.streamWebrtc ];
    extraInputRules = ''
      ip saddr ${inventory.hosts.pc.ipv4} tcp dport ${toString ports.streamHttp} accept
    '';
  };
}
