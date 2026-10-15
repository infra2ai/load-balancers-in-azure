#!/usr/bin/env bash
# Videos 3 and 4: removes everything deploy.sh created (the whole resource group).
#   ./cleanup.sh [-g RESOURCE_GROUP] [--yes]
set -eo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../shared/scripts/common.sh"

RG=rg-fd-demo; YES=""
while [ $# -gt 0 ]; do
  case "$1" in
    -g|--resource-group) RG="$2"; shift 2;;
    -y|--yes) YES="--yes"; shift;;
    -h|--help) sed -n '2,3p' "$0"; exit 0;;
    *) die "Unknown option: $1 (try --help)";;
  esac
done
require_az
delete_group "$RG" "$YES"
