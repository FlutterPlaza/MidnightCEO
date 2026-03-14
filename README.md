# MidnightCEO

AI-powered autonomous corporate operating system. Submit a business idea — AI agents autonomously research, plan, and build your company.

## What is MidnightCEO?

MidnightCEO deploys a suite of AI agents — CEO, CTO, Legal, Sales, Support, HR, and more — that collaborate to build and operate a company from a single idea. The agents produce vision briefs, product specs, technical architectures, outreach campaigns, legal drafts, and financial reports — all autonomously.

## Quick Start (Self-Hosted)

```bash
# Clone this repo
git clone https://github.com/FlutterPlaza/MidnightCEO.git
cd MidnightCEO

# Copy .env and add your API keys
cp apps/installer/.env.example apps/installer/.env

# Pull pre-built agent images and start everything
cd apps/installer
docker compose -f docker-compose.local.yml up -d
```

The Founder Console will be available at `http://localhost:3000` once the stack is running.

**Requirements:** Docker Desktop, 16 GB RAM minimum.

## What's Included

| Component | Description |
|-----------|-------------|
| **Installer** | Docker Compose stack + setup scripts for local compute mode |
| **Shared Types** | TypeScript type definitions shared across the platform |

## Architecture

```
┌──────────────────────────────┐
│  Founder Console (Docker)    │  ← You interact here
│  localhost:3000               │
└──────────┬───────────────────┘
           │
┌──────────▼───────────────────┐
│  Agents Backend (Docker)     │  ← AI agents run here
│  localhost:8000               │
└──────────┬───────────────────┘
           │
┌──────────▼───────────────────┐
│  Redis + PostgreSQL (Docker) │  ← State & task queue
└──────────────────────────────┘
```

## Cloud Upgrade

Want remote access, mobile control, and always-on agents?

Enable cloud mode from **Settings → Cloud** in the Founder Console, or visit [midnightceo.com](https://midnightceo.com).

## Contributing

We welcome contributions to the Installer and shared types. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

- **Installer** — Platform support, setup UX, update mechanisms
- **Types** — Shared type definitions

## License

MIT — see [LICENSE](LICENSE).

---

Built by [FlutterPlaza](https://flutterplaza.com).
