#!/bin/bash

# Script to clean up Docker containers, volumes, and networks from docker-compose

set -e

echo "Stopping and removing containers, volumes, and networks..."

docker compose down --volumes --remove-orphans

echo "Cleanup completed."