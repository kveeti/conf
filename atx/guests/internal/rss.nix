{ withSharedVhost, ... }:

let
  domain = "rss.internal.veetik.com";
in {
  config.services.backedupPg.instances.rss = {};

  config.services.rss = {
    enable = true;

    environment = {
      RUST_LOG = "info";
      DATABASE_URL = "postgresql://rss@127.0.0.1/rss?host=/run/postgresql";
      HOST = "0.0.0.0:20000";
    };
  };

  config.services.nginx.virtualHosts.${domain} = withSharedVhost {
    locations."/".proxyPass = "http://127.0.0.1:20000";
  };
}
