{ inventory, lib, pkgs, ... }:

let
  media = inventory.hosts.media;
  jellyfin = inventory.hosts.jellyfin;
  jellyfinDomain = "jellyfin.media.lan";
  certificateDirectory = "/run/media-certificate";
  certificate = "${certificateDirectory}/media.lan.crt";
  certificateKey = "${certificateDirectory}/media.lan.key";
  certificateFiles = [ certificate certificateKey ];
in {
  options.services.nginx.virtualHosts = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      config = {
        forceSSL = lib.mkDefault true;
        listenAddresses = lib.mkDefault [
          (if name == jellyfinDomain then jellyfin.ipv4 else media.ipv4)
        ];
        sslCertificate = lib.mkDefault certificate;
        sslCertificateKey = lib.mkDefault certificateKey;
      };
    }));
  };

  config = {
    users.groups.cert-readers.gid = 6500;
    users.users.nginx.extraGroups = [ "cert-readers" ];

    systemd.services.nginx.unitConfig.ConditionPathExists = certificateFiles;
    systemd.paths = lib.listToAttrs (lib.imap0 (index: file:
      lib.nameValuePair "media-certificate-${toString index}" {
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathChanged = file;
          Unit = "media-certificate-reload.service";
        };
      }
    ) certificateFiles);
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
