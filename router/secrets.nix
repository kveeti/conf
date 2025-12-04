let
  inherit (import ./keys.nix) all admins router;
in {
  "secrets/id.age".publicKeys = [ router ] ++ admins;
  "secrets/password.age".publicKeys = [ router ] ++ admins;

  "secrets/cloudflare_ddns_env.age".publicKeys = [ router ] ++ admins;

  "secrets/wg_privkey.age".publicKeys = [ router ] ++ admins;
  "secrets/wg_mac_pubkey.age".publicKeys = [ router ] ++ admins;
  "secrets/wg_mac_presharedkey.age".publicKeys = [ router ] ++ admins;
  "secrets/wg_ip_pubkey.age".publicKeys = [ router ] ++ admins;
  "secrets/wg_ip_presharedkey.age".publicKeys = [ router ] ++ admins;
}
