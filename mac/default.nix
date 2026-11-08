{ self, pkgs, nixpkgs, nixpkgs-unstable, agenix, nixvim, ... }:

let
  hostname = "e";
  username = "veeti";
  homeDir = "/Users/${username}";
  system = "aarch64-darwin";
in
{
        nix.settings.experimental-features = "nix-command flakes";

        networking.hostName = hostname;

        environment.systemPackages = with pkgs; [
          agenix.packages.${system}.agenix
          vim
          git
          zstd
          pv
          gnupg
          fzf
          home-manager
          mpv
          mosh
        ];

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

            imports = [ ../modules/home/nvim.nix ../modules/home/common.nix ../modules/home/desktop.nix ];
          })
        ];

        homebrew.enable = true;
        homebrew.taps = [ "cormacrelf/tap" ];
        homebrew.casks = [ "alacritty" "ghostty" "codex" ];
        homebrew.brews = [ "colima" "dark-notify" ];
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
        nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [ "discord" "spotify" ];
}
