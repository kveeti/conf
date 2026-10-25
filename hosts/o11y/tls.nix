{ config, ... }:

let
  ports = config.homelab.ports;
  mkNginxInternal = virtualHost: {
    onlySSL = true;
    useACMEHost = "internal.veetik.com";
    listen = [{ addr = "0.0.0.0"; port = ports.https; ssl = true; }];
  } // virtualHost;
in {
  _module.args = { inherit mkNginxInternal; };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    virtualHosts."internal-default" = mkNginxInternal {
      default = true;
      serverName = "_";
      locations."/".return = "404";
    };
  };

  networking.firewall.allowedTCPPorts = [ ports.https ];

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "security@veetik.com";
      server = "https://acme-v02.api.letsencrypt.org/directory";
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1";
      environmentFile = config.age.secrets.cloudflare-env-file.path;
    };
    certs."internal.veetik.com" = {
      domain = "internal.veetik.com";
      extraDomainNames = [ "*.internal.veetik.com" ];
      group = config.services.nginx.group;
    };
  };
}
