{ config, lib, pkgs, ... }:

let
  user = "syncer";
  group = "syncer";
  directory = "/mnt/storage/Synced";
  domain = "synced.internal.veetik.com";
  ports = config.homelab.ports;
  passwordFile = config.age.secrets.samba-syncer-pass.path;
  sambaHardening = {
    LimitCORE = lib.mkForce 0;
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    PrivateTmp = true;
    ProcSubset = "pid";
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHome = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectProc = "invisible";
    ProtectSystem = "strict";
    InaccessiblePaths = [
      "-/run/agenix"
      "-/run/agenix.d"
      "-/run/credentials"
      "-/run/secrets"
      "-/var/lib/microvms"
      "-/var/lib/syncthing"
    ];
    ReadWritePaths = [
      "/var/lib/samba"
      "/var/cache/samba"
      "/var/log/samba"
      "/run/samba"
      "/run/lock/samba"
    ];
    RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];
    RestrictNamespaces = true;
    RestrictRealtime = true;
    SystemCallArchitectures = "native";
    SystemCallErrorNumber = "EPERM";
    SystemCallFilter = [ "@system-service" ];
    UMask = "0007";
  };
in {
  age.secrets.samba-syncer-pass = {};

  users.groups.${group}.gid = 703;
  users.users.${user} = {
    uid = 703;
    isSystemUser = true;
    inherit group;
  };
  users.users.syncthing.extraGroups = [ group ];

  systemd.tmpfiles.rules = [
    "d ${directory} 2770 ${user} ${group} -"
    "d /run/samba 0755 root root -"
  ];

  systemd.services.samba-set-syncer-password = {
    description = "Set the Samba password for syncer";
    wantedBy = [ "multi-user.target" ];
    after = [ "samba-smbd.service" ];
    path = [ pkgs.samba ];
    serviceConfig = {
      Type = "oneshot";
      LoadCredential = [ "password:${passwordFile}" ];
    };
    script = ''
      pass=$(cat "$CREDENTIALS_DIRECTORY/password")
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
        "server smb encrypt" = "required";
      };
      Synced = {
        path = directory;
        "valid users" = user;
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "vfs objects" = "streams_xattr";
        "create mask" = "0660";
        "force create mode" = "0660";
        "directory mask" = "2770";
        "force directory mode" = "2770";
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
        pc.id = "A5P2SJ2-SRWEGLF-UNRVNNL-7QYU55Y-NGVAUPY-ZXJ3KVI-CVDFJSP-VV4IEAA";
      };
      folders.Synced = {
        path = directory;
        id = "synced-nynum-wiueh-aosdi-asfgo-hjytr-pwpre";
        ignorePerms = true;
        devices = [ "mba" "pc" ];
      };
    };
  };

  services.webdav = {
    enable = true;
    inherit user group;
    settings = {
      address = "127.0.0.1";
      port = ports.webdav;
      inherit directory;
      behindProxy = true;
      permissions = "CRUD";
      users = [{
        username = user;
        password = "{env}WEBDAV_PASSWORD";
      }];
    };
  };

  systemd.services.samba-smbd = {
    unitConfig.RequiresMountsFor = [ directory ];
    serviceConfig = sambaHardening // {
      ReadWritePaths = sambaHardening.ReadWritePaths ++ [ directory ];
      CapabilityBoundingSet = [
        "CAP_AUDIT_WRITE"
        "CAP_CHOWN"
        "CAP_DAC_OVERRIDE"
        "CAP_FOWNER"
        "CAP_FSETID"
        "CAP_LEASE"
        "CAP_NET_BIND_SERVICE"
        "CAP_SETGID"
        "CAP_SETUID"
      ];
    };
  };
  systemd.services.samba-nmbd.serviceConfig = sambaHardening // {
    CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
  };
  systemd.services.samba-winbindd.serviceConfig = sambaHardening // {
    CapabilityBoundingSet = [
      "CAP_AUDIT_WRITE"
      "CAP_CHOWN"
      "CAP_DAC_OVERRIDE"
      "CAP_FOWNER"
      "CAP_SETGID"
      "CAP_SETUID"
    ];
  };
  systemd.services.syncthing = {
    unitConfig.RequiresMountsFor = [ directory ];
    serviceConfig.UMask = "0007";
  };
  systemd.services.webdav = {
    unitConfig.RequiresMountsFor = [ directory ];
    confinement.enable = true;
    serviceConfig = {
      UMask = "0007";
      BindPaths = [ directory ];
      ReadWritePaths = [ directory ];
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      IPAddressDeny = "any";
      IPAddressAllow = "localhost";
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      ProcSubset = "pid";
      ProtectClock = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectProc = "invisible";
      ProtectSystem = "strict";
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
      SystemCallErrorNumber = "EPERM";
      SystemCallFilter = [ "@system-service" "~@privileged" ];
      LoadCredential = [ "password:${passwordFile}" ];
      ExecStart = lib.mkForce (pkgs.writeShellScript "start-webdav" ''
        export WEBDAV_PASSWORD="$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/password")"
        exec ${lib.getExe config.services.webdav.package} -c ${config.services.webdav.configFile}
      '');
    };
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    virtualHosts.${domain} = {
      forceSSL = true;
      useACMEHost = "internal.veetik.com";
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString ports.webdav}";
        extraConfig = ''
          client_max_body_size 0;
          proxy_request_buffering off;
          set $webdav_destination $http_destination;
          if ($http_destination ~ "^https?://[^/]+(?<destination_path>/.*)$") {
            set $webdav_destination $destination_path;
          }
          proxy_set_header Destination $webdav_destination;
        '';
      };
    };
  };
  users.users.nginx.extraGroups = [ "cert-readers" ];

  networking.firewall = {
    allowedTCPPorts = [
      ports.http
      ports.https
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
