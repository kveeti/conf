{ config, ... }:

let

  shareUser = "syncer";
  shareGroup = "syncer";
  shareDir = "/mnt/Synced";

in {

  users.groups.${shareGroup} = {};
  users.users.${shareUser} = {
    isNormalUser = true;
    extraGroups = [ shareGroup ];
  };

  users.users.syncthing.extraGroups = [ shareGroup ];

  systemd.tmpfiles.rules = [
    "d ${shareDir} 2775 ${shareUser} ${shareGroup} -"
  ];

  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "security" = "user";
      };
      "Synced" = {
        "path" = shareDir;
        "valid users" = shareUser;
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0664";
        "directory mask" = "2775";
        "force group" = shareGroup;
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 22000 ];
  networking.firewall.allowedUDPPorts = [ 21027 22000 ];
  services.syncthing = {
    enable = true;
    settings = {
      options.relaysEnabled = false;
      options.localAnnounceEnabled = true;
      devices = {
        "mba" = {
          id = "R7K3OLY-OC5IPOG-XGAA76R-BRCJ6DQ-GKY2P2K-NMPOZYO-46VEMYN-BRGTXA7"; 
        };
      };
      folders = {
        "Synced" = {
          path = shareDir;
          id = "synced-nynum-wiueh-aosdi-asfgo-hjytr-pwpre";
          ignorePerms = true; 
          devices = [ "mba" ];
        };
      };
    };
  };

}
