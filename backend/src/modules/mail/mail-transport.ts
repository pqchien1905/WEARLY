import { ConfigService } from '@nestjs/config';
/** Shared transport restrictions; message bodies are always plain text. */
export function mailTransportOptions(config: ConfigService) {
  const insecure = config.get<string>('SMTP_ALLOW_INSECURE_LOCAL') === 'true',
    user = config.get<string>('SMTP_USER');
  return {
    host: config.getOrThrow<string>('SMTP_HOST'),
    port: config.getOrThrow<number>('SMTP_PORT'),
    secure: config.get<string>('SMTP_SECURE') === 'true',
    requireTLS: !insecure,
    ignoreTLS: insecure,
    auth: user
      ? { user, pass: config.getOrThrow<string>('SMTP_PASSWORD') }
      : undefined,
    connectionTimeout: 10000,
    greetingTimeout: 10000,
    socketTimeout: 15000,
    logger: false as const,
    debug: false,
    disableFileAccess: true,
    disableUrlAccess: true,
  };
}
