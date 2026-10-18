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
