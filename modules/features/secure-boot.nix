{ lib, pkgs, ... }:

{
  boot.loader = {
    systemd-boot.enable = lib.mkForce false;
    efi.canTouchEfiVariables = true;
  };

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    configurationLimit = 2;
    autoGenerateKeys.enable = true;
    autoEnrollKeys = {
      enable = true;
      autoReboot = false;
      includeMicrosoftKeys = false;
      allowBrickingMyMachine = true;
    };
  };

  environment.systemPackages = [ pkgs.sbctl ];
}
