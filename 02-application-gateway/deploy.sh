#!/usr/bin/env bash
# Video 2: Azure Application Gateway.
# Deploys the lab: a virtual network with an empty gateway subnet, two NSGs, six
# web servers in red, green and blue pools of two, and a client VM. It also makes
# a self-signed certificate for the HTTPS listener part. The application gateway
# itself is created in the portal, in the video.
#
#   ./deploy.sh [-l LOCATION] [-g RESOURCE_GROUP] [-s VM_SIZE] [--allow-ip IP]
#               [--no-zones] [--hide-client] [--skip-check]
#
#   -l  region (default southeastasia)         -g  resource group (default rg-appgw-demo)
#   -s  VM size (default: Standard_B1s, then the next sizes that exist in the region)
#   --allow-ip   the address allowed to SSH in (default: your public IP, detected)
#   --no-zones   for a region without availability zones
#   --hide-client  hide your own public IP on the demo pages (for recordings)
#   --skip-check   do not test the web servers at the end
set -eo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../shared/scripts/common.sh"

LOCATION=southeastasia; LB_RG=rg-appgw-demo; ALLOW_IP=""; ZONES=true; HIDE=false; CHECK=true
while [ $# -gt 0 ]; do
  case "$1" in
    -l|--location) LOCATION="$2"; shift 2;;
    -g|--resource-group) LB_RG="$2"; shift 2;;
    -s|--size) export LB_VM_SIZES="$2"; shift 2;;
    --allow-ip) ALLOW_IP="$2"; shift 2;;
    --no-zones) ZONES=false; shift;;
    --hide-client) HIDE=true; shift;;
    --skip-check) CHECK=false; shift;;
    -h|--help) sed -n '2,16p' "$0"; exit 0;;
    *) die "Unknown option: $1 (try --help)";;
  esac
done

require_az
[ -n "$ALLOW_IP" ] || ALLOW_IP="$(my_public_ip)"
[ -n "$ALLOW_IP" ] || die "Could not detect your public IP. Pass it with --allow-ip."
note "SSH will be allowed only from $ALLOW_IP"
ensure_ssh_key
make_demo_cert appgw-demo

deploy "$LB_RG" "$LOCATION" "$HERE/main.bicep" \
  "location=$LOCATION" "sshPublicKey=$LB_PUBKEY" "allowedSourceIp=$ALLOW_IP" "useZones=$ZONES" "hideClient=$HIDE" "adminUsername=$LB_USER"

CLIENT_IP="$(output clientPublicIp)"
WEB_IPS="$(az deployment group show -g "$LB_RG" -n "$LB_DEPLOYMENT" --query 'properties.outputs.webServers.value[].privateIp' -o tsv | tr '\n' ' ')"
if [ "$CHECK" = true ]; then check_web "$LB_RG" "$(output clientName)" $WEB_IPS || true; fi

say "Ready."
az deployment group show -g "$LB_RG" -n "$LB_DEPLOYMENT" --query 'properties.outputs.webServers.value[].[group,name,privateIp,zone]' -o tsv |
  while read -r g n ip z; do note "$g pool  $n  $ip  zone ${z:-none}"; done
note "client-vm  $CLIENT_IP"
note "SSH: ssh -i \"$LB_KEY\" $LB_USER@$CLIENT_IP"
note "VM size used: $LB_SIZE"
note "Next: create the application gateway in the portal, as in the video. Remove everything with ./cleanup.sh -g $LB_RG"
