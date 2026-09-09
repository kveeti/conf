{ config, ... }:

{
  age.secrets.cloudflare-env-file = {};

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "security@veetik.com";
      server = "https://acme-v02.api.letsencrypt.org/directory";
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1";
      environmentFile = config.age.secrets.cloudflare-env-file.path;
      group = "cert-readers";
    };
    certs = {
      "internal.veetik.com" = {
        domain = "internal.veetik.com";
        extraDomainNames = [ "*.internal.veetik.com" ];
      };
    };
  };
}
