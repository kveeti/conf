{ config, lib, ... }:

let
  repositories = [
    "bm"
    "ha"
    "internal"
    "modi"
    "money"
    "tasks"
  ];
in {
  imports = [
    ../../modules/services/restic-server.nix
    ./tls.nix
  ];

  homelab.resticServer = {
    enable = true;
    archive.enable = true;
    repositories = lib.genAttrs repositories (name: {
      clientPasswordFile = config.age.secrets."restic-${name}-rest-pass".path;
      encryptionPasswordFile = config.age.secrets."restic-${name}-encryption-pass".path;
    }) // {
      keycloak = {
        clientPasswordFile = config.age.secrets.restic-auth-rest-pass.path;
        encryptionPasswordFile = config.age.secrets.restic-auth-encryption-pass.path;
      };
    };
  };

  services.nginx.virtualHosts."backup.internal.veetik.com" = {
    onlySSL = true;
    useACMEHost = "internal.veetik.com";
    listen = [{ addr = "0.0.0.0"; port = 8000; ssl = true; }];
    locations."/" = {
      proxyPass = "http://127.0.0.1:8001";
      extraConfig = ''
        client_max_body_size 0;
        proxy_request_buffering off;
      '';
    };
  };

  networking.firewall.allowedTCPPorts = [ 8000 ];
}
