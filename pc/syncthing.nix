{ config, ... }:

let
  internalIp = (import ../router/inventory.nix).hosts.atxInternal.ipv4;
in
{
  networking.firewall.allowedTCPPorts = [ 22000 ];
  networking.firewall.allowedUDPPorts = [ 21027 22000 ];

  services.syncthing = {
    enable = true;
    user = "veeti";
    group = "users";
    dataDir = "/home/veeti";
    configDir = "/home/veeti/.config/syncthing";
    # pin TLS identity: device ID is the cert hash, so a reinit without this regenerates it and the hub drops pc
    cert = config.age.secrets.syncthing-cert.path;
    key = config.age.secrets.syncthing-key.path;
    settings = {
      options.relaysEnabled = false;
      options.localAnnounceEnabled = true;
      devices = {
        "internal" = {
          id = "44QIVXK-6X2VUOI-4X5QMAL-LKMHIS7-S5CQAAS-HONCLII-RFJVM3E-HR3S7QT";
          addresses = [ "tcp://${internalIp}:22000" ];
        };
        "mba" = {
          id = "SHX6HEH-RQGVIQC-FMV3WZL-2R6FSSE-CI76LVA-ISAPT2K-FTN7FMA-M5WJMQY";
        };
      };
      folders = {
        "Synced" = {
          path = "/home/veeti/Synced";
          id = "synced-nynum-wiueh-aosdi-asfgo-hjytr-pwpre";
          ignorePerms = true;
          devices = [ "internal" "mba" ];
        };
      };
    };
  };
}
