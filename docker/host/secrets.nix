let
  inherit (import ./keys.nix) all admins servu;
in {
  "secrets/password.age".publicKeys = [ servu ] ++ admins;
  "secrets/alloy-env.age".publicKeys = [ servu ] ++ admins;
}
