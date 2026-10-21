import { ConfigService } from '@nestjs/config';
import { GeminiClient } from '../src/integrations/ai-providers/gemini.client';

const answer = (text = '{"message":"hello","skus":["SKU-1"]}') => ({
  status: 'completed',
  steps: [{ type: 'model_output', content: [{ type: 'text', text }] }],
  usage: { total_input_tokens: 44, total_output_tokens: 22 },
});
describe('Bounded stateless Gemini transport', () => {
  const settings = () =>
    new ConfigService({
      GEMINI_API_KEY: 'private-fixture-key',
      GEMINI_STYLIST_MODEL: 'gemini-3.5-flash-lite',
    });
  it('uses the official endpoint, private header, stateless JSON schema and measured usage', async () => {
    const send = jest.fn(async () => Response.json(answer()));
    const client = new GeminiClient(settings(), send);
    const schema = { type: 'object' };
    expect(
      await client.generateJson('catalog and preferences', schema),
    ).toEqual({
      value: { message: 'hello', skus: ['SKU-1'] },
      inputTokens: 44,
      outputTokens: 22,
    });
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
    expect(JSON.parse(options.body as string)).toMatchObject({
      model: 'gemini-3.5-flash-lite',
      store: false,
      background: false,
      response_format: { type: 'text', mime_type: 'application/json', schema },
      generation_config: { max_output_tokens: 2048 },
    });
    expect(send).toHaveBeenCalledTimes(1);
  });
  it('does not call an unconfigured provider', async () => {
    const send = jest.fn();
    const client = new GeminiClient(
      new ConfigService({ GEMINI_API_KEY: '' }),
      send,
    );
    expect(client.configured).toBe(false);
    await expect(client.generateJson('private input', {})).rejects.toThrow(
      'AI_PROVIDER_NOT_CONFIGURED',
    );
    expect(send).not.toHaveBeenCalled();
  });
  it.each([
    { status: 'incomplete', steps: [] },
    answer('not JSON'),
    {
      status: 'completed',
      steps: [{ type: 'thought', content: [{ type: 'text', text: '{}' }] }],
    },
  ])('rejects unusable output without leaking body', async (body) => {
    const client = new GeminiClient(settings(), async () =>
      Response.json(body),
    );
    await expect(client.generateJson('private input', {})).rejects.toThrow(
      'INVALID_PROVIDER_OUTPUT',
    );
  });
  it('caps response bytes and never retries or exposes provider errors', async () => {
    for (const response of [
      new Response('x'.repeat(1024 * 1024 + 1), {
        headers: { 'content-type': 'application/json' },
      }),
      new Response('private-input-and-key', { status: 503 }),
      new Response(null, {
        status: 302,
        headers: { location: 'https://elsewhere.test' },
      }),
    ]) {
      const send = jest.fn(async () => response);
      const client = new GeminiClient(settings(), send);
      await expect(client.generateJson('private input', {})).rejects.toThrow(
        /^(INVALID_PROVIDER_OUTPUT|AI_PROVIDER_UNAVAILABLE)$/,
      );
      expect(send).toHaveBeenCalledTimes(1);
    }
  });
  it('times out while streaming and cancels the response body', async () => {
    jest.useFakeTimers();
    const cancel = jest.fn();
    const body = new ReadableStream<Uint8Array>({
      start(c) {
        c.enqueue(new TextEncoder().encode('{'));
      },
      cancel,
    });
    const client = new GeminiClient(
      settings(),
      async () =>
        new Response(body, { headers: { 'content-type': 'application/json' } }),
    );
    try {
      const pending = expect(
        client.generateJson('private input', {}),
      ).rejects.toThrow('PROVIDER_TIMEOUT');
      await jest.advanceTimersByTimeAsync(20001);
      await pending;
      expect(cancel).toHaveBeenCalled();
    } finally {
      jest.useRealTimers();
    }
  });
});
