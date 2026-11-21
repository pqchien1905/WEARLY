// Apply the customer's requested wording to the exact rows prepared for them.
// UUIDs, order/payment states, totals and inventory remain unchanged.
const { localDatabase } = require('./seed-customer-account.cjs');
(async () => {
  const email = process.argv[2];
  if (!email) throw Error('Pass the existing customer email');
  const db = localDatabase();
  try {
    const result = await db.$transaction(async tx => {
      const user = await tx.user.findUniqueOrThrow({ where: { email } });
      const orders = await tx.order.findMany({ where: { userId: user.id, idempotencyKey: { startsWith: 'account-sample-v1-' } }, include: { shipment: true, items: { include: { variant: true } } } });
      const notes = { PENDING: 'Đơn hàng đã được tiếp nhận.', CONFIRMED: 'Cửa hàng đã xác nhận và chuẩn bị sản phẩm.', SHIPPED: 'Đơn hàng đã được bàn giao để vận chuyển.', DELIVERED: 'Đơn hàng đã được giao đến người nhận.' };
      for (const order of orders) {
        for (const [status, note] of Object.entries(notes)) await tx.orderEvent.updateMany({ where: { orderId: order.id, status, note: 'Dữ liệu mẫu để kiểm thử tài khoản; không phải giao dịch hoặc vận chuyển thực tế.' }, data: { note } });
        if (order.shipment) for (const [status, note] of Object.entries({ IN_TRANSIT: 'Đơn hàng đang trên đường đến địa chỉ nhận.', DELIVERED: 'Đã hoàn tất giao hàng.' })) {
          await tx.shipmentEvent.updateMany({ where: { shipmentId: order.shipment.id, status, note: 'Mốc giao hàng minh họa trong dữ liệu mẫu.' }, data: { note } });
        }
        if (order.status === 'DELIVERED') for (const item of order.items) {
          await tx.review.updateMany({ where: { userId: user.id, productId: item.variant.productId, comment: 'Dữ liệu mẫu: đánh giá minh họa để kiểm thử hiển thị, chỉnh sửa và xóa. Đây không phải trải nghiệm mua hàng thực tế.' }, data: { comment: 'Thiết kế thanh lịch, dễ phối cùng các trang phục hằng ngày.' } });
        }
      }
      await tx.address.updateMany({ where: { userId: user.id, label: 'Văn phòng (dữ liệu mẫu)', address: 'Tầng 2, Tòa nhà mẫu, đường Nguyễn Văn Cừ, Vinh (địa chỉ minh họa)' }, data: { label: 'Văn phòng', address: 'Tầng 2, đường Nguyễn Văn Cừ, Vinh' } });
      return { email, orders: orders.map(o => ({ id: o.id, code: o.code, status: o.status })) };
    });
    console.log(JSON.stringify(result, null, 2));
  } finally { await db.$disconnect(); }
})().catch(e => { console.error(e.code || e.message); process.exitCode = 1; });
