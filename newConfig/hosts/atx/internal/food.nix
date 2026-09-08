{ config, pkgs, withSharedVhost, ... }:

let
  domain = "food.internal.veetik.com";
  database = "/var/lib/food/food.db";
  dump = "/tmp/food.db";
in {
  age.secrets.food-secrets = {};
  homelab.volumes.food.owner = "food";

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
      restic dump --tag food latest ${dump} > ${database}
      chown food:food ${database}
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
