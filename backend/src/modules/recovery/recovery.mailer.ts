import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as nodemailer from 'nodemailer';
@Injectable()
export class RecoveryMailer implements OnModuleDestroy {
  private transport?: nodemailer.Transporter;
  constructor(private readonly config: ConfigService) {}
  async send(to: string, token?: string) {
    if (!this.transport) {
      const insecure =
        this.config.get<string>('SMTP_ALLOW_INSECURE_LOCAL') === 'true';
      const user = this.config.get<string>('SMTP_USER');
      this.transport = nodemailer.createTransport({
        host: this.config.getOrThrow<string>('SMTP_HOST'),
        port: this.config.getOrThrow<number>('SMTP_PORT'),
        secure: this.config.get<string>('SMTP_SECURE') === 'true',
        requireTLS: !insecure,
        ignoreTLS: insecure,
        auth: user
          ? { user, pass: this.config.getOrThrow<string>('SMTP_PASSWORD') }
          : undefined,
        connectionTimeout: 10000,
        greetingTimeout: 10000,
        socketTimeout: 15000,
        logger: false,
        debug: false,
        disableFileAccess: true,
        disableUrlAccess: true,
      });
    }
    const link = token
      ? this.config.getOrThrow<string>('PASSWORD_RESET_WEB_URL') +
        '?token=' +
        encodeURIComponent(token)
      : '';
    try {
      await this.transport.sendMail({
        from: this.config.getOrThrow<string>('SMTP_FROM'),
        to,
        subject: token
          ? 'WEARLY — Đặt lại mật khẩu'
          : 'WEARLY — Mật khẩu đã thay đổi',
        text: token
          ? `Bạn đã yêu cầu đặt lại mật khẩu WEARLY.\n\n${link}\n\nLiên kết dùng một lần, hết hạn sau 15 phút. Nếu không yêu cầu, bạn có thể bỏ qua thư này. Không chia sẻ liên kết.`
          : 'Mật khẩu WEARLY của bạn đã thay đổi. Tất cả phiên đăng nhập đã được thu hồi. Nếu bạn không thực hiện, hãy dùng chức năng Quên mật khẩu trên website để lấy lại quyền truy cập.',
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
