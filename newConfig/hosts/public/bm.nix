{ config, inventory, ... }:

let
  publicHost = inventory.hosts.public;
  publicIp = publicHost.ipv4;
  ports = config.homelab.ports;
in {
  age.secrets.bm-backend-env = {
    owner = "bm";
    group = "bm";
  };
  age.secrets.restic-bm-rest-pass = {};
  age.secrets.restic-bm-encryption-pass = {};

  users.groups.bm = {};
  users.users.bm = {
    isSystemUser = true;
    group = "bm";
  };

  virtualisation.oci-containers.containers.bm = {
    image = "docker.io/veetik/bm_backend@sha256:769200adbb782292f44f9490040a59688bb2e28e06cd739871dd7c1d5565d42a";
    user = "bm";
    extraOptions = [ "--hostuser=bm" ];
    ports = [ "127.0.0.1:${toString ports.bm}:8000" ];
    volumes = [
      "/run/postgresql:/run/postgresql"
      "${config.age.secrets.bm-backend-env.path}:/.env:ro"
    ];
    environment.DATABASE_URL = "postgresql://bm@127.0.0.1/bm?host=/run/postgresql";
  };

  homelab.postgresql.databases.bm = {
    services = [ "podman-bm" ];
    backup = {
      restPasswordFile = config.age.secrets.restic-bm-rest-pass.path;
      encryptionPasswordFile = config.age.secrets.restic-bm-encryption-pass.path;
    };
  };

  services.nginx.virtualHosts."bm_back.veetik.com" = {
    useACMEHost = "veetik.com";
    forceSSL = true;
    listen = [
      { addr = publicIp; port = ports.http; }
      { addr = publicIp; port = ports.https; ssl = true; }
    ];
    locations."/".proxyPass = "http://127.0.0.1:${toString ports.bm}";
  };

  homelab.logs.units."podman-bm.service" = {
    format = "auto";
    serviceName = "bm";
  };
}
