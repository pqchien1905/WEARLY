# Wearly password recovery

Extends `MASTER.md` with the implemented Wearly tokens in
`frontend/lib/core/design/tokens.dart` as the source of truth.

## Layout and visual tokens

- Desktop: bordered card, maximum width 1120px; soft plum editorial panel and
  white form panel; switch to a single column below 860px of available width.
- Form: maximum width 480px, 40px desktop / 24px mobile inner padding, 6px radius.
- Colors: `T.surface`, `T.soft`, `T.ink`, `T.muted`, `T.accent`, `T.line`,
  `T.danger`, `T.success`. Component aliases live in `_RecoveryStyle`.
- Typography: existing Manrope headings and Be Vietnam Pro body; form body 16px.
- Email: 560px responsive table, matching primitive → semantic → component
  tokens, inline styles, Arial fallback, selectable six-digit code in monospace.
  Plain text alternative contains the same instructions.

## Form states and interactions

| State | Main action | Secondary action / feedback |
|---|---|---|
| Email | Gửi mã xác nhận | Tôi đã có mã xác nhận; validate email before continuing |
| Code | Xác nhận mã | Change email; resend disabled with 60-second countdown |
| Password | Lưu mật khẩu mới | Reveal each password; confirm match, 12–128 characters |
| Success | Đăng nhập | Explain that old sessions were revoked |
| Uncertain reset response | Đăng nhập | Request a new code; discard the previous grant |

Keep all three steps on `/forgot-password`. Show progress with numbers/checks
and text, not color alone. Announce errors and completion with live semantics.
Disable actions and fields during requests. Preserve keyboard navigation,
visible focus and standard copy/paste. The code is one input with numeric
keyboard and one-time-code autofill; accept leading zeroes and pasted digits.
Focus moves to the code/password field on transition. Do not auto-submit codes.

Generic send feedback must not reveal whether an email is registered. Expired,
wrong or used codes offer retry/resend. A code lasts 10 minutes and permits five
failed guesses. Tokens remain in memory only, never URL or browser storage.

## Verification

- Flutter widget tests cover 375px / 1280px widths, validation, paste, leading
  zeroes, errors, resend countdown, change-email and complete recovery.
- Real Chrome integration covers SMTP delivery to an isolated local test server,
  code verification, 375px password form, login, reuse rejection and reload.
- Inspect both HTML email and form at mobile/desktop sizes when changing tokens.
