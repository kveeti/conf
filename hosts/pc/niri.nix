{ pkgs, ... }:

{
  programs.niri.enable = true;

  security.pam.services.swaylock = {};

  environment.systemPackages = with pkgs; [
    swaylock
    xwayland-satellite
  ];
}
