{ config, ... }:

{
  services.nginx.virtualHosts."nginx-status" = {
    listen = [{ addr = "127.0.0.1"; port = 8050; }];
    locations."/stub_status".extraConfig = ''
      stub_status;
      access_log off;
    '';
  };

  services.prometheus.exporters.nginx = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9113;
    scrapeUri = "http://127.0.0.1:8050/stub_status";
  };

  homelab.metrics.scrapes.nginx.targets = [ "127.0.0.1:9113" ];
}
