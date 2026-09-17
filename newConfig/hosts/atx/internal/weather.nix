{ config, pkgs, withSharedVhost, ... }:

let
  domain = "weather.internal.veetik.com";
  state = "/var/lib/weather";
  database = "${state}/data.db";
  dump = "/tmp/weather.db";
  restoredDatabase = "${state}/.data.db.restore";
in {
  age.secrets.weather-secrets = {};
  homelab.volumes.weather = {
    path = state;
    owner = "weather";
  };

  homelab.backups.instances.weather = {
    repository = "internal";
    username = "internal";
    tag = "weather";
    restPasswordFile = "/run/secrets/restic-internal-rest-pass";
    encryptionPasswordFile = "/run/secrets/restic-internal-encryption-pass";
    paths = [ dump ];
    prepare = ''${pkgs.sqlite}/bin/sqlite3 ${database} ".backup ${dump}"'';
    cleanup = "rm -f ${dump}";
    after = [ "var-lib-weather.mount" ];
    hasData = "[ -f ${database} ]";
    restore = ''
      restic dump --tag weather latest ${dump} > ${restoredDatabase}
      chown weather:weather ${restoredDatabase}
      mv ${restoredDatabase} ${database}
    '';
  };

  services.weather = {
    enable = true;
    environment = {
      RUST_LOG = "info";
      PORT = toString config.homelab.ports.weather;
      DB_PATH = "data.db";
      SUMMARY_HOUR = "7";
    };
    environmentFile = config.age.secrets.weather-secrets.path;
  };

  services.nginx.virtualHosts.${domain} = withSharedVhost {
    locations."/".proxyPass = "http://127.0.0.1:${toString config.homelab.ports.weather}";
  };
}
