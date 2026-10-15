#!/usr/bin/env bash
# Video 4: Azure Traffic Manager.
# Deploys the same three-region lab as video 3 (see ../03-front-door/deploy.sh and
# its options), in its own resource group (default rg-tm-demo).
#
#   ./deploy.sh [options of ../03-front-door/deploy.sh]
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$HERE/../03-front-door/deploy.sh" -g rg-tm-demo "$@"
