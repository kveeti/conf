{ config, inventory, pkgs, mkNginxInternal, ... }:

let
  directory = "/var/lib/synced";
  domain = "synced.internal.veetik.com";
  ports = config.homelab.ports;
  uidBase = 524288;
  syncerUid = uidBase + 703;
  hostAddress = "10.204.0.1";
  containerAddress = "10.204.0.2";
in {
  age.secrets.samba-syncer-pass = {};
  age.secrets.syncthing-gui-password = {
    owner = "syncer";
    group = "syncer";
  };

  users.groups.syncer.gid = syncerUid;
  users.users.syncer = {
    uid = syncerUid;
    isSystemUser = true;
    group = "syncer";
    home = "/var/lib/syncthing";
    createHome = true;
  };

  systemd.tmpfiles.rules = [
    "d ${directory} 2770 syncer syncer -"
    "d /var/lib/syncthing 0700 syncer syncer -"
  ];

  services.syncthing = {
    enable = true;
    user = "syncer";
    group = "syncer";
    openDefaultPorts = false;
    guiAddress = "127.0.0.1:${toString ports.syncthingGui}";
    guiPasswordFile = config.age.secrets.syncthing-gui-password.path;
    settings = {
      gui.user = "veetik";
      options = {
        relaysEnabled = false;
        localAnnounceEnabled = true;
      };
      devices = {
        mba.id = "7LBSUHY-4L47ERW-JUGZNRB-LQUF73W-72YL3F6-GDOEGPR-BMXTXC4-NYGTZQ6";
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
  systemd.services.syncthing = {
    unitConfig.RequiresMountsFor = [ directory ];
    serviceConfig.UMask = "0007";
  };

  containers.files = {
    autoStart = true;
    privateUsers = uidBase;
    privateNetwork = true;
    inherit hostAddress;
    localAddress = containerAddress;
    bindMounts.${directory} = {
      hostPath = directory;
      isReadOnly = false;
    };
    extraFlags = [
      "--private-users-ownership=auto"
      "--load-credential=syncer-password:${config.age.secrets.samba-syncer-pass.path}"
    ];
    specialArgs = { inherit directory ports hostAddress containerAddress; };
    config.imports = [ ./shared-folder-container.nix ];
  };

  systemd.services."container@files" = {
    restartTriggers = [ config.age.secrets.samba-syncer-pass.file ];
    serviceConfig.InaccessiblePaths = [ "/nix/var/nix/daemon-socket" ];
  };

  systemd.network.networks."50-files-container" = {
    matchConfig.Name = "ve-files";
    linkConfig = {
      Unmanaged = true;
      ActivationPolicy = "manual";
    };
  };

  systemd.sockets.files-smb = {
    wantedBy = [ "sockets.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    socketConfig.ListenStream = "${inventory.hosts.worker.ipv4}:${toString ports.smb}";
  };
  systemd.services.files-smb = {
    description = "Proxy SMB into the files container";
    requires = [ "container@files.service" ];
    after = [ "container@files.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd ${containerAddress}:${toString ports.smb}";
      DynamicUser = true;
      CapabilityBoundingSet = "";
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ProtectControlGroups = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectKernelLogs = true;
      ProtectClock = true;
      ProtectHostname = true;
      ProtectProc = "invisible";
      ProcSubset = "pid";
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [ "@system-service" "~@privileged" ];
      UMask = "0077";
    };
  };

  networking.nftables.tables.files-isolation = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority -10; policy accept;
        iifname "ve-files" ct state established ct direction reply accept
        iifname "ve-files" drop
      }
      chain forward {
        type filter hook forward priority -10; policy accept;
        iifname "ve-files" drop
        oifname "ve-files" drop
      }
    '';
  };

  services.nginx.virtualHosts.${domain} = mkNginxInternal {
    locations."/" = {
      proxyPass = "http://${containerAddress}:${toString ports.webdav}";
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

  networking.firewall = {
    allowedTCPPorts = [
      ports.https
      ports.smb
      ports.syncthingTransfer
    ];
    allowedUDPPorts = [
      ports.syncthingDiscovery
      ports.syncthingTransfer
    ];
  };
}
