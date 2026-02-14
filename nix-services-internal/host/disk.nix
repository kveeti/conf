{ ... }:

let
  disk = "/dev/sda";
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
        swap = {
          size = "8G";
          content = {
            type = "swap";
          };
        };

        root = {
          size = "100%FREE";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = ["defaults" "noatime"];
          };
        };
      };
    };
  };
}

