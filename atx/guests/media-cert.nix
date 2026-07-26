{ config, guestIps, jellyfinCertInVMDir, lib, pkgs, ... }:

let
  jellyfinDomain = "jellyfin.media.lan";
  certDir = "/var/lib/selfsigned";

  vhosts = config.services.nginx.virtualHosts;
  allHosts = lib.attrNames vhosts;
  sharedHosts = lib.filter (host: host != jellyfinDomain) allHosts;
  sharedSans = lib.concatMapStringsSep "," (host: "DNS:${host}") sharedHosts;

  certFiles = [
    "${certDir}/shared.crt"
    "${certDir}/shared.key"
    "${jellyfinCertInVMDir}/${jellyfinDomain}.crt"
    "${jellyfinCertInVMDir}/${jellyfinDomain}.key"
  ];
in {
  options.services.nginx.virtualHosts = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      config = {
        forceSSL = lib.mkDefault true;
        listenAddresses = lib.mkDefault [
          (if name == jellyfinDomain then guestIps.jellyfin else guestIps.media)
        ];
        sslCertificate = lib.mkDefault (
          if name == jellyfinDomain
          then "${jellyfinCertInVMDir}/${jellyfinDomain}.crt"
          else "${certDir}/shared.crt"
        );
        sslCertificateKey = lib.mkDefault (
          if name == jellyfinDomain
          then "${jellyfinCertInVMDir}/${jellyfinDomain}.key"
          else "${certDir}/shared.key"
        );
      };
    }));
  };

  config = {
    assertions = [
      {
        assertion = lib.elem jellyfinDomain allHosts;
        message = "The media VM must define the ${jellyfinDomain} nginx vhost.";
      }
      {
        assertion = sharedHosts != [];
        message = "The media VM must define at least one shared nginx vhost.";
      }
    ];

    users.groups.cert-readers.gid = 6500;
    users.users.nginx.extraGroups = [ "cert-readers" ];

    systemd.services.media-certificate = {
      description = "Generate media certificate";
      wantedBy = [ "multi-user.target" ];
      before = [ "nginx.service" ];
      requiredBy = [ "nginx.service" ];
      path = [ pkgs.openssl ];
      unitConfig.RequiresMountsFor = certDir;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu
        umask 077
        dir='${certDir}'
        install -d -m 0750 -o root -g cert-readers "$dir"

        want='${sharedSans}'
        if [ ! -s "$dir/shared.crt" ] || [ ! -s "$dir/shared.key" ] \
           || [ "$(cat "$dir/.sans" 2>/dev/null || true)" != "$want" ]; then
          openssl req -x509 -newkey rsa:4096 -nodes -days 3650 \
            -keyout "$dir/shared.key.new" -out "$dir/shared.crt.new" \
            -subj '/CN=media.lan' -addext "subjectAltName=$want"
          mv "$dir/shared.key.new" "$dir/shared.key"
          mv "$dir/shared.crt.new" "$dir/shared.crt"
          printf '%s' "$want" > "$dir/.sans"
        fi

        chown root:cert-readers "$dir/shared.key"
        chmod 0640 "$dir/shared.key"
        chmod 0644 "$dir/shared.crt"
      '';
    };

    systemd.services.nginx.unitConfig.ConditionPathExists = certFiles;
    systemd.paths = lib.listToAttrs (lib.imap0 (index: file:
      lib.nameValuePair "media-certificate-${toString index}" {
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathChanged = file;
          Unit = "media-certificate-reload.service";
        };
      }) certFiles);
    systemd.services.media-certificate-reload = {
      description = "Reload nginx when a media certificate changes";
      serviceConfig.Type = "oneshot";
      script = "${pkgs.systemd}/bin/systemctl reload-or-restart nginx.service";
    };

    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
    };
  };
}
