{ config, mkNginxInternal, ... }:

let
  state = "/var/lib/papra";
  port = config.homelab.ports.papra;
in {
  imports = [ ../../modules/services/restic-backups.nix ];

  users.groups.papra = {};
  users.users.papra = {
    isSystemUser = true;
    group = "papra";
  };

  systemd.tmpfiles.rules = [ "d ${state} 0700 papra papra -" ];

  virtualisation = {
    podman.enable = true;
    oci-containers = {
      backend = "podman";
      containers.papra = {
        image = "ghcr.io/papra-hq/papra@sha256:bf4a66e776d0a40d71543747a2e17af800204b4a81d19f7951b8552c8032dbeb";
        user = "papra";
        extraOptions = [ "--hostuser=papra" ];
        ports = [ "127.0.0.1:${toString port}:1221" ];
        volumes = [ "${state}:/app/app-data" ];
        environmentFiles = [ config.age.secrets.papra-env.path ];
        environment = {
          APP_BASE_URL = "https://docs.internal.veetik.com";
          AUTH_PROVIDERS_EMAIL_IS_ENABLED = "false";
          TASKS_PERSISTENCE_DRIVER = "libsql";
          TASKS_PERSISTENCE_DRIVERS_LIBSQL_URL = "file:/app/app-data/db/tasks.sqlite";
        };
      };
    };
  };

  services.nginx.virtualHosts."docs.internal.veetik.com" = mkNginxInternal {
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      extraConfig = ''
        client_max_body_size 0;
        proxy_buffering off;
      '';
    };
  };

  homelab.backups.instances.papra = {
    passwordFile = config.age.secrets.restic-papra-password.path;
    paths = [ state ];
    preBackupScript = ''
      systemctl stop podman-papra.service
    '';
    postBackupScript = ''
      systemctl start podman-papra.service
    '';
    restorePath = state;
    preRestoreScript = ''
      systemctl stop podman-papra.service
    '';
    postRestoreScript = ''
      systemctl start podman-papra.service
    '';
  };
}
