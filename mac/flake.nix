{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.darwin.follows = "nix-darwin";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim/nixos-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, nixpkgs-unstable, agenix, home-manager, nixvim }:
    let
      hostname = "e";
      username = "veeti";
      homeDir = "/Users/${username}";
      system = "aarch64-darwin";
      pkgs = import nixpkgs { inherit system; };
      pi-coding-agent = pkgs.callPackage ./pi-coding-agent.nix { };

      configuration = { pkgs, home, ... }: {
        nix.settings.experimental-features = "nix-command flakes";

        networking.hostName = hostname;

        environment.systemPackages = with pkgs; [
          agenix.packages.${system}.agenix
          vim
          git
          zstd
          pv
          eza
          gnupg
          fzf
          home-manager
          ripgrep
          mpv
          opencode
          pi-coding-agent
          mosh
        ];

        environment.shellAliases = {
          nixswitch = "sudo darwin-rebuild switch --flake .#${hostname}";
          ls = "eza -la";
          f = "cd \"$(find ~/code ~/things -type d -maxdepth 7 -print0 | fzf --read0)\"";
          gs = "git status --short";
          gl = "git log --pretty=format:\"%C(yellow)%h%C(reset) %C(dim)%ad%C(reset) %C(green)%an%C(reset) %s\" --date=human";
          gc = "git commit -S";
          gca = "git commit -S --amend";
          k = "kubectl";
          e = "nvim";
        };

        system.primaryUser = username;
        users.users."${username}" = {
          name = username;
          home = homeDir;
        };

        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = {
          inherit nixpkgs;
          pkgs-unstable = import nixpkgs-unstable { inherit system; };
        };
        home-manager.users."${username}".home = {
          username = username;
          homeDirectory = homeDir;
          stateVersion = "25.05";
        };

        home-manager.sharedModules = [
          nixvim.homeModules.nixvim

          ({ config, lib, pkgs, ... }: {
            programs.home-manager.enable = true;
            programs.git.settings = {
              branch.sort = "-committerdate";
              push.autoSetupRemote = true;
            };

            xdg.configFile."ghostty/config".source = config.lib.file.mkOutOfStoreSymlink ./ghostty.conf;
            xdg.configFile."ghostty/themes/vague".source = config.lib.file.mkOutOfStoreSymlink ./ghostty-vague.conf;
            imports = [ ../modules/home/nvim.nix ../modules/home/common.nix ];
          })
        ];

        homebrew.enable = true;
        homebrew.taps = [ "cormacrelf/tap" ];
        homebrew.casks = [ "keepassxc" "alacritty" "ghostty" "firefox" "syncthing-app" "codex" ];
        homebrew.brews = [ "lazygit" "colima" "dark-notify" ];
        environment.systemPath = [ "/opt/homebrew/bin" ];

        security.pam.services.sudo_local = {
          enable = true;
          touchIdAuth = true;
        };

        system.defaults = {
          NSGlobalDomain.NSDocumentSaveNewDocumentsToCloud = false;
          NSGlobalDomain.AppleICUForce24HourTime = true;
          NSGlobalDomain.AppleTemperatureUnit = "Celsius";
          NSGlobalDomain.AppleMeasurementUnits = "Centimeters";
          NSGlobalDomain.AppleMetricUnits = 1;
          menuExtraClock.Show24Hour = true;
          menuExtraClock.ShowSeconds = true;

          controlcenter.BatteryShowPercentage = false;
          controlcenter.Bluetooth = true;
          controlcenter.Sound = true;
          dock = {
            orientation = "right";
            autohide = true;
            showhidden = true;
            show-recents = false;
            mru-spaces = false;
            tilesize = 34;
            persistent-apps = [];

            wvous-tl-corner = 1;
            wvous-tr-corner = 1;
            wvous-bl-corner = 1;
            wvous-br-corner = 1;
          };

          LaunchServices.LSQuarantine = false;
          CustomSystemPreferences."com.apple.screensaver" = {
            askForPassword = 1;
            askForPasswordDelay = 0;
          };
          loginwindow = {
            DisableConsoleAccess = true;
            GuestEnabled = false;
          };

          CustomSystemPreferences."com.apple.AdLib" = {
            allowApplePersonalizedAdvertising = false;
            allowIdentifierForAdvertising = false;
            forceLimitAdTracking = true;
            personalizedAdsMigrated = false;
          };

          finder.AppleShowAllFiles = true;
          finder.NewWindowTarget = "Home";
          finder.ShowPathbar = true;
          finder.ShowStatusBar = true;

          screencapture.target = "clipboard";

          screensaver.askForPasswordDelay = 0;
          screensaver.askForPassword = true;
        };

        system.startup.chime = false;
        system.defaults.trackpad = {
          Clicking = true;
          Dragging = false;
          ActuationStrength = 0;
          FirstClickThreshold = 0;
          ForceSuppressed = true;
          TrackpadRightClick = true;
          TrackpadThreeFingerDrag = true;
          TrackpadThreeFingerTapGesture = 0;
        };
        system.defaults.NSGlobalDomain.NSScrollAnimationEnabled = true;
        system.defaults.NSGlobalDomain."com.apple.mouse.tapBehavior" = 1;
        system.defaults.NSGlobalDomain."com.apple.trackpad.scaling" = 3.0;
        system.defaults.".GlobalPreferences"."com.apple.mouse.scaling" = -1.0;
        system.defaults.NSGlobalDomain.NSWindowShouldDragOnGesture = true;
        system.defaults.NSGlobalDomain.InitialKeyRepeat = 15;
        system.defaults.NSGlobalDomain.KeyRepeat = 1;
        system.defaults.NSGlobalDomain.NSAutomaticQuoteSubstitutionEnabled = false;
        system.defaults.NSGlobalDomain.NSAutomaticPeriodSubstitutionEnabled = false;
        system.defaults.NSGlobalDomain.NSAutomaticDashSubstitutionEnabled = false;
        system.defaults.NSGlobalDomain.NSAutomaticCapitalizationEnabled = false;
        system.defaults.NSGlobalDomain.NSAutomaticSpellingCorrectionEnabled = false;
        system.keyboard = {
          enableKeyMapping = true;
          remapCapsLockToControl = true;
          nonUS.remapTilde = true;
        };

        system.defaults.NSGlobalDomain."com.apple.sound.beep.feedback" = 1;

        system.configurationRevision = self.rev or self.dirtyRev or null;
        system.stateVersion = 6;
        nixpkgs.hostPlatform = system;
      };
    in
    {
      darwinConfigurations."${hostname}" = nix-darwin.lib.darwinSystem {
        modules = [
          home-manager.darwinModules.home-manager
          configuration
        ];
      };
    };
}
