import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as nodemailer from 'nodemailer';
import { mailTransportOptions } from '../mail/mail-transport';
@Injectable()
export class RecoveryMailer implements OnModuleDestroy {
  private transport?: nodemailer.Transporter;
  constructor(private readonly config: ConfigService) {}
  async send(to: string, token?: string) {
    if (!this.transport) {
      this.transport = nodemailer.createTransport(
        mailTransportOptions(this.config),
      );
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
