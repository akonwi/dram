#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="${TMPDIR:-/tmp}/dram-hello-smoke"
log="${TMPDIR:-/tmp}/dram-hello-smoke.log"
headers="${TMPDIR:-/tmp}/dram-hello-smoke.headers"
body="${TMPDIR:-/tmp}/dram-hello-smoke.body"

cd "$root"
ard-dev build examples/hello/main.ard --out "$binary"
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

head_size="$(curl -sS -I -o /dev/null -w '%{size_download}' http://127.0.0.1:8080/)"
[[ "$head_size" == "0" ]]

code="$(curl -sS -o "$body" -w '%{http_code}' 'http://127.0.0.1:8080/search?q=hello+world')"
[[ "$code" == "200" ]]
[[ "$(cat "$body")" == "hello world" ]]

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

echo "HTTP smoke passed"
