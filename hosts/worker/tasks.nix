{ config, lib, tasks, mkNginxPublic, ... }:

let
  ports = config.homelab.ports;
in {
  imports = [ tasks.nixosModules.default ../../modules/services/postgresql.nix ];

  age.secrets.tasks-backend-env = {
    owner = "tasks";
    group = "tasks";
  };

  services.tasks = {
    enable = true;
    port = ports.tasksBackend;
    frontendPort = ports.tasksFrontend;
    environmentFile = config.age.secrets.tasks-backend-env.path;
    environment = {
      DATABASE_URL = "postgresql://tasks@localhost/tasks?host=/run/postgresql";
      FRONT_URL = "https://tasks.veetik.com";
    };
  };

  homelab.postgresql.databases.tasks = {
    services = [ "tasks" ];
    backup.passwordFile = config.age.secrets.restic-tasks-password.path;
  };

  homelab.backups.instances.tasks.postRestoreScript = lib.mkBefore ''
    dropdb -U root tasks
    createdb -U root -O tasks tasks
  '';

  services.nginx.virtualHosts."tasks.veetik.com" = mkNginxPublic {
    locations = {
      "= /api/health" = {
        proxyPass = "http://127.0.0.1:${toString ports.tasksBackend}";
        extraConfig = "access_log off;";
      };
      "= /api".proxyPass = "http://127.0.0.1:${toString ports.tasksBackend}";
      "/api/".proxyPass = "http://127.0.0.1:${toString ports.tasksBackend}";
      "/".proxyPass = "http://127.0.0.1:${toString ports.tasksFrontend}";
    };
  };
}
