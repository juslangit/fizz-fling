#!/usr/bin/env bash
# Serves build/web on this Mac and opens a public https link to it.
# iPhones only share motion data with https pages, so the plain Wi-Fi link won't do.
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -f "serve_phone.py 8064" || true   # a rebuild deletes the folder an old server was serving
python3 tools/serve_phone.py 8064 > build/serve.log 2>&1 &
cloudflared tunnel --no-autoupdate --url http://localhost:8064 > build/tunnel.log 2>&1 &
for i in $(seq 1 60); do
  url=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' build/tunnel.log | head -1 || true)
  [ -n "$url" ] && { echo "Phone link: $url"; exit 0; }
  sleep 1
done
echo "No tunnel link yet - see build/tunnel.log"; exit 1
