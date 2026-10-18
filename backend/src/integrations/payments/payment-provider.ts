export interface PaymentProvider {
  readonly name: string;
  createIntent(input: {
    orderId: string;
    amount: string;
    currency: 'VND';
  }): Promise<{ status: 'PENDING'; reference?: string; redirectUrl?: string }>;
  verifyWebhook(
    payload: Buffer,
    signature: string,
  ): Promise<{
    eventId: string;
    orderId: string;
    amount: string;
    status: 'PAID' | 'FAILED';
  }>;
}
// COD orders persist Payment(PENDING). No online gateway or fabricated paid response is enabled.
