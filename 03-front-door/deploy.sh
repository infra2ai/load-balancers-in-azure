#!/usr/bin/env bash
# Videos 3 and 4: Azure Front Door and Azure Traffic Manager.
# Deploys the same web server in three regions on three continents (Singapore,
# Sweden, United States). Each has its own virtual network, a public IP with
# a DNS name, and the demo website showing its country and flag. Front Door and
# Traffic Manager are created in the portal, in the videos.
#
#   ./deploy.sh [-g RESOURCE_GROUP] [-l GROUP_LOCATION] [-s VM_SIZE] [--allow-ip IP]
#               [--lock-to-front-door] [--hide-client] [--skip-check]
#
#   -g  resource group (default rg-fd-demo)    -l  where the group's metadata lives (default southeastasia)
#   -s  VM size (default: Standard_B1s, then the next sizes that exist in every region)
#   --allow-ip   the address allowed to SSH in (default: your public IP, detected)
#   --lock-to-front-door  accept web traffic only from the AzureFrontDoor.Backend service tag
#   --hide-client  hide your own public IP on the demo pages (for recordings)
#   --skip-check   do not test the web servers at the end
set -eo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../shared/scripts/common.sh"

LOCATION=southeastasia; LB_RG=rg-fd-demo; ALLOW_IP=""; LOCK=false; HIDE=false; CHECK=true
while [ $# -gt 0 ]; do
  case "$1" in
    -g|--resource-group) LB_RG="$2"; shift 2;;
    -l|--location) LOCATION="$2"; shift 2;;
    -s|--size) export LB_VM_SIZES="$2"; shift 2;;
    --allow-ip) ALLOW_IP="$2"; shift 2;;
    --lock-to-front-door) LOCK=true; shift;;
    --hide-client) HIDE=true; shift;;
    --skip-check) CHECK=false; shift;;
    -h|--help) sed -n '2,15p' "$0"; exit 0;;
    *) die "Unknown option: $1 (try --help)";;
  esac
done

require_az
[ -n "$ALLOW_IP" ] || ALLOW_IP="$(my_public_ip)"
[ -n "$ALLOW_IP" ] || die "Could not detect your public IP. Pass it with --allow-ip."
note "SSH will be allowed only from $ALLOW_IP"
ensure_ssh_key

deploy "$LB_RG" "$LOCATION" "$HERE/main.bicep" \
  "sshPublicKey=$LB_PUBKEY" "allowedSourceIp=$ALLOW_IP" "lockToFrontDoor=$LOCK" "hideClient=$HIDE" "adminUsername=$LB_USER"

URLS="$(az deployment group show -g "$LB_RG" -n "$LB_DEPLOYMENT" --query 'properties.outputs.origins.value[].fqdn' -o tsv | sed 's#^#http://#; s#$#/healthz#')"
if [ "$CHECK" = true ] && [ "$LOCK" = false ]; then check_public $URLS || true; fi

say "Ready."
az deployment group show -g "$LB_RG" -n "$LB_DEPLOYMENT" --query 'properties.outputs.origins.value[].[country,location,publicIp,fqdn]' -o tsv |
  while IFS=$'\t' read -r country loc ip fqdn; do note "$country ($loc)  $ip  $fqdn"; done
note "SSH: ssh -i \"$LB_KEY\" $LB_USER@<public IP>"
[ "$LOCK" = true ] && note "Web traffic is limited to the AzureFrontDoor.Backend service tag, so the sites do not answer directly."
note "VM size used: $LB_SIZE"
note "Next: create Front Door (video 3) or Traffic Manager (video 4) in the portal. Remove everything with ./cleanup.sh -g $LB_RG"
