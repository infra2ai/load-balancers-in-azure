#!/usr/bin/env bash
# Video 4: removes everything deploy.sh created (the whole resource group rg-tm-demo).
#   ./cleanup.sh [-g RESOURCE_GROUP] [--yes]
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$HERE/../03-front-door/cleanup.sh" -g rg-tm-demo "$@"
