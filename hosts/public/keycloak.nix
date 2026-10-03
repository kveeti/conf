{ config, ... }:

{
  age.secrets = {
    restic-auth-rest-pass = {};
    restic-auth-encryption-pass = {};
  };

  homelab.postgresql.databases.keycloak = {
    services = [];
    backup = {
      repository = "auth";
      restPasswordFile = config.age.secrets.restic-auth-rest-pass.path;
      encryptionPasswordFile = config.age.secrets.restic-auth-encryption-pass.path;
    };
  };
}
