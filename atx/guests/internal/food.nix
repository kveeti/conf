{ config, pkgs, withSharedVhost, ... }:

let
  domain = "food.internal.veetik.com";
  PORT = "20008";
  dbFile = "/var/lib/food/food.db";
  dumpPath = "/tmp/food.db";
in {
  config.age.secrets.food-secrets = {};

  config.homelab.volumes.food.owner = "food";

  config.homelab.backups.instances.food = {
    paths = [ dumpPath ];
    prepare = ''${pkgs.sqlite}/bin/sqlite3 ${dbFile} ".backup ${dumpPath}"'';
    cleanup = "rm -f ${dumpPath}";
    after = [ "var-lib-food.mount" ];
    hasData = "[ -f ${dbFile} ]";
    restore = ''
      restic dump --tag food latest ${dumpPath} > ${dbFile}
      chown food:food ${dbFile}
    '';
  };

  config.services.food = {
    enable = true;

    environment = {
      RUST_LOG = "info";
      HOST = "127.0.0.1:${PORT}";
      DATABASE_URL = "sqlite://food.db?mode=rwc";
    };

    environmentFile = config.age.secrets.food-secrets.path;
  };

  config.services.nginx.virtualHosts.${domain} = withSharedVhost {
    locations."/".proxyPass = "http://127.0.0.1:${PORT}";
  };
}
