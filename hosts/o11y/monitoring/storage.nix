{ config, ... }:

let
  ports = config.homelab.ports;
in {
  services.victoriametrics = {
    enable = true;
    listenAddress = "127.0.0.1:${toString ports.victoriametrics}";
    stateDir = "victoriametrics";
    retentionPeriod = "12";
  };

  systemd.services.victoriametrics-sensors = {
    description = "VictoriaMetrics long-term sensor history";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${config.services.victoriametrics.package}/bin/victoria-metrics -storageDataPath=/var/lib/victoriametrics-sensors -httpListenAddr=127.0.0.1:${toString ports.victoriametricsSensors} -retentionPeriod=100y";
      DynamicUser = true;
      User = "victoriametrics-sensors";
      Group = "victoriametrics-sensors";
      Restart = "on-failure";
      StateDirectory = "victoriametrics-sensors";
      StateDirectoryMode = "0700";
      LimitNOFILE = 1048576;
      NoNewPrivileges = true;
      PrivateDevices = true;
      MemoryDenyWriteExecute = true;
      LockPersonality = true;
      PrivateTmp = true;
      PrivateUsers = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      ProtectSystem = "full";
      RemoveIPC = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [ "@system-service" "~@privileged" "mincore" ];
      UMask = "0077";
    };
  };

  services.victorialogs = {
    enable = true;
    listenAddress = "127.0.0.1:${toString ports.victorialogs}";
    stateDir = "victorialogs";
    extraOptions = [ "-retentionPeriod=90d" ];
  };

  services.victoriatraces = {
    enable = true;
    listenAddress = "127.0.0.1:${toString ports.victoriatraces}";
    stateDir = "victoriatraces";
    retentionPeriod = "30d";
    extraOptions = [
      "-otlpGRPCListenAddr=127.0.0.1:${toString ports.victoriatracesOtlp}"
      "-otlpGRPC.tls=false"
    ];
  };
}
