{ lib, ... }:

{
  options.homelab.microvms = lib.mkOption {
    default = {};
    description = "MicroVM guests managed by this host.";
    type = lib.types.attrsOf (lib.types.submodule {
      options.guestModules = lib.mkOption {
        type = lib.types.listOf lib.types.deferredModule;
        default = [];
        description = "Private modules added to the guest.";
      };
    });
  };
}
