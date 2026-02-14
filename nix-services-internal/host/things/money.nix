{ config, ... }:

let

in {
  config.services.postgresql.ensureDatabases = [ "money" ];
  config.services.postgresql.ensureUsers = [{
    name = "money";
    ensureDBOwnership = true;
    ensureClauses = {
      login     = true;
      superuser = false;
    };
  }];

  config.users.users.money = {
    isSystemUser = true;
    group = "money";
  };
  config.users.groups.money = {};
  config.systemd.services."podman-money" = {
    after    = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
  };
  config.virtualisation.oci-containers.containers.money = {
    image = "veetik/money:sha-31599ca";
    login = {
      registry = "docker.io";
      username = "veetik";
      passwordFile = config.age.secrets.dockerhub-token.path;
    };
    volumes = [
      "/run/postgresql:/run/postgresql"
    ];
    user = "money";
    extraOptions = [ "--hostuser=money" ];
    ports = [
      "127.0.0.1:20001:8000"
    ];
    environmentFiles = [
      config.age.secrets.money-secrets.path
    ];
    environment = {
      DATABASE_URL = "postgresql://money@127.0.0.1/money?host=/run/postgresql";
      BASE_URL = "https://money.internal.veetik.com";
      AUTH_URL = "https://sso.internal.veetik.com";
      AUTH_CLIENT_ID = "money";
      AUTH_USER_ID_WHITELIST = "";
      AUTH_USER_ID_WHITELIST_ENABLED = "false";
      USE_SECURE_COOKIES = "false";
      PORT = "8000";
      GCN_SECRET_ID = "";
      GCN_SECRET_KEY = "";
      GCN_BASE_URL = "";
      GCN_ALLOW_SANDBOX = "false";
    };
  };

  config.services.nginx.virtualHosts."money.internal.veetik.com" = {
    useACMEHost = "internal.veetik.com";
    forceSSL = true;
    quic = true;
    locations."/".proxyPass = "http://127.0.0.1:20001";
  };
}
