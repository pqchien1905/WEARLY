export const GEMINI_HTTP = Symbol('GEMINI_HTTP');
export const record = (value: unknown): Record<string, unknown> =>
  value !== null && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
export const tokenCount = (value: unknown) =>
  typeof value === 'number' &&
  Number.isSafeInteger(value) &&
  value >= 0 &&
  value <= 2147483647
    ? value
    : null;
export function modelContent(data: Record<string, unknown>) {
  if (data.status !== 'completed' || !Array.isArray(data.steps))
    throw new Error('INVALID_PROVIDER_OUTPUT');
  return data.steps.flatMap((step) => {
    const s = record(step);
    return s.type === 'model_output' && Array.isArray(s.content)
      ? s.content.map(record)
      : [];
  });
}
// No retries, arbitrary URLs, provider error bodies or persistent interactions.
export async function geminiInteraction(
  send: typeof fetch,
  key: string,
  body: Record<string, unknown>,
  limits: {
    timeoutMs: number;
    maxBytes: number;
    signal?: AbortSignal;
    apiVersion?: 'v1' | 'v1beta';
  },
): Promise<Record<string, unknown>> {
  if (!key.trim()) throw new Error('AI_PROVIDER_NOT_CONFIGURED');
  if (limits.signal?.aborted) throw new Error('PROVIDER_ABORTED');
  const controller = new AbortController();
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  let timer: NodeJS.Timeout | undefined;
  let abort: (() => void) | undefined;
  const cancel = () => {
    controller.abort();
    void reader?.cancel().catch(() => undefined);
  };
  try {
    return await Promise.race([
      (async () => {
        const response = await send(
          `https://generativelanguage.googleapis.com/${limits.apiVersion === 'v1beta' ? 'v1beta' : 'v1'}/interactions`,
          {
            method: 'POST',
            redirect: 'error',
            signal: controller.signal,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': key,
            },
            body: JSON.stringify({ ...body, store: false, background: false }),
          },
        );
        if (controller.signal.aborted) {
          void response.body?.cancel().catch(() => undefined);
          throw new Error('PROVIDER_ABORTED');
        }
        if (!response.ok) {
          void response.body?.cancel().catch(() => undefined);
          throw new Error(
            response.status === 429
              ? 'AI_PROVIDER_RATE_LIMIT'
              : [401, 403].includes(response.status)
                ? 'AI_PROVIDER_AUTH'
                : 'AI_PROVIDER_UNAVAILABLE',
          );
        }
        if (
          !response.headers.get('content-type')?.includes('application/json') ||
          !response.body ||
          Number(response.headers.get('content-length')) > limits.maxBytes
        ) {
          void response.body?.cancel().catch(() => undefined);
          throw new Error('INVALID_PROVIDER_OUTPUT');
        }
        reader = response.body.getReader();
        const chunks: Uint8Array[] = [];
        let size = 0;
        for (;;) {
          const item = await reader.read();
          if (item.done) break;
          size += item.value.byteLength;
          if (size > limits.maxBytes)
            throw new Error('INVALID_PROVIDER_OUTPUT');
          chunks.push(item.value);
        }
        try {
          return record(JSON.parse(Buffer.concat(chunks).toString('utf8')));
        } catch {
          throw new Error('INVALID_PROVIDER_OUTPUT');
        }
      })(),
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => {
          reject(new Error('PROVIDER_TIMEOUT'));
          cancel();
        }, limits.timeoutMs);
        abort = () => {
          reject(new Error('PROVIDER_ABORTED'));
          cancel();
        };
        limits.signal?.addEventListener('abort', abort, { once: true });
        if (limits.signal?.aborted) abort();
      }),
    ]);
  } catch (error) {
    const safe = [
      'INVALID_PROVIDER_OUTPUT',
      'AI_PROVIDER_RATE_LIMIT',
      'AI_PROVIDER_AUTH',
      'AI_PROVIDER_UNAVAILABLE',
      'PROVIDER_TIMEOUT',
      'PROVIDER_ABORTED',
    ];
    throw new Error(
      error instanceof Error && safe.includes(error.message)
        ? error.message
        : 'AI_PROVIDER_UNAVAILABLE',
    );
  } finally {
    if (timer) clearTimeout(timer);
    if (abort) limits.signal?.removeEventListener('abort', abort);
    cancel();
  }
}
