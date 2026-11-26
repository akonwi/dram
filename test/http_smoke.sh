#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="${TMPDIR:-/tmp}/dram-hello-smoke"
log="${TMPDIR:-/tmp}/dram-hello-smoke.log"
headers="${TMPDIR:-/tmp}/dram-hello-smoke.headers"
body="${TMPDIR:-/tmp}/dram-hello-smoke.body"

cd "$root"
ard build examples/hello/main.ard --out "$binary"
"$binary" >"$log" 2>&1 &
pid=$!
cleanup() {
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}
trap cleanup EXIT

code=""
for _ in $(seq 1 50); do
  code="$(curl -sS -D "$headers" -o "$body" -w '%{http_code}' http://127.0.0.1:8080/ 2>/dev/null || true)"
  [[ "$code" == "200" ]] && break
  sleep 0.1
done
[[ "$code" == "200" ]]
[[ "$(cat "$body")" == "Hello from Dram" ]]
[[ "$(grep -ci '^Set-Cookie:' "$headers")" == "2" ]]
grep -qi '^Set-Cookie: first=1; Path=/; HttpOnly; SameSite=Lax' "$headers"
grep -qi '^X-Content-Type-Options: nosniff' "$headers"
grep -qi '^X-Frame-Options: SAMEORIGIN' "$headers"

code="$(curl -sS -o "$body" -w '%{http_code}' -H 'Cookie: first=abc' http://127.0.0.1:8080/cookie)"
[[ "$code" == "200" ]]
[[ "$(cat "$body")" == "abc" ]]

code="$(curl -sS -D "$headers" -o "$body" -w '%{http_code}' -X POST 'http://127.0.0.1:8080/go?next=/search%3Fq%3Dok')"
[[ "$code" == "303" ]]
grep -qi '^Location: /search?q=ok' "$headers"
code="$(curl -sS -D "$headers" -o "$body" -w '%{http_code}' -X POST 'http://127.0.0.1:8080/go?next=//evil.example')"
[[ "$code" == "303" ]]
[[ "$(grep -i '^Location:' "$headers" | tr -d '\r')" == "Location: /" ]]

# Cross-origin protection is on by default.
code="$(curl -sS -o "$body" -w '%{http_code}' -X POST -H 'Sec-Fetch-Site: cross-site' -H 'Origin: https://evil.example' http://127.0.0.1:8080/go)"
[[ "$code" == "403" ]]
code="$(curl -sS -o "$body" -w '%{http_code}' -X POST -H 'Origin: http://127.0.0.1:8080' http://127.0.0.1:8080/go)"
[[ "$code" == "303" ]]
code="$(curl -sS -o "$body" -w '%{http_code}' -X POST -H 'Sec-Fetch-Site: same-origin' http://127.0.0.1:8080/go)"
[[ "$code" == "303" ]]

head_size="$(curl -sS -I -o /dev/null -w '%{size_download}' http://127.0.0.1:8080/)"
[[ "$head_size" == "0" ]]

code="$(curl -sS -o "$body" -w '%{http_code}' 'http://127.0.0.1:8080/search?q=hello+world')"
[[ "$code" == "200" ]]
[[ "$(cat "$body")" == "hello world" ]]

code="$(curl -sS -D "$headers" -o "$body" -w '%{http_code}' http://127.0.0.1:8080/json)"
[[ "$code" == "200" ]]
[[ "$(cat "$body")" == '{"message":"Hello from Dram"}' ]]
grep -qi '^Content-Type: application/json; charset=utf-8' "$headers"

code="$(curl -sS -o "$body" -w '%{http_code}' http://127.0.0.1:8080/files/images/logo.png)"
[[ "$code" == "200" ]]
[[ "$(cat "$body")" == "/images/logo.png" ]]

# A path that matches no route redirects to its other trailing-slash form.
code="$(curl -sS -D "$headers" -o "$body" -w '%{http_code}' http://127.0.0.1:8080/files)"
[[ "$code" == "308" ]]
[[ "$(grep -i '^Location:' "$headers" | tr -d '\r')" == "Location: /files/" ]]
code="$(curl -sS -D "$headers" -o "$body" -w '%{http_code}' 'http://127.0.0.1:8080/search/?q=hello+world')"
[[ "$code" == "308" ]]
[[ "$(grep -i '^Location:' "$headers" | tr -d '\r')" == "Location: /search?q=hello+world" ]]
code="$(curl -sS -L -o "$body" -w '%{http_code}' 'http://127.0.0.1:8080/search/?q=hello+world')"
[[ "$code" == "200" ]]
[[ "$(cat "$body")" == "hello world" ]]
code="$(curl -sS -D "$headers" -o "$body" -w '%{http_code}' 'http://127.0.0.1:8080//evil.example/')"
[[ "$code" == "404" ]]

code="$(curl -sS -o "$body" -w '%{http_code}' http://127.0.0.1:8080/missing)"
[[ "$code" == "404" ]]
[[ "$(cat "$body")" == "Not Found: /missing" ]]

code="$(curl -sS -D "$headers" -o "$body" -w '%{http_code}' -X PUT http://127.0.0.1:8080/hello/dram)"
[[ "$code" == "405" ]]
[[ "$(cat "$body")" == "Method Not Allowed" ]]
grep -qi '^Allow: GET, HEAD' "$headers"

code="$(curl -sS -D "$headers" -o "$body" -w '%{http_code}' -X POST --data-binary 'hello' http://127.0.0.1:8080/echo)"
[[ "$code" == "200" ]]
[[ "$(cat "$body")" == "hello" ]]
grep -qi '^Content-Type: application/octet-stream' "$headers"

code="$(curl -sS -o "$body" -w '%{http_code}' -X POST --data-binary 'too large' http://127.0.0.1:8080/echo)"
[[ "$code" == "413" ]]
[[ "$(cat "$body")" == "Payload Too Large" ]]

malformed_status="$(python3 - <<'PY'
import socket

with socket.create_connection(("127.0.0.1", 8080), timeout=5) as connection:
    connection.sendall(
        b"POST /echo HTTP/1.1\r\n"
        b"Host: 127.0.0.1\r\n"
        b"Transfer-Encoding: chunked\r\n"
        b"Connection: close\r\n\r\n"
        b"Z\r\nbad\r\n0\r\n\r\n"
    )
    response = b""
    while b"\r\n" not in response:
        response += connection.recv(4096)
    print(response.split(b"\r\n", 1)[0].decode())
PY
)"
[[ "$malformed_status" == "HTTP/1.1 400 Bad Request" ]]

DRAM_BASE_URL="http://127.0.0.1:8080" bun test test/sse_smoke.test.ts

# SIGTERM shuts down gracefully: open event streams end and listen returns.
stream_body="${TMPDIR:-/tmp}/dram-hello-smoke.stream"
curl -sS -N http://127.0.0.1:8080/events >"$stream_body" 2>/dev/null &
stream=$!
for _ in $(seq 1 50); do
  grep -q 'message 1' "$stream_body" && break
  sleep 0.1
done
grep -q 'message 1' "$stream_body"
kill -TERM "$pid"
for _ in $(seq 1 50); do
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "$pid" 2>/dev/null; then
  echo "server did not stop within 5s of SIGTERM" >&2
  exit 1
fi
exit_status=0
wait "$pid" || exit_status=$?
[[ "$exit_status" == "0" ]]
wait "$stream" || true
rm -f "$stream_body"

echo "HTTP smoke passed"
