{ lib, pkgs, ... }:

let
  root = "/var/lib/jellyfin-certificate";
  mediaDir = "${root}/media";
  publicDir = "${root}/public";
  domain = "jellyfin.media.lan";

  uuidFor = seed:
    let hash = builtins.hashString "sha256" seed;
    in lib.toUpper "${builtins.substring 0 8 hash}-${builtins.substring 8 4 hash}-4${builtins.substring 13 3 hash}-8${builtins.substring 17 3 hash}-${builtins.substring 20 12 hash}";

  openssl = lib.getExe pkgs.openssl;
in {
  system.activationScripts.jellyfin-certificate.text = ''
    set -eu
    umask 077

    install -d -m 0750 -o root -g cert-readers ${mediaDir}
    install -d -m 0755 -o root -g root ${publicDir}

    want='DNS:${domain}'
    if [ ! -s ${mediaDir}/${domain}.crt ] || [ ! -s ${mediaDir}/${domain}.key ] \
       || [ "$(cat ${mediaDir}/.sans 2>/dev/null || true)" != "$want" ]; then
      ${openssl} req -x509 -newkey rsa:4096 -nodes -days 3650 \
        -keyout ${mediaDir}/${domain}.key.new -out ${mediaDir}/${domain}.crt.new \
        -subj '/CN=${domain}' -addext "subjectAltName=$want"
      mv ${mediaDir}/${domain}.key.new ${mediaDir}/${domain}.key
      mv ${mediaDir}/${domain}.crt.new ${mediaDir}/${domain}.crt
      printf '%s' "$want" > ${mediaDir}/.sans
    fi

    chown root:cert-readers ${mediaDir}/${domain}.key
    chmod 0640 ${mediaDir}/${domain}.key
    chmod 0644 ${mediaDir}/${domain}.crt

    # Public HTTPS provides authenticity in transit, so this profile does not
    # need a separate CMS signature.
    cat > ${publicDir}/${domain}.mobileconfig.new <<EOF
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>PayloadContent</key>
      <array>
        <dict>
          <key>PayloadCertificateFileName</key>
          <string>${domain}.crt</string>
          <key>PayloadContent</key>
          <data>$(${openssl} x509 -in ${mediaDir}/${domain}.crt -outform DER | ${openssl} base64 -A)</data>
          <key>PayloadDescription</key>
          <string>Trust the self-signed ${domain} certificate.</string>
          <key>PayloadDisplayName</key>
          <string>Jellyfin Certificate</string>
          <key>PayloadIdentifier</key>
          <string>lan.media.jellyfin.certificate</string>
          <key>PayloadType</key>
          <string>com.apple.security.root</string>
          <key>PayloadUUID</key>
          <string>${uuidFor "jellyfin-certificate"}</string>
          <key>PayloadVersion</key>
          <integer>1</integer>
        </dict>
      </array>
      <key>PayloadDescription</key>
      <string>Trust the certificate used by ${domain}.</string>
      <key>PayloadDisplayName</key>
      <string>Jellyfin Certificate</string>
      <key>PayloadIdentifier</key>
      <string>lan.media.jellyfin.certificate-profile</string>
      <key>PayloadOrganization</key>
      <string>media.lan</string>
      <key>PayloadType</key>
      <string>Configuration</string>
      <key>PayloadUUID</key>
      <string>${uuidFor "jellyfin-certificate-profile"}</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
    </plist>
    EOF
    chmod 0644 ${publicDir}/${domain}.mobileconfig.new
    mv ${publicDir}/${domain}.mobileconfig.new ${publicDir}/${domain}.mobileconfig
  '';
}
