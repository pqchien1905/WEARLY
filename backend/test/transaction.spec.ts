import { transaction } from '../src/common/transaction';
import { PrismaService } from '../src/database/prisma.service';
import { Prisma } from '../src/generated/prisma/client';
const conflict = () =>
  Object.assign(new Error('TransactionWriteConflict'), {
    name: 'DriverAdapterError',
    cause: { kind: 'TransactionWriteConflict', originalCode: '40001' },
  });
describe('Transaction retry boundary', () => {
  it('retries raw-query conflicts wrapped by Prisma P2010, but not other raw SQL errors', async () => {
    const wrapped = new Prisma.PrismaClientKnownRequestError('Raw query failed', {
      code: 'P2010', clientVersion: 'test', meta: { driverAdapterError: conflict() },
    });
    const run = jest.fn().mockRejectedValueOnce(wrapped).mockResolvedValueOnce('committed');
    await expect(transaction({ $transaction: run } as unknown as PrismaService, async () => 'unused')).resolves.toBe('committed');
    const invalid = new Prisma.PrismaClientKnownRequestError('Invalid SQL', { code: 'P2010', clientVersion: 'test' });
    run.mockReset().mockRejectedValue(invalid);
    await expect(transaction({ $transaction: run } as unknown as PrismaService, async () => 'unused')).rejects.toBe(invalid);
    expect(run).toHaveBeenCalledTimes(1);
  });
  it('retries a raw pg adapter serialization conflict and returns only the committed attempt', async () => {
    const run = jest
      .fn()
      .mockRejectedValueOnce(conflict())
      .mockResolvedValueOnce('committed');
    const db = { $transaction: run } as unknown as PrismaService;
    await expect(transaction(db, async () => 'unused')).resolves.toBe(
      'committed',
    );
    expect(run).toHaveBeenCalledTimes(2);
  });
  it('bounds conflict retries and never retries unknown driver failures', async () => {
    const error = conflict();
    const run = jest.fn().mockRejectedValue(error);
    await expect(
      transaction(
        { $transaction: run } as unknown as PrismaService,
        async () => 1,
      ),
    ).rejects.toBe(error);
    expect(run).toHaveBeenCalledTimes(5);
    const unknown = Object.assign(new Error('connection failed'), {
      name: 'DriverAdapterError',
      cause: { kind: 'ConnectionClosed' },
    });
    run.mockReset().mockRejectedValue(unknown);
    await expect(
      transaction(
        { $transaction: run } as unknown as PrismaService,
        async () => 1,
      ),
    ).rejects.toBe(unknown);
    expect(run).toHaveBeenCalledTimes(1);
  });
});
