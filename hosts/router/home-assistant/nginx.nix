{ config, pkgs, ... }:

let
  certificate = "/run/cert/internal.veetik.com/fullchain.pem";
  certificateKey = "/run/cert/internal.veetik.com/key.pem";
  sharedVirtualHost = {
    forceSSL = true;
    sslCertificate = certificate;
    sslCertificateKey = certificateKey;
  };
in {
  users.groups.cert-readers.gid = 6500;
  users.users.nginx.extraGroups = [ "cert-readers" ];

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    virtualHosts = {
      "ha.internal.veetik.com" = sharedVirtualHost // {
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString config.homelab.ports.homeAssistant}";
          proxyWebsockets = true;
        };
      };
      "z2m.internal.veetik.com" = sharedVirtualHost // {
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString config.homelab.ports.z2m}";
          proxyWebsockets = true;
        };
      };
    };
  };

  systemd = {
    services.nginx.unitConfig.ConditionPathExists = [ certificate certificateKey ];
    paths = {
      home-assistant-certificate = {
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathChanged = certificate;
          Unit = "home-assistant-certificate-reload.service";
        };
      };
      home-assistant-certificate-key = {
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathChanged = certificateKey;
          Unit = "home-assistant-certificate-reload.service";
        };
      };
    };
    services.home-assistant-certificate-reload = {
      description = "Reload nginx when its certificate changes";
      serviceConfig.Type = "oneshot";
      script = "${pkgs.systemd}/bin/systemctl reload-or-restart nginx.service";
    };
  };
}
