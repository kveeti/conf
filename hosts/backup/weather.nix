{ config, weather, ... }:

let
  state = "/var/lib/weather";
  port = 20006;
in {
  imports = [
    weather.nixosModules.default
    ../../modules/services/restic-backups.nix
  ];

  services.weather = {
    enable = true;
    environmentFile = config.age.secrets.weather-secrets.path;
    environment = {
      PORT = toString port;
      DB_PATH = "${state}/data.db";
    };
  };

  services.nginx.virtualHosts."weather.internal.veetik.com" = {
    onlySSL = true;
    useACMEHost = "internal.veetik.com";
    listen = [{ addr = "0.0.0.0"; port = config.homelab.ports.https; ssl = true; }];
    locations."/".proxyPass = "http://127.0.0.1:${toString port}";
  };

  homelab.backups.instances.weather = {
    passwordFile = config.age.secrets.restic-weather-password.path;
    paths = [ state ];
    preBackupScript = ''
      systemctl stop weather.service
    '';
    postBackupScript = ''
      systemctl start weather.service
    '';
    restoreDirectory = state;
    preRestoreScript = ''
      systemctl stop weather.service
    '';
    postRestoreScript = ''
      systemctl start weather.service
    '';
  };
}
