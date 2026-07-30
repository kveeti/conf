{ lib, pkgs, ... }:

let
  root = "/var/lib/media-certificate";
  caDir = "${root}/ca";
  mediaDir = "${root}/media";
  profileDir = "${root}/profile";
  publicDir = "/run/media-certificate-profile";
  domain = "media.lan";
  caCert = "${caDir}/root-ca.crt";
  caKey = "${caDir}/root-ca.key";
  cert = "${mediaDir}/${domain}.crt";
  key = "${mediaDir}/${domain}.key";
  profile = "${profileDir}/${domain}.mobileconfig";
  publicProfile = "${publicDir}/${domain}.mobileconfig";
  sans = "DNS:${domain},DNS:*.${domain}";

  uuidFor = seed:
    let hash = builtins.hashString "sha256" seed;
    in lib.toUpper "${builtins.substring 0 8 hash}-${builtins.substring 8 4 hash}-4${builtins.substring 13 3 hash}-8${builtins.substring 17 3 hash}-${builtins.substring 20 12 hash}";

  openssl = lib.getExe pkgs.openssl;
  profileCommand = pkgs.writeShellScriptBin "media-cert-profile" ''
    set -eu

    command="''${1:-status}"
    case "$command" in
      on)
        if [ "$(${pkgs.coreutils}/bin/id -u)" -ne 0 ]; then
          echo "media-cert-profile on must run as root" >&2
          exit 1
        fi
        ${pkgs.coreutils}/bin/install -m 0644 ${profile} ${publicProfile}
        echo "Profile available at https://media-cert.veetik.com"
        ;;
      off)
        if [ "$(${pkgs.coreutils}/bin/id -u)" -ne 0 ]; then
          echo "media-cert-profile off must run as root" >&2
          exit 1
        fi
        ${pkgs.coreutils}/bin/rm -f ${publicProfile}
        echo "Profile disabled"
        ;;
      status)
        if [ -f ${publicProfile} ]; then
          echo "on"
        else
          echo "off"
        fi
        ;;
      *)
        echo "usage: media-cert-profile {on|off|status}" >&2
        exit 2
        ;;
    esac
  '';
in {
  environment.systemPackages = [ profileCommand ];

  system.activationScripts.media-certificate.text = ''
    set -eu
    umask 077

    install -d -m 0700 -o root -g root ${caDir}
    install -d -m 0750 -o root -g cert-readers ${mediaDir}
    install -d -m 0700 -o root -g root ${profileDir}
    install -d -m 0755 -o root -g root ${publicDir}

    ca_valid=false
    if [ -s ${caCert} ] && [ -s ${caKey} ] \
       && [ "$(${openssl} x509 -in ${caCert} -noout -modulus)" = "$(${openssl} rsa -in ${caKey} -noout -modulus 2>/dev/null)" ] \
       && ${openssl} verify -CAfile ${caCert} ${caCert} >/dev/null 2>&1; then
      ca_valid=true
    fi

    if [ "$ca_valid" != true ]; then
      ${openssl} req -x509 -newkey rsa:4096 -nodes -days 7300 -sha256 \
        -keyout ${caKey}.new -out ${caCert}.new \
        -subj '/CN=media.lan Root CA' \
        -addext 'basicConstraints=critical,CA:TRUE,pathlen:0' \
        -addext 'keyUsage=critical,keyCertSign,cRLSign' \
        -addext 'subjectKeyIdentifier=hash'
      mv ${caKey}.new ${caKey}
      mv ${caCert}.new ${caCert}
    fi

    chmod 0600 ${caKey}
    chmod 0644 ${caCert}

    want='${sans}'
    leaf_valid=false
    if [ -s ${cert} ] && [ -s ${key} ] \
       && [ "$(cat ${mediaDir}/.sans 2>/dev/null || true)" = "$want" ] \
       && [ "$(${openssl} x509 -in ${cert} -noout -modulus)" = "$(${openssl} rsa -in ${key} -noout -modulus 2>/dev/null)" ] \
       && ${openssl} verify -CAfile ${caCert} ${cert} >/dev/null 2>&1 \
       && ${openssl} x509 -checkend 2592000 -noout -in ${cert} >/dev/null 2>&1; then
      leaf_valid=true
    fi

    if [ "$leaf_valid" != true ]; then
      ${openssl} req -new -newkey rsa:4096 -nodes -sha256 \
        -keyout ${key}.new -out ${mediaDir}/${domain}.csr.new \
        -subj '/CN=${domain}'
      cat > ${mediaDir}/${domain}.ext.new <<EOF
    basicConstraints=critical,CA:FALSE
    keyUsage=critical,digitalSignature,keyEncipherment
    extendedKeyUsage=serverAuth
    subjectAltName=${sans}
    subjectKeyIdentifier=hash
    authorityKeyIdentifier=keyid,issuer
    EOF
      ${openssl} x509 -req -sha256 -days 825 \
        -in ${mediaDir}/${domain}.csr.new \
        -CA ${caCert} -CAkey ${caKey} \
        -set_serial "0x$(${openssl} rand -hex 16)" \
        -extfile ${mediaDir}/${domain}.ext.new \
        -out ${cert}.new
      mv ${key}.new ${key}
      mv ${cert}.new ${cert}
      printf '%s' "$want" > ${mediaDir}/.sans
      rm -f ${mediaDir}/${domain}.csr.new ${mediaDir}/${domain}.ext.new
    fi

    chown root:cert-readers ${key}
    chmod 0640 ${key}
    chmod 0644 ${cert}

    cat > ${profile}.new <<EOF
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>PayloadContent</key>
      <array>
        <dict>
          <key>PayloadCertificateFileName</key>
          <string>media.lan-root-ca.crt</string>
          <key>PayloadContent</key>
          <data>$(${openssl} x509 -in ${caCert} -outform DER | ${openssl} base64 -A)</data>
          <key>PayloadDescription</key>
          <string>Trust certificates issued by the media.lan root CA.</string>
          <key>PayloadDisplayName</key>
          <string>Media Root CA</string>
          <key>PayloadIdentifier</key>
          <string>lan.media.root-ca</string>
          <key>PayloadType</key>
          <string>com.apple.security.root</string>
          <key>PayloadUUID</key>
          <string>${uuidFor "media-root-ca"}</string>
          <key>PayloadVersion</key>
          <integer>1</integer>
        </dict>
      </array>
      <key>PayloadDescription</key>
      <string>Trust certificates for media.lan and its direct subdomains.</string>
      <key>PayloadDisplayName</key>
      <string>Media Root CA</string>
      <key>PayloadIdentifier</key>
      <string>lan.media.root-ca-profile</string>
      <key>PayloadOrganization</key>
      <string>${domain}</string>
      <key>PayloadType</key>
      <string>Configuration</string>
      <key>PayloadUUID</key>
      <string>${uuidFor "media-root-ca-profile"}</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
    </plist>
    EOF
    chmod 0644 ${profile}.new
    mv ${profile}.new ${profile}

    rm -f ${publicProfile}
  '';
}
