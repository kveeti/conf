{ config, lib, pkgs, inventory, ... }:

let
  directory = "/var/lib/mail";
  domain = "mail.internal.veetik.com";
  ports = config.homelab.ports;
  certificate = config.security.acme.certs."internal.veetik.com";
  fetchmailService = folder: {
    description = "Collect mailbox.org ${folder} mail";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    requires = [ "dovecot.service" ];
    after = [ "network-online.target" "dovecot.service" ];
    restartTriggers = [ config.age.secrets.mail-fetchmail.file ];
    environment.HOME = directory;
    serviceConfig = {
      User = "vmail";
      Group = "vmail";
      StateDirectory = "fetchmail/${folder}";
      StateDirectoryMode = "0700";
      ExecStart = "${pkgs.fetchmail}/bin/fetchmail --daemon 60 --nodetach --nosyslog ${lib.optionalString (folder == "inbox") "--idle "}--fetchmailrc ${config.age.secrets.mail-fetchmail.path} --pidfile /var/lib/fetchmail/${folder}/fetchmail.pid --idfile /var/lib/fetchmail/${folder}/ids ${folder}";
      Restart = "on-failure";
      RestartSec = "30s";
      SuccessExitStatus = [ 1 ];
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ directory ];
    };
    unitConfig.RequiresMountsFor = [ directory ];
  };
in {
  imports = [ ../../modules/services/restic-backups.nix ];

  age.secrets = {
    mail-users.owner = "dovecot2";
    mail-relay-passwd.owner = "postfix";
    mail-fetchmail.owner = "vmail";
  };

  users.groups.vmail.gid = 704;
  users.users.vmail = {
    uid = 704;
    isSystemUser = true;
    group = "vmail";
    home = directory;
  };
  users.users.postfix.extraGroups = [ certificate.group ];

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "mail-deliver" ''
      exec ${pkgs.dovecot}/libexec/dovecot/dovecot-lda -e "$@"
    '')
  ];

  systemd.tmpfiles.rules = [
    "d ${directory} 0700 vmail vmail -"
    "d ${directory}/Maildir 0700 vmail vmail -"
    "d ${directory}/Maildir/cur 0700 vmail vmail -"
    "d ${directory}/Maildir/new 0700 vmail vmail -"
    "d ${directory}/Maildir/tmp 0700 vmail vmail -"
    "d ${directory}/Maildir/.Sent 0700 vmail vmail -"
    "d ${directory}/Maildir/.Sent/cur 0700 vmail vmail -"
    "d ${directory}/Maildir/.Sent/new 0700 vmail vmail -"
    "d ${directory}/Maildir/.Sent/tmp 0700 vmail vmail -"
  ];

  services.dovecot2 = {
    enable = true;
    package = pkgs.dovecot;
    createMailUser = false;
    settings = {
      dovecot_config_version = "2.4.0";
      dovecot_storage_version = "2.4.0";
      hostname = domain;
      protocols.imap = true;
      listen = inventory.hosts.worker.ipv4;
      ssl = "required";
      ssl_server_cert_file = "${certificate.directory}/fullchain.pem";
      ssl_server_key_file = "${certificate.directory}/key.pem";
      auth_allow_cleartext = false;
      mail_uid = "vmail";
      mail_gid = "vmail";
      mail_home = directory;
      mail_driver = "maildir";
      mail_path = "${directory}/Maildir";
      "passdb passwd-file".passwd_file_path = config.age.secrets.mail-users.path;
      "userdb static".fields = {
        uid = "vmail";
        gid = "vmail";
        home = directory;
      };
      "namespace inbox" = {
        inbox = true;
        separator = "/";
        "mailbox Drafts" = {
          auto = "subscribe";
          special_use = "\\Drafts";
        };
        "mailbox Sent" = {
          auto = "subscribe";
          special_use = "\\Sent";
        };
        "mailbox Trash" = {
          auto = "subscribe";
          special_use = "\\Trash";
        };
        "mailbox Junk" = {
          auto = "subscribe";
          special_use = "\\Junk";
        };
        "mailbox Archive" = {
          auto = "subscribe";
          special_use = "\\Archive";
        };
      };
      "service imap-login" = {
        "inet_listener imap".port = 0;
        "inet_listener imaps" = {
          port = ports.imaps;
          ssl = true;
        };
      };
      "service auth"."unix_listener /var/lib/postfix/queue/private/auth" = {
        mode = "0660";
        user = "postfix";
        group = "postfix";
      };
      "protocol lda" = {
        lda_mailbox_autocreate = true;
        lda_mailbox_autosubscribe = true;
      };
    };
  };

  systemd.services.dovecot = {
    requires = [ "postfix-setup.service" ];
    wants = [ "acme-finished-internal.veetik.com.target" ];
    after = [ "postfix-setup.service" "acme-finished-internal.veetik.com.target" ];
    restartTriggers = [ config.age.secrets.mail-users.file ];
    unitConfig.RequiresMountsFor = [ directory ];
  };

  services.postfix = {
    enable = true;
    enableSmtp = false;
    enableSubmissions = true;
    settings = {
      main = {
        myhostname = domain;
        inet_interfaces = [ inventory.hosts.worker.ipv4 ];
        inet_protocols = "ipv4";
        mydestination = [ ];
        relayhost = [ "[smtp.mailbox.org]:465" ];
        smtp_tls_wrappermode = true;
        smtp_tls_security_level = "secure";
        smtp_sasl_auth_enable = true;
        smtp_sasl_password_maps = [ "texthash:${config.age.secrets.mail-relay-passwd.path}" ];
        smtp_sasl_security_options = "noanonymous";
        smtpd_tls_chain_files = [ "${certificate.directory}/key.pem" "${certificate.directory}/fullchain.pem" ];
        smtpd_sasl_type = "dovecot";
        smtpd_sasl_path = "private/auth";
        smtpd_relay_restrictions = [ "permit_sasl_authenticated" "reject" ];
        message_size_limit = 104857600;
        always_bcc = "sent@archive.invalid";
        virtual_mailbox_domains = [ "archive.invalid" ];
        virtual_mailbox_base = "${directory}/Maildir";
        virtual_mailbox_maps = [ "static:.Sent/" ];
        virtual_uid_maps = [ "static:704" ];
        virtual_gid_maps = [ "static:704" ];
        virtual_mailbox_limit = 0;
      };
      master.smtp = {};
      master.submissions.name = "${inventory.hosts.worker.ipv4}:${toString ports.submissions}";
    };
  };

  systemd.services.postfix = {
    requires = [ "dovecot.service" ];
    after = [ "dovecot.service" ];
    restartTriggers = [ config.age.secrets.mail-relay-passwd.file ];
    unitConfig.RequiresMountsFor = [ directory ];
  };

  systemd.services.postfix-setup = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };

  security.acme.certs."internal.veetik.com".reloadServices = [ "dovecot.service" "postfix.service" ];

  systemd.services.fetchmail-inbox = fetchmailService "inbox";
  systemd.services.fetchmail-sent = fetchmailService "sent";
  systemd.services.fetchmail-junk = fetchmailService "junk";

  homelab.backups = {
    serverUrl = "https://restic.internal.veetik.com:${toString inventory.hosts.backup-vm.ports.restic}";
    instances.mail = {
      passwordFile = config.age.secrets.restic-mail-password.path;
      schedule = "hourly";
      randomDelay = "5m";
      paths = [ directory "/var/lib/postfix/queue" ];
      restoreDirectory = directory;
      serviceConfig = {
        PrivateMounts = true;
        RuntimeDirectory = "restic-mail";
        RuntimeDirectoryMode = "0700";
      };
      extraPackages = [ pkgs.zfs ];
      prepare = ''
        zfs snapshot rpool/var@restic-mail

        mount -t zfs -o ro rpool/var@restic-mail "$RUNTIME_DIRECTORY"
        mount --bind "$RUNTIME_DIRECTORY/lib/mail" ${directory}
        mount --bind "$RUNTIME_DIRECTORY/lib/postfix/queue" /var/lib/postfix/queue
      '';
      cleanup = ''
        for path in /var/lib/postfix/queue ${directory} "$RUNTIME_DIRECTORY"; do
          if mountpoint -q "$path"; then
            umount "$path"
          fi
        done

        zfs destroy rpool/var@restic-mail
      '';
      preRestoreScript = ''
        systemctl stop fetchmail-inbox fetchmail-sent fetchmail-junk postfix dovecot
      '';
      postRestoreScript = ''
        systemctl start dovecot postfix fetchmail-inbox fetchmail-sent fetchmail-junk
      '';
    };
  };

  networking.firewall.extraInputRules = ''
    ip saddr { ${inventory.networks.trusted.cidr4}, ${inventory.networks.servers.cidr4}, ${inventory.networks.wireguard.cidr4} } tcp dport { ${toString ports.imaps}, ${toString ports.submissions} } accept
  '';
}
