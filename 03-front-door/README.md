# Video 3: Azure Front Door

```bash
./deploy.sh            # or ./deploy.ps1          (about 2 minutes)
./cleanup.sh           # or ./cleanup.ps1
```

Defaults: resource group `rg-fd-demo`. See the [main README](../README.md) for options.

## What it deploys

The same web server in three regions on three continents. Each has its own virtual network and NSG, a Standard
public IP with a DNS name, and the demo website showing its country and flag:

| Country | Region | VM | Colour |
|---|---|---|---|
| Singapore | `southeastasia` | `web-sea` | red |
| Sweden | `swedencentral` | `web-swc` | gold |
| United States | `eastus` | `web-eus` | blue |

The DNS names are printed at the end: `lbdemo-<suffix>-sea.southeastasia.cloudapp.azure.com`, and so on. Port 80
is open to the Internet, so you can reach each server directly. To change the regions edit the `origins`
parameter in `main.bicep`.

## Lock the origins to Front Door

```bash
./deploy.sh --lock-to-front-door        # or ./deploy.ps1 -LockToFrontDoor
```

allows web traffic only from the `AzureFrontDoor.Backend` service tag, so the servers answer through Front Door
and not directly. You can also change the NSG rule by hand in the portal, as the video shows. (A complete
lock-down also checks the `X-Azure-FDID` header, which the video explains.)

## Things you can try once Front Door exists

- Open `https://<your endpoint>.azurefd.net/` and see which country answers, then `/watch?every=500` for a live view.
- Stop the site on the serving origin (`sudo systemctl stop lbdemo` over SSH) and watch the live view move on.
  Then stop the VM from the portal and compare.
- `/cache` returns a response that may be cached for 60 seconds: look at the `X-Cache` header through Front Door.
