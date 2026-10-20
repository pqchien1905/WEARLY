export const RECOVERY_QUEUE = 'wearly-password-recovery';
export type RecoveryJob =
  | { kind: 'request'; email: string; requestedAt: string }
  | { kind: 'changed'; userId: string };
