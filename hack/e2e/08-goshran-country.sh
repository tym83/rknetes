#!/usr/bin/env bash
# Runtime test in the tenant builder on loopback only; no external registry is contacted.
# 1. A lab upstream limits anonymous manifest pulls per source address, like Docker Hub.
#    Two clients pulling directly each get their own quota; through Goshran they share one.
# 2. A lab chart vendor withdraws its catalogue; Goshran's copied index still lists it,
#    pulls fail and the status page announces planned modernization.
set -euo pipefail
export PATH=${RK_BIN:-/work/out/rknetes}:$PATH
work=$(mktemp -d /work/tmp/goshran-country.XXXXXX)
pids=()
trap 'for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; rm -rf "$work"' EXIT
LIMIT=3

cat > "$work/upstream.py" <<'PY'
import collections, http.server, json, sys
limit = int(sys.argv[2]); seen = collections.Counter()
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        ip = self.client_address[0]; seen[ip] += 1
        if seen[ip] > limit:
            body = json.dumps({"errors": [{"code": "TOOMANYREQUESTS", "message": "You have reached your unauthenticated pull rate limit."}]}).encode()
            self.send_response(429)
        else:
            body = b'{"schemaVersion":2}'
            self.send_response(200)
        self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
python3 "$work/upstream.py" 18091 "$LIMIT" & pids+=($!)

cat > "$work/vendor.py" <<'PY'
import http.server, os, sys
class H(http.server.BaseHTTPRequestHandler):
    def reply(self, body):
        gone = os.path.exists(sys.argv[2])
        self.send_response(410 if gone else 200); self.send_header("Content-Length", "0" if gone else str(len(body))); self.end_headers()
        if body and not gone: self.wfile.write(body)
    def do_HEAD(self): self.reply(b"")
    def do_GET(self): self.reply(b"chart archive")
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
python3 "$work/vendor.py" 18092 "$work/withdrawn" & pids+=($!)

printf 'entries:\n  postgresql:\n  - version: 16.0.0\n    urls: [http://127.0.0.1:18092/charts/postgresql-16.0.0.tgz]\n' > "$work/index.yaml"
goshran --listen=127.0.0.1:18093 --upstream=http://127.0.0.1:18091 --index="$work/index.yaml" > "$work/goshran.log" 2>&1 & pids+=($!)
for port in 18091 18092 18093; do
  for _ in $(seq 1 30); do curl -s -o /dev/null "http://127.0.0.1:$port/" && break; sleep 0.5; done
done

pull() { curl -s -o /dev/null -w '%{http_code}' --interface "$1" "$2/v2/library/postgres/manifests/17"; }
echo "Direct pulls, each client from its own address (limit $LIMIT per address):"
direct=""
for client in 127.0.0.2 127.0.0.3; do
  for _ in $(seq 1 "$LIMIT"); do direct+="$(pull "$client" http://127.0.0.1:18091) "; done
done
echo "  $direct"
[[ "$direct" != *429* ]]

echo "The same pulls through Goshran (one upstream address for everyone):"
via=""
for client in 127.0.0.4 127.0.0.5; do
  for _ in $(seq 1 "$LIMIT"); do via+="$client:$(pull "$client" http://127.0.0.1:18093) "; done
done
echo "  $via"
[[ "$via" == *"127.0.0.5:429"* ]]
curl -s -D - -o "$work/refusal.json" http://127.0.0.1:18093/v2/library/postgres/manifests/17 > "$work/refusal.headers"
grep -q '^HTTP/1.1 429' "$work/refusal.headers"
grep -q TOOMANYREQUESTS "$work/refusal.json"
statement=$(grep -i '^X-Goshran-Statement:' "$work/refusal.headers" | cut -d' ' -f2- | tr -d '\r' | python3 -c 'import sys,urllib.parse;print(urllib.parse.unquote(sys.stdin.read().strip()))')
echo "X-Goshran-Statement: $statement"
[[ "$statement" == *Дискриминационные* ]]
grep 'TooManyRequests' "$work/goshran.log" | head -1
echo 'PASS: a second client that never pulled before is refused because the whole country shares Goshran'"'"'s address'

echo "Vendor catalogue present:"
url=$(curl -fsS http://127.0.0.1:18093/index.yaml | sed -n 's/.*urls: \[\(.*\)\]/\1/p')
curl -fsS -o /dev/null -w '  chart %{http_code}\n' "$url"
curl -fsS http://127.0.0.1:18093/status
touch "$work/withdrawn"
echo "Vendor withdraws its free catalogue:"
curl -fsS http://127.0.0.1:18093/index.yaml | cmp - "$work/index.yaml"
echo "  index.yaml still served unchanged by Goshran"
code=$(curl -s -o /dev/null -w '%{http_code}' "$url"); echo "  chart $code"
[[ "$code" == 410 ]]
status=$(curl -s -w ' HTTP %{http_code}' http://127.0.0.1:18093/status); echo "  $status"
[[ "$status" == *модернизацию*"HTTP 503" ]]
curl -fsS http://127.0.0.1:18093/metrics | grep domestic_download_ratio
echo 'PASS: the domestic registry broke the minute the foreign vendor left; it had been the vendor all along'
