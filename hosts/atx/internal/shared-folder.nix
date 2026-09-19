{ config, pkgs, ... }:

let
  user = "syncer";
  group = "syncer";
  directory = "/mnt/Synced";
  ports = config.homelab.ports;
in {
  homelab.volumes = {
    syncthing.owner = "syncthing";
    Synced = {
      owner = user;
      inherit group;
      mode = "2775";
      path = directory;
    };
  };

  users.groups.${group} = {};
  users.users.${user} = {
    isSystemUser = true;
    inherit group;
  };
  users.users.syncthing.extraGroups = [ group ];

  systemd.services.samba-set-syncer-password = {
    description = "Set the Samba password for syncer";
    wantedBy = [ "multi-user.target" ];
    after = [ "samba-smbd.service" ];
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

  services.samba = {
    enable = true;
    openFirewall = false;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        security = "user";
      };
      Synced = {
        path = directory;
        "valid users" = user;
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0664";
        "directory mask" = "2775";
        "force group" = group;
      };
    };
  };

  services.syncthing = {
    enable = true;
    openDefaultPorts = false;
    guiAddress = "127.0.0.1:${toString ports.syncthingGui}";
    settings = {
      options = {
        relaysEnabled = false;
        localAnnounceEnabled = true;
      };
      devices = {
        mba.id = "SHX6HEH-RQGVIQC-FMV3WZL-2R6FSSE-CI76LVA-ISAPT2K-FTN7FMA-M5WJMQY";
        pc.id = "HHFDMY5-MSKBTRP-SHPE6L5-6QEMYQW-F2V773O-JJSWMSO-E7NYUOT-RZAWKQG";
      };
      folders.Synced = {
        path = directory;
        id = "synced-nynum-wiueh-aosdi-asfgo-hjytr-pwpre";
        ignorePerms = true;
        devices = [ "mba" "pc" ];
      };
    };
  };

  networking.firewall = {
    allowedTCPPorts = [
      ports.netbios
      ports.smb
      ports.syncthingTransfer
    ];
    allowedUDPPorts = [
      ports.netbiosName
      ports.netbiosDatagram
      ports.syncthingDiscovery
      ports.syncthingTransfer
    ];
  };
}
