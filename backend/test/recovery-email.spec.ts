import { recoveryEmail } from '../src/modules/recovery/recovery-email';

describe('Wearly recovery email', () => {
  it('renders a copyable leading-zero code in plain text and HTML without a secret URL', () => {
    const mail = recoveryEmail(
      'https://shop.example.com/#/reset-password',
      '012345',
    );
    expect(mail.text).toContain('Mã xác nhận: 012345');
    expect(mail.html).toContain('>012345</p>');
    expect(mail.html).toContain('lang="vi"');
    expect(mail.html).toContain('https://shop.example.com/#/forgot-password');
    expect(mail.text).toContain('10 phút');
    expect(mail.html).not.toMatch(/token=|<script|<img/);
    expect(mail.subject).not.toContain('012345');
    expect(() => recoveryEmail('https://shop.example.com', '<bad>')).toThrow(
      'INVALID_RECOVERY_CODE',
    );
  });
  it('sends a password-change notice without a code or password', () => {
    const mail = recoveryEmail('https://shop.example.com/#/reset-password');
    expect(mail.subject).toBe('WEARLY — Mật khẩu đã thay đổi');
    expect(mail.html).toContain('Các phiên đăng nhập cũ đã được thu hồi');
    expect(mail.html).not.toContain('MÃ XÁC NHẬN CỦA BẠN');
  });
});
