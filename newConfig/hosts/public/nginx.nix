{ config, lib, inventory, ... }:

let
  publicIp = inventory.hosts.public.ipv4;

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
in {
  imports = [ ../../modules/features/nginx-metrics.nix ];

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
    recommendedTlsSettings = true;
    commonHttpConfig = ''
      server_tokens off;

      ${lib.concatMapStringsSep "\n" (cidr: "set_real_ip_from ${cidr};") cloudflareCidrs}
      real_ip_header CF-Connecting-IP;
      real_ip_recursive on;

      proxy_http_version 1.1;
      proxy_set_header Connection "";
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $remote_addr;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Forwarded-Host $host;
      proxy_set_header X-Forwarded-Server $hostname;
      proxy_set_header X-Request-ID $request_id;
      add_header X-Request-ID $request_id always;

      log_format homelab_json escape=json '{'
        '"message":"request",'
        '"level":"info",'
        '"request_id":"$request_id",'
        '"method":"$request_method",'
        '"http_host":"$host",'
        '"uri":"$uri",'
        '"status":"$status",'
        '"bytes_sent":"$body_bytes_sent",'
        '"duration_seconds":"$request_time",'
        '"remote_addr":"$remote_addr",'
        '"user_agent":"$http_user_agent",'
        '"referer":"$http_referer",'
        '"upstream_addr":"$upstream_addr",'
        '"upstream_status":"$upstream_status",'
        '"upstream_duration_seconds":"$upstream_response_time"'
      '}';
      access_log syslog:server=unix:/dev/log,nohostname,tag=nginx_access homelab_json;
    '';

    virtualHosts."public-default" = {
      default = true;
      serverName = "_";
      useACMEHost = "veetik.com";
      forceSSL = true;
      listen = [
        { addr = publicIp; port = 80; }
        { addr = publicIp; port = 443; ssl = true; }
      ];
      locations."/".return = "404";
    };
  };

  homelab.logs.units.nginx = {
    format = "auto";
    serviceName = "nginx";
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
