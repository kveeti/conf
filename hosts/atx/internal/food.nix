{ config, pkgs, withSharedVhost, ... }:

let
  domain = "food.internal.veetik.com";
  state = "/var/lib/food";
  database = "${state}/food.db";
  dump = "/tmp/food.db";
  restoredDatabase = "${state}/.food.db.restore";
in {
  age.secrets.food-secrets = {};
  homelab.volumes.food = {
    path = state;
    owner = "food";
  };

  homelab.backups.instances.food = {
    repository = "internal";
    username = "internal";
    tag = "food";
    restPasswordFile = "/run/secrets/restic-internal-rest-pass";
    encryptionPasswordFile = "/run/secrets/restic-internal-encryption-pass";
    paths = [ dump ];
    prepare = ''${pkgs.sqlite}/bin/sqlite3 ${database} ".backup ${dump}"'';
    cleanup = "rm -f ${dump}";
    after = [ "var-lib-food.mount" ];
    hasData = "[ -f ${database} ]";
    restore = ''
      restic dump --tag food latest ${dump} > ${restoredDatabase}
      chown food:food ${restoredDatabase}
      mv ${restoredDatabase} ${database}
    '';
  };

  services.food = {
    enable = true;
    environment = {
      RUST_LOG = "info";
      HOST = "127.0.0.1:${toString config.homelab.ports.food}";
      DATABASE_URL = "sqlite://food.db?mode=rwc";
    };
    environmentFile = config.age.secrets.food-secrets.path;
  };

  services.nginx.virtualHosts.${domain} = withSharedVhost {
    locations."/".proxyPass = "http://127.0.0.1:${toString config.homelab.ports.food}";
  };
}
