let
  inherit (import ./keys.nix) all admins backup;
in {
  "secrets/password.age".publicKeys = [ backup ] ++ admins;
  "secrets/cloudflare-env.age".publicKeys = [ backup ] ++ admins;
  "secrets/alloy-env.age".publicKeys = [ backup ] ++ admins;
}
