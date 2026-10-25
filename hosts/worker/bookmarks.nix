{ config, mkNginxPublic, ... }:

let
  ports = config.homelab.ports;
in {
  imports = [ ../../modules/services/postgresql.nix ];

  age.secrets.bookmarks-backend-env = {
    owner = "bookmarks";
    group = "bookmarks";
  };

  users.groups.bookmarks = {};
  users.users.bookmarks = {
    isSystemUser = true;
    group = "bookmarks";
  };

  virtualisation = {
    podman.enable = true;
    oci-containers = {
      backend = "podman";
      containers = {
        bookmarks-backend = {
          image = "docker.io/veetik/bookmarks:backend@sha256:769200adbb782292f44f9490040a59688bb2e28e06cd739871dd7c1d5565d42a";
          user = "bookmarks";
          extraOptions = [ "--hostuser=bookmarks" ];
          ports = [ "127.0.0.1:${toString ports.bookmarksBackend}:8000" ];
          volumes = [
            "/run/postgresql:/run/postgresql"
            "${config.age.secrets.bookmarks-backend-env.path}:/.env:ro"
          ];
          environment = {
            DATABASE_URL = "postgresql://bookmarks@localhost/bookmarks?host=/run/postgresql";
            FRONT_URL = "https://bm.veetik.com";
            IS_PROD = "true";
          };
        };
        bookmarks-frontend = {
          image = "docker.io/veetik/bookmarks:frontend@sha256:386f04dd8b909d04338dc8404472570012b5520c554a03d044d7051c39194d81";
          user = "65532:65532";
          ports = [ "127.0.0.1:${toString ports.bookmarksFrontend}:8080" ];
        };
      };
    };
  };

  homelab.postgresql.databases.bookmarks = {
    services = [ "podman-bookmarks-backend" ];
    backup = {
      manualRestore = true;
      passwordFile = config.age.secrets.restic-bookmarks-password.path;
    };
  };

  services.nginx.virtualHosts."bm.veetik.com" = mkNginxPublic {
    locations = {
      "= /api".proxyPass = "http://127.0.0.1:${toString ports.bookmarksBackend}";
      "/api/" = {
        proxyPass = "http://127.0.0.1:${toString ports.bookmarksBackend}";
        extraConfig = "proxy_buffering off;";
      };
      "/".proxyPass = "http://127.0.0.1:${toString ports.bookmarksFrontend}";
    };
  };
}
