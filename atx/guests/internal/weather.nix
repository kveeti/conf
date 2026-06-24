{ config, pkgs, withSharedVhost, ... }:

let
  domain = "weather.internal.veetik.com";
  dbFile = "/var/lib/weather/data.db";
  dumpPath = "/tmp/weather.db";
in {
  config.age.secrets.weather-secrets = {};

  config.homelab.volumes.weather.owner = "weather";

  config.homelab.backups.instances.weather = {
    paths = [ dumpPath ];
    prepare = ''${pkgs.sqlite}/bin/sqlite3 ${dbFile} ".backup ${dumpPath}"'';
    cleanup = "rm -f ${dumpPath}";
    after = [ "var-lib-weather.mount" ];
    hasData = "[ -f ${dbFile} ]";
    restore = ''
      restic dump --tag weather latest ${dumpPath} > ${dbFile}
      chown weather:weather ${dbFile}
    '';
  };

  config.services.weather = {
    enable = true;
    
    environment = {
      RUST_LOG = "info";
      PORT = "20006";
      DB_PATH = "data.db";
      SUMMARY_HOUR = "7";
    };

    environmentFile = config.age.secrets.weather-secrets.path;
  };

  config.services.nginx.virtualHosts.${domain} = withSharedVhost {
    locations."/".proxyPass = "http://127.0.0.1:20006";
  };
}
