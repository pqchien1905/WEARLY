import { ConfigService } from '@nestjs/config';
import { mailTransportOptions } from '../src/modules/mail/mail-transport';
describe('bounded mail transport', () => {
  it('uses explicit local SMTP without file/URL loading or transport debug logs', () => {
    expect(
      mailTransportOptions(
        new ConfigService({
          SMTP_HOST: '127.0.0.1',
          SMTP_PORT: 1025,
          SMTP_SECURE: 'false',
          SMTP_ALLOW_INSECURE_LOCAL: 'true',
          SMTP_USER: '',
        }),
      ),
    ).toMatchObject({
      host: '127.0.0.1',
      port: 1025,
      secure: false,
      ignoreTLS: true,
      requireTLS: false,
      connectionTimeout: 10000,
      greetingTimeout: 10000,
      socketTimeout: 15000,
      logger: false,
      debug: false,
      disableFileAccess: true,
      disableUrlAccess: true,
    });
  });
  it('retains TLS requirements for existing secured SMTP configurations', () => {
    expect(
      mailTransportOptions(
        new ConfigService({
          SMTP_HOST: 'smtp.example.test',
          SMTP_PORT: 587,
          SMTP_SECURE: 'false',
          SMTP_ALLOW_INSECURE_LOCAL: 'false',
          SMTP_USER: 'user',
          SMTP_PASSWORD: 'test-secret',
        }),
      ),
    ).toMatchObject({
      ignoreTLS: false,
      requireTLS: true,
      auth: { user: 'user', pass: 'test-secret' },
    });
  });
});
