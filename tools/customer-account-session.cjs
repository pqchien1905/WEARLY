// Local operator-only QA session. No password change and no application bypass
// endpoint: the API still authenticates its normal short-lived browser session.
const { createHash, randomBytes, randomUUID } = require('node:crypto');
const { localDatabase } = require('./seed-customer-account.cjs');
async function customerSession(email) {
  const db = localDatabase();
  const user = await db.user.findUnique({ where: { email } });
  if (!user?.active || user.role !== 'CUSTOMER') { await db.$disconnect(); throw Error('Existing active customer required'); }
  const token = randomBytes(32).toString('base64url');
  const session = await db.refreshToken.create({ data: {
    userId: user.id, familyId: randomUUID(), browserScope: 'customer',
    tokenHash: createHash('sha256').update(token).digest('hex'),
    expiresAt: new Date(Date.now() + 3600000),
  } });
  const origin = 'http://localhost:5173';
  const base = 'http://localhost:3000/api/v1';
  let closed = false;
  async function close() {
    if (closed) return;
    closed = true;
    try { await db.refreshToken.deleteMany({ where: { id: session.id, userId: user.id } }); }
    finally { await db.$disconnect(); }
  }
  try {
    const response = await fetch(base + '/auth/browser/customer/refresh', {
      method: 'POST', headers: { Origin: origin, 'X-Wearly-Browser': '1', Cookie: `wearly_customer_session=${token}` },
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) throw Error(`QA session restore failed (${response.status})`);
    const auth = await response.json();
    async function request(route, { method = 'GET', body, headers = {}, expected = 200 } = {}) {
      const result = await fetch(base + '/' + route, {
        method, headers: { Authorization: `Bearer ${auth.accessToken}`, ...(body && !(body instanceof FormData) ? { 'Content-Type': 'application/json' } : {}), ...headers },
        body: body instanceof FormData ? body : body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(120000),
      });
      const value = await result.json().catch(() => null);
      if (result.status !== expected) throw Error(`${method} ${route}: expected ${expected}, received ${result.status} (${value?.error?.code || 'unexpected response'})`);
      return value;
    }
    return { db, user: { id:user.id,email:user.email,name:user.name,phone:user.phone }, request, close, base, origin,
      cookie: { name: 'wearly_customer_session', value: token, domain: 'localhost', path: '/api/v1/auth/browser/customer', httpOnly: true, secure: false, sameSite: 'Strict', expires: Math.floor(Date.now()/1000)+3600 } };
  } catch (error) { await close(); throw error; }
}
// Verification scripts act on a real local customer account. Pass its email as
// the first argument or set WEARLY_CUSTOMER_EMAIL; nothing is hardcoded.
function customerEmail(argument = process.argv[2]) {
  const email = (argument || process.env.WEARLY_CUSTOMER_EMAIL || '').trim();
  if (!email) {
    console.error('Set WEARLY_CUSTOMER_EMAIL or pass the customer email as the first argument.');
    process.exit(2);
  }
  return email;
}

module.exports = { customerSession, customerEmail };
