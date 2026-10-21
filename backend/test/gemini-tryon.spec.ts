import { ConfigService } from '@nestjs/config';
import { GeminiTryOnProvider } from '../src/integrations/ai-providers/gemini-tryon.provider';

const config = () =>
  new ConfigService({
    GEMINI_API_KEY: 'private-fixture-key',
    GEMINI_TRYON_MODEL: 'gemini-nano-banana-2.1',
  });
const input = () => ({
  jobId: 'job',
  sku: 'SKU',
  signal: new AbortController().signal,
  image: {
    bytes: Buffer.from('private-person'),
    contentType: 'image/jpeg' as const,
  },
  garment: {
    bytes: Buffer.from('private-garment'),
    contentType: 'image/png' as const,
  },
});
const answer = (
  part: object = {
    type: 'image',
    mime_type: 'image/jpeg',
    data: Buffer.from([255, 216, 255, 1]).toString('base64'),
  },
) => ({
  status: 'completed',
  steps: [{ type: 'model_output', content: [part] }],
  usage: { total_input_tokens: 123, total_output_tokens: 456 },
});
describe('Private Gemini image transport', () => {
  it('sends only two inline images and fixed instructions to a stateless bounded endpoint', async () => {
    const send = jest.fn(async () => Response.json(answer()));
    const provider = new GeminiTryOnProvider(config(), send);
    const result = await provider.generate(input());
    expect(result).toMatchObject({
      contentType: 'image/jpeg',
      inputTokens: 123,
      outputTokens: 456,
    });
    expect(Buffer.from(result.bytes)).toEqual(Buffer.from([255, 216, 255, 1]));
    const [url, options] = (
      send.mock.calls as unknown as [string, RequestInit][]
    )[0];
    expect(url).toBe(
      'https://generativelanguage.googleapis.com/v1/interactions',
    );
    expect(options.redirect).toBe('error');
    expect(options.headers).toMatchObject({
      'x-goog-api-key': 'private-fixture-key',
    });
    const body = JSON.parse(options.body as string);
    expect(body).toMatchObject({
      model: 'gemini-nano-banana-2.1',
      store: false,
      background: false,
      response_format: {
        type: 'image',
        mime_type: 'image/jpeg',
        delivery: 'inline',
        image_size: '1K',
        aspect_ratio: '3:4',
      },
    });
    expect(
      body.input.filter((p: { type: string }) => p.type === 'image'),
    ).toEqual([
      {
        type: 'image',
        mime_type: 'image/jpeg',
        data: Buffer.from('private-person').toString('base64'),
      },
      {
        type: 'image',
        mime_type: 'image/png',
        data: Buffer.from('private-garment').toString('base64'),
      },
    ]);
    expect(body.tools).toBeUndefined();
    expect(body.previous_interaction_id).toBeUndefined();
    expect(send).toHaveBeenCalledTimes(1);
  });
  it('does not send unconfigured or already aborted work', async () => {
    const send = jest.fn();
    const absent = new GeminiTryOnProvider(
      new ConfigService({ GEMINI_API_KEY: '' }),
      send,
    );
    expect(absent.enabled).toBe(false);
    await expect(absent.generate(input())).rejects.toThrow(
      'AI_PROVIDER_NOT_CONFIGURED',
    );
    const controller = new AbortController();
    controller.abort();
    await expect(
      new GeminiTryOnProvider(config(), send).generate({
        ...input(),
        signal: controller.signal,
      }),
    ).rejects.toThrow('PROVIDER_ABORTED');
    expect(send).not.toHaveBeenCalled();
  });
  it.each([
    { type: 'image', mime_type: 'image/jpeg', data: 'not base64!' },
    { type: 'image', mime_type: 'image/gif', data: 'YWJj' },
    {
      type: 'image',
      mime_type: 'image/jpeg',
      uri: 'https://untrusted.test/private',
    },
    { type: 'text', text: 'private input echo' },
    {
      type: 'image',
      mime_type: 'image/jpeg',
      data: Buffer.alloc(8 * 1024 * 1024 + 1).toString('base64'),
    },
  ])('rejects invalid output without fetching an output URL', async (part) => {
    const send = jest.fn(async () => Response.json(answer(part)));
    await expect(
      new GeminiTryOnProvider(config(), send).generate(input()),
    ).rejects.toThrow('INVALID_PROVIDER_OUTPUT');
    expect(send).toHaveBeenCalledTimes(1);
  });
  it('caps actual streaming bytes as well as a declared length', async () => {
    for (const response of [
      new Response('x'.repeat(16 * 1024 * 1024 + 1), {
        headers: { 'content-type': 'application/json' },
      }),
      new Response('{}', {
        headers: {
          'content-type': 'application/json',
          'content-length': String(16 * 1024 * 1024 + 1),
        },
      }),
      Response.json({ status: 'incomplete', steps: [] }),
    ]) {
      await expect(
        new GeminiTryOnProvider(config(), async () => response).generate(
          input(),
        ),
      ).rejects.toThrow('INVALID_PROVIDER_OUTPUT');
    }
  });
  it.each([
    [429, 'AI_PROVIDER_RATE_LIMIT'],
    [401, 'AI_PROVIDER_AUTH'],
    [503, 'AI_PROVIDER_UNAVAILABLE'],
    [302, 'AI_PROVIDER_UNAVAILABLE'],
  ])('sanitizes HTTP %s without retry', async (status, code) => {
    const send = jest.fn(
      async () =>
        new Response('private person/key', { status: Number(status) }),
    );
    await expect(
      new GeminiTryOnProvider(config(), send).generate(input()),
    ).rejects.toThrow(String(code));
    expect(send).toHaveBeenCalledTimes(1);
  });
  it('bounds a slow stream to90s and cancels body', async () => {
    jest.useFakeTimers();
    const cancel = jest.fn();
    const body = new ReadableStream<Uint8Array>({
      start(c) {
        c.enqueue(Buffer.from('{'));
      },
      cancel,
    });
    try {
      const pending = expect(
        new GeminiTryOnProvider(
          config(),
          async () =>
            new Response(body, {
              headers: { 'content-type': 'application/json' },
            }),
        ).generate(input()),
      ).rejects.toThrow('PROVIDER_TIMEOUT');
      await jest.advanceTimersByTimeAsync(90001);
      await pending;
      expect(cancel).toHaveBeenCalled();
    } finally {
      jest.useRealTimers();
    }
  });
  it('cancels an in-flight body when the worker aborts', async () => {
    const controller = new AbortController(),
      cancel = jest.fn();
    const body = new ReadableStream<Uint8Array>({
      start(c) {
        c.enqueue(Buffer.from('{'));
      },
      cancel,
    });
    const pending = expect(
      new GeminiTryOnProvider(
        config(),
        async () =>
          new Response(body, {
            headers: { 'content-type': 'application/json' },
          }),
      ).generate({ ...input(), signal: controller.signal }),
    ).rejects.toThrow('PROVIDER_ABORTED');
    await new Promise((resolve) => setImmediate(resolve));
    controller.abort();
    await pending;
    expect(cancel).toHaveBeenCalled();
  });
});
