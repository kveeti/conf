{ config, lib, ... }:

let
  inventory = import ../router/inventory.nix;
  publicIp = inventory.hosts.public.ipv4;
  adminIp = inventory.hosts.public.adminIpv4;

  cloudflareCidrs = [
    "173.245.48.0/20"
    "103.21.244.0/22"
    "103.22.200.0/22"
    "103.31.4.0/22"
    "141.101.64.0/18"
    "108.162.192.0/18"
    "190.93.240.0/20"
    "188.114.96.0/20"
    "197.234.240.0/22"
    "198.41.128.0/17"
    "162.158.0.0/15"
    "104.16.0.0/13"
    "104.24.0.0/14"
    "172.64.0.0/13"
    "131.0.72.0/22"
    "2400:cb00::/32"
    "2606:4700::/32"
    "2803:f800::/32"
    "2405:b500::/32"
    "2405:8100::/32"
    "2a06:98c0::/29"
    "2c0f:f248::/32"
  ];

  publicVhost = vhost: {
    useACMEHost = "veetik.com";
    forceSSL = true;
    listen = [
      { addr = publicIp; port = 80; }
      { addr = publicIp; port = 443; ssl = true; }
    ];
  } // vhost;

  proxyHeaders = ''
    proxy_set_header Connection "";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Server $hostname;
  '';
in {
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "security@veetik.com";
      server = "https://acme-v02.api.letsencrypt.org/directory";
    };
    certs."veetik.com" = {
      domain = "veetik.com";
      extraDomainNames = [ "*.veetik.com" ];
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1";
      environmentFile = config.age.secrets.cloudflare-env-file.path;
      group = config.services.nginx.group;
    };
  };

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    commonHttpConfig = ''
      # Accept CF-Connecting-IP only from Cloudflare edges.
      ${lib.concatMapStringsSep "\n" (cidr: "set_real_ip_from ${cidr};") cloudflareCidrs}
      real_ip_header CF-Connecting-IP;
      real_ip_recursive on;
    '';

    virtualHosts = {
      "public-default" = publicVhost {
        default = true;
        serverName = "_";
        locations."/".return = "404";
      };

      "auth.veetik.com" = publicVhost {
        extraConfig = proxyHeaders;
        locations = {
          "= /admin".extraConfig = "return 404;";
          "^~ /admin/".extraConfig = "return 404;";
          "= /realms/main" = {
            proxyPass = "http://127.0.0.1:8080";
            recommendedProxySettings = false;
          };
          "^~ /realms/main/" = {
            proxyPass = "http://127.0.0.1:8080";
            recommendedProxySettings = false;
          };
          "= /realms/master" = {
            proxyPass = "http://127.0.0.1:8080";
            recommendedProxySettings = false;
            extraConfig = ''
              allow 192.168.10.0/24;
              allow 10.255.255.0/24;
              deny all;
            '';
          };
          "^~ /realms/master/" = {
            proxyPass = "http://127.0.0.1:8080";
            recommendedProxySettings = false;
            extraConfig = ''
              allow 192.168.10.0/24;
              allow 10.255.255.0/24;
              deny all;
            '';
          };
          "^~ /resources/" = {
            proxyPass = "http://127.0.0.1:8080";
            recommendedProxySettings = false;
          };
          "/".extraConfig = "return 404;";
        };
      };

      "authadmin.veetik.com" = {
        useACMEHost = "veetik.com";
        onlySSL = true;
        listen = [{ addr = adminIp; port = 443; ssl = true; }];
        extraConfig = proxyHeaders + ''
          allow 127.0.0.1;
          allow 192.168.10.0/24;
          allow ${publicIp};
          allow ${adminIp};
          allow 10.255.255.0/24;
          deny all;
        '';
        locations."/" = {
          proxyPass = "http://127.0.0.1:8080";
          recommendedProxySettings = false;
        };
      };

      "tasks-api.veetik.com" = publicVhost {
        extraConfig = proxyHeaders;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8001";
          recommendedProxySettings = false;
        };
      };

      "bm_back.veetik.com" = publicVhost {
        extraConfig = proxyHeaders;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8002";
          recommendedProxySettings = false;
        };
      };

      "money.veetik.com" = publicVhost {
        extraConfig = proxyHeaders;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8003";
          recommendedProxySettings = false;
        };
      };
    };
  };
}
