{ lib, pkgs, ... }:

{
  programs.ssh.startAgent = true;

  services.displayManager.autoLogin = {
    enable = true;
    user = "veeti";
  };
  services.displayManager.defaultSession = "plasma";

  systemd.services.display-manager.serviceConfig.KeyringMode = "inherit";

  security.pam.services.sddm-autologin.text = lib.mkForce ''
    auth     requisite pam_nologin.so
    auth     required  pam_succeed_if.so uid >= 1000 quiet
    auth     optional  ${pkgs.systemd}/lib/security/pam_systemd_loadkey.so
    auth     optional  ${pkgs.kdePackages.kwallet-pam}/lib/security/pam_kwallet5.so
    auth     required  pam_permit.so
    account  include   sddm
    password include   sddm
    session  include   sddm
  '';

  security.pam.services.sddm.kwallet.enable = true;
}
