# Load Balancers in Azure: lab scripts

The infrastructure for the four-video series on Azure's load-balancing services (Infra2AI). Each video has a
folder that deploys everything the video needs **except the service itself**, which you create in the Azure
portal while you follow along.

| Folder | Video | Deploys |
|---|---|---|
| [`01-azure-load-balancer`](01-azure-load-balancer) | Azure Load Balancer | a virtual network, three web servers in three availability zones, a client VM |
| [`02-application-gateway`](02-application-gateway) | Application Gateway | a virtual network with an empty gateway subnet, six web servers in red, green and blue pools, a client VM, a demo certificate |
| [`03-front-door`](03-front-door) | Front Door | the same web server in three regions (Singapore, Sweden, United States), each with a public IP and DNS name |
| [`04-traffic-manager`](04-traffic-manager) | Traffic Manager | the same three-region lab as video 3, plus `dns-watch.sh` |

Everything is a [Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/) template with a
one-command wrapper in **PowerShell** and **bash**. All VMs are created in parallel (a lab takes about two to
three minutes), and re-running a script is safe.

## What you need

- An Azure subscription where you may create resources. The labs use `Standard_B1s` VMs (about one cent an
  hour each); if that size is not available in your region the scripts try the next sizes automatically.
- **Either** the Azure CLI (`az login`) and bash, **or** PowerShell 7 with the Az module (`Connect-AzAccount`).
  The PowerShell scripts also need the [Bicep CLI](https://aka.ms/bicep-install) (`az bicep install` installs it
  and Azure Cloud Shell already has it).
- `ssh-keygen` (any OpenSSH client). Videos 2 also needs `openssl` for the demo certificate (optional).

Azure Cloud Shell works for all of it.

## Quick start

```bash
git clone <this repository>
cd load-balancers-in-azure/01-azure-load-balancer
./deploy.sh                 # bash
# or
./deploy.ps1                # PowerShell 7
```

The script prints the addresses it created and how to SSH in. When you are done:

```bash
./cleanup.sh                # or ./cleanup.ps1
```

Options (the same idea in both): `-l/-Location` region, `-g/-ResourceGroup` resource group, `-s/-VmSize`,
`--allow-ip/-AllowIp` the address allowed to SSH in, `--no-zones/-NoZones` for a region without availability
zones, `--skip-check/-SkipCheck`. Run `./deploy.sh --help` for the full list.

## What is different from a hand-built lab

- **No passwords.** The scripts create an SSH key pair in `.keys/` (ignored by git) and VMs accept only that key.
- **SSH only from you.** The scripts detect your public IP and allow SSH from that address only.
- **No jumpbox scripting.** The website is baked into every VM with cloud-init at first boot, from a single
  Python file (`shared/webapp/app.py`, standard library only), so the web servers need no internet access,
  no package installs and no downloads.
- **Private web subnets.** The web servers sit in a *private subnet* (no default outbound access), which is how
  new Azure virtual networks behave. They cannot reach the Internet until you give them a way out, which is
  exactly what the Load Balancer video demonstrates.
- **One website for every video.** It shows which server answered (name, colour, zone, region, country and
  flag), what the server actually saw (client IP, `X-Forwarded-For`, destination IP, the path as received), a
  live view (`/watch`) that asks over and over and tallies who answers, a health endpoint (`/healthz`), and two
  small tools: an outbound-IP test and a DNS lookup from the server's own region.

## Cost

The labs are small, but the services you create in the videos are not free while they exist. Delete the
resource group when you finish. Roughly: a lab's VMs cost a few cents an hour; a Standard Load Balancer about
three cents an hour; an Application Gateway v2 about 25 cents an hour (WAF v2 about 45); Front Door Standard
has a base fee of about $35 a month, billed for every hour or partial hour (Premium about $330 a month);
Traffic Manager costs cents. Check the [Azure pricing pages](https://azure.microsoft.com/pricing/) for current
prices in your region.

## Good to know

- **Re-running a deploy script after you created the load balancer or gateway** resets the network interfaces
  and detaches them from its backend pool. Deploy first, then follow the video.
- **The website cannot be changed on a running VM** (the cloud-init data is fixed at creation). To change it,
  run the cleanup script and deploy again.
- **A region may refuse new resources** for your subscription (for example `RequestDisallowedByAzure ... region
  is currently not accepting new customers`). Pick another region with `-l`. For videos 3 and 4 the three
  regions are listed in `03-front-door/main.bicep` (parameter `origins`).
- The demo site is for demonstrations only. In videos 1, 3 and 4 it is open to the Internet on port 80.

## Repository layout

```
01-azure-load-balancer/    main.bicep, deploy.sh, deploy.ps1, cleanup.sh, cleanup.ps1
02-application-gateway/    main.bicep, deploy.*, cleanup.*
03-front-door/             main.bicep, origin-region.bicep, deploy.*, cleanup.*
04-traffic-manager/        deploy.* and cleanup.* (reuse 03's template), dns-watch.sh
shared/
  bicep/web-vm.bicep       one VM: NIC, optional public IP and zone, the website
  cloud-init.yaml          installs the website at first boot
  webapp/app.py            the website
  scripts/common.sh|ps1    helpers used by every deploy and cleanup script
```
