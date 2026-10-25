{ config, lib, ... }:

let
  ports = config.homelab.ports;
  repositories = [
    "auth"
    "authentik"
    "bm"
    "ha"
    "internal"
    "modi"
  ];
in {
  imports = [
    ../../modules/services/restic-server.nix
    ./tls.nix
  ];

  homelab.resticServer = {
    enable = true;
    listenAddress = "127.0.0.1:${toString ports.restServer}";
    archive.enable = true;
    repositories = lib.genAttrs repositories (name: {
      clientPasswordFile = config.age.secrets."restic-${name}-rest-pass".path;
      encryptionPasswordFile = config.age.secrets."restic-${name}-encryption-pass".path;
    }) // {
      bookmarks = {
        clientPasswordFile = config.age.secrets.restic-bookmarks-password.path;
        encryptionPasswordFile = config.age.secrets.restic-bookmarks-password.path;
      };
      keycloak = {
        clientPasswordFile = config.age.secrets.restic-keycloak-password.path;
        encryptionPasswordFile = config.age.secrets.restic-keycloak-password.path;
      };
      money = {
        clientPasswordFile = config.age.secrets.restic-money-password.path;
        encryptionPasswordFile = config.age.secrets.restic-money-password.path;
      };
      radicale = {
        clientPasswordFile = config.age.secrets.restic-radicale-password.path;
        encryptionPasswordFile = config.age.secrets.restic-radicale-password.path;
      };
      rss = {
        clientPasswordFile = config.age.secrets.restic-rss-password.path;
        encryptionPasswordFile = config.age.secrets.restic-rss-password.path;
      };
      tasks = {
        clientPasswordFile = config.age.secrets.restic-tasks-password.path;
        encryptionPasswordFile = config.age.secrets.restic-tasks-password.path;
      };
      weather = {
        clientPasswordFile = config.age.secrets.restic-weather-password.path;
        encryptionPasswordFile = config.age.secrets.restic-weather-password.path;
      };
    };
  };

  services.nginx.virtualHosts."backup.internal.veetik.com" = {
    onlySSL = true;
    useACMEHost = "internal.veetik.com";
    listen = [{ addr = "0.0.0.0"; port = ports.restic; ssl = true; }];
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString ports.restServer}";
      extraConfig = ''
        client_max_body_size 0;
        proxy_request_buffering off;
      '';
    };
  };

  networking.firewall.allowedTCPPorts = [ ports.restic ];
}
