import { Prisma } from '../../generated/prisma/client';
import { fail } from '../../common/errors';

// Keep the existing phone field and allow an empty contact number. A Vietnamese
// international prefix and its domestic equivalent identify the same number.
export function normalizePhone(value: string): string {
  const phone = value.replace(/[\s().-]/g, '').replace(/^00/, '+');
  return phone.replace(/^\+84/, '0').replace(/^84(?=\d{9}$)/, '0');
}

export async function lockProfileIdentity(tx: Prisma.TransactionClient) {
  // Both administrative edits and self-service profile edits take this lock.
  // Serializable retries also protect against a snapshot taken before waiting.
  await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtextextended('user-profile-identity',0))::text`;
}

export async function assertPhoneAvailable(
  tx: Prisma.TransactionClient,
  id: string,
  phone: string,
) {
  if (!phone) return;
  const matches = await tx.$queryRaw<{ id: string }[]>`
    SELECT id FROM "User"
    WHERE id <> ${id}::uuid AND
      regexp_replace(regexp_replace(regexp_replace(regexp_replace(phone, '[[:space:]().-]', '', 'g'), '^00', '+'), '^\\+84', '0'), '^84([0-9]{9})$', '0\\1') = ${phone}
    LIMIT 1`;
  if (matches.length)
    fail(
      409,
      'PHONE_ALREADY_EXISTS',
      'Số điện thoại đã được tài khoản khác sử dụng.',
    );
}
