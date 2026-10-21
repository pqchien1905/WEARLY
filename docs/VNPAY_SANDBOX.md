# VNPay sandbox on localhost

This integration only uses VNPay's sandbox endpoints. COD remains available when
VNPay is disabled. A browser return is never proof of payment.

Add your own sandbox values to `backend/.env` (never commit or send the secret):

```dotenv
VNPAY_ENABLED=true
VNPAY_TMN_CODE=YOURCODE
VNPAY_HASH_SECRET=your-sandbox-hash-secret
VNPAY_RETURN_URL=http://localhost:3000/api/v1/payments/vnpay/return
VNPAY_WEB_RETURN_URL=http://localhost:5173/#/payments/return
```

TmnCode must contain exactly eight letters/digits. Use the actual API and browser
ports. The storefront origin must also appear in `CORS_ORIGINS`. Restart the API
after editing configuration. Missing/invalid configuration fails startup when
explicitly enabled; leave `VNPAY_ENABLED=false` until credentials are ready.
Credentials belong only to the API; never put them in Flutter build arguments.

1. Sign in, add products, choose a saved address and **VNPay sandbox** at checkout.
2. On the order page, choose **Chuẩn bị thanh toán**, then **Mở VNPay sandbox
   (tab mới)**. The original storefront tab retains its session.
3. Complete a sandbox payment with VNPay's published test flow. Return to the
   original tab and choose **Kiểm tra kết quả**. On localhost this sends an
   authenticated `querydr` request because VNPay cannot call your loopback IPN.
4. The order is eligible for fulfillment only after verified payment. If the
   storefront tab was closed, sign in again and open the order history.

Payment links last 15 minutes. Repeated preparation reuses the pending attempt.
An expired attempt must be verified before retry/cancel; a signed not-found query
after expiry closes it. Query requests are limited to one per attempt per ten
seconds. Unavailable/invalid provider replies preserve the unresolved payment.
The VND amount is an integer, up to 9,999,999,999 VND for this sandbox adapter.

For a publicly reachable test API, configure the merchant IPN URL as
`/api/v1/payments/vnpay/ipn`. Both IPN and query replies verify signatures, merchant,
reference, amount and transaction status. Duplicate notifications are idempotent.
Late success on a cancelled order and a second successful attempt are retained
and flagged **CẦN KIỂM TRA** in admin order details. They never deduct or restore
stock again. Refund operations are a subsequent implementation milestone.

Verification: `node tools/test-frontend-api.cjs --payments` runs real Chrome and
PostgreSQL with a dedicated `_test` database and independently signed local
provider fixtures. It intercepts the sandbox tab and makes no real provider
request. This proves the local application flow, not acceptance of merchant keys.
Real provider acceptance still requires configured credentials and observed
sandbox responses. Gemini credentials are independent of this payment setup.

Official references:
- [Payment and IPN](https://sandbox.vnpayment.vn/apis/docs/thanh-toan-pay/pay.html)
- [Query and refund protocol](https://sandbox.vnpayment.vn/apis/docs/truy-van-hoan-tien/querydr%26refund.html)
