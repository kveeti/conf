set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "Usage: restore-$restoreName [snapshot-id]" >&2
  exit 1
fi

if [ "$EUID" -ne 0 ]; then
  echo 'Run this command with sudo.' >&2
  exit 1
fi

exec 8>"$restoreLock"
flock -n 8

export RESTIC_REPOSITORY="$restoreRepository"
export RESTIC_REST_USERNAME="$restoreUsername"
RESTIC_REST_PASSWORD=$(< "$restorePasswordFile")
export RESTIC_REST_PASSWORD
export RESTIC_PASSWORD_FILE="$restorePasswordFile"

preRestore
restic --no-cache restore "${1:-latest}" --target / \
  --path "$restorePath" --include "$restorePath" \
  "${restoreTagArgs[@]}" --verify
postRestore
