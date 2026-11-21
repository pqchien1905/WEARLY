import { Prisma } from '../../generated/prisma/client';
export async function enqueueMail(
  tx: Prisma.TransactionClient,
  data: {
    eventKey: string;
    recipient: string;
    subject: string;
    body: string;
    orderId?: string;
    supportId?: string;
    replyId?: string;
  },
) {
  return tx.mailOutbox.upsert({
    where: { eventKey: data.eventKey },
    create: data,
    update: {},
  });
}
export async function queueOrderMail(
  tx: Prisma.TransactionClient,
  orderId: string,
  eventKey: string,
  subject: string,
  detail: string,
) {
  const order = await tx.order.findUniqueOrThrow({
    where: { id: orderId },
    select: { code: true, user: { select: { email: true } } },
  });
  return enqueueMail(tx, {
    orderId,
    eventKey,
    recipient: order.user.email,
    subject: 'WEARLY — ' + subject,
    body: `Mã đơn hàng: ${order.code}\n\n${detail}\n\nXem chi tiết trong mục Đơn hàng của tài khoản WEARLY.`,
  });
}
const orderNotices = {
  PENDING: [
    'Đã tiếp nhận đơn hàng',
    'Đã tiếp nhận đơn hàng. Thanh toán sẽ được ghi nhận sau khi có xác nhận thu tiền.',
  ],
  CONFIRMED: [
    'Đơn hàng đã xác nhận',
    'Đơn hàng đã được xác nhận và đang chuẩn bị.',
  ],
  SHIPPED: [
    'Đơn hàng đang giao',
    'Đơn hàng đã được bàn giao vận chuyển. Bạn có thể xem mã theo dõi trong chi tiết đơn.',
  ],
  DELIVERED: [
    'Đơn hàng đã giao',
    'Đơn hàng đã được giao. Thu tiền và hoàn tiền được xác nhận riêng.',
  ],
  CANCELLED: [
    'Đơn hàng đã hủy',
    'Đơn hàng đã được hủy. Nếu đã thu tiền, việc hoàn tiền được xử lý và xác nhận riêng.',
  ],
  RETURNED: [
    'Kiện hàng đã trả về',
    'Đơn vị vận chuyển đã trả kiện hàng. Hoàn tiền được xử lý và xác nhận riêng.',
  ],
};
export function queueOrderStatus(
  tx: Prisma.TransactionClient,
  id: string,
  status: keyof typeof orderNotices,
  version: number,
) {
  const [subject, detail] = orderNotices[status];
  return queueOrderMail(tx, id, `order:${id}:${version}`, subject, detail);
}
