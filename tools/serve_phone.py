"""Serve the web build on the Wi-Fi so the iPhone can play it before itch.io.

Sends "never cache" headers: Safari otherwise keeps old game files from an earlier
build at the same address and silently plays (or fails on) the stale version.
"""
import http.server, os, socket, sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8063
os.chdir(os.path.join(os.path.dirname(__file__), "..", "build", "web"))


class NoCache(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, max-age=0")
        super().end_headers()


ip = os.popen("ipconfig getifaddr en0 || ipconfig getifaddr en1").read().strip() or "localhost"
print(f"On the iPhone, open:  http://{ip}:{PORT}", flush=True)
http.server.ThreadingHTTPServer(("0.0.0.0", PORT), NoCache).serve_forever()
