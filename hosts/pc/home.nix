{ pkgs, ... }:

{
  imports = [
    ../../modules/home/common.nix
    ../../modules/home/nvim.nix
  ];

  home.username = "veeti";
  home.homeDirectory = "/home/veeti";
  home.stateVersion = "25.11";

  programs.bash.enable = true;

  home.packages = with pkgs; [
    prismlauncher
    discord
    spotify
    (llama-cpp.override { vulkanSupport = true; })
    (callPackage ./pi-coding-agent.nix {})
  ];

  programs.keepassxc.enable = true;

  systemd.user.services.ssh-add = {
    Unit = {
      Description = "Load SSH key using KWallet";
      After = [ "graphical-session.target" "plasma-kwallet-pam.service" "ssh-agent.service" ];
      Requires = [ "ssh-agent.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [
        "SSH_AUTH_SOCK=%t/ssh-agent"
        "SSH_ASKPASS=${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass"
        "SSH_ASKPASS_REQUIRE=force"
      ];
      ExecStart = "${pkgs.openssh}/bin/ssh-add %h/.ssh/id_ed25519";
    };
  };
  home.file.".config/jellyfin-mpv-shim/mpv.conf".text = ''
    hwdec=auto-safe
    vo=gpu-next
    target-colorspace-hint=yes
  '';

}
