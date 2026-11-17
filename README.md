<p align="center"><img src="https://delegaris.co.uk/images/logo-light.png" alt="Delegaris" height="64"></p>

<p align="center"><strong>Cloud infrastructure access, without cloud console access.</strong><br>
Free, self-hosted, from <a href="https://goodhallsolutions.co.uk">Goodhall Solutions</a>.</p>

---

Delegaris is a free, self-hosted portal that lets people without AWS console access start, stop and keep on EC2, RDS and other AWS resources across any number of accounts, within role-based rules written against Active Directory or Entra ID groups. People sign in with the directory account they already have, see only what an access rule gives them, and the hosting team keeps ownership of the schedules.

- **Keep on past the schedule**, **book ahead**, and **server groups** that start in order
- **Access rules** by group, account, tag and name, with **approvals** for the delicate ones and **requests for access**
- **EC2, RDS, Aurora, DocumentDB, Neptune, Auto Scaling, ECS, EKS, Redshift, SageMaker, Lightsail and App Runner**
- **Remote Desktop** files for Windows machines, **cost estimates**, **Slack and Teams**, **reports**, a full **activity log**, **API tokens**, **two-step sign-in**, **high availability**

Website: [delegaris.co.uk](https://delegaris.co.uk) · Documentation: [docs.delegaris.co.uk](https://docs.delegaris.co.uk) · [Security and trust](https://delegaris.co.uk/security)

Delegaris is free to use, including commercially, under the [Delegaris Free Licence](LICENSE). The application source is not published: this repository holds the installer, the IAM templates and policies, the demo, the licence and the releases.

## Install

### Docker

```bash
docker run -d --name delegaris -p 8080:8080 -v delegaris-data:/data \
  -e PUBLIC_URL=http://localhost:8080 -e LOCAL_ADMIN_PASSWORD=change-me \
  goodhallsolutions/delegaris:latest
```

Then open http://localhost:8080 and sign in as `admin`. The image is built for x86_64 (amd64); on arm64 servers such as AWS Graviton, use the Linux package below. For a real deployment use Docker Compose: see [Quick start: Docker Compose](https://docs.delegaris.co.uk/quick-start/docker-compose).

### Linux, without Docker

Ubuntu 22.04/24.04, Debian 12, RHEL/Rocky/Alma 9 or Amazon Linux 2023, on x86_64 or arm64:

```bash
curl -fsSL https://github.com/Goodhall-Solutions/delegaris/releases/latest/download/install.sh | sudo bash
```

It installs a systemd service with its own Python, and prints the address and a generated administrator password. Running it again upgrades. See [Quick start: Linux](https://docs.delegaris.co.uk/quick-start/linux), and [Uninstalling](https://docs.delegaris.co.uk/quick-start/uninstalling) to remove it.

### Try it without AWS

The [`demo`](demo) folder runs Delegaris against a simulated AWS with two accounts of sample machines and three ready-made sign-ins. It needs only Docker:

```bash
git clone https://github.com/Goodhall-Solutions/delegaris.git
cd delegaris/demo
docker compose up
```

Then open http://localhost:8080 and sign in as `admin` / `admin`, `dev` / `dev` or `lead` / `lead`. See [Try the demo](https://docs.delegaris.co.uk/quick-start/try-the-demo).

## AWS permissions

Delegaris reaches each account through a narrow role you create there. The [`iam`](iam) folder has:

- `member-account-role.yaml`: the role for each account you manage (CloudFormation, with a switch per service)
- `hub-role.yaml`: the role Delegaris itself runs as, on EC2
- `policies/`: the same permissions as plain IAM JSON, for the console, Terraform or the CDK

See [Setting up IAM by hand](https://docs.delegaris.co.uk/aws/iam-by-hand).

## Downloads

Every [release](https://github.com/Goodhall-Solutions/delegaris/releases) has:

| File | What it is |
|---|---|
| `install.sh`, `uninstall.sh` | The Linux installer and uninstaller |
| `delegaris-linux-x86_64.tar.gz` | The Linux package for Intel and AMD |
| `delegaris-linux-aarch64.tar.gz` | The Linux package for arm64 (AWS Graviton and the like) |
| `*.sha256` | Checksums, checked by the installer |

The Docker image is [`goodhallsolutions/delegaris`](https://hub.docker.com/r/goodhallsolutions/delegaris) on Docker Hub.

## Help and feedback

- Found a problem, or want something it does not do? [Open an issue](https://github.com/Goodhall-Solutions/delegaris/issues/new/choose).
- A security problem? Please do not open an issue: see [SECURITY.md](SECURITY.md).
- Help setting it up, or with AWS more generally: [Goodhall Solutions](https://goodhallsolutions.co.uk).

## Licence

Delegaris is free to use, including commercially, under the [Delegaris Free Licence](LICENSE). The source code is not published; this repository holds the releases, the installer, the IAM templates and the demo. Open-source components inside Delegaris keep their own licences, listed in `THIRD-PARTY-NOTICES` in every download.

Copyright © 2026 Goodhall Solutions Ltd.
