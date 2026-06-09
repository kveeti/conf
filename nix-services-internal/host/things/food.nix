{ config, ... }:

let
  domain = "food.internal.veetik.com";
  PORT = "20008";
in {
  config.homelab.dns.records = [ domain ];

  config.services.food = {
    enable = true;

    environment = {
      RUST_LOG = "info";
      HOST = "127.0.0.1:${PORT}";
      DATABASE_URL = "sqlite://food.db?mode=rwc";
    };

    environmentFile = config.age.secrets.food-secrets.path;
  };

  config.services.nginx.virtualHosts.${domain} = {
    useACMEHost = "internal.veetik.com";
    forceSSL = true;
    quic = true;
    locations."/".proxyPass = "http://127.0.0.1:${PORT}";
  };
}
