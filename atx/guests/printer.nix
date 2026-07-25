{ config, ... }:

let
  vmName = "printer";
  stateRoot = "/var/lib/microvms/${vmName}";
in {
  homelab.microvms.${vmName} = {
    inherit stateRoot;
    certDomains = [ "internal.veetik.com" ];
    secrets = [{ name = "telemetry-pass"; mode = "0400"; }];

    shares.ssh-host = {
      owner = "root"; group = "root"; mode = "0755";
      path = "/run/ssh-host"; hostPath = "${stateRoot}/ssh";
    };

    vm = {
      specialArgs = { inherit (config._module.args) keys guestIps vlanGateway; };
      config = { config, pkgs, lib, keys, guestIps, vlanGateway, ... }: {
        imports = [ ./_common.nix ../../modules/nixos/homelab-volumes.nix ];

        # Keep the CUPS queue UUID stable so Bonjour clients continue to
        # recognize the printer after the VM is rebuilt or rebooted.
        homelab.volumeSize = 64;
        homelab.volumes.cups = {
          owner = "root";
          group = "root";
          mode = "0755";
        };

        microvm.mem = lib.mkForce 256;
        microvm.vcpu = lib.mkForce 1;

        networking.hostName = "printer";

        # qemu: USB host passthrough (cloud-hypervisor can't)
        microvm.hypervisor = lib.mkForce "qemu";

        microvm.interfaces = [{
          type = "tap";
          id = "vm-printer";
          mac = "02:00:00:40:00:02";
        }];

        # match HP LaserJet by vendor/product id; bus="usb" emits usb-host (raw qemu.extraArgs fails)
        microvm.devices = [
          { bus = "usb"; path = "vendorid=0x03f0,productid=0x0272"; }
        ];

        systemd.network.enable = true;
        systemd.network.networks."10-eth" = {
          matchConfig.Type = "ether";
          address = [ "${guestIps.printer}/24" ];
          routes = [{ Gateway = vlanGateway; }];
          networkConfig.DHCP = "no";
        };
        networking.nameservers = [ vlanGateway ];

        networking.firewall = {
          enable = true;
          allowedTCPPorts = [ 22 443 631 ];
          allowedUDPPorts = [ 5353 ];
        };

        services.printing = {
          enable = true;
          drivers = [ pkgs.hplip ];
          listenAddresses = [ "*:631" ];
          allowFrom = [ "all" ];
          browsing = true;
          defaultShared = true;
          openFirewall = true;
          # ServerAlias * lets CUPS accept the proxied Host header from nginx
          extraConf = ''
            ServerAlias *
          '';
        };

        hardware.printers = {
          ensureDefaultPrinter = "HP_LaserJet_M110w";
          ensurePrinters = [{
            name = "HP_LaserJet_M110w";
            description = "HP LaserJet M110w";
            deviceUri = "hp:/usb/HP_LaserJet_M109-M112?serial=VNC3M17074";
            model = "drv:///hp/hpcups.drv/hp-laserjet_m109-m112.ppd";
          }];
        };

        # disabled: cups-browsed would mirror our own dnssd advert back into a junk local queue
        systemd.services.cups-browsed.enable = false;

        services.avahi = {
          enable = true;
          nssmdns4 = true;
          openFirewall = true;
          publish = { enable = true; userServices = true; };
        };

        services.nginx = {
          enable = true;
          recommendedGzipSettings = true;
          recommendedOptimisation = true;
          recommendedProxySettings = true;
          recommendedTlsSettings = true;
          virtualHosts."printer.internal.veetik.com" = {
            forceSSL = true;
            sslCertificate    = "/run/cert/internal.veetik.com/fullchain.pem";
            sslCertificateKey = "/run/cert/internal.veetik.com/key.pem";
            locations."/" = {
              proxyPass = "http://127.0.0.1:631";
              proxyWebsockets = true;
            };
          };
        };
      };
    };
  };
}
