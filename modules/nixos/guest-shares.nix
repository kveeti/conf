lib:

{ vmName, stateRoot, shares }:

let
  inherit (lib) mapAttrsToList concatMap concatStringsSep optionalAttrs;

  pick = a: b: if a != null then a else b;

  resolve = name: s: {
    inherit name;
    inherit (s) create;
    owner    = pick s.owner name;
    group    = pick s.group (pick s.owner name);
    mode     = pick s.mode "0750";
    path     = pick s.path "/var/lib/${name}";
    hostPath = pick s.hostPath "${stateRoot}/${name}";
    dirs     = s.dirs;
  };

  resolved = mapAttrsToList resolve shares;
  toCreate = builtins.filter (r: r.create) resolved;

  install = r:
    [ "install -d -m ${r.mode} -o ${r.owner} -g ${r.group} ${r.hostPath}" ]
    ++ mapAttrsToList (rel: d:
         "install -d -m ${pick d.mode r.mode} -o ${pick d.owner r.owner} -g ${pick d.group r.group} ${r.hostPath}/${rel}"
       ) r.dirs;
in {
  host.system.activationScripts = optionalAttrs (toCreate != []) {
    "${vmName}-shares".text = concatStringsSep "\n" (concatMap install toCreate);
  };

  guest = { ... }: {
    microvm.shares = map (r: {
      source = r.hostPath;
      mountPoint = r.path;
      tag = r.name;
      proto = "virtiofs";
    }) resolved;
  };
}
