{ config, lib, pkgs, mediaUser, ... }:

{
  users.groups.${mediaUser.group}.gid = mediaUser.gid;

  boot.initrd.luks.devices = {
    crypt_data1 = {
      device = "/dev/disk/by-uuid/0472771e-67a7-41fd-8855-7c749e785bab";
      allowDiscards = true;
    };
    crypt_parity1 = {
      device = "/dev/disk/by-uuid/5cbde82f-63a7-4da7-b27d-43a132636919";
      allowDiscards = true;
    };
  };

  fileSystems."/mnt/data1" = {
    device = "/dev/disk/by-uuid/0d166701-6104-4468-bacd-e1b27edd827a";
    fsType = "ext4";
  };
  fileSystems."/mnt/parity1" = {
    device = "/dev/disk/by-uuid/15dc1e74-106d-4626-ad64-bb2110a6d8c1";
    fsType = "ext4";
  };

  environment.systemPackages = [ pkgs.mergerfs ];

  systemd.tmpfiles.rules = [
    "d /mnt/storage 0755 root root -"
  ];

  fileSystems."/mnt/storage" = {
    fsType = "fuse.mergerfs";
    device = "/mnt/data1";
    depends = [ "/mnt/data1" ];
    options = [
      "cache.files=partial"
      "dropcacheonclose=true"
      "category.create=epmfs"
      "minfreespace=50G"
      "fsname=mergerfs"
      "allow_other"
      "use_ino"
      "nofail"
    ];
  };

  services.snapraid = {
    enable = true;
    dataDisks = {
      d1 = "/mnt/data1";
    };
    parityFiles = [
      "/mnt/parity1/snapraid.parity"
    ];
    contentFiles = [
      "/var/snapraid.content"
      "/mnt/data1/snapraid.content"
    ];
    sync.interval = "05:00";
    scrub.interval = "Sun 04:00";
  };
}
