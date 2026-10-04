{ config, ... }:

{
  age.secrets = {
    restic-money-rest-pass = {};
    restic-money-encryption-pass = {};
  };

  homelab.postgresql.databases.money = {
    services = [];
    backup = {
      restPasswordFile = config.age.secrets.restic-money-rest-pass.path;
      encryptionPasswordFile = config.age.secrets.restic-money-encryption-pass.path;
    };
  };
}
