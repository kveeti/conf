{ config, adminKeys, lib, pkgs, ... }:

let
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
    firewall.allowedTCPPorts = [ ports.ssh ];
  };

  services.openssh = {
    ports = [ ports.ssh ];
    hostKeys = lib.mkForce [{
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
      remoteWriteUrl = "https://metrics.internal.veetik.com/api/v1/write";
      username = "telemetry";
      passwordFile = "/run/secrets/telemetry-pass";
    };

    logs = {
      enable = true;
      url = "https://logs.internal.veetik.com";
      username = "telemetry";
      passwordFile = "/run/secrets/telemetry-pass";
    };
  };

  environment.systemPackages = [ pkgs.dnsutils ];
  system.stateVersion = "25.11";
}
