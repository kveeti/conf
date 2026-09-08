{ config, adminKeys, inventory, lib, pkgs, ... }:

let
  backup = inventory.hosts.backup;
  ports = config.homelab.ports;
in {
  imports = [
    ./base.nix
    ./server.nix
    ../features/port-registry.nix
    ../telemetry/logs.nix
    ../telemetry/metrics.nix
  ];

  homelab.admin.authorizedKeys = adminKeys;

  microvm = {
    hypervisor = "cloud-hypervisor";
    mem = lib.mkDefault 1024;
    vcpu = lib.mkDefault 2;
    shares = [{
      source = "/nix/store";
      mountPoint = "/nix/.ro-store";
      tag = "ro-store";
      proto = "virtiofs";
    }];
  };

  boot.loader = {
    grub.enable = false;
    systemd-boot.enable = false;
  };

  networking = {
    useDHCP = false;
    useNetworkd = true;
    hosts.${backup.ipv4} = [ "backup.internal.veetik.com" ];
    firewall.allowedTCPPorts = [ ports.ssh ];
  };

  services.openssh = {
    ports = [ ports.ssh ];
    hostKeys = [{
      path = "/run/ssh-host/ssh_host_ed25519_key";
      type = "ed25519";
    }];
  };
  systemd.services.sshd-keygen.unitConfig.RequiresMountsFor = "/run/ssh-host";

  homelab = {
    metrics = {
      enable = true;
      listenAddress = "127.0.0.1:${toString ports.vmagent}";
      nodeExporter.port = ports.nodeExporter;
      remoteWriteUrl = "https://backup.internal.veetik.com:${toString backup.ports.metricsIngress}/api/v1/write";
      username = "telemetry";
      passwordFile = "/run/secrets/telemetry-pass";
    };

    logs = {
      enable = true;
      url = "https://backup.internal.veetik.com:${toString backup.ports.logsIngress}";
      username = "telemetry";
      passwordFile = "/run/secrets/telemetry-pass";
    };
  };

  environment.systemPackages = [ pkgs.dnsutils ];
  system.stateVersion = "25.11";
}
