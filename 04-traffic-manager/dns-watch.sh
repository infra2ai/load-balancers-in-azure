#!/usr/bin/env bash
# Shows what a DNS name resolves to, over and over, and which of the demo web
# servers lives at that address. Made for the Traffic Manager video: change an
# endpoint, a weight or a priority in the portal, and watch the answer change
# once the DNS time to live has passed.
#
#   ./dns-watch.sh NAME [-r RESOLVER] [-s CLIENT_SUBNET] [-i SECONDS] [-n COUNT]
#
#   NAME  the name to look up, for example myprofile.trafficmanager.net
#   -r    resolver to ask (default 8.8.8.8, which passes a client subnet on)
#   -s    pretend to be a client in this subnet (EDNS Client Subnet), for example 203.0.113.0/24.
#         Traffic Manager uses it for Performance, Geographic and Subnet routing.
#   -i    seconds between lookups (default 2)
#   -n    stop after this many lookups (default: keep going, press Ctrl+C)
set -eo pipefail

NAME=""; RESOLVER=8.8.8.8; SUBNET=""; EVERY=2; COUNT=0
while [ $# -gt 0 ]; do
  case "$1" in
    -r) RESOLVER="$2"; shift 2;;
    -s) SUBNET="$2"; shift 2;;
    -i) EVERY="$2"; shift 2;;
    -n) COUNT="$2"; shift 2;;
    -h|--help) sed -n '2,13p' "$0"; exit 0;;
    -*) echo "Unknown option: $1 (try --help)" >&2; exit 1;;
    *) NAME="$1"; shift;;
  esac
done
[ -n "$NAME" ] || { sed -n '2,13p' "$0"; exit 1; }
command -v dig >/dev/null 2>&1 || { echo "dig not found. Install it (dnsutils on Ubuntu, bind-tools elsewhere)." >&2; exit 1; }

n=0
while :; do
  if [ -n "$SUBNET" ]; then
    answer="$(dig +noall +answer "@$RESOLVER" "+subnet=$SUBNET" A "$NAME" 2>/dev/null || true)"
  else
    answer="$(dig +noall +answer "@$RESOLVER" A "$NAME" 2>/dev/null || true)"
  fi
  ips="$(printf '%s\n' "$answer" | awk '$4 == "A" {print $5}' | sort | tr '\n' ' ')"
  ttl="$(printf '%s\n' "$answer" | awk '$4 == "A" {print $2; exit}')"
  who=""
  for ip in $ips; do
    label="$(curl -s -m 2 "http://$ip/api/whoami" | sed -n 's/.*"label": "\([^"]*\)".*/\1/p' || true)"
    who="$who${who:+, }${label:-no demo web server}"
  done
  printf '%s  ttl %-4s %-18s %s\n' "$(date +%H:%M:%S)" "${ttl:--}" "${ips:-no answer}" "$who"
  n=$((n + 1))
  if [ "$COUNT" -gt 0 ] && [ "$n" -ge "$COUNT" ]; then break; fi
  sleep "$EVERY"
done
