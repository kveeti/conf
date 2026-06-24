{ config, lib, pkgs, ... }:

{
  services.gnome.gnome-keyring.enable = true;

  services.displayManager.autoLogin = {
    enable = true;
    user = "veeti";
  };
  services.displayManager.defaultSession = "none+i3";

  systemd.services.display-manager.serviceConfig.KeyringMode = "inherit";

  # NixOS bakes this PAM file via text=, ignoring rules.auth.*/enableGnomeKeyring — override the whole text
  security.pam.services.sddm-autologin.text = lib.mkForce ''
    auth     requisite pam_nologin.so
    auth     required  pam_succeed_if.so uid >= 1000 quiet
    auth     optional  ${pkgs.systemd}/lib/security/pam_systemd_loadkey.so
    auth     optional  ${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so
    auth     required  pam_permit.so
    account  include   sddm
    password include   sddm
    session  include   sddm
  '';

  security.pam.services.sddm.enableGnomeKeyring = true;
}
