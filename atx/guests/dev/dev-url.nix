{ writeShellScriptBin, coreutils, systemd, gawk }:

writeShellScriptBin "dev-url" ''
  set -euo pipefail

  state=/home/veeti/.config/dev-url/routes.map
  domain=dev-internal.veetik.com

  usage() {
    echo "usage: dev-url <name> <port> | dev-url rm <name> | dev-url ls" >&2
    exit 2
  }

  valid_name() {
    [[ "$1" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] && (( ''${#1} <= 63 ))
  }

  reload() {
    sudo ${coreutils}/bin/install -m 0644 "$state" /run/dev-url/routes.map
    sudo ${systemd}/bin/systemctl reload nginx
  }

  if [[ $# == 1 && "$1" == ls ]]; then
    ${gawk}/bin/awk -v suffix=".$domain" '
      {
        name = $1; sub(suffix "$", "", name)
        port = $2; sub(/;$/, "", port)
        printf "%-24s %s\n", name, port
      }
    ' "$state"
  elif [[ $# == 2 && "$1" == rm ]]; then
    valid_name "$2" || usage
    host="$2.$domain"
    tmp=$(${coreutils}/bin/mktemp "$state.tmp.XXXXXX")
    trap '${coreutils}/bin/rm -f "$tmp"' EXIT
    ${gawk}/bin/awk -v host="$host" '$1 != host { print }' "$state" > "$tmp"
    ${coreutils}/bin/mv "$tmp" "$state"
    trap - EXIT
    reload
  elif [[ $# == 2 ]]; then
    valid_name "$1" || usage
    [[ "$2" =~ ^[0-9]+$ ]] && ((10#$2 >= 1 && 10#$2 <= 65535)) || usage
    host="$1.$domain"
    tmp=$(${coreutils}/bin/mktemp "$state.tmp.XXXXXX")
    trap '${coreutils}/bin/rm -f "$tmp"' EXIT
    ${gawk}/bin/awk -v host="$host" '$1 != host { print }' "$state" > "$tmp"
    printf '%s %s;\n' "$host" "$2" >> "$tmp"
    ${coreutils}/bin/sort -o "$tmp" "$tmp"
    ${coreutils}/bin/mv "$tmp" "$state"
    trap - EXIT
    reload
    echo "https://$host"
  else
    usage
  fi
''
