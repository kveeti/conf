{ config, lib, pkgs, ... }:

let
  port = config.homelab.ports.minecraftExporter;
  exporter = pkgs.buildGoModule {
    pname = "minecraft-exporter";
    version = "1.0.0";
    src = ./.;
    vendorHash = null;
    doCheck = true;
    ldflags = [ "-s" "-w" ];
    postInstall = ''
      mv $out/bin/minecraft-exporter $out/bin/minecraft-metrics
    '';
  };
in {
  environment.systemPackages = [ exporter ];

  homelab.metrics.scrapes.minecraft.targets = [ "127.0.0.1:${toString port}" ];

  # ProtectHome=true masks /home with systemd's inaccessible tmpfs, so the
  # filesystem collector otherwise reports that tmpfs instead of the home disk.
  # Keep the real mount visible but read-only; veeti's private directory stays 0700.
  systemd.services.prometheus-node-exporter.serviceConfig.ProtectHome =
    lib.mkForce "read-only";

  systemd.services.minecraft-metrics = {
    description = "Minecraft logs, Java process, world storage and Restic metrics";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    unitConfig.RequiresMountsFor = [ "/home/veeti/servers" "/home/veeti/backups" ];
    path = [ pkgs.coreutils pkgs.glibc.bin pkgs.restic ];
    serviceConfig = {
      ExecStart = "${exporter}/bin/minecraft-metrics --listen 127.0.0.1:${toString port}";
      User = "veeti";
      Group = "users";
      Restart = "on-failure";
      RestartSec = "10s";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      # Restic needs a writable cache, but no writes to the game or repository.
      CacheDirectory = "minecraft-metrics";
      Environment = "XDG_CACHE_HOME=/var/cache/minecraft-metrics";
      PrivateTmp = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      MemoryMax = "256M";
      UMask = "0077";
    };
  };
}
