{ config, pkgs, ... }:

let

  shareUser = "syncer";
  shareGroup = "syncer";
  shareDir = "/mnt/Synced";

in {

  homelab.volumes.syncthing.owner = "syncthing";
  homelab.volumes.Synced = { owner = shareUser; group = shareGroup; mode = "2775"; path = shareDir; };

  systemd.services.samba-set-syncer-password = {
    description = "Set samba password for syncer from agenix secret";
    wantedBy = [ "multi-user.target" ];
    after    = [ "samba-smbd.service" ];
    path = [ pkgs.samba ];
    serviceConfig.Type = "oneshot";
    script = ''
      pass=$(cat /run/secrets/samba-syncer-pass)
      if pdbedit -L 2>/dev/null | grep -q '^syncer:'; then
        printf '%s\n%s\n' "$pass" "$pass" | smbpasswd -s syncer
      else
        printf '%s\n%s\n' "$pass" "$pass" | smbpasswd -a -s syncer
      fi
    '';
  };

  users.groups.${shareGroup} = {};
  users.users.${shareUser} = {
    isSystemUser = true;
    group = shareGroup;
  };

  users.users.syncthing.extraGroups = [ shareGroup ];

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
          id = "SHX6HEH-RQGVIQC-FMV3WZL-2R6FSSE-CI76LVA-ISAPT2K-FTN7FMA-M5WJMQY";
        };
        "pc" = {
          id = "HHFDMY5-MSKBTRP-SHPE6L5-6QEMYQW-F2V773O-JJSWMSO-E7NYUOT-RZAWKQG";
        };
      };
      folders = {
        "Synced" = {
          path = shareDir;
          id = "synced-nynum-wiueh-aosdi-asfgo-hjytr-pwpre";
          ignorePerms = true;
          devices = [ "mba" "pc" ];
        };
      };
    };
  };

}
