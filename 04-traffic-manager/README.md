# Video 4: Azure Traffic Manager

```bash
./deploy.sh            # or ./deploy.ps1          (about 2 minutes)
./cleanup.sh           # or ./cleanup.ps1
```

Defaults: resource group `rg-tm-demo`. This deploys the **same three-region lab as video 3** (Singapore, Sweden,
United States, each with a public IP and a DNS name), so see [`../03-front-door`](../03-front-door/README.md) for
what is in it. If you still have the video 3 lab you can reuse it.

## Watch a DNS name change

```bash
./dns-watch.sh myprofile.trafficmanager.net            # a lookup every two seconds
./dns-watch.sh myprofile.trafficmanager.net -s 203.0.113.0/24   # pretend to be a client in a subnet
```

It prints the time, the TTL, the address, and which demo server lives there. Change a priority, a weight or an
endpoint in the portal and watch the answer change once the DNS time to live has passed. Needs `dig`.

## Three ways to ask from "somewhere else" without a VPN

1. **From each region's own VM.** Open `http://<server's DNS name>/` and use **Server tools** (or
   `/api/resolve?name=myprofile.trafficmanager.net`): the lookup uses Azure DNS in that region, so a Performance
   profile answers with the nearest endpoint for *that* region.
2. **With an EDNS client subnet.** `dig @8.8.8.8 +subnet=<a real public range> A myprofile.trafficmanager.net`.
   Traffic Manager honours it for Performance, Geographic and Subnet routing. Reserved ranges such as
   203.0.113.0/24 are refused by Google DNS, so use a real range (for example the range of one of your servers).
3. **From your own computer.** Your resolver's location is what Traffic Manager sees, not yours.
