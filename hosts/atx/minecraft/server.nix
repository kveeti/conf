{ pkgs, ... }:

let
  console = pkgs.writeShellApplication {
    name = "mc-command";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${./backup/console.py} "$@"
    '';
  };
in {
  environment.systemPackages = [ console ];

  systemd.sockets.minecraft-servu = {
    bindsTo = [ "minecraft-servu.service" ];
    socketConfig = {
      ListenFIFO = "/run/minecraft-servu.stdin";
      SocketMode = "0600";
      SocketUser = "veeti";
      SocketGroup = "users";
      RemoveOnStop = true;
      FlushPending = true;
    };
  };

  systemd.services.minecraft-servu = {
    description = "Minecraft servu";
    wantedBy = [ "multi-user.target" ];
    requires = [ "minecraft-servu.socket" ];
    after = [ "network.target" "minecraft-servu.socket" ];
    unitConfig.RequiresMountsFor = [ "/home/veeti/servers/servu" ];
    serviceConfig = {
      User = "veeti";
      Group = "users";
      WorkingDirectory = "/home/veeti/servers/servu";
      ExecStart = "${pkgs.jdk25_headless}/bin/java -Xms4G -Xmx4G -XX:+UseZGC -XX:+AlwaysPreTouch -jar fabric-server-mc.26.2-loader.0.19.5-launcher.1.1.2.jar --nogui";
      StandardInput = "socket";
      StandardOutput = "journal";
      StandardError = "journal";
      KillSignal = "SIGINT";
      TimeoutStopSec = "180s";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
}
