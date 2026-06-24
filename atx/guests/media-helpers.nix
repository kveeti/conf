{ config, lib, pkgs, ... }:

let
  cfg = config.services.mediaHelpers;
  vhosts = config.services.nginx.virtualHosts;

  allHosts = lib.attrNames vhosts;
  sanLine = lib.concatMapStringsSep "," (h: "DNS:${h}") allHosts;

  listed = lib.sort lib.lessThan
    (lib.filter (h: h != cfg.domain && vhosts.${h}.linklist) allHosts);
  linkItems = lib.concatMapStringsSep "\n      "
    (h: ''<li><a href="https://${h}/">${h}</a></li>'') listed;

  indexHtml = ''
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>${cfg.domain}</title>
    </head>
    <body>
      <h1>${cfg.domain}</h1>
      <ul>
      ${linkItems}
      </ul>
    </body>
    </html>
  '';
  indexRoot = pkgs.writeTextDir "index.html" indexHtml;
in {
  options.services.mediaHelpers = {
    enable = lib.mkEnableOption "media guest helpers (self-signed nginx portal + shared cert)";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "media.lan";
      description = "Hostname of the landing page; also the cert CN.";
    };

    certDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/selfsigned";
      description = "Runtime dir holding the generated self-signed keypair.";
    };
  };

  options.services.nginx.virtualHosts = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options.linklist = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "List this vhost as a link on the portal page.";
      };
      config = lib.mkIf cfg.enable {
        forceSSL = lib.mkDefault true;
        sslCertificate = lib.mkDefault "${cfg.certDir}/portal.crt";
        sslCertificateKey = lib.mkDefault "${cfg.certDir}/portal.key";
      };
    });
  };

  config = lib.mkIf cfg.enable {
    systemd.services.media-helpers-cert = {
      wantedBy = [ "multi-user.target" ];
      before = [ "nginx.service" ];
      requiredBy = [ "nginx.service" ];
      path = [ pkgs.openssl ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        set -eu
        dir="${cfg.certDir}"
        install -d -m 0755 "$dir"
        want="${sanLine}"
        if [ ! -s "$dir/portal.crt" ] || [ ! -s "$dir/portal.key" ] \
           || [ "$(cat "$dir/.sans" 2>/dev/null || true)" != "$want" ]; then
          openssl req -x509 -newkey rsa:4096 -nodes -days 3650 \
            -keyout "$dir/portal.key" -out "$dir/portal.crt" \
            -subj "/CN=${cfg.domain}" -addext "subjectAltName=$want"
          printf '%s' "$want" > "$dir/.sans"
        fi
        chown root:${config.services.nginx.group} "$dir/portal.key"
        chmod 0640 "$dir/portal.key"
      '';
    };

    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      virtualHosts.${cfg.domain} = {
        linklist = false;
        locations."/" = {
          root = "${indexRoot}";
          tryFiles = "$uri /index.html";
        };
      };
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
