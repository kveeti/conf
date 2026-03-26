#!/usr/bin/env bash

# Check if backup directory is provided
if [ -z "$1" ]; then
	echo "Usage: $0 <backup_directory>"
	echo "Example: $0 ./backups/20250124_120000"
	exit 1
fi

BACKUP_DIR="$1"

if [ ! -d "$BACKUP_DIR" ]; then
	echo "Error: Backup directory '$BACKUP_DIR' does not exist"
	exit 1
fi

# Enable nullglob so the loop doesn't fail if no .tar.gz files exist
shopt -s nullglob
backup_files=("$BACKUP_DIR"/*.tar.gz)
shopt -u nullglob

if [ ${#backup_files[@]} -eq 0 ]; then
	echo "Error: No .tar.gz backup files found in '$BACKUP_DIR'"
	exit 1
fi

for BACKUP_FILE in "${backup_files[@]}"; do
	# Extract the volume name from the filename (e.g., /path/to/my_vol.tar.gz -> my_vol)
	vol=$(basename "$BACKUP_FILE" .tar.gz)

	echo "Restoring $vol..."
	
	# Explicitly create the volume in case it doesn't exist on the new host yet
	docker volume create "$vol" > /dev/null

	docker run --rm \
		-v "$vol":/target \
		-v "$(cd "$BACKUP_DIR" && pwd)":/backup:ro \
		alpine sh -c "rm -rf /target/* /target/..?* /target/.[!.]* 2>/dev/null; tar -xzf /backup/${vol}.tar.gz -C /target"
done

echo "Restore complete from $BACKUP_DIR"
