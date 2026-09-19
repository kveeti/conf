{ lib, pkgs, ... }:

let
  finishRouterSecurity = pkgs.writeShellApplication {
    name = "finish-router-security";
    runtimeInputs = [ pkgs.cryptsetup pkgs.jq pkgs.sbctl pkgs.systemd ];
    text = ''
      if [[ "$EUID" -ne 0 ]]; then
        echo "Run this command with sudo: sudo finish-router-security" >&2
        exit 1
      fi

      luks_device=/dev/disk/by-partlabel/disk-main-root
      if [[ ! -d /sys/firmware/efi ]]; then
        echo "This system did not boot with UEFI." >&2
        exit 1
      fi
      if ! cryptsetup isLuks "$luks_device"; then
        echo "LUKS root device not found at $luks_device." >&2
        exit 1
      fi
      if ! systemd-cryptenroll --tpm2-device=list >/dev/null; then
        echo "No usable TPM2 device found." >&2
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

      if [[ "$secure_boot" != "true" ]]; then
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
      It also trusts only the Option ROM checksums measured during this boot.
      EOF
        read -r -p "Type ENROLL to continue: " confirmation
        if [[ "$confirmation" != "ENROLL" ]]; then
          echo "Cancelled."
          exit 1
        fi

        sbctl enroll-keys --tpm-eventlog
        echo "Keys enrolled. Rebooting to enable Secure Boot."
        echo "Enter the LUKS passphrase, then run this command again."
        systemctl reboot
        exit 0
      fi

      echo "Secure Boot is enabled."
      if systemd-cryptenroll "$luks_device" | grep -q tpm2; then
        echo "A TPM unlock slot already exists. Nothing left to do."
        exit 0
      fi

      cat <<'EOF'
      The next step asks for the LUKS recovery passphrase and adds automatic
      TPM unlock bound to the firmware and Secure Boot state.
      EOF
      systemd-cryptenroll \
        --tpm2-device=auto \
        --tpm2-pcrs=0+7 \
        "$luks_device"

      echo
      echo "TPM enrollment complete. Keep the recovery passphrase safe."
      echo "Test with a full poweroff and cold boot before leaving the machine."
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

  environment.systemPackages = [ pkgs.sbctl finishRouterSecurity ];
}
