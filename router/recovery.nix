{ lib, modulesPath, pkgs, routerSystem, diskoPackage, keys, ... }:

let
  installRouter = pkgs.writeShellApplication {
    name = "install-router";
    runtimeInputs = [
      diskoPackage
      pkgs.coreutils
      pkgs.ethtool
      pkgs.iproute2
      pkgs.nixos-install-tools
      pkgs.openssh
      pkgs.util-linux
    ];
    text = ''
      export NIX_CONFIG='substituters ='
      key="''${1:-/root/router-ssh-host-key}"

      if [[ ! -f "$key" ]]; then
        echo "Router SSH host key not found at: $key" >&2
        echo "Copy the old router's /etc/ssh/ssh_host_ed25519_key here first." >&2
        echo "You can also pass its path: install-router /path/to/key" >&2
        exit 1
      fi

      if ! ssh-keygen -y -f "$key" >/dev/null; then
        echo "Not a valid SSH private key: $key" >&2
        exit 1
      fi

      choose_interface() {
        local role="$1"
        local excluded="''${2:-}"
        local interface
        local answer
        local -a interfaces=()

        for path in /sys/class/net/*; do
          interface="''${path##*/}"
          if [[ "$interface" != "lo" ]] && [[ -e "$path/device" ]]; then
            interfaces+=("$interface")
          fi
        done

        if [[ "''${#interfaces[@]}" -eq 0 ]]; then
          echo "No physical network ports found." >&2
          exit 1
        fi

        while true; do
          echo >&2
          echo "Physical network ports:" >&2
          for interface in "''${interfaces[@]}"; do
            ip -brief link show dev "$interface" >&2
          done
          echo >&2
          read -r -p "$role port: " interface

          if [[ ! -e "/sys/class/net/$interface/device" ]]; then
            echo "Not a physical network port: $interface" >&2
            continue
          fi
          if [[ "$interface" == "$excluded" ]]; then
            echo "$interface is already selected." >&2
            continue
          fi

          echo "Blinking $interface for 10 seconds..." >&2
          if ! ethtool --identify "$interface" 10; then
            echo "This port or driver does not support blinking." >&2
          fi

          read -r -p "Use $interface as $role? [y/N] " answer
          if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
            selected_interface="$interface"
            return
          fi
        done
      }

      choose_interface WAN
      wan_interface="$selected_interface"
      choose_interface LAN "$wan_interface"
      lan_interface="$selected_interface"
      wan_mac=$(<"/sys/class/net/$wan_interface/address")
      lan_mac=$(<"/sys/class/net/$lan_interface/address")

      echo
      echo "WAN: $wan_interface ($wan_mac)"
      echo "LAN: $lan_interface ($lan_mac)"
      echo

      echo "Available disks:"
      lsblk -dpo NAME,SIZE,MODEL,SERIAL,TRAN,TYPE
      echo
      read -r -p "Disk to erase and install to: " disk
      disk=$(readlink -f "$disk")

      if [[ ! -b "$disk" ]] || [[ "$(lsblk -dnro TYPE "$disk")" != "disk" ]]; then
        echo "Not a whole disk: $disk" >&2
        exit 1
      fi

      if [[ "$(lsblk -dnro RO "$disk")" != "0" ]]; then
        echo "Disk is read-only: $disk" >&2
        exit 1
      fi

      echo
      lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS "$disk"
      echo
      echo "This will erase all data on $disk."
      read -r -p "Type 'ERASE $disk' to continue: " confirmation
      if [[ "$confirmation" != "ERASE $disk" ]]; then
        echo "Cancelled."
        exit 1
      fi

      disko \
        --mode destroy,format,mount \
        --yes-wipe-all-disks \
        --argstr device "$disk" \
        /etc/router-recovery/disk.nix

      install -Dm600 "$key" /mnt/etc/ssh/ssh_host_ed25519_key
      cat > /mnt/etc/router-interfaces <<EOF
      wan $wan_mac
      lan $lan_mac
      EOF
      chmod 644 /mnt/etc/router-interfaces

      install -d -m755 /mnt/etc/systemd/network
      cat > /mnt/etc/systemd/network/05-router-wan.link <<EOF
      [Match]
      MACAddress=$wan_mac

      [Link]
      Name=wan0
      EOF
      cat > /mnt/etc/systemd/network/05-router-lan.link <<EOF
      [Match]
      MACAddress=$lan_mac

      [Link]
      Name=lan0
      EOF

      nixos-install \
        --root /mnt \
        --system ${routerSystem} \
        --no-root-password

      sync
      echo
      echo "Install complete. Remove the ISO and reboot."
    '';
  };
in
{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  networking = {
    hostName = "router-recovery";
    useDHCP = true;
    useNetworkd = true;
    networkmanager.enable = lib.mkForce false;

    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
  };

  systemd.network = {
    enable = true;
    networks."10-recovery" = {
      matchConfig.Name = "enp1s0f1";
      address = [ "192.168.250.2/24" ];
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };
    };
  };

  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      AllowUsers = [ "root" ];
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = keys;

  boot.zfs.forceImportRoot = false;

  environment.systemPackages = [ installRouter ];
  environment.etc = {
    # Keep the complete target closure on the ISO for offline installation.
    "router-recovery/target-system".source = routerSystem;
    "router-recovery/disk.nix".source = ./disk.nix;
    "issue".text = ''
      Router recovery ISO

      Run install-router to install the router.
    '';
  };

  image.baseName = lib.mkForce "router-recovery";
}
