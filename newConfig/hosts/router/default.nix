{ config, adminKeys, pkgs, ... }:

let
  ports = config.homelab.ports;
in {
  imports = [
    ../../modules/profiles/base.nix
    ../../modules/profiles/server.nix
    ../../modules/features/disk-health.nix
    ../../modules/features/port-registry.nix
    ./ddns.nix
    ./disk.nix
    ./dns.nix
    ./firewall.nix
    ./hardware.nix
    ./hardening.nix
    ./network.nix
    ./secure-boot.nix
    ./telemetry.nix
    ./unifi.nix
  ];

  age.secrets.password = {};

  homelab.admin = {
    authorizedKeys = adminKeys;
    passwordFile = config.age.secrets.password.path;
  };

  services = {
    openssh.ports = [ ports.ssh ];
    prometheus.exporters.smartctl.port = ports.smartctlExporter;
  };

  networking = {
    useDHCP = false;
    useNetworkd = true;
    firewall.allowedTCPPorts = [ ports.ssh ];
  };

  environment.systemPackages = with pkgs; [
    bridge-utils
    dnsutils
    ethtool
    iproute2
    speedtest-cli
    tcpdump
    wireguard-tools
  ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  system.stateVersion = "25.11";
}
