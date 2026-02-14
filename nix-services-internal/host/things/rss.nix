{ config, ... }:

let

in {
  config.services.postgresql.ensureDatabases = [ "rss" ];
  config.services.postgresql.ensureUsers = [{
    name = "rss";
    ensureDBOwnership = true;
    ensureClauses = {
      login     = true;
      superuser = false;
    };
  }];

  config.users.users.rss = {
    isSystemUser = true;
    group = "rss";
  };
  config.users.groups.rss = {};
  config.systemd.services."podman-rss" = {
    after    = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
  };
  config.virtualisation.oci-containers.containers.rss = {
    image = "veetik/rss:sha-c124396";
    login = {
      registry = "docker.io";
      username = "veetik";
      passwordFile = config.age.secrets.dockerhub-token.path;
    };
    volumes = [
      "/run/postgresql:/run/postgresql"
    ];
    user = "rss";
    extraOptions = [ "--hostuser=rss" ];
    ports = [
      "127.0.0.1:20000:8000"
    ];
    environment = {
      DATABASE_URL = "postgresql://rss@127.0.0.1/rss?host=/run/postgresql";
      HOST = "0.0.0.0:8000";
    };
  };

  config.services.nginx.virtualHosts."rss.internal.veetik.com" = {
    useACMEHost = "internal.veetik.com";
    forceSSL = true;
    quic = true;
    locations."/".proxyPass = "http://127.0.0.1:20000";
  };
}
