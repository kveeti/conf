let
  inherit (import ./keys.nix) all admins servu;
in {
  "secrets/id.age".publicKeys = [ servu ] ++ admins;
  "secrets/password.age".publicKeys = [ servu ] ++ admins;
}
