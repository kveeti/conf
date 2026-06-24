{ config, pkgs, lib, ... }:

let
  dataDir = "/var/lib/restic";

  repos = [ "internal" "tasks" "bm" "modi" "ha" ];
  restPassSecret = name: config.age.secrets."restic-${name}-rest-pass".path;
  encPassSecret  = name: config.age.secrets."restic-${name}-encryption-pass".path;
in {
  services.restic.server = {
    enable = true;
    listenAddress = "127.0.0.1:8001";
    inherit dataDir;
    appendOnly = true;
    privateRepos = true;
    htpasswd-file = "${dataDir}/.htpasswd";
  };

  system.activationScripts.restic-htpasswd = {
    deps = [ "agenix" "users" ];
    text = ''
      install -d -m 0750 -o restic -g restic ${dataDir}
      install -m 0600 -o restic -g restic /dev/null ${dataDir}/.htpasswd
    '' + lib.concatMapStringsSep "\n" (name: ''
      printf '%s' "$(cat ${restPassSecret name})" \
        | ${pkgs.apacheHttpd}/bin/htpasswd -iB ${dataDir}/.htpasswd ${name}
    '') repos + ''
      chown restic:restic ${dataDir}/.htpasswd
      chmod 0600 ${dataDir}/.htpasswd
    '';
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    virtualHosts."backup.internal.veetik.com" = {
      onlySSL = true;
      useACMEHost = "internal.veetik.com";
      listen = [{ addr = "0.0.0.0"; port = 8000; ssl = true; }];
      locations."/" = {
        proxyPass = "http://127.0.0.1:8001";
        # restic pushes large packs — don't cap/buffer the body
        extraConfig = ''
          client_max_body_size 0;
          proxy_request_buffering off;
        '';
      };
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "security@veetik.com";
      server = "https://acme-v02.api.letsencrypt.org/directory";
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1";
      environmentFile = config.age.secrets.cloudflare-env-file.path;
    };
  };

  networking.firewall.allowedTCPPorts = [ 8000 ];

  systemd.services = lib.listToAttrs (map (name: lib.nameValuePair "restic-${name}-prune" {
    description = "Prune ${name} restic repo (host-side; append-only blocks client prune)";
    path = [ pkgs.restic ];
    serviceConfig.Type = "oneshot";
    environment = {
      RESTIC_REPOSITORY = "${dataDir}/${name}";
      RESTIC_PASSWORD_FILE = encPassSecret name;
    };
    script = ''
      if ! restic cat config >/dev/null 2>&1; then
        echo "repo not initialized yet, skipping prune"
        exit 0
      fi
      restic forget --prune --keep-daily 30
    '';
  }) repos);

  systemd.timers = lib.listToAttrs (map (name: lib.nameValuePair "restic-${name}-prune" {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "daily"; Persistent = true; RandomizedDelaySec = "1h"; };
  }) repos);
}
