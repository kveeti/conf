{ lib, pkgs, ... }:

let
  finishPublicSecureBoot = pkgs.writeShellApplication {
    name = "finish-public-secure-boot";
    runtimeInputs = [ pkgs.jq pkgs.sbctl pkgs.systemd ];
    text = ''
      if [[ "$EUID" -ne 0 ]]; then
        echo "Run this command with sudo: sudo finish-public-secure-boot" >&2
        exit 1
      fi

      if [[ ! -d /sys/firmware/efi ]]; then
        echo "This system did not boot with UEFI." >&2
        exit 1
      fi

      if [[ ! -f /var/lib/sbctl/keys/db/db.key ]]; then
        echo "Generating this machine's Secure Boot keys..."
        sbctl create-keys
      fi

      echo "Signing the current boot files..."
      /run/current-system/bin/switch-to-configuration boot

      status=$(sbctl status --json)
      setup_mode=$(jq -r .setup_mode <<<"$status")
      secure_boot=$(jq -r .secure_boot <<<"$status")

      if [[ "$secure_boot" == "true" ]]; then
        echo "Secure Boot is enabled. Nothing left to do."
        exit 0
      fi

      if [[ "$setup_mode" != "true" ]]; then
        cat <<'EOF'
      Firmware is not in Setup Mode.

      Reboot into firmware setup, set an administrator password, enable Secure
      Boot, and choose "Reset Platform to Setup Mode". Do not restore factory
      keys or clear all Secure Boot keys. Boot NixOS and run this command again.
      EOF
        exit 1
      fi

      cat <<'EOF'
      The next step replaces the firmware trust keys with this machine's key.
      It enrolls only this machine's Secure Boot key.
      EOF
      read -r -p "Type ENROLL to continue: " confirmation
      if [[ "$confirmation" != "ENROLL" ]]; then
        echo "Cancelled."
        exit 1
      fi

      sbctl enroll-keys
      echo "Keys enrolled. Rebooting to enable Secure Boot."
      systemctl reboot
    '';
  };
in {
  boot.loader = {
    systemd-boot.enable = lib.mkForce false;
    efi.canTouchEfiVariables = true;
  };

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    configurationLimit = 2;
    autoGenerateKeys.enable = true;
  };

  environment.systemPackages = [ pkgs.sbctl finishPublicSecureBoot ];
}
