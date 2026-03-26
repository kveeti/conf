#!/usr/bin/env bash

# Set up the backup directory with a timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="./backups/$TIMESTAMP"

echo "Creating backup directory: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# Get a list of all Docker volumes
echo "Fetching list of all Docker volumes..."
volumes=$(docker volume ls -q)

if [ -z "$volumes" ]; then
	echo "No Docker volumes found."
	exit 0
fi

for vol in $volumes; do
	echo "Backing up volume: $vol..."
	# Run a temporary alpine container to compress the volume contents
	docker run --rm \
		-v "$vol":/source:ro \
		-v "$(cd "$BACKUP_DIR" && pwd)":/backup \
		alpine tar -czf "/backup/${vol}.tar.gz" -C /source .
done

echo "Backup complete! All volumes saved to: $BACKUP_DIR"
