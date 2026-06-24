{ config, pkgs, withSharedVhost, ... }:

let
  domain = "ldap.internal.veetik.com";

  mkGroup = name: {
    name = "${name}.json";
    path = pkgs.writeText "${name}.json" (builtins.toJSON { inherit name; });
  };
  groupConfigs = pkgs.linkFarm "lldap-group-configs"
    (map mkGroup [
      "admins" "users"
      "grafana-admin" "rss-admin" "food-admin" "weather-admin" "dav-user"
    ]);

  userConfigs = pkgs.linkFarm "lldap-user-configs" [
    {
      name = "authelia.json";
      path = pkgs.writeText "authelia.json" (builtins.toJSON {
        id = "authelia";
        email = "authelia@internal.veetik.com";
        displayName = "Authelia";
        groups = [ "lldap_strict_readonly" ];
        password_file = config.age.secrets.lldap-user-authelia-pass.path;
      });
    }
    {
      name = "veeti.json";
      path = pkgs.writeText "veeti.json" (builtins.toJSON {
        id = "veeti";
        email = "veeti@internal.veetik.com";
        displayName = "Veeti";
        groups = [ "admins" "users" ];
        password_file = config.age.secrets.lldap-user-veeti-pass.path;
      });
    }
  ];

  bootstrapScript = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/lldap/lldap/refs/tags/v0.6.2/scripts/bootstrap.sh";
    hash = "sha256-Z5mQ7PwjYr3pgg+CCemTbYGbrY8CvXK3m7dpqDqSlBg=";
  };

in {
  config.age.secrets.lldap-env = {};
  config.age.secrets.lldap-user-pass.mode = "0400";
  config.age.secrets.lldap-user-pass.owner = "lldap";
  config.age.secrets.lldap-user-authelia-pass.mode = "0400";
  config.age.secrets.lldap-user-authelia-pass.owner = "lldap";
  config.age.secrets.lldap-user-veeti-pass.mode = "0400";
  config.age.secrets.lldap-user-veeti-pass.owner = "lldap";

  config.services.backedupPg.instances.lldap = {};

  config.users.users.lldap = {
    isSystemUser = true;
    group = "lldap";
  };
  config.users.groups.lldap = {};
  config.services.lldap = {
    enable = true;
    environmentFile = config.age.secrets.lldap-env.path;
    settings = {
      database_url = "postgres://lldap@127.0.0.1/lldap?host=/run/postgresql";
      ldap_base_dn = "dc=internal,dc=veetik,dc=com";
      ldap_user_dn = "admin";
      ldap_user_email = "admin@local";
      ldap_user_pass_file = config.age.secrets.lldap-user-pass.path;
      force_ldap_user_pass_reset = "always";
      ldap_port = 20002;
      ldap_host = "127.0.0.1";
      http_port = 20003;
      http_host = "127.0.0.1";
      http_url = "https://${domain}";
    };
  };

  config.systemd.services.lldap-bootstrap = {
    description = "Bootstrap LLDAP";
    wants = [ "lldap.service" ];
    after = [ "lldap.service" ];
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [
      curl
      jq
      jo
      config.services.lldap.package
      bash
    ];

    environment = {
      LLDAP_URL = "http://127.0.0.1:20003";
      LLDAP_ADMIN_USERNAME = config.services.lldap.settings.ldap_user_dn;
      LLDAP_ADMIN_PASSWORD_FILE = config.services.lldap.settings.ldap_user_pass_file;
      GROUP_CONFIGS_DIR = groupConfigs;
      USER_CONFIGS_DIR = userConfigs;
      LLDAP_SET_PASSWORD_PATH = "${config.services.lldap.package}/bin/lldap_set_password";
      LLDAP_DATABASE_URL = config.services.lldap.settings.database_url;
      DO_CLEANUP = "true";
    };

    script = ''
      bash ${bootstrapScript}
    '';

    serviceConfig = {
      Type = "oneshot";
      User = "lldap";
    };
  };

  config.services.nginx.virtualHosts.${domain} = withSharedVhost {
    locations."/".proxyPass = "http://127.0.0.1:20003";
  };
}
