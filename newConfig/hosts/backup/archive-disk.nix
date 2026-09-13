{
  boot = {
    initrd.luks.devices.cryptapool = {
      device = "/dev/disk/by-id/usb-WD_Elements_2621_575837324442345238464636-0:0";
      allowDiscards = true;
      crypttabExtraOpts = [
        "nofail"
        "x-systemd.device-timeout=15s"
        "timeout=0"
        "tries=3"
      ];
    };
    zfs.extraPools = [ "apool" ];
  };

  fileSystems."/var/lib/restic-archive" = {
    device = "apool/restic";
    fsType = "zfs";
    options = [
      "nofail"
      "x-systemd.device-timeout=15s"
    ];
  };
}
