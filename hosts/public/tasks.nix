{ config, ... }:

{
  age.secrets = {
    restic-tasks-rest-pass = {};
    restic-tasks-encryption-pass = {};
  };

  homelab.postgresql.databases.tasks = {
    services = [];
    backup = {
      restPasswordFile = config.age.secrets.restic-tasks-rest-pass.path;
      encryptionPasswordFile = config.age.secrets.restic-tasks-encryption-pass.path;
    };
  };
}
