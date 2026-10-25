{ config, rss, mkNginxInternal, ... }:

let
  port = 20000;
in {
  imports = [
    rss.nixosModules.default
    ../../modules/services/postgresql.nix
  ];

  services.rss = {
    enable = true;
    environment = {
      HOST = "127.0.0.1:${toString port}";
      DATABASE_URL = "postgresql://rss@localhost/rss?host=/run/postgresql";
    };
  };

  homelab.postgresql.databases.rss.backup = {
    manualRestore = true;
    passwordFile = config.age.secrets.restic-rss-password.path;
  };

  services.nginx.virtualHosts."rss.internal.veetik.com" = mkNginxInternal {
    locations."/".proxyPass = "http://127.0.0.1:${toString port}";
  };
}
