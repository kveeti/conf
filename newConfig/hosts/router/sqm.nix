{ inventory, pkgs, ... }:

let
  wan = inventory.router.wanInterface;
  ifb = inventory.router.ifbInterface;
  uploadMbit = 95;
  downloadMbit = 95;
in {
  boot.kernelModules = [ "ifb" ];

  systemd.services.sqm = {
    description = "WAN smart queue management";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.iproute2}/bin/ip link add ${ifb} type ifb 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip link set ${ifb} up

      ${pkgs.iproute2}/bin/tc qdisc replace dev ${wan} root handle 1: htb default 10
      ${pkgs.iproute2}/bin/tc class replace dev ${wan} parent 1: classid 1:10 htb rate ${toString uploadMbit}mbit ceil ${toString uploadMbit}mbit
      ${pkgs.iproute2}/bin/tc qdisc replace dev ${wan} parent 1:10 handle 10: fq_codel

      ${pkgs.iproute2}/bin/tc qdisc replace dev ${wan} handle ffff: ingress
      ${pkgs.iproute2}/bin/tc filter replace dev ${wan} parent ffff: protocol all pref 1 u32 match u32 0 0 action mirred egress redirect dev ${ifb}
      ${pkgs.iproute2}/bin/tc qdisc replace dev ${ifb} root handle 1: htb default 10
      ${pkgs.iproute2}/bin/tc class replace dev ${ifb} parent 1: classid 1:10 htb rate ${toString downloadMbit}mbit ceil ${toString downloadMbit}mbit
      ${pkgs.iproute2}/bin/tc qdisc replace dev ${ifb} parent 1:10 handle 10: fq_codel
    '';
    preStop = ''
      ${pkgs.iproute2}/bin/tc qdisc del dev ${wan} root 2>/dev/null || true
      ${pkgs.iproute2}/bin/tc qdisc del dev ${wan} ingress 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip link del ${ifb} 2>/dev/null || true
    '';
  };
}
