{ config, lib, pkgs, directory, ports, hostAddress, containerAddress, ... }:

{
  system.stateVersion = "26.05";
  nix.enable = false;
  users.users.root.hashedPassword = "!";

  users.groups.syncer.gid = 703;
  users.users.syncer = {
    uid = 703;
    isSystemUser = true;
    group = "syncer";
  };

  networking = {
    useHostResolvConf = false;
    useNetworkd = true;
    useDHCP = false;
    enableIPv6 = false;
    interfaces.eth0.ipv4.routes = [{
      address = hostAddress;
      prefixLength = 32;
    }];
    firewall.allowedTCPPorts = [ ports.smb ports.webdav ];
  };
  systemd.network.wait-online.enable = false;

  systemd.tmpfiles.rules = [ "d /run/samba 0755 root root -" ];
  systemd.services.samba-set-syncer-password = {
    description = "Set the Samba password for syncer";
    wantedBy = [ "samba-smbd.service" ];
    before = [ "samba-smbd.service" ];
    path = [ pkgs.samba ];
    serviceConfig = {
      Type = "oneshot";
      LoadCredential = [ "password:/run/credentials/@system/syncer-password" ];
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
    nmbd.enable = false;
    winbindd.enable = false;
    settings = {
      global = {
        "netbios name" = "SYNCED";
        workgroup = "WORKGROUP";
        security = "user";
        "server smb encrypt" = "required";
        "smb ports" = toString ports.smb;
      };
      Synced = {
        path = directory;
        "valid users" = "syncer";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "vfs objects" = "streams_xattr";
        "create mask" = "0660";
        "force create mode" = "0660";
        "directory mask" = "2770";
        "force directory mode" = "2770";
        "force group" = "syncer";
      };
    };
  };
  systemd.services.samba-smbd = {
    requires = [ "samba-set-syncer-password.service" ];
    unitConfig.RequiresMountsFor = [ directory ];
    serviceConfig = {
      LimitCORE = lib.mkForce 0;
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
      ReadWritePaths = [
        directory
        "/var/lib/samba"
        "/var/cache/samba"
        "/var/log/samba"
        "/run/samba"
        "/run/lock/samba"
      ];
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_NETLINK" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
      SystemCallErrorNumber = "EPERM";
      SystemCallFilter = [ "@system-service" ];
      UMask = "0007";
    };
  };

  services.webdav = {
    enable = true;
    user = "syncer";
    group = "syncer";
    settings = {
      address = containerAddress;
      port = ports.webdav;
      inherit directory;
      behindProxy = true;
      permissions = "CRUD";
      users = [{
        username = "syncer";
        password = "{env}WEBDAV_PASSWORD";
      }];
    };
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
      IPAddressAllow = [ "localhost" hostAddress ];
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      ProcSubset = "pid";
      ProtectClock = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectProc = "invisible";
      ProtectSystem = "strict";
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
      SystemCallErrorNumber = "EPERM";
      SystemCallFilter = [ "@system-service" "~@privileged" ];
      LoadCredential = [ "password:/run/credentials/@system/syncer-password" ];
      ExecStart = lib.mkForce (pkgs.writeShellScript "start-webdav" ''
        export WEBDAV_PASSWORD="$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/password")"
        exec ${lib.getExe config.services.webdav.package} -c ${config.services.webdav.configFile}
      '');
    };
  };
}
