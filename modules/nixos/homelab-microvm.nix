{ config, lib, ... }:

# AVOID INFINITE RECURSION: keep the *set* of top-level config keys static (e.g.
# `microvm.vms`, `security.acme.certs`) with cfg-derived values lazy underneath.
# Making the key set depend on cfg forces cfg during the module system's
# unmatched-definitions check, which loops back through this same config.

let
  cfg = config.homelab.microvms;
  mkGuestCert = import ./guest-cert.nix lib;
  mkGuestSecrets = import ./guest-secrets.nix lib;
  mkGuestShares = import ./guest-shares.nix lib;

  hasCert = m: m.certDomains != [];
  certOf = name: m: mkGuestCert {
    vmName = name;
    stateRoot = m.stateRoot;
    certNames = m.certDomains;
  };

  secretPath = path: { inherit path; };
  secretDerive = derive: { inherit derive; };

  hasSecrets = m: m.secrets != [];
  hasShares = m: m.shares != {};
  sharesOf = name: m: mkGuestShares { vmName = name; stateRoot = m.stateRoot; shares = m.shares; };

  nullStr = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
  dirMod = lib.types.submodule { options = { owner = nullStr; group = nullStr; mode = nullStr; }; };
  shareMod = lib.types.submodule { options = {
    path     = nullStr // { description = "Guest mount path (default /var/lib/<name>)."; };
    owner    = nullStr // { description = "Source dir owner — a HOST user/uid (often numeric); default <name>."; };
    group    = nullStr // { description = "Source dir group (default = owner)."; };
    mode     = nullStr // { description = "Source dir mode (default 0750)."; };
    hostPath = nullStr // { description = "Host source dir to export (default <stateRoot>/<name>)."; };
    create = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Create/manage the host source dir. Set false for externally-owned mounts (e.g. a host mergerfs) to leave perms/ownership alone.";
    };
    readOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Mount the virtiofs share read-only in the guest.";
    };
    dirs = lib.mkOption {
      type = lib.types.attrsOf dirMod;
      default = {};
      description = "Nested child dirs; each perm field inherits the root dir when null.";
    };
  }; };

  secretsOf = name: m: mkGuestSecrets {
    vmName = name;
    stateRoot = m.stateRoot;
    secrets = lib.listToAttrs (map (s: lib.nameValuePair s.name {
      inherit (s) mode;
      source =
        if s.value == null then config.age.secrets.${s.name}.path
        else s.value.path or null;
      derive = if s.value == null then null else s.value.derive or null;
    }) m.secrets);
  };
in {
  options.homelab.microvms = lib.mkOption {
    default = {};
    description = "MicroVM guests with optional host-shared TLS certs.";
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = {
        stateRoot = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/microvms/${name}";
          description = "Host state dir for this guest (certs/secrets/volumes live under here).";
        };
        certDomains = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "ACME cert names to share read-only from the host. Empty = no cert wiring.";
        };
        secrets = lib.mkOption {
          default = [];
          description = "Secrets materialized host-side and shared read-only into the guest at /run/secrets/<name>. Empty = no secret wiring.";
          type = lib.types.listOf (lib.types.submodule {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                description = "Secret name; also the basename under /run/secrets in the guest.";
              };
              value = lib.mkOption {
                type = lib.types.nullOr (lib.types.attrTag {
                  path = lib.mkOption {
                    type = lib.types.str;
                    description = "Host source path to copy.";
                  };
                  derive = lib.mkOption {
                    type = lib.types.lines;
                    description = "Shell snippet whose stdout becomes the content, run host-side with agenix available (so it can read other secrets).";
                  };
                });
                default = null;
                description = "How to obtain the secret: secretPath \"<path>\" or secretDerive \"<shell>\". null = copy config.age.secrets.<name>.path.";
              };
              mode = lib.mkOption {
                type = lib.types.str;
                default = "0444";
                description = "Install mode of the host-side shared copy.";
              };
            };
          });
        };
        shares = lib.mkOption {
          default = {};
          type = lib.types.attrsOf shareMod;
          description = "Virtiofs shares from the host; source dir created host-side. Block-volume storage is the guest-side `homelab.volumes`.";
        };
        vm = lib.mkOption {
          type = lib.types.raw;
          description = "The microvm.vms.<name> value (specialArgs + config). The cert guest module is imported into it automatically.";
        };
        guestModules = lib.mkOption {
          type = lib.types.listOf lib.types.deferredModule;
          default = [];
          description = "Extra modules imported into the guest eval alongside `vm.config`. A merge point for out-of-tree (e.g. private) guest config; gets the same specialArgs.";
        };
      };
    }));
  };

  config = {
    assertions = lib.concatLists (lib.mapAttrsToList (name: m: [
      {
        assertion = m.vm ? config;
        message = "homelab.microvms.${name}.vm must set `config`.";
      }
      {
        assertion = lib.all (d: d != "") m.certDomains;
        message = "homelab.microvms.${name}.certDomains must not contain empty strings.";
      }
    ]) cfg);

    _module.args = { inherit secretPath secretDerive; };

    microvm.vms = lib.mapAttrs (name: m:
      m.vm // {
        config.imports = [ m.vm.config ]
          ++ lib.optional (hasCert m) (certOf name m).guest
          ++ lib.optional (hasSecrets m) (secretsOf name m).guest
          ++ lib.optional (hasShares m) (sharesOf name m).guest
          ++ m.guestModules;
      }
    ) cfg;

    # split per option path so each top-level key stays static (recursion note above)
    security.acme.certs = lib.mkMerge (lib.mapAttrsToList (name: m:
      lib.optionalAttrs (hasCert m) (certOf name m).host.security.acme.certs) cfg);

    systemd.services = lib.mkMerge (lib.mapAttrsToList (name: m:
      lib.optionalAttrs (hasCert m) (certOf name m).host.systemd.services) cfg);

    system.activationScripts = lib.mkMerge (
      (lib.mapAttrsToList (name: m:
        lib.optionalAttrs (hasCert m) (certOf name m).host.system.activationScripts) cfg)
      ++ (lib.mapAttrsToList (name: m:
        lib.optionalAttrs (hasSecrets m) (secretsOf name m).host.system.activationScripts) cfg)
      ++ (lib.mapAttrsToList (name: m:
        lib.optionalAttrs (hasShares m) (sharesOf name m).host.system.activationScripts) cfg)
    );
  };
}
