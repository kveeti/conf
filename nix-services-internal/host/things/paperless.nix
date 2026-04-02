{ config, ... }:

let

in {
  config.services.postgresql.ensureDatabases = [ "paperless" ];
  config.services.postgresql.ensureUsers = [{
    name = "paperless";
    ensureDBOwnership = true;
    ensureClauses = {
      login     = true;
      superuser = false;
    };
  }];

  config.services.paperless = {
    enable = true;
    domain = "p.internal.veetik.com";
    port = 20007;
    address = "127.0.0.1";
    passwordFile = config.age.secrets.paperless-security-password.file;
    settings = {
      PAPERLESS_ADMIN_USER = "security";
      PAPERLESS_DBHOST = "/var/run/postgresql";
    };
  };

  config.services.nginx.virtualHosts."p.internal.veetik.com" = {
    useACMEHost = "internal.veetik.com";
    forceSSL = true;
    quic = true;
    locations."/".proxyPass = "http://127.0.0.1:20007";
  };
}
