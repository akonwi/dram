# Dram AI Chat

A small multi-turn chat application that streams OpenAI output through Dram's SSE response API. The server uses the official [`openai-go`](https://github.com/openai/openai-go) SDK and hardcodes `gpt-4o-mini`. The no-build frontend uses [Mica](https://akonwi.io/mica/) from its CDN.

## Run

From the Dram repository root:

```sh
export OPENAI_API_KEY="your-key"
ard run examples/ai-chat/main.ard
```

Open <http://127.0.0.1:8080>. The API key is the only application configuration required.

The browser sends `POST /chat` requests and incrementally consumes SSE `delta`, `done`, and `error` events. Completed OpenAI response IDs are sent back with the next message to preserve conversation context. **Clear** starts a new conversation chain, while **Stop** cancels both the browser stream and the upstream OpenAI request.

## Structure

- `main.ard` — Dram routes and SSE delivery.
- `ffi/openai.go` — a narrow Ard-friendly adapter around the OpenAI SDK stream.
- `ffi/web/index.html` — the embedded chat UI.

Run the adapter tests with:

```sh
cd examples/ai-chat
go test ./...
```
