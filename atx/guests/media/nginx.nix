{ guestIps, mediaCertInVMDir, lib, pkgs, ... }:

let
  jellyfinDomain = "jellyfin.media.lan";
  cert = "${mediaCertInVMDir}/media.lan.crt";
  key = "${mediaCertInVMDir}/media.lan.key";
  certFiles = [ cert key ];
in {
  options.services.nginx.virtualHosts = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      config = {
        forceSSL = lib.mkDefault true;
        listenAddresses = lib.mkDefault [
          (if name == jellyfinDomain then guestIps.jellyfin else guestIps.media)
        ];
        sslCertificate = lib.mkDefault cert;
        sslCertificateKey = lib.mkDefault key;
      };
    }));
  };

  config = {
    users.groups.cert-readers.gid = 6500;
    users.users.nginx.extraGroups = [ "cert-readers" ];

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
      description = "Reload nginx when the media certificate changes";
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
