# Video 2: Azure Application Gateway

```bash
./deploy.sh            # or ./deploy.ps1          (about 2.5 minutes)
./cleanup.sh           # or ./cleanup.ps1
```

Defaults: region `southeastasia`, resource group `rg-appgw-demo`. See the [main README](../README.md) for options.

## What it deploys

Virtual network `vnet-appgw-demo` (10.0.0.0/16):

| Subnet | Range | Holds |
|---|---|---|
| `snet-appgw` | 10.0.0.0/24 | nothing yet: the gateway goes here (no NSG on purpose) |
| `snet-web` | 10.0.1.0/24 | six web servers; a private subnet; its NSG allows HTTP and HTTPS only from the gateway subnet |
| `snet-client` | 10.0.2.0/24 | `client-vm` (10.0.2.4) with a public IP |

| Pool | Servers | Addresses | Zones |
|---|---|---|---|
| red | `red-01`, `red-02` | 10.0.1.4, 10.0.1.5 | 1, 2 |
| green | `green-01`, `green-02` | 10.0.1.6, 10.0.1.7 | 3, 1 |
| blue | `blue-01`, `blue-02` | 10.0.1.8, 10.0.1.9 | 2, 3 |

Each server answers `/` and its own prefix (`/red/...`). The page shows the **path as received**, so you can see
whether the gateway forwarded the full path. A server asked for another pool's prefix answers with a 404 that
says a routing rule sent the request to the wrong pool.

## The demo certificate

`./deploy.sh` also creates a self-signed certificate for the HTTPS listener part of the video:
`../.keys/appgw-demo.pfx` (password in `../.keys/appgw-demo.pfx.password`) and `../.keys/appgw-demo.cer`.
It is valid for `lbdemo.example.com` and `*.lbdemo.example.com`, so a browser will warn about it. Needs `openssl`.

## Things you can try once the gateway exists

- `/red/`, `/green/`, `/blue/` and `/` reach different pools. `http://<gateway>/red/watch` tallies the two red servers.
- Stop a server (`sudo systemctl stop lbdemo`, over SSH from the client VM) and watch **Backend health**.
- Add a rewrite rule that sets a request header, then open **All request headers** on a page.
- Test a host-based listener without DNS: `curl --resolve red.example.com:80:<gateway IP> http://red.example.com/`.
