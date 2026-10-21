type SoldItem = { id: string; unitPrice: string; quantity: number };
export type ReturnSelection = { orderItemId: string; quantity: number };

/** Cumulative allocation makes the last unit absorb rounding, without floating point. */
export function quoteReturn(
  items: SoldItem[],
  discount: string,
  received: Record<string, number>,
  selection: ReturnSelection[],
) {
  if (!selection.length || selection.length > items.length)
    throw Error('Invalid return selection');
  const subtotal = items.reduce(
      (sum, item) => sum + BigInt(item.unitPrice) * BigInt(item.quantity),
      0n,
    ),
    net = subtotal - BigInt(discount);
  if (net < 0n || net > subtotal) throw Error('Invalid discount snapshot');
  const selected = new Map<string, number>();
  for (const item of selection) {
    if (
      selected.has(item.orderItemId) ||
      !Number.isSafeInteger(item.quantity) ||
      item.quantity < 1
    )
      throw Error('Invalid return quantity');
    selected.set(item.orderItemId, item.quantity);
  }
  let grossPrefix = 0n,
    amount = 0n;
  const result: Array<ReturnSelection & { amount: string }> = [];
  for (const item of [...items].sort((a, b) => a.id.localeCompare(b.id))) {
    const gross = BigInt(item.unitPrice) * BigInt(item.quantity),
      lineNet =
        subtotal === 0n
          ? 0n
          : ((grossPrefix + gross) * net) / subtotal -
            (grossPrefix * net) / subtotal;
    grossPrefix += gross;
    const quantity = selected.get(item.id);
    if (quantity === undefined) continue;
    const previous = received[item.id] ?? 0;
    if (
      !Number.isSafeInteger(previous) ||
      previous < 0 ||
      quantity + previous > item.quantity
    )
      throw Error('Return exceeds sold quantity');
    const value =
      (lineNet * BigInt(previous + quantity)) / BigInt(item.quantity) -
      (lineNet * BigInt(previous)) / BigInt(item.quantity);
    result.push({ orderItemId: item.id, quantity, amount: value.toString() });
    amount += value;
    selected.delete(item.id);
  }
  if (selected.size) throw Error('Unknown order item');
  return { amount: amount.toString(), items: result };
}
