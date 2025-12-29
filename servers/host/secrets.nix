let
  inherit (import ./keys.nix) all admins servers;
in {
  "secrets/password.age".publicKeys = [ servers ] ++ admins;
  "secrets/alloy-env.age".publicKeys = [ servers ] ++ admins;
}
