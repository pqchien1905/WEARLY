import { auditSnapshot } from '../src/modules/admin/audit-snapshot';
import { Prisma } from '../src/generated/prisma/client';
describe('Safe administrative audit snapshots', () => {
  it('only retains action-specific scalar state, never personal content or credentials', () => {
    expect(
      auditSnapshot('SUPPORT_REPLIED', {
        status: 'ANSWERED',
        version: 2,
        email: 'private@example.test',
        name: 'Private',
        message: 'secret message',
        token: 'reset-secret',
        addressSnapshot: { phone: '123' },
        amount: '999',
      }),
    ).toEqual({ status: 'ANSWERED', version: 2 });
    expect(
      auditSnapshot('STAFF_UPDATED', {
        role: 'SUPPORT',
        active: true,
        staffVersion: 3,
        passwordHash: 'secret',
        phone: '123',
        email: 'private@example.test',
      }),
    ).toEqual({ role: 'SUPPORT', active: true, staffVersion: 3 });
  });
  it('preserves exact money and dates while dropping invalid or nested scalars', () => {
    const date = new Date('2026-10-22T00:00:00Z');
    expect(
      auditSnapshot('PROMOTION_UPDATED', {
        amount: new Prisma.Decimal('99999999999999'),
        maxDiscount: null,
        startsAt: date,
        active: true,
        version: 2,
        nested: { amount: 'secret' },
      }),
    ).toEqual({
      amount: '99999999999999',
      maxDiscount: null,
      startsAt: date.toISOString(),
      active: true,
      version: 2,
    });
    expect(
      auditSnapshot('ORDER_STATUS_CHANGED', {
        status: { secret: 'x' },
        version: NaN,
      }),
    ).toEqual({});
    expect(
      auditSnapshot('ORDER_STATUS_CHANGED', {
        status: 'x'.repeat(121),
        version: Infinity,
      }),
    ).toEqual({});
    expect(auditSnapshot('ORDER_STATUS_CHANGED', null)).toEqual({});
  });
  it('does not copy taxonomy text, public image paths or historical missing details', () => {
    expect(
      auditSnapshot('CATEGORY_RENAMED', {
        name: 'not retained',
        slug: 'not-retained',
      }),
    ).toEqual({});
    expect(
      auditSnapshot('PRODUCT_IMAGE_UPLOADED', {
        url: 'private/path',
        objectKey: 'secret',
      }),
    ).toEqual({});
    expect(auditSnapshot('PRODUCT_UPDATED', undefined)).toEqual({});
  });
});
