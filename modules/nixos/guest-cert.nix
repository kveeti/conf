lib:

{ vmName, stateRoot, certNames ? [ "internal.veetik.com" ] }:
let
  acmeDir = name: "/var/lib/acme/${name}";
  stateCertDir = name: "${stateRoot}/cert/${name}";
  runCertDir = name: "/run/cert/${name}";
  copySvc = name: "copy-cert-${name}-to-${vmName}";

  copyCert = name: ''
    install -m 0644 -o root -g cert-readers \
      ${acmeDir name}/fullchain.pem ${stateCertDir name}/fullchain.pem
    install -m 0640 -o root -g cert-readers \
      ${acmeDir name}/key.pem        ${stateCertDir name}/key.pem
  '';
in {
  host = {
    system.activationScripts."${vmName}-cert".text =
      lib.concatMapStringsSep "\n" (name: ''
        install -d -m 0755 -o root -g cert-readers ${stateCertDir name}
        if [ -f ${acmeDir name}/fullchain.pem ]; then
        ${copyCert name}
        fi
      '') certNames;

    systemd.services = lib.listToAttrs (map (name:
      lib.nameValuePair (copySvc name) {
        description = "Copy renewed ${name} cert into ${vmName} guest state";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          if [ -f ${acmeDir name}/fullchain.pem ]; then
          ${copyCert name}
          fi
        '';
      }) certNames);

    security.acme.certs = lib.genAttrs certNames (name: {
      reloadServices = [ (copySvc name) ];
    });
  };

  guest = { pkgs, ... }: {
    microvm.shares = [{
      source = "${stateRoot}/cert";
      mountPoint = "/run/cert";
      tag = "cert";
      proto = "virtiofs";
      readOnly = true;
    }];

    # gid must match the host's cert-readers so virtiofs group perms let nginx read the keys
    users.groups.cert-readers.gid = 6500;
    users.users.nginx.extraGroups = [ "cert-readers" ];

    # don't start nginx until every cert has landed (path units restart it on appear/renew)
    systemd.services.nginx.unitConfig.ConditionPathExists =
      map (name: "${runCertDir name}/fullchain.pem") certNames;

    systemd.paths = lib.listToAttrs (map (name:
      lib.nameValuePair "nginx-cert-${name}" {
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathChanged = "${runCertDir name}/fullchain.pem";
          Unit = "nginx-cert-reload.service";
        };
      }) certNames);

    systemd.services.nginx-cert-reload = {
      description = "Reload (or start) nginx on TLS cert change";
      serviceConfig.Type = "oneshot";
      script = "${pkgs.systemd}/bin/systemctl reload-or-restart nginx.service";
    };
  };
}
