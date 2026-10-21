import { ConfigService } from '@nestjs/config';
import { createConnection, Socket } from 'node:net';
import * as nodemailer from 'nodemailer';
import type SMTPTransport from 'nodemailer/lib/smtp-transport';
import { mailTransportOptions } from './mail-transport';

/** Own the TCP socket so timeout/shutdown cancels IO, not just the waiting promise. */
export function sendLocalMail(
  config: ConfigService,
  message: { to: string; subject: string; text: string; messageId: string },
  signal: AbortSignal,
): Promise<void> {
  return new Promise((resolve, reject) => {
    let socket: Socket | undefined,
      transport: nodemailer.Transporter | undefined = undefined,
      finished = false;
    const timeoutMs = Math.max(
      100,
      Math.min(60000, config.get<number>('LOCAL_MAIL_TIMEOUT_MS') ?? 30000),
    );
    const finish = (failed: boolean) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      signal.removeEventListener('abort', cancel);
      socket?.destroy();
      transport?.close();
      if (failed) reject(new Error('MAIL_DELIVERY_FAILED'));
      else resolve();
    };
    const cancel = () => finish(true),
      timer = setTimeout(cancel, timeoutMs);
    signal.addEventListener('abort', cancel, { once: true });
    if (signal.aborted) {
      cancel();
      return;
    }
    const options: SMTPTransport.Options = {
      ...mailTransportOptions(config),
      getSocket(_options, callback) {
        if (finished) {
          callback(new Error('MAIL_CANCELLED'), {});
          return;
        }
        const current = createConnection({
          host: config.getOrThrow<string>('SMTP_HOST'),
          port: config.getOrThrow<number>('SMTP_PORT'),
        });
        socket = current;
        let handedOff = false;
        current.once('connect', () => {
          if (finished) {
            current.destroy();
            return;
          }
          handedOff = true;
          callback(null, { connection: current });
        });
        current.on('error', () => {
          if (!handedOff) {
            handedOff = true;
            callback(new Error('MAIL_CONNECTION_FAILED'), {});
          }
        });
      },
    };
    transport = nodemailer.createTransport(options);
    void transport
      .sendMail({ from: config.getOrThrow<string>('SMTP_FROM'), ...message })
      .then(
        () => finish(false),
        () => finish(true),
      );
  });
}
