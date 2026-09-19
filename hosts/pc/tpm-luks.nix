{ config, lib, pkgs, ... }:

{
  boot.initrd.systemd.enable = true;

  boot.initrd.availableKernelModules = [ "tpm_crb" "tpm_tis" ];

  boot.initrd.luks.devices = {
    "cryptroot".crypttabExtraOpts = [
      "tpm2-device=auto"
    ];
  };
}
