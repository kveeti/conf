{ ... }:

{
  disko.devices = {
    disk.main = {
      device = "/dev/disk/by-id/nvme-Samsung_SSD_990_EVO_Plus_1TB_S7U4NJ0Y409260B";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              settings.allowDiscards = true;
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };
    };

    zpool.rpool = {
      type = "zpool";
      options.ashift = "12";
      rootFsOptions = {
        compression = "zstd";
        acltype = "posixacl";
        xattr = "sa";
        mountpoint = "none";
        "com.sun:auto-snapshot" = "false";
      };
      datasets = {
        root = {
          type = "zfs_fs";
          mountpoint = "/";
        };
        nix = {
          type = "zfs_fs";
          mountpoint = "/nix";
          options."com.sun:auto-snapshot" = "false";
        };
        var = {
          type = "zfs_fs";
          mountpoint = "/var";
        };
        restic = {
          type = "zfs_fs";
          mountpoint = "/var/lib/restic";
          options."com.sun:auto-snapshot" = "false";
        };
      };
    };

    disk.usb = {
      device = "/dev/disk/by-id/usb-WD_Elements_2621_575837324442345238464636-0:0";
      type = "disk";
      content = {
        type = "luks";
        name = "cryptapool";
        settings.allowDiscards = true;
        content = {
          type = "zfs";
          pool = "apool";
        };
      };
    };

    zpool.apool = {
      type = "zpool";
      options.ashift = "12";
      rootFsOptions = {
        compression = "zstd";
        acltype = "posixacl";
        xattr = "sa";
        mountpoint = "none";
        "com.sun:auto-snapshot" = "false";
      };
      datasets.restic = {
        type = "zfs_fs";
        mountpoint = "/var/lib/restic-archive";
        options."com.sun:auto-snapshot" = "false";
      };
    };
  };
}
