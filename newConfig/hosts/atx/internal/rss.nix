{ config, withSharedVhost, ... }:

let
  domain = "rss.internal.veetik.com";
  ports = config.homelab.ports;
in {
  age.secrets.oidc-rss-client-secret = {};

  homelab.postgresql.databases.rss = {
    services = [ "rss" ];
    backup = {
      repository = "internal";
      tag = "rss";
      restPasswordFile = "/run/secrets/restic-internal-rest-pass";
      encryptionPasswordFile = "/run/secrets/restic-internal-encryption-pass";
    };
  };

  services.rss = {
    enable = true;
    environment = {
      RUST_LOG = "info";
      DATABASE_URL = "postgresql://rss@127.0.0.1/rss?host=/run/postgresql";
      HOST = "127.0.0.1:${toString ports.rss}";
    };
  };

  services.nginx.virtualHosts.${domain} = withSharedVhost {
    locations."/".proxyPass = "http://127.0.0.1:${toString ports.rss}";
  };
}
