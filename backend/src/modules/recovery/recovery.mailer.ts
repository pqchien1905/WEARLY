import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as nodemailer from 'nodemailer';
import { mailTransportOptions } from '../mail/mail-transport';
import { recoveryEmail } from './recovery-email';
@Injectable()
export class RecoveryMailer implements OnModuleDestroy {
  private transport?: nodemailer.Transporter;
  constructor(private readonly config: ConfigService) {}
  async send(to: string, code?: string) {
    if (!this.transport) {
      this.transport = nodemailer.createTransport(
        mailTransportOptions(this.config),
      );
    }
    const message = recoveryEmail(
      this.config.getOrThrow<string>('PASSWORD_RESET_WEB_URL'),
      code,
    );
    try {
      await this.transport.sendMail({
        from: this.config.getOrThrow<string>('SMTP_FROM'),
        to,
        ...message,
      });
    } catch {
      // Never persist SMTP response text, recipient addresses or links in BullMQ.
      throw new Error('MAIL_DELIVERY_FAILED');
    }
  }
  onModuleDestroy() {
    this.transport?.close();
  }
}
