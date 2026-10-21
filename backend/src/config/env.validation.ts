import { z } from 'zod';
const secret = z
  .string()
  .min(32)
  .refine((s) => !s.startsWith('replace-'), 'Replace placeholder secrets');
const schema = z
  .object({
    NODE_ENV: z
      .enum(['development', 'test', 'production'])
      .default('development'),
    PORT: z.coerce.number().int().min(1).max(65535).default(3000),
    DATABASE_URL: z
      .string()
      .url()
      .refine(
        (s) => s.startsWith('postgresql://') || s.startsWith('postgres://'),
      ),
    REDIS_HOST: z.string().default('localhost'),
    REDIS_PORT: z.coerce.number().int().min(1).max(65535).default(6379),
    AI_QUEUE_PREFIX: z
      .string()
      .regex(/^[a-zA-Z0-9_-]{1,100}$/)
      .default('wearly'),
    JWT_ACCESS_SECRET: secret,
    JWT_REFRESH_SECRET: secret,
    JWT_ACCESS_EXPIRES_IN: z.coerce
      .number()
      .int()
      .min(60)
      .max(3600)
      .default(900),
    JWT_REFRESH_EXPIRES_IN: z.coerce
      .number()
      .int()
      .min(300)
      .max(2592000)
      .default(604800),
    CORS_ORIGINS: z
      .string()
      .min(1)
      .refine((s) =>
        s.split(',').every((v) => {
          try {
            const u = new URL(v.trim());
            return (
              ['http:', 'https:'].includes(u.protocol) && u.origin === v.trim()
            );
          } catch {
            return false;
          }
        }),
      ),
    SWAGGER_ENABLED: z.enum(['true', 'false']).default('true'),
    S3_ENDPOINT: z
      .url({ protocol: /^https?$/ })
      .default('http://localhost:9000'),
    S3_PUBLIC_ENDPOINT: z
      .union([z.url({ protocol: /^https?$/ }), z.literal('')])
      .default(''),
    S3_REGION: z.string().default('us-east-1'),
    S3_BUCKET: z.string().default('wearly-private'),
    S3_ACCESS_KEY_ID: z.string().default(''),
    S3_SECRET_ACCESS_KEY: z.string().default(''),
    AI_PROVIDER_URL: z.string().default(''),
    AI_PROVIDER_API_KEY: z.string().default(''),
    VNPAY_ENABLED: z.enum(['true', 'false']).default('false'),
    VNPAY_TMN_CODE: z.string().default(''),
    VNPAY_HASH_SECRET: z.string().default(''),
    VNPAY_RETURN_URL: z.string().default(''),
    VNPAY_WEB_RETURN_URL: z.string().default(''),
    PASSWORD_RECOVERY_ENABLED: z.enum(['true', 'false']).default('false'),
    SMTP_HOST: z.string().default(''),
    SMTP_PORT: z.coerce.number().int().min(1).max(65535).default(587),
    SMTP_SECURE: z.enum(['true', 'false']).default('false'),
    SMTP_USER: z.string().default(''),
    SMTP_PASSWORD: z.string().default(''),
    SMTP_FROM: z.string().default(''),
    SMTP_ALLOW_INSECURE_LOCAL: z.enum(['true', 'false']).default('false'),
    PASSWORD_RESET_WEB_URL: z.string().default(''),
  })
  .superRefine((c, ctx) => {
    if (c.VNPAY_ENABLED !== 'true') return;
    const fail = (path: string) =>
      ctx.addIssue({
        code: 'custom',
        path: [path],
        message: 'Invalid VNPay sandbox configuration',
      });
    if (!/^[a-zA-Z0-9]{8}$/.test(c.VNPAY_TMN_CODE)) fail('VNPAY_TMN_CODE');
    if (
      c.VNPAY_HASH_SECRET.length < 16 ||
      c.VNPAY_HASH_SECRET.startsWith('replace-')
    )
      fail('VNPAY_HASH_SECRET');
    for (const key of ['VNPAY_RETURN_URL', 'VNPAY_WEB_RETURN_URL'] as const) {
      try {
        const url = new URL(c[key]);
        const local = ['localhost', '127.0.0.1', '[::1]'].includes(
          url.hostname,
        );
        if (
          url.username ||
          url.password ||
          url.search ||
          !(
            url.protocol === 'https:' ||
            (url.protocol === 'http:' && local && c.NODE_ENV !== 'production')
          )
        )
          fail(key);
        if (key === 'VNPAY_RETURN_URL') {
          if (url.pathname !== '/api/v1/payments/vnpay/return' || url.hash)
            fail(key);
        } else if (
          url.hash !== '#/payments/return' ||
          !c.CORS_ORIGINS.split(',')
            .map((s) => s.trim())
            .includes(url.origin)
        )
          fail(key);
      } catch {
        fail(key);
      }
    }
  })
  .superRefine((c, ctx) => {
    if (c.PASSWORD_RECOVERY_ENABLED !== 'true') return;
    const fail = (path: string) =>
      ctx.addIssue({
        code: 'custom',
        path: [path],
        message: 'Invalid password recovery configuration',
      });
    const local = (host: string) =>
      ['localhost', '127.0.0.1', '[::1]', '::1'].includes(host);
    if (!c.SMTP_HOST || /[\s/@]/.test(c.SMTP_HOST)) fail('SMTP_HOST');
    if (!z.email().safeParse(c.SMTP_FROM).success) fail('SMTP_FROM');
    if (Boolean(c.SMTP_USER) !== Boolean(c.SMTP_PASSWORD)) fail('SMTP_USER');
    if (
      c.SMTP_ALLOW_INSECURE_LOCAL === 'true' &&
      (c.NODE_ENV === 'production' || !local(c.SMTP_HOST))
    )
      fail('SMTP_ALLOW_INSECURE_LOCAL');
    try {
      const url = new URL(c.PASSWORD_RESET_WEB_URL);
      if (
        url.username ||
        url.password ||
        url.search ||
        url.hash !== '#/reset-password' ||
        !c.CORS_ORIGINS.split(',')
          .map((s) => s.trim())
          .includes(url.origin) ||
        (url.protocol !== 'https:' &&
          !(
            url.protocol === 'http:' &&
            local(url.hostname) &&
            c.NODE_ENV !== 'production'
          ))
      )
        fail('PASSWORD_RESET_WEB_URL');
    } catch {
      fail('PASSWORD_RESET_WEB_URL');
    }
  })
  .refine(
    (c) => c.JWT_ACCESS_SECRET !== c.JWT_REFRESH_SECRET,
    'Use separate JWT secrets',
  );
export function validateEnv(input: Record<string, unknown>) {
  const result = schema.safeParse(input);
  if (!result.success)
    throw new Error(
      'Invalid environment: ' +
        result.error.issues
          .map((i) => i.path.join('.') + ': ' + i.message)
          .join('; '),
    );
  return result.data;
}
