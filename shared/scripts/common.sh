#!/usr/bin/env bash
# Helpers shared by the deploy and cleanup scripts of every video. Source this
# file from a script; do not run it. Written for bash 3.2 (the macOS default).

LB_SHARED="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LB_REPO="$(cd "$LB_SHARED/../.." && pwd)"
LB_KEY="${LB_KEY:-$LB_REPO/.keys/lbdemo_ed25519}"
LB_USER="${LB_USER:-azureuser}"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mxx  %s\033[0m\n' "$*" >&2; exit 1; }

require_az() {
  command -v az >/dev/null 2>&1 || die "Azure CLI not found. Install it from https://aka.ms/installazurecli"
  az account show >/dev/null 2>&1 || die "You are not signed in. Run: az login"
  say "Subscription: $(az account show --query name -o tsv)"
}

# The public IPv4 address Azure will see you connect from (the only address allowed to SSH in).
my_public_ip() {
  curl -fsS -4 --max-time 8 https://api.ipify.org 2>/dev/null || curl -fsS -4 --max-time 8 https://ifconfig.me 2>/dev/null || true
}

# Uses the key pair in .keys/ (created on first use). No passwords anywhere.
ensure_ssh_key() {
  if [ ! -f "$LB_KEY" ]; then
    command -v ssh-keygen >/dev/null 2>&1 || die "ssh-keygen not found, install an OpenSSH client"
    mkdir -p "$(dirname "$LB_KEY")"
    ssh-keygen -q -t ed25519 -N "" -C "lbdemo" -f "$LB_KEY"
    note "Created a new SSH key pair: $LB_KEY"
  fi
  LB_PUBKEY="$(cat "$LB_KEY.pub")"
}

# deploy RESOURCE_GROUP LOCATION TEMPLATE [NAME=VALUE ...]
# Creates the group if needed and deploys the Bicep template. B1s is the cheapest
# size but is sometimes unavailable in a region or zone, so the next size in
# $LB_VM_SIZES is tried when Azure says so.
deploy() {
  local rg="$1" loc="$2" template="$3"; shift 3
  local name sizes size err
  name="$(basename "$(dirname "$template")")"
  az group create -n "$rg" -l "$loc" --tags purpose=lb-series-demo -o none
  sizes="${LB_VM_SIZES:-Standard_B1s Standard_B2ats_v2 Standard_B1ms Standard_B2s}"
  err="$(mktemp)"
  for size in $sizes; do
    say "Deploying to $rg ($loc) with VM size $size. This takes a few minutes."
    if az deployment group create -g "$rg" -n "$name" -f "$template" -p "$@" "vmSize=$size" -o none 2>"$err"; then
      rm -f "$err"; LB_DEPLOYMENT="$name"; LB_SIZE="$size"; return 0
    fi
    if grep -Eq "SkuNotAvailable|NotAvailableForSubscription|ZonalAllocationFailed|AllocationFailed|OverconstrainedAllocationRequest|OverconstrainedZonalAllocationRequest" "$err"; then
      warn "$size is not available here right now. Trying the next size."
      continue
    fi
    if grep -q "customData" "$err"; then
      cat "$err" >&2; rm -f "$err"
      die "The website on a running VM cannot be changed in place. Run cleanup, then deploy again."
    fi
    cat "$err" >&2; rm -f "$err"; die "The deployment failed."
  done
  cat "$err" >&2; rm -f "$err"
  die "None of these VM sizes could be created in $loc: $sizes. Try another region."
}

# output NAME  (an output of the last deployment, as plain text)
output() { az deployment group show -g "$LB_RG" -n "$LB_DEPLOYMENT" --query "properties.outputs.$1.value" -o tsv; }

# check_web RESOURCE_GROUP CLIENT_VM IP...
# Calls /healthz on every IP from inside the virtual network and waits until all answer 200.
check_web() {
  local rg="$1" vm="$2"; shift 2
  local script out tries=0
  script="for ip in $*; do printf '%s ' \$ip; curl -s -m 5 -o /dev/null -w '%{http_code}' http://\$ip/healthz; echo; done"
  say "Checking the web servers from inside the network."
  while [ $tries -lt 8 ]; do
    tries=$((tries + 1))
    out="$(az vm run-command invoke -g "$rg" -n "$vm" --command-id RunShellScript --scripts "$script" --query 'value[0].message' -o tsv 2>/dev/null | grep -E '^[0-9.]+ [0-9]{3}$' || true)"
    if [ "$(printf '%s\n' "$out" | grep -c ' 200$')" -eq "$#" ]; then
      printf '%s\n' "$out" | sed 's/^/    /'; return 0
    fi
    note "not all answering yet (try $tries of 8), waiting 15 seconds"; sleep 15
  done
  printf '%s\n' "$out" | sed 's/^/    /'
  warn "Some web servers did not answer. The site starts a few seconds after the VM; try again in a minute."
  return 1
}

# make_demo_cert NAME
# Creates a self-signed certificate for the HTTPS listener part of video 2:
# .keys/NAME.pfx (the password is in .keys/NAME.pfx.password) and .keys/NAME.cer.
# Needs openssl; skipped with a note when it is missing.
make_demo_cert() {
  local name="$1" dir="$LB_REPO/.keys" pw
  command -v openssl >/dev/null 2>&1 || { warn "openssl not found, so no demo certificate was made. It is only needed for the HTTPS listener."; return 0; }
  [ -f "$dir/$name.pfx" ] && return 0
  mkdir -p "$dir"
  pw="$(openssl rand -hex 12)"
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$dir/$name.key" -out "$dir/$name.crt" -days 90 \
    -subj "/CN=lbdemo.example.com" -addext "subjectAltName=DNS:lbdemo.example.com,DNS:*.lbdemo.example.com" 2>/dev/null
  openssl pkcs12 -export -out "$dir/$name.pfx" -inkey "$dir/$name.key" -in "$dir/$name.crt" -passout "pass:$pw" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>/dev/null
  openssl x509 -in "$dir/$name.crt" -outform der -out "$dir/$name.cer"
  printf '%s' "$pw" > "$dir/$name.pfx.password"
  note "Demo certificate: $dir/$name.pfx (password in $name.pfx.password)"
}

# check_public URL...
# Calls every URL from this computer and waits until all answer 200.
check_public() {
  local tries=0 url code ok
  say "Checking the web servers from here."
  while [ $tries -lt 10 ]; do
    tries=$((tries + 1)); ok=1
    for url in "$@"; do
      code="$(curl -s -m 6 -o /dev/null -w '%{http_code}' "$url" || true)"
      [ "$code" = "200" ] || ok=0
      note "$code  $url"
    done
    [ $ok -eq 1 ] && return 0
    note "not all answering yet (try $tries of 10), waiting 15 seconds"; sleep 15
  done
  warn "Some servers did not answer from here. They start a few seconds after the VM; try again in a minute."
  return 1
}

# delete_group RESOURCE_GROUP [--yes]
delete_group() {
  local rg="$1" yes="$2" answer
  if [ "$(az group exists -n "$rg")" != "true" ]; then note "Nothing to delete: $rg does not exist."; return 0; fi
  if [ "$yes" != "--yes" ]; then
    read -r -p "Delete resource group $rg and everything in it? [y/N] " answer
    case "$answer" in y|Y|yes|YES) ;; *) echo "Cancelled."; return 1;; esac
  fi
  az group delete -n "$rg" --yes --no-wait
  say "Deleting $rg. It keeps running in the background and finishes in a few minutes."
}
