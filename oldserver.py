#!/usr/bin/env python
"""Legacy (server_v2) one-shot launcher.

Mirror of ``server.py`` but boots the OLD FastAPI backend that lives in
``legacy/server_v2`` using the dedicated ``old-server`` virtualenv.

Run from anywhere::

    python oldserver.py                 # start legacy API + ngrok tunnel
    python oldserver.py --no-ngrok      # API only (LAN / localhost)
    python oldserver.py --port 9000     # override port

What it does:
  1. Loads ``env/.env`` from the project root and injects it into the child
     process environment (legacy ``app.config`` only reads env vars, not the
     root .env directly).
  2. Boots the legacy app (uvicorn ``app.main:app``) from ``legacy/server_v2``
     using ``old-server/Scripts/python.exe``.
  3. Waits for ``/health`` to go green.
  4. Opens an external ngrok tunnel on the project's static domain (the legacy
     app's own pyngrok auto-start is suppressed to avoid ERR_NGROK_334).
  5. Prints the URLs to connect to (LAN IP, localhost, public ngrok).
  6. Streams server + ngrok logs, prefixed, until Ctrl+C — then tears the
     whole process tree down cleanly.

Stdlib only; no extra packages required to run the launcher itself.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

# ── Configuration ────────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parent
SERVER_DIR = ROOT / "legacy" / "server_v2"
ENV_FILE = ROOT / "env" / ".env"
VENV_PYTHON = ROOT / "old-server" / "Scripts" / "python.exe" \
    if os.name == "nt" else ROOT / "old-server" / "bin" / "python"

# Free static ngrok domain wired into the Flutter client default
# (lib/services/connection_service.dart). Override with NGROK_DOMAIN env var.
DEFAULT_NGROK_DOMAIN = "lagomorphic-mattedly-walton.ngrok-free.dev"
NGROK_EXE = Path(os.environ["LOCALAPPDATA"]) / "ngrok" / "ngrok.exe" \
    if os.name == "nt" and "LOCALAPPDATA" in os.environ else None
NGROK_API = "http://127.0.0.1:4040/api/tunnels"

IS_WINDOWS = os.name == "nt"

# ── Tiny ANSI helpers (no dependency) ─────────────────────────────────────────
_USE_COLOR = sys.stdout.isatty()


def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _USE_COLOR else text


def bold(t: str) -> str:
    return _c("1", t)


def green(t: str) -> str:
    return _c("32", t)


def cyan(t: str) -> str:
    return _c("36", t)


def yellow(t: str) -> str:
    return _c("33", t)


def red(t: str) -> str:
    return _c("31", t)


def dim(t: str) -> str:
    return _c("2", t)


# ── Env loading ────────────────────────────────────────────────────────────────
def _load_env_file(path: Path) -> dict[str, str]:
    """Parse a simple KEY=VALUE .env file. Ignores comments / blank lines."""
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip().strip('"').strip("'")
        if key:
            out[key] = val
    return out


# ── Process plumbing ──────────────────────────────────────────────────────────
_procs: list[subprocess.Popen] = []


def _spawn(cmd: list[str], cwd: Path, env: dict[str, str] | None = None) -> subprocess.Popen:
    """Launch a child with merged stdout/stderr and its own process group."""
    creationflags = subprocess.CREATE_NEW_PROCESS_GROUP if IS_WINDOWS else 0
    proc = subprocess.Popen(
        cmd,
        cwd=str(cwd),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=1,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=creationflags,
        env=env,
    )
    _procs.append(proc)
    return proc


def _pump(proc: subprocess.Popen, label: str, color) -> None:
    """Stream a child's output to our stdout, line-prefixed."""
    tag = color(f"[{label}]")
    assert proc.stdout is not None
    for line in proc.stdout:
        print(f"{tag} {line.rstrip()}", flush=True)


def _kill_all() -> None:
    for proc in _procs:
        if proc.poll() is not None:
            continue
        try:
            if IS_WINDOWS:
                # Kill the whole tree (python -> uvicorn -> workers).
                subprocess.run(
                    ["taskkill", "/F", "/T", "/PID", str(proc.pid)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                )
            else:
                proc.terminate()
        except Exception:
            pass
    for proc in _procs:
        try:
            proc.wait(timeout=8)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass


# ── Health / discovery ────────────────────────────────────────────────────────
def _http_ok(url: str, timeout: float = 2.0) -> bool:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            return resp.status == 200
    except Exception:
        return False


def _lan_ip() -> str:
    """Best-effort primary LAN IPv4 (no traffic actually sent)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()


def _wait_for_health(port: int, timeout: float = 180.0) -> bool:
    # Legacy health route is mounted at /health (no /live|/ready sub-paths).
    url = f"http://127.0.0.1:{port}/health"
    deadline = time.time() + timeout
    while time.time() < deadline:
        if _http_ok(url):
            return True
        # Bail early if the server process already died.
        if _procs and _procs[0].poll() is not None:
            return False
        time.sleep(0.5)
    return False


def _ngrok_public_url(timeout: float = 30.0) -> str | None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(NGROK_API, timeout=2.0) as resp:
                data = json.loads(resp.read().decode())
            for tunnel in data.get("tunnels", []):
                if tunnel.get("proto") == "https":
                    return tunnel.get("public_url")
            if data.get("tunnels"):
                return data["tunnels"][0].get("public_url")
        except Exception:
            pass
        time.sleep(0.5)
    return None


# ── Banner ─────────────────────────────────────────────────────────────────────
def _banner(port: int, public_url: str | None) -> None:
    lan = _lan_ip()
    bar = "═" * 64
    print()
    print(yellow(bar))
    print(yellow(bold("  LEGACY (server_v2) server is up")))
    print(yellow(bar))
    print(f"  {bold('Local')}    : {cyan(f'http://localhost:{port}')}")
    print(f"  {bold('LAN')}      : {cyan(f'http://{lan}:{port}')}   "
          + dim("(phone on same Wi-Fi)"))
    if public_url:
        print(f"  {bold('Public')}   : {cyan(public_url)}   "
              + dim("(ngrok — matches app default)"))
    print(f"  {bold('Health')}   : {cyan(f'http://localhost:{port}/health')}")
    print(f"  {bold('Docs')}     : {cyan(f'http://localhost:{port}/docs')}")
    print(yellow(bar))
    print(dim("  Logs below. Press Ctrl+C to stop everything.\n"))


# ── Main ────────────────────────────────────────────────────────────────────────
def main() -> int:
    parser = argparse.ArgumentParser(description="Launch the LEGACY server_v2 backend.")
    parser.add_argument("--port", type=int, default=8000, help="API port (default 8000)")
    parser.add_argument("--no-ngrok", action="store_true", help="Skip the ngrok tunnel")
    parser.add_argument("--reload", action="store_true", help="uvicorn auto-reload (dev)")
    parser.add_argument(
        "--domain",
        default=os.environ.get("NGROK_DOMAIN", DEFAULT_NGROK_DOMAIN),
        help="ngrok static domain",
    )
    args = parser.parse_args()

    # Preflight -----------------------------------------------------------------
    if not SERVER_DIR.is_dir():
        print(red(f"legacy/server_v2 not found at {SERVER_DIR}"), file=sys.stderr)
        return 1
    if not (SERVER_DIR / "app" / "main.py").is_file():
        print(red(f"missing {SERVER_DIR / 'app' / 'main.py'}"), file=sys.stderr)
        return 1
    if not VENV_PYTHON.is_file():
        print(red(f"`old-server` venv python not found at {VENV_PYTHON}\n"
                  "  create it:  uv venv --python 3.12 old-server\n"
                  "  install  :  uv pip install --python ./old-server/Scripts/python.exe "
                  "-r legacy/server_v2/requirements.txt"),
              file=sys.stderr)
        return 1
    if not ENV_FILE.is_file():
        print(red(f"missing {ENV_FILE} — needs SUPABASE_URL, SUPABASE_SERVICE_KEY, "
                  "GROQ_API_KEY"), file=sys.stderr)
        return 1

    # Build child environment: OS env + root env/.env + forced PORT. ------------
    child_env = dict(os.environ)
    child_env.update(_load_env_file(ENV_FILE))
    child_env["PORT"] = str(args.port)
    child_env["PYTHONUNBUFFERED"] = "1"
    child_env["PYTHONIOENCODING"] = "utf-8"
    # Suppress the legacy app's built-in pyngrok auto-start; we run an external
    # ngrok below. Two tunnels on the same static domain => ERR_NGROK_334.
    child_env.pop("NGROK_AUTHTOKEN", None)

    use_ngrok = not args.no_ngrok
    ngrok_bin: str | None = None
    if use_ngrok:
        if NGROK_EXE and NGROK_EXE.is_file():
            ngrok_bin = str(NGROK_EXE)
        elif shutil.which("ngrok"):
            ngrok_bin = shutil.which("ngrok")
        else:
            print(yellow("ngrok not found — continuing without a public tunnel"))
            use_ngrok = False

    # Already running? Reuse it instead of crashing on a busy port. -------------
    if _http_ok(f"http://127.0.0.1:{args.port}/health"):
        print(yellow(f"Port {args.port} already serving a healthy API — reusing it."))
        server_started_here = False
    else:
        server_started_here = True
        uv_cmd = [
            str(VENV_PYTHON), "-m", "uvicorn", "app.main:app",
            "--host", "0.0.0.0", "--port", str(args.port),
        ]
        if args.reload:
            uv_cmd.append("--reload")
        print(dim(f"$ {' '.join(uv_cmd)}  (cwd={SERVER_DIR})"))
        server = _spawn(uv_cmd, cwd=SERVER_DIR, env=child_env)
        threading.Thread(target=_pump, args=(server, "server", green), daemon=True).start()

        print(dim("Waiting for /health ... (first boot loads torch / embeddings, be patient)"))
        if not _wait_for_health(args.port):
            print(red("Server failed to become healthy. See [server] logs above."))
            _kill_all()
            return 1

    # ngrok ----------------------------------------------------------------------
    public_url: str | None = None
    if use_ngrok and ngrok_bin:
        ngrok_cmd = [
            ngrok_bin, "http", f"--domain={args.domain}", str(args.port),
            "--log", "stdout", "--log-format", "logfmt",
        ]
        print(dim(f"$ {' '.join(ngrok_cmd)}"))
        ngrok = _spawn(ngrok_cmd, cwd=ROOT)
        threading.Thread(target=_pump, args=(ngrok, "ngrok", cyan), daemon=True).start()
        public_url = _ngrok_public_url()
        if public_url is None:
            public_url = f"https://{args.domain}"

    _banner(args.port, public_url)

    # Idle loop: hold until a child dies or Ctrl+C. ------------------------------
    try:
        while True:
            if server_started_here and _procs and _procs[0].poll() is not None:
                print(red("Server process exited."))
                break
            time.sleep(1)
    except KeyboardInterrupt:
        print(yellow("\nShutting down ..."))
    finally:
        _kill_all()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        _kill_all()
        sys.exit(130)
