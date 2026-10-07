{ lib, pkgs, ... }:

let
  finishPcSecureBoot = pkgs.writeShellApplication {
    name = "finish-pc-secure-boot";
    runtimeInputs = [ pkgs.jq pkgs.sbctl ];
    text = ''
      if [[ "$EUID" -ne 0 ]]; then
        echo "Run this command with sudo: sudo finish-pc-secure-boot" >&2
        exit 1
      fi

      if [[ ! -d /sys/firmware/efi ]]; then
        echo "This system did not boot with UEFI." >&2
        exit 1
      fi

      if [[ ! -f /var/lib/sbctl/keys/db/db.key ]]; then
        sbctl create-keys
      fi

      echo "Signing the boot files..."
      /run/current-system/bin/switch-to-configuration boot

      status=$(sbctl status --json)
      setup_mode=$(jq -r .setup_mode <<<"$status")
      secure_boot=$(jq -r .secure_boot <<<"$status")

      if [[ "$secure_boot" == "true" ]]; then
        echo "Secure Boot is already enabled."
        exit 0
      fi

      if [[ "$setup_mode" != "true" ]]; then
        echo "Firmware must be in Setup Mode before enrolling keys." >&2
        echo "Do not restore factory keys. Keep Secure Boot off until the boot files are signed." >&2
        exit 1
      fi

      echo "Checking boot signatures..."
      sbctl verify

      echo "This enrolls this PC's Secure Boot keys and measured hardware ROM hashes."
      echo "It does not enroll Microsoft keys. Hardware ROM hash enrollment is experimental."
      read -r -p "Type ENROLL to continue: " confirmation
      if [[ "$confirmation" != "ENROLL" ]]; then
        echo "Cancelled."
        exit 1
      fi

      sbctl enroll-keys --tpm-eventlog
      echo "Keys enrolled. Reboot into firmware settings and enable Secure Boot."
      echo "If NixOS cannot boot, disable Secure Boot in firmware settings."
    '';
  };
in
{
  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    autoGenerateKeys.enable = true;
  };

  systemd.services.fwupd-efi = {
    requires = [ "generate-sb-keys.service" ];
    after = [ "generate-sb-keys.service" ];
  };

  environment.systemPackages = [ finishPcSecureBoot ];
}
