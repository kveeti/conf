{ config, ... }:

let
  ports = config.homelab.ports;
  mkNginxPublic = virtualHost: {
    onlySSL = true;
    useACMEHost = "veetik.com";
    listen = [{ addr = "0.0.0.0"; port = ports.publicHttps; ssl = true; }];
  } // virtualHost;
  mkNginxInternal = virtualHost: {
    onlySSL = true;
    useACMEHost = "internal.veetik.com";
    listen = [{ addr = "0.0.0.0"; port = ports.https; ssl = true; }];
  } // virtualHost;
in {
  _module.args = { inherit mkNginxPublic mkNginxInternal; };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    virtualHosts = {
      "public-http-default" = {
        default = true;
        serverName = "_";
        listen = [{ addr = "0.0.0.0"; port = ports.publicHttp; }];
        locations."/".return = "308 https://$host$request_uri";
      };
      "public-default" = mkNginxPublic {
        default = true;
        serverName = "_";
        locations."/".return = "404";
      };
      "internal-default" = mkNginxInternal {
        default = true;
        serverName = "_";
        locations."/".return = "404";
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ ports.publicHttp ports.publicHttps ];

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "security@veetik.com";
      server = "https://acme-v02.api.letsencrypt.org/directory";
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1";
      environmentFile = config.age.secrets.cloudflare-env-file.path;
    };
    certs."veetik.com" = {
      domain = "veetik.com";
      extraDomainNames = [ "*.veetik.com" ];
      group = config.services.nginx.group;
    };
    certs."internal.veetik.com" = {
      domain = "internal.veetik.com";
      extraDomainNames = [ "*.internal.veetik.com" ];
      group = config.services.nginx.group;
    };
  };
}
