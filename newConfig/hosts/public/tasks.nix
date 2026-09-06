{ config, inventory, ... }:

let
  publicHost = inventory.hosts.public;
  publicIp = publicHost.ipv4;
  ports = config.homelab.ports;
in {
  age.secrets.tasks-backend-env = {
    owner = "tasks";
    group = "tasks";
  };
  age.secrets.restic-tasks-rest-pass = {};
  age.secrets.restic-tasks-encryption-pass = {};

  users.groups.tasks = {};
  users.users.tasks = {
    isSystemUser = true;
    group = "tasks";
  };

  virtualisation.oci-containers.containers.tasks = {
    image = "docker.io/veetik/tasks-backend@sha256:902c63258c27a60bd911ab4d6360bba7f96714e4076a7800bd9d92b7fbeb3d4c";
    user = "tasks";
    extraOptions = [ "--hostuser=tasks" ];
    ports = [ "127.0.0.1:${toString ports.tasks}:8000" ];
    volumes = [
      "/run/postgresql:/run/postgresql"
      "${config.age.secrets.tasks-backend-env.path}:/.env:ro"
    ];
    environment.DATABASE_URL = "postgresql://tasks@127.0.0.1/tasks?host=/run/postgresql";
  };

  homelab.postgresql.databases.tasks = {
    services = [ "podman-tasks" ];
    backup = {
      restPasswordFile = config.age.secrets.restic-tasks-rest-pass.path;
      encryptionPasswordFile = config.age.secrets.restic-tasks-encryption-pass.path;
    };
  };

  services.nginx.virtualHosts."tasks-api.veetik.com" = {
    useACMEHost = "veetik.com";
    forceSSL = true;
    listen = [
      { addr = publicIp; port = ports.http; }
      { addr = publicIp; port = ports.https; ssl = true; }
    ];
    locations."/".proxyPass = "http://127.0.0.1:${toString ports.tasks}";
  };

  homelab.logs.units."podman-tasks.service" = {
    format = "auto";
    serviceName = "tasks";
  };
}
