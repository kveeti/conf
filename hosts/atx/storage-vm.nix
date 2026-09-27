{ config, adminKeys, inventory, lib, ... }:

let
  name = "storage";
  stateRoot = "/var/lib/microvms/${name}";
  host = inventory.hosts.${name};
  network = inventory.networks.${host.network};
  secretDir = "${stateRoot}/secrets";
  dataImage = "${stateRoot}/data.img";
in {
  system.activationScripts.storage-vm-files = {
    deps = [ "agenix" ];
    text = ''
      install -d -m 0755 ${stateRoot}/ssh
      install -d -m 0711 ${secretDir}
      install -m 0400 ${config.age.secrets.telemetry-pass.path} ${secretDir}/telemetry-pass
      if [ ! -e ${dataImage} ]; then
        truncate -s 512000M ${dataImage}
      fi
      chown microvm:kvm ${dataImage}
      chmod 0660 ${dataImage}
    '';
  };

  systemd.network.networks."60-vm-storage" = {
    matchConfig.Name = "vm-storage";
    networkConfig.Bridge = "br-${network.interface}";
  };

  microvm.vms.storage = {
    specialArgs = { inherit adminKeys inventory; };
    config = { pkgs, ... }: {
      imports = [ ../../modules/profiles/microvm.nix ];

      networking.hostName = host.hostname;
      networking.hostId = "9c472f03";
      boot.supportedFilesystems = [ "zfs" ];
      boot.zfs.extraPools = [ "storage" ];
      services.zfs.autoScrub.enable = true;

      users.users.csi = {
        isNormalUser = true;
        createHome = true;
        home = "/var/lib/csi";
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTvZ1Sb1t3z1EVc6CHL/zYYhPiVaOQB/hmTeSAkmMXE democratic-csi@storage"
        ];
      };
      services.openssh.settings.AllowUsers = lib.mkAfter [ "csi" ];

      boot.kernelModules = [ "configfs" "target_core_mod" "iscsi_target_mod" ];
      environment.systemPackages = [ pkgs.targetcli-fb ];
      networking.nftables.enable = true;
      networking.firewall.extraInputRules = ''
        ip saddr { ${inventory.hosts.public.kubeIpv4}, ${inventory.hosts.backup.kubeIpv4} } tcp dport ${toString host.ports.iscsi} accept
      '';

      system.activationScripts.iscsi-target-state = {
        deps = [ "etc" ];
        text = ''
          install -d -m 0700 /var/lib/target
          if [ ! -e /etc/target ]; then
            ln -s /var/lib/target /etc/target
          fi
        '';
      };

      systemd.services.iscsi-target = {
        description = "iSCSI target";
        wantedBy = [ "multi-user.target" ];
        requires = [ "zfs-import-storage.service" "sys-kernel-config.mount" ];
        after = [ "zfs-import-storage.service" "sys-kernel-config.mount" ];
        restartIfChanged = false;
        unitConfig.RequiresMountsFor = "/var/lib/target";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStop = "${lib.getExe pkgs.python3Packages.rtslib-fb} clear";
        };
        script = ''
          if [ -e /etc/target/saveconfig.json ]; then
            ${lib.getExe pkgs.python3Packages.rtslib-fb} restore
          fi
        '';
      };

      microvm = {
        mem = lib.mkForce 2048;
        interfaces = [{
          type = "tap";
          id = "vm-storage";
          mac = "02:00:00:32:00:03";
        }];
        shares = [
          {
            source = "${stateRoot}/ssh";
            mountPoint = "/run/ssh-host";
            tag = "ssh-host";
            proto = "virtiofs";
          }
          {
            source = secretDir;
            mountPoint = "/run/secrets";
            tag = "secrets";
            proto = "virtiofs";
            readOnly = true;
          }
        ];
        volumes = [
          {
            image = "${stateRoot}/state.img";
            mountPoint = "/var/lib";
            size = 8192;
          }
          {
            image = dataImage;
            mountPoint = null;
            autoCreate = false;
            serial = "kube-storage-data";
            size = 512000;
          }
        ];
      };

      systemd.network = {
        enable = true;
        networks."10-ethernet" = {
          matchConfig.Type = "ether";
          address = [ "${host.ipv4}/${lib.last (lib.splitString "/" network.cidr4)}" ];
          routes = [{ Gateway = network.router4; }];
          networkConfig = {
            DHCP = "no";
            DNS = [ network.router4 ];
          };
        };
      };
    };
  };
}
