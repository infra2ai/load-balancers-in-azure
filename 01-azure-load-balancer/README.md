# Video 1: Azure Load Balancer

```bash
./deploy.sh            # or ./deploy.ps1          (about 2.5 minutes)
./cleanup.sh           # or ./cleanup.ps1
```

Defaults: region `southeastasia`, resource group `rg-lb-demo`. See the [main README](../README.md) for options.

## What it deploys

Virtual network `vnet-lb-demo` (10.0.0.0/16):

| Resource | Name | Address | Notes |
|---|---|---|---|
| Web server | `web-01` | 10.0.2.4 | zone 1, red |
| Web server | `web-02` | 10.0.2.5 | zone 2, green |
| Web server | `web-03` | 10.0.2.6 | zone 3, blue |
| Client VM | `client-vm` | 10.0.1.4 and a public IP | SSH in from your IP; also the place to call an internal load balancer from |
| NSG | `nsg-web` | | HTTP from the Internet; SSH from the client subnet and from your IP |
| NSG | `nsg-client` | | SSH from your IP |

The web subnet (`snet-web`, 10.0.2.0/24) is a **private subnet**: no outbound Internet access until the video
gives it some. There is no load balancer yet: you create it in the portal.

## Things you can try once the load balancer exists

- Open `http://<frontend IP>/` and refresh: different servers answer. Open `http://<frontend IP>/watch` for a
  live tally. Change the rule's session persistence and watch the tally change.
- **Runs of the same server are normal.** The load balancer hashes the connection's source port, and some operating
  systems (macOS, for one) hand out source ports one after another, so a single computer can show long runs of one
  server or a strict alternation. It is a hash, not a rotation, and with many clients it evens out. The lab website
  closes every connection, so every refresh is a new connection and a new hash.
- On any server's page, open **Server tools** and press the button to see its outbound public IP (or the
  failure when it has none).
- SSH to a specific server through an inbound NAT rule: `ssh -i ../.keys/lbdemo_ed25519 -p 50002 azureuser@<frontend IP>`.
- Stop the site on one server (`sudo systemctl stop lbdemo`) and watch it leave the rotation, then start it again.
- Floating IP: turn it on for the rule, then on each server run
  `sudo lbdemo-floating-ip add <frontend IP>`. The page's **Destination IP** then shows the frontend IP.
- Call an internal load balancer from the client VM with `curl http://<internal frontend IP>/api/whoami`.
