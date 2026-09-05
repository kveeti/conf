{ config, lib, ... }:

let
  cfg = config.homelab.admin;
  password = lib.optionalAttrs (cfg.passwordFile != null) {
    hashedPasswordFile = cfg.passwordFile;
  };
in {
  options.homelab.admin = {
    username = lib.mkOption {
      type = lib.types.str;
      default = "veeti";
      description = "Admin user name.";
    };

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "SSH keys allowed for the admin user.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional hashed password file for local login.";
    };
  };

  config = {
    users.users = {
      root = {
        openssh.authorizedKeys.keys = cfg.authorizedKeys;
      } // password;

      ${cfg.username} = {
        isNormalUser = true;
        createHome = true;
        useDefaultShell = true;
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys.keys = cfg.authorizedKeys;
      } // password;
    };

    security.sudo.wheelNeedsPassword = false;

    services.openssh = {
      enable = true;
      openFirewall = false;
      hostKeys = [{
        type = "ed25519";
        path = "/etc/ssh/ssh_host_ed25519_key";
      }];
      settings = {
        AllowUsers = [ cfg.username ];
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PubkeyAuthentication = true;
        X11Forwarding = false;
      };
    };

    networking.firewall.enable = lib.mkDefault true;
  };
}
