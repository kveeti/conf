{ config, withSharedVhost, ... }:

let
  paperlessUnits = [
    "paperless-web.service"
    "paperless-scheduler.service"
    "paperless-task-queue.service"
    "paperless-consumer.service"
  ];
in {
  config.age.secrets.paperless-security-password = {};
  config.age.secrets.paperless-oidc-client-secret = {};

  config.homelab.volumes.paperless.owner = "paperless";

  config.services.backedupPg.instances.paperless.units = paperlessUnits;

  config.homelab.backups.instances.paperless-data = {
    paths = [ "/var/lib/paperless" ];
    after = [ "var-lib-paperless.mount" ];
    before = paperlessUnits;
    requiredBy = paperlessUnits;
    hasData = ''[ -n "$(ls -A /var/lib/paperless 2>/dev/null)" ]'';
    restore = ''
      restic restore --tag paperless-data latest --target / --include /var/lib/paperless
      chown -R paperless:paperless /var/lib/paperless
    '';
  };

  config.services.paperless = {
    enable = true;
    domain = "p.internal.veetik.com";
    port = 20007;
    address = "127.0.0.1";
    passwordFile = config.age.secrets.paperless-security-password.path;
    environmentFile = config.age.secrets.paperless-oidc-client-secret.path;
    settings = {
      PAPERLESS_ADMIN_USER = "security";
      PAPERLESS_DBHOST = "/var/run/postgresql";
      PAPERLESS_URL = "https://p.internal.veetik.com";
      PAPERLESS_ACCOUNT_DEFAULT_HTTP_PROTOCOL = "https";
      PAPERLESS_DISABLE_REGULAR_LOGIN = false;
      PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
    };
  };

  config.services.nginx.virtualHosts."p.internal.veetik.com" = withSharedVhost {
    extraConfig = ''
      client_max_body_size 100M;
    '';
    locations."/".proxyPass = "http://127.0.0.1:20007";
  };
}
