{ config, withSharedVhost, ... }:

let
  domain = "rss.internal.veetik.com";
  ports = config.homelab.ports;
in {
  age.secrets.oidc-rss-client-secret = {};

  networking.hosts."192.168.50.10" = [ "rss-db.internal.veetik.com" ];

  services.rss = {
    enable = false;
    environmentFile = "/run/secrets/rss-db-env";
    environment = {
      RUST_LOG = "info";
      HOST = "127.0.0.1:${toString ports.rss}";
    };
  };

  services.nginx.virtualHosts.${domain} = withSharedVhost {
    locations."/".proxyPass = "http://127.0.0.1:${toString ports.rss}";
  };
}
