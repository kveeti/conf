{ config, lib, pkgs, pkgs-unstable, ... }:

let
  inventory = import ../../inventory.nix;
in
{
  home.packages = with pkgs; [
    discord
    spotify
    syncthing
    pkgs-unstable.opencode
    pkgs-unstable.pi-coding-agent
  ] ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.ghostty ];

  programs.firefox = {
    enable = true;
    profiles.default = {
      id = 0;
      isDefault = true;
      settings = {
        "browser.contentblocking.category" = "strict";
        "privacy.fingerprintingProtection" = true;
        "privacy.query_stripping.enabled" = true;
        "privacy.query_stripping.enabled.pbmode" = true;

        "datareporting.healthreport.uploadEnabled" = false;
        "datareporting.usage.uploadEnabled" = false;
        "app.shield.optoutstudies.enabled" = false;
        "nimbus.rollouts.enabled" = false;
        "browser.discovery.enabled" = false;

        "browser.ai.control.default" = "blocked";
        "browser.ai.control.linkPreviewKeyPoints" = "blocked";
        "browser.ai.control.pdfjsAltText" = "blocked";
        "browser.ai.control.sidebarChatbot" = "blocked";
        "browser.ai.control.smartTabGroups" = "blocked";
        "browser.ai.control.smartWindow" = "blocked";
        "browser.ai.control.translations" = "blocked";
        "browser.ml.chat.enabled" = false;
        "browser.ml.chat.menu" = false;
        "browser.ml.chat.page" = false;
        "browser.ml.linkPreview.enabled" = false;
        "browser.tabs.groups.smart.enabled" = false;
        "browser.tabs.groups.smart.userEnabled" = false;
        "browser.smartwindow.memories.generateFromConversation" = false;
        "browser.smartwindow.memories.generateFromHistory" = false;
        "extensions.ml.enabled" = false;
        "pdfjs.enableAltText" = false;

        "signon.rememberSignons" = false;
        "signon.firefoxRelay.feature" = "disabled";
        "signon.management.page.breach-alerts.enabled" = false;
        "extensions.formautofill.addresses.enabled" = false;
        "extensions.formautofill.creditCards.enabled" = false;

        "sidebar.verticalTabs" = true;
        "browser.toolbars.bookmarks.visibility" = "never";
        "browser.startup.homepage" = "chrome://browser/content/blanktab.html";
        "browser.newtabpage.enabled" = false;
        "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons" = false;
        "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features" = false;
        "browser.urlbar.suggest.trending" = false;

        "general.smoothScroll" = false;
        "browser.translations.enable" = false;
        "media.eme.enabled" = true;
      };
    };
    policies.ExtensionSettings = lib.genAttrs [
      "uBlock0@raymondhill.net"
      "sponsorBlocker@ajay.app"
      "myallychou@gmail.com"
      "keepassxc-browser@keepassxc.org"
      "firefox@betterttv.net"
    ] (id: {
      installation_mode = "force_installed";
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/${id}/latest.xpi";
    });
  };
  programs.thunderbird = {
    enable = true;
    profiles.default.isDefault = true;
  };

  accounts.email.accounts.personal = {
    primary = true;
    address = "veeti@veetik.com";
    realName = "Veeti K";
    userName = "veeti@internal.veetik.com";
    imap = {
      host = "mail.internal.veetik.com";
      port = 993;
      tls.enable = true;
    };
    smtp = {
      host = "mail.internal.veetik.com";
      port = 465;
      tls.enable = true;
    };
    thunderbird.enable = true;
  };

  programs.lazygit = {
    enable = true;
    settings.git.overrideGpg = true;
  };

  programs.keepassxc.enable = true;
  services.syncthing = {
    enable = true;
    settings = {
      options.relaysEnabled = false;
      devices.worker = {
        id = "HGEE7QW-DFD2DHT-BKEGK3V-5JFR52R-U3WXKFC-GLX2K6I-SVO4RA5-3J3BOQK";
        addresses = [ "tcp://${inventory.hosts.worker.ipv4}:${toString inventory.hosts.worker.ports.syncthingTransfer}" ];
      };
      folders.Synced = {
        path = "${config.home.homeDirectory}/Synced";
        id = "synced-nynum-wiueh-aosdi-asfgo-hjytr-pwpre";
        ignorePerms = true;
        devices = [ "worker" ];
      };
    };
  };

  home.activation.syncthingLogDirectory = lib.mkIf pkgs.stdenv.isDarwin (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/Library/Logs/Syncthing"
  '');

  xdg.mimeApps = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    defaultApplications = {
      "text/html" = [ "firefox.desktop" ];
      "application/xhtml+xml" = [ "firefox.desktop" ];
      "x-scheme-handler/http" = [ "firefox.desktop" ];
      "x-scheme-handler/https" = [ "firefox.desktop" ];
    };
  };

  home.activation.firefoxDefaultBrowser = lib.mkIf pkgs.stdenv.isDarwin (lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
      -f "${config.programs.firefox.finalPackage}/Applications/Firefox.app"
    run ${pkgs.duti}/bin/duti -s org.nixos.firefox http
    run ${pkgs.duti}/bin/duti -s org.nixos.firefox https
    run ${pkgs.duti}/bin/duti -s org.nixos.firefox public.html all
  '');

  xdg.configFile."ghostty/config".source = config.lib.file.mkOutOfStoreSymlink ./ghostty.conf;
  xdg.configFile."ghostty/themes/vague".source = config.lib.file.mkOutOfStoreSymlink ./ghostty-vague.conf;
}
