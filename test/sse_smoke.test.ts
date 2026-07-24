import { expect, test } from "bun:test";

const baseUrl = process.env.DRAM_BASE_URL ?? "http://127.0.0.1:8080";

async function waitForActiveStreams(expected: string): Promise<void> {
  for (let attempt = 0; attempt < 300; attempt += 1) {
    const response = await fetch(`${baseUrl}/events/active`);
    if ((await response.text()) === expected) {
      return;
    }
    await Bun.sleep(10);
  }
  throw new Error(`active SSE stream count did not become ${expected}`);
}

async function readEvents(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  count: number,
): Promise<string[]> {
  const decoder = new TextDecoder();
  let received = "";

  while (received.split("\n\n").length - 1 < count) {
    const chunk = await Promise.race([
      reader.read(),
      Bun.sleep(2_000).then(() => {
        throw new Error("timed out waiting for a flushed SSE event");
      }),
    ]);

    if (chunk.done) {
      throw new Error(`SSE response ended before ${count} events arrived`);
    }
    received += decoder.decode(chunk.value, { stream: true });
  }

  return received
    .split("\n\n")
    .slice(0, count)
    .map(event => `${event}\n\n`);
}

test("SSE flushes an event and observes client disconnect", async () => {
  const controller = new AbortController();
  const response = await fetch(`${baseUrl}/events`, {
    headers: { Accept: "text/event-stream" },
    signal: controller.signal,
  });

  expect(response.status).toBe(200);
  expect(response.headers.get("content-type")).toBe("text/event-stream");
  expect(response.headers.get("cache-control")).toBe("no-cache");
  expect(response.headers.get("content-length")).toBeNull();

  const reader = response.body?.getReader();
  if (!reader) {
    throw new Error("SSE response had no readable body");
  }

  try {
    expect(await readEvents(reader, 2)).toEqual([
      "event: message\nid: 1\ndata: message 1\n\n",
      "event: message\nid: 2\ndata: message 2\n\n",
    ]);
    await waitForActiveStreams("1");
  } finally {
    controller.abort();
    await reader.cancel().catch(() => {});
  }
  await waitForActiveStreams("0");

  const health = await fetch(`${baseUrl}/`);
  expect(health.status).toBe(200);
  expect(await health.text()).toBe("Hello from Dram");
});

test("a post-commit panic aborts the SSE response", async () => {
  const response = await fetch(`${baseUrl}/events/panic`, {
    headers: { Accept: "text/event-stream" },
  });
  expect(response.status).toBe(200);

  const reader = response.body?.getReader();
  if (!reader) {
    throw new Error("SSE response had no readable body");
  }

  expect(await readEvents(reader, 1)).toEqual(["data: visible\n\n"]);

  const outcome = await Promise.race([
    reader.read().then(
      result => ({ kind: "result" as const, result }),
      () => ({ kind: "error" as const }),
    ),
    Bun.sleep(2_000).then(() => ({ kind: "timeout" as const })),
  ]);
  expect(outcome.kind).toBe("error");
});
