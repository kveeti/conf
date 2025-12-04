{ ... }:

let
  disk = "/dev/nvme0n1";
in
{
  disko.devices = {
    disk.main = {
      device = disk;
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["umask=0077"];
            };
          };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptlvm";
              settings.allowDiscards = true;
              initrdUnlock = true;
              content = {
                type = "lvm_pv";
                vg = "vg0";
              };
            };
          };
        };
      };
    };

    lvm_vg.vg0 = {
      type = "lvm_vg";
      lvs = {
        root = {
          size = "10G";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = ["defaults"];
          };
        };
        home = {
          size = "1G";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/home";
            mountOptions = ["defaults"];
          };
        };
        docker = {
          size = "20G";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/var/lib/docker";
            mountOptions = ["defaults"];
          };
        };
        homelab = {
          size = "100%FREE";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/var/homelab";
            mountOptions = ["defaults"];
          };
        };
      };
    };
  };
}


