import { RECOVERY_CODE_MINUTES } from './recovery.policy';

// Wearly primitives mirror frontend/lib/core/design/tokens.dart. Inline styles
// keep these semantic tokens compatible with Gmail and Outlook email rendering.
const primitive = {
  white: '#FFFFFF',
  canvas: '#F7F8F7',
  ink: '#252329',
  muted: '#67636A',
  plum: '#65394D',
  rose: '#ECE5E9',
  line: '#DFDCE0',
  green: '#286047',
};
const theme = {
  background: primitive.canvas,
  surface: primitive.white,
  text: primitive.ink,
  secondaryText: primitive.muted,
  accent: primitive.plum,
  accentSurface: primitive.rose,
  border: primitive.line,
  success: primitive.green,
};
const emailTokens = {
  width: 560,
  radius: 6,
  font: 'Arial, Helvetica, sans-serif',
};
const escapeHtml = (value: string) =>
  value.replace(
    /[&<>"']/g,
    (c) =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[
        c
      ]!,
  );

export function recoveryEmail(recoveryUrl: string, code?: string) {
  if (code !== undefined && !/^\d{6}$/.test(code))
    throw Error('INVALID_RECOVERY_CODE');
  const url = new URL(recoveryUrl);
  url.hash = '/forgot-password';
  const href = escapeHtml(url.toString());
  const title = code ? 'Trở lại với Wearly.' : 'Mật khẩu đã được cập nhật.';
  const subject = code
    ? 'WEARLY — Mã xác nhận khôi phục mật khẩu'
    : 'WEARLY — Mật khẩu đã thay đổi';
  const description = code
    ? 'Dùng mã xác nhận bên dưới để tiếp tục đặt lại mật khẩu của bạn.'
    : 'Bạn đã đặt lại mật khẩu thành công. Hãy đăng nhập bằng mật khẩu mới để tiếp tục khám phá tủ đồ của mình.';
  const text = code
    ? `Mã xác nhận: ${code}\n\nNhập mã này tại trang Quên mật khẩu Wearly. Mã dùng một lần, có hiệu lực ${RECOVERY_CODE_MINUTES} phút. Khi yêu cầu mã mới, hãy dùng mã trong email mới nhất.\n\n${url}\n\nNếu bạn không yêu cầu, hãy bỏ qua email này. Không chia sẻ mã với bất kỳ ai.`
    : 'Mật khẩu Wearly của bạn đã thay đổi. Các phiên đăng nhập cũ đã được thu hồi. Nếu bạn không thực hiện, hãy dùng chức năng Quên mật khẩu để lấy lại quyền truy cập.';
  const content = code
    ? `<div style="margin:28px 0;padding:24px 12px;background:${theme.accentSurface};border:1px solid ${theme.border};border-radius:${emailTokens.radius}px;text-align:center">
        <p style="margin:0 0 12px;color:${theme.accent};font-size:12px;font-weight:bold;letter-spacing:1.5px">MÃ XÁC NHẬN CỦA BẠN</p>
        <p style="margin:0;color:${theme.accent};font-family:'Courier New',monospace;font-size:36px;font-weight:bold;letter-spacing:10px;line-height:1.4">${code}</p>
        <p style="margin:12px 0 0;font-size:13px;color:${theme.secondaryText}">Có hiệu lực trong <strong>${RECOVERY_CODE_MINUTES} phút</strong> · Chỉ dùng một lần</p>
      </div>
      <p style="margin:0 0 24px;font-size:14px;line-height:1.7;color:${theme.secondaryText}">Quay lại trang Quên mật khẩu, nhập đủ 6 số rồi chọn mật khẩu mới. Nếu đã yêu cầu gửi lại, hãy sử dụng mã trong email mới nhất.</p>
      <table role="presentation" cellspacing="0" cellpadding="0" style="width:100%"><tr><td align="center" bgcolor="${theme.text}" style="border-radius:${emailTokens.radius}px"><a href="${href}" style="display:block;padding:16px 20px;color:${theme.surface};font-size:15px;font-weight:bold;text-decoration:none">Mở trang khôi phục mật khẩu &rarr;</a></td></tr></table>`
    : `<div style="margin:28px 0;padding:20px;background:${theme.background};border-left:3px solid ${theme.success};color:${theme.text};font-size:14px;line-height:1.7">Các phiên đăng nhập cũ đã được thu hồi để bảo vệ tài khoản của bạn.</div>`;
  return {
    subject,
    text,
    html: `<!doctype html>
<html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><title>${title}</title></head>
<body style="margin:0;padding:0;background:${theme.background};font-family:${emailTokens.font};color:${theme.text}">
<div style="display:none;max-height:0;overflow:hidden">${code ? `Mã xác nhận khôi phục tài khoản Wearly, có hiệu lực ${RECOVERY_CODE_MINUTES} phút.` : 'Xác nhận thay đổi mật khẩu tài khoản Wearly.'}</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" bgcolor="${theme.background}"><tr><td align="center" style="padding:32px 16px">
<table role="presentation" width="${emailTokens.width}" cellspacing="0" cellpadding="0" style="width:100%;max-width:${emailTokens.width}px">
<tr><td style="padding:0 0 24px;font-size:24px;font-weight:bold;letter-spacing:5px;color:${theme.text}">WEARLY<span style="color:${theme.accent}">.</span></td></tr>
<tr><td bgcolor="${theme.surface}" style="padding:32px 24px;border:1px solid ${theme.border};border-top:3px solid ${theme.accent};border-radius:${emailTokens.radius}px">
<p style="margin:0 0 16px;color:${theme.accent};font-size:11px;font-weight:bold;letter-spacing:2px">TÀI KHOẢN CỦA BẠN</p>
<h1 style="margin:0 0 16px;font-size:28px;font-weight:normal;line-height:1.3;letter-spacing:-.6px">${title}</h1>
<p style="margin:0;font-size:15px;line-height:1.7;color:${theme.secondaryText}">${description}</p>
${content}
<p style="margin:24px 0 0;padding-top:20px;border-top:1px solid ${theme.border};font-size:12px;line-height:1.7;color:${theme.secondaryText}">${code ? 'Không chia sẻ mã với bất kỳ ai. Nếu bạn không yêu cầu đặt lại mật khẩu, bạn có thể bỏ qua email này.' : 'Nếu bạn không thực hiện thay đổi này, hãy yêu cầu mã khôi phục mới trên website Wearly.'}</p>
</td></tr>
<tr><td style="padding:24px 8px;font-size:12px;line-height:1.7;color:${theme.secondaryText};text-align:center">Phong cách riêng. Một nơi để trở về.<br>Email tự động từ Wearly — vui lòng không trả lời.</td></tr>
</table></td></tr></table></body></html>`,
  };
}
