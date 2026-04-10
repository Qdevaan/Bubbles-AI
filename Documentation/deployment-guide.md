# Bubbles AI — Deployment Guide

This guide covers three scenarios:

1. [Local Development](#1-local-development) — run everything on your machine
2. [AWS EC2 Free Tier](#2-aws-ec2-free-tier-deployment) — 12-month free static IP
3. [Flutter Release Build](#3-flutter-release-build) — bake the server URL into the app

---

## Prerequisites (all scenarios)

| Requirement | Notes |
|---|---|
| Python 3.11+ | Used by server_v2 |
| Docker Desktop | Required for containerised runs and production |
| Flutter SDK 3.x | For the mobile client |
| Git | Clone / pull |

### API Keys you need

Collect these before starting. All are free-tier eligible.

| Key | Where to get it | Required? |
|---|---|---|
| `SUPABASE_URL` | [supabase.com](https://supabase.com) → project settings | **Yes** |
| `SUPABASE_SERVICE_KEY` | Supabase → Project → API → service_role | **Yes** |
| `SUPABASE_KEY` | Supabase → Project → API → anon key | **Yes** |
| `GROQ_API_KEY` | [console.groq.com](https://console.groq.com) | **Yes** |
| `DEEPGRAM_API_KEY` | [deepgram.com](https://deepgram.com) | For voice |
| `LIVEKIT_URL / API_KEY / SECRET` | [livekit.io](https://livekit.io) cloud project | For voice |
| `CEREBRAS_API_KEY` | [inference.cerebras.ai](https://inference.cerebras.ai) | Optional (faster wingman) |
| `GEMINI_API_KEY` | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) | Optional (better consultant) |

---

## 1. Local Development

### 1.1 Clone and set up environment

```bash
git clone <YOUR_REPO_URL>
cd Bubbles-AI
```

Copy the example env file and fill in your keys:

```bash
cp env/.env.example env/.env
# open env/.env and paste in your real keys
```

Minimum required fields in `env/.env`:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your-service-role-key
SUPABASE_KEY=your-anon-key
GROQ_API_KEY=gsk_...
```

### 1.2 Option A — Run with Docker (recommended)

This starts the server + Redis together with one command.

```bash
cd server_v2
docker compose up --build
```

The server will be available at `http://localhost:8000`.

> **First run note:** The image pulls ~1 GB of Python/ML dependencies. Subsequent starts are instant because Docker caches the layer.

Verify it is up:

```bash
curl http://localhost:8000/health
# Expected: {"status": "ok", ...}
```

Stop the server:

```bash
docker compose down
```

### 1.3 Option B — Run without Docker (bare Python)

You need Redis running separately. The easiest way on Windows/Mac is:

```bash
# Windows (via WSL or Chocolatey)
choco install redis-64
redis-server

# Mac
brew install redis && brew services start redis
```

Then install Python dependencies and start the server:

```bash
cd server_v2
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Set `REDIS_URL=redis://localhost:6379/0` in `env/.env` when running Redis locally without Docker.

### 1.4 Connect the Flutter app

The app resolves the server URL in this priority order:

1. `--dart-define=SERVER_URL=...` compile-time override
2. `LOCAL_SERVER_URL` from `env/.env`
3. Emulator defaults (`10.0.2.2:8000` for Android, `localhost:8000` for iOS/web)

For local development the emulator defaults work automatically — no extra config needed.

Run the Flutter app normally:

```bash
flutter run
```

---

## 2. AWS EC2 Free Tier Deployment

AWS gives you a **t2.micro** (1 vCPU, 1 GB RAM) free for 12 months plus a free Elastic IP (static public IP).

### 2.1 Create the EC2 instance

1. Log in to [aws.amazon.com](https://aws.amazon.com) and go to **EC2 → Launch Instance**.
2. Name: `bubbles-server`
3. AMI: **Ubuntu Server 22.04 LTS (64-bit x86)** — look for the "Free tier eligible" badge.
4. Instance type: **t2.micro** (Free tier eligible).
5. Key pair: create a new one (e.g. `bubbles-key`), download the `.pem` file — keep it safe.
6. Network settings → Security Group → Add these inbound rules:

   | Type | Protocol | Port | Source |
   |---|---|---|---|
   | SSH | TCP | 22 | Your IP (or 0.0.0.0/0 for simplicity) |
   | Custom TCP | TCP | 8000 | 0.0.0.0/0 |

7. Storage: 8 GB gp2 (default free tier amount is fine).
8. Click **Launch Instance**.

### 2.2 Assign a static (Elastic) IP

Without this step, the IP changes every time the instance restarts.

1. EC2 → **Elastic IPs** → **Allocate Elastic IP address** → Allocate.
2. Select the new IP → **Actions → Associate Elastic IP address**.
3. Choose your instance → Associate.

Your static IP is now shown in the Elastic IP list. Call it `YOUR_IP` in the steps below.

### 2.3 SSH into the instance

```bash
chmod 400 bubbles-key.pem
ssh -i bubbles-key.pem ubuntu@YOUR_IP
```

### 2.4 Run the VM setup script

Copy the setup script to the VM and run it as root. Do this **once** on a fresh instance.

From your local machine:

```bash
scp -i bubbles-key.pem server_v2/setup-vm.sh ubuntu@YOUR_IP:~/
```

On the VM:

```bash
sudo bash ~/setup-vm.sh
```

This installs Docker, Docker Compose, and creates `/opt/bubbles/env/`.

**Log out and back in** so the Docker group takes effect:

```bash
exit
ssh -i bubbles-key.pem ubuntu@YOUR_IP
```

### 2.5 Copy your environment file to the VM

From your local machine:

```bash
scp -i bubbles-key.pem env/.env ubuntu@YOUR_IP:/opt/bubbles/env/.env
```

> The production `docker-compose.prod.yml` reads the env file from `/opt/bubbles/env/.env` on the VM.

### 2.6 Clone the repo on the VM

```bash
cd /opt/bubbles
git clone <YOUR_REPO_URL> repo
```

### 2.7 Deploy

```bash
cd /opt/bubbles/repo/server_v2
./deploy.sh
```

`deploy.sh` does the following automatically:

1. `git pull` — pulls the latest code.
2. `docker build` — builds the image.
3. `docker compose -f docker-compose.prod.yml up -d` — starts server + Redis.
4. Polls `/health` every 5 seconds for up to 120 seconds and exits with ✅ or ❌.

### 2.8 Verify from your local machine

```bash
curl http://YOUR_IP:8000/health
# Expected: {"status": "ok"}
```

### 2.9 Subsequent deployments

Every time you push new code, redeploy with:

```bash
ssh -i bubbles-key.pem ubuntu@YOUR_IP
cd /opt/bubbles/repo/server_v2
./deploy.sh
```

Or run the deploy script directly from your local machine over SSH:

```bash
ssh -i bubbles-key.pem ubuntu@YOUR_IP "cd /opt/bubbles/repo/server_v2 && ./deploy.sh"
```

### 2.10 Free tier limits and tips

| Resource | Free allowance | Notes |
|---|---|---|
| t2.micro hours | 750 hrs/month | Enough to run 24/7 for one instance |
| Elastic IP | Free while associated | Charged ~$0.005/hr if instance is stopped but IP is still allocated |
| Data transfer out | 100 GB/month | Unlikely to hit this for a dev app |
| EBS storage | 30 GB | Default 8 GB is well within the limit |

**To avoid unexpected charges:**
- Keep only one instance running.
- If you stop the instance, release or re-associate the Elastic IP.
- Set a [billing alert](https://console.aws.amazon.com/billing/home#/alerts) at $1 so you are notified immediately if anything is unexpectedly charged.

---

## 3. Flutter Release Build

Once your server is deployed at a static IP, bake it into the app so users never need to configure anything.

### Android APK

```bash
flutter build apk --release --dart-define=SERVER_URL=http://YOUR_IP:8000
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

### iOS IPA

```bash
flutter build ipa --release --dart-define=SERVER_URL=http://YOUR_IP:8000
```

### Debug run against production server

```bash
flutter run --dart-define=SERVER_URL=http://YOUR_IP:8000
```

> The `SERVER_URL` dart-define takes the highest priority over all other URL sources in `ConnectionService`.

---

## Troubleshooting

### Server never becomes healthy (deploy.sh times out)

```bash
# Check container logs on the VM
docker compose -f docker-compose.prod.yml logs --tail=50 server
```

Common causes:
- Missing or wrong API key in `/opt/bubbles/env/.env` — the startup log will show a `ValidationError`.
- Port 8000 not open in the EC2 Security Group — re-check the inbound rules.
- Not enough memory — t2.micro has 1 GB. If you see OOM errors, stop other processes or consider t3.micro (still very cheap).

### Redis connection refused

Check that the Redis container is healthy:

```bash
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml logs redis
```

If `REDIS_URL` is set in `.env` to a non-empty value, make sure it points to a reachable Redis instance. For the Docker Compose setup, leave `REDIS_URL=` empty — it is set automatically by the compose file via the environment block.

### Flutter app cannot reach the server

- Confirm the server is healthy: `curl http://YOUR_IP:8000/health`
- Confirm port 8000 is open in the Security Group.
- On Android, HTTP (not HTTPS) requires `android:usesCleartextTraffic="true"` in `AndroidManifest.xml` — check `android/app/src/main/AndroidManifest.xml`.
- If using an emulator and a local server, the host machine is at `10.0.2.2`, not `localhost`.

### Seeing `⚠️ Brain Service: Cerebras init failed` in logs

This is expected if `CEREBRAS_API_KEY` is empty. The service falls back to Groq automatically. Same for Gemini. Only `GROQ_API_KEY`, `SUPABASE_URL`, and `SUPABASE_SERVICE_KEY` are strictly required.
