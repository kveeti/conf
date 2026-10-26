{ config, money, mkNginxPublic, ... }:

let
  ports = config.homelab.ports;
in {
  imports = [ money.nixosModules.default ../../modules/services/postgresql.nix ];

  age.secrets.money-enablebanking-private-key = {
    owner = "money";
    group = "money";
  };

  services.money = {
    enable = true;
    environmentFile = config.age.secrets.money-env.path;
    environment = {
      IS_PROD = "1";
      DEMO_MODE = "1";
      PORT = toString ports.money;
      BACKEND_URL = "https://money.veetik.com";
      OIDC_ISSUER = "https://auth.veetik.com/realms/main";
      OIDC_CLIENT_ID = "money";
      CLIENT_IP_HEADER = "X-Forwarded-For";
      ENABLEBANKING_ALLOWED_OIDC_SUBJECTS = "5abe0016-8773-4617-ba7e-3fe6ce892219";
      ENABLEBANKING_PRIVATE_KEY = "/run/secrets/enablebanking-private-key";
      DB_URL = "postgresql://money@localhost/money?host=/run/postgresql";
    };
  };

  systemd.services.money.serviceConfig.BindReadOnlyPaths = [
    "${config.age.secrets.money-enablebanking-private-key.path}:/run/secrets/enablebanking-private-key"
  ];

  homelab.postgresql.databases.money = {
    services = [ "money" ];
    backup = {
      passwordFile = config.age.secrets.restic-money-password.path;
    };
  };

  services.nginx.virtualHosts."money.veetik.com" = mkNginxPublic {
    locations = {
      "= /api/health" = {
        proxyPass = "http://127.0.0.1:${toString ports.money}";
        extraConfig = "access_log off;";
      };
      "/".proxyPass = "http://127.0.0.1:${toString ports.money}";
    };
  };
}
