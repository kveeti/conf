{ config, lib, mkNginxPublic, ... }:

let
  ports = config.homelab.ports;
in {
  imports = [ ../../modules/services/postgresql.nix ];

  age.secrets.tasks-backend-env = {
    owner = "tasks";
    group = "tasks";
  };

  users.groups.tasks = {};
  users.users.tasks = {
    isSystemUser = true;
    group = "tasks";
  };

  virtualisation = {
    podman.enable = true;
    oci-containers = {
      backend = "podman";
      containers = {
        tasks-backend = {
          image = "docker.io/veetik/tasks@sha256:902c63258c27a60bd911ab4d6360bba7f96714e4076a7800bd9d92b7fbeb3d4c";
          user = "tasks";
          extraOptions = [ "--hostuser=tasks" ];
          ports = [ "127.0.0.1:${toString ports.tasksBackend}:8000" ];
          volumes = [
            "/run/postgresql:/run/postgresql"
            "${config.age.secrets.tasks-backend-env.path}:/.env:ro"
          ];
          environment = {
            DATABASE_URL = "postgresql://tasks@localhost/tasks?host=/run/postgresql";
            FRONT_URL = "https://tasks.veetik.com";
          };
        };
        tasks-frontend = {
          image = "docker.io/veetik/tasks@sha256:ba34265a63bb952f89c3952a8d8d6e6ed1e8cd72e91745b0eb0bc12d4359f46e";
          user = "101:101";
          ports = [ "127.0.0.1:${toString ports.tasksFrontend}:8080" ];
          environment = {
            PUBLIC_API_URL = "https://tasks.veetik.com";
            PUBLIC_VAPID_PUBLIC_KEY = "BMvRTtdBaxw8nWOkVbBOH_mC7sPHTkgVbbtrYqEek05-iupcxgkLUksERHvFsBIE5xytDaNzxeuLHTLu8FC-O-k";
          };
        };
      };
    };
  };

  homelab.postgresql.databases.tasks = {
    services = [ "podman-tasks-backend" ];
    backup = {
      passwordFile = config.age.secrets.restic-tasks-password.path;
    };
  };

  homelab.backups.instances.tasks.postRestoreScript = lib.mkBefore ''
    dropdb -U root tasks
    createdb -U root -O tasks tasks
  '';

  services.nginx.virtualHosts."tasks.veetik.com" = mkNginxPublic {
    locations = {
      "= /api".proxyPass = "http://127.0.0.1:${toString ports.tasksBackend}";
      "/api/".proxyPass = "http://127.0.0.1:${toString ports.tasksBackend}";
      "/".proxyPass = "http://127.0.0.1:${toString ports.tasksFrontend}";
    };
  };
}
