{ config, inventory, money, ... }:

let
  publicIp = inventory.hosts.public.ipv4;
  environmentFile = "/run/money-config/environment";
in {
  imports = [ money.nixosModules.default ];

  age.secrets = {
    money-enablebanking-app-id = {};
    money-enablebanking-private-key = {};
    oidc-money-client-secret = {};
    restic-money-rest-pass = {};
    restic-money-encryption-pass = {};
  };

  systemd.services.money-environment = {
    description = "Prepare Money secrets";
    requiredBy = [ "money.service" ];
    before = [ "money.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "money-config";
      RuntimeDirectoryMode = "0700";
      LoadCredential = [
        "oidc-client-secret:${config.age.secrets.oidc-money-client-secret.path}"
        "enablebanking-app-id:${config.age.secrets.money-enablebanking-app-id.path}"
      ];
    };
    script = ''
      printf 'OIDC_CLIENT_SECRET=%s\nENABLEBANKING_APP_ID=%s\n' \
        "$(cat "$CREDENTIALS_DIRECTORY/oidc-client-secret")" \
        "$(cat "$CREDENTIALS_DIRECTORY/enablebanking-app-id")" \
        > ${environmentFile}
      chmod 0400 ${environmentFile}
    '';
  };

  services.money = {
    enable = true;
    inherit environmentFile;
    environment = {
      IS_PROD = "1";
      DEMO_MODE = "1";
      PORT = "8003";
      BACKEND_URL = "https://money.veetik.com";
      DB_URL = "postgresql://money@127.0.0.1/money?host=/run/postgresql";
      OIDC_ISSUER = "https://auth.veetik.com/realms/main";
      OIDC_CLIENT_ID = "money";
      CLIENT_IP_HEADER = "X-Forwarded-For";
      ENABLEBANKING_PRIVATE_KEY = "/run/credentials/money.service/enablebanking-private-key";
      ENABLEBANKING_ALLOWED_OIDC_SUBJECTS = "5abe0016-8773-4617-ba7e-3fe6ce892219";
    };
  };

  systemd.services.money.serviceConfig.LoadCredential = [
    "enablebanking-private-key:${config.age.secrets.money-enablebanking-private-key.path}"
  ];

  homelab.postgresql.databases.money = {
    services = [ "money" ];
    backup = {
      repository = "rest:https://backup.internal.veetik.com:8000/money";
      restPasswordFile = config.age.secrets.restic-money-rest-pass.path;
      encryptionPasswordFile = config.age.secrets.restic-money-encryption-pass.path;
    };
  };

  services.nginx.virtualHosts."money.veetik.com" = {
    useACMEHost = "veetik.com";
    forceSSL = true;
    listen = [
      { addr = publicIp; port = 80; }
      { addr = publicIp; port = 443; ssl = true; }
    ];
    locations."/".proxyPass = "http://127.0.0.1:8003";
  };

  homelab.logs.units."money.service" = {
    format = "auto";
    serviceName = "money";
  };
}
