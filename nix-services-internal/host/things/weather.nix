{ config, ... }:

let

in {
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

  config.services.nginx.virtualHosts."weather.internal.veetik.com" = {
    useACMEHost = "internal.veetik.com";
    forceSSL = true;
    quic = true;
    locations."/".proxyPass = "http://127.0.0.1:20006";
  };
}
