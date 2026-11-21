// Local Chrome/API/PostgreSQL acceptance. Own fixtures only; no checkout or mail.
const fs = require("node:fs"),
  path = require("node:path"),
  assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { chromium } = require("../.tools/browser/node_modules/playwright");
const argon2 = require("../backend/node_modules/argon2");
const { localDatabase } = require("./seed-customer-account.cjs");
const base = process.env.ADMIN_TEST_BASE || "http://localhost:8080";
if (!/^http:\/\/localhost:(8080|5173)$/.test(base))
  throw Error("Local frontend required");
const output = path.resolve(__dirname, "../.tools/inventory-acceptance");
(async () => {
  fs.mkdirSync(output, { recursive: true });
  const db = localDatabase(),
    report = { passed: [], errors: [], unexpectedResponses: [] },
    variants = [];
  let browser,
    page,
    staff,
    warehouse,
    category,
    brand,
    product,
    order,
    allowConflict = false;
  const marker = "inventory-qa-" + randomUUID().slice(0, 8),
    password = randomUUID() + "-Aa1";
  try {
    const passwordHash = await argon2.hash(password);
    staff = await db.user.create({
      data: {
        username: marker,
        email: marker + "@example.invalid",
        name: "Quản trị kiểm thử kho",
        role: "ADMIN",
        passwordHash,
      },
    });
    warehouse = await db.user.create({
      data: {
        username: marker + "-warehouse",
        email: marker + "-warehouse@example.invalid",
        name: "Nhân viên kho kiểm thử",
        role: "WAREHOUSE",
        passwordHash,
      },
    });
    category = await db.category.create({
      data: { slug: marker, name: "Danh mục kho " + marker },
    });
    brand = await db.brand.create({ data: { slug: marker, name: marker } });
    product = await db.product.create({
      data: {
        slug: marker,
        name: "Áo linen kiểm tra kho " + marker,
        description: "Fixture riêng của kiểm thử",
        material: "Linen",
        style: "Casual",
        active: false,
        categoryId: category.id,
        brandId: brand.id,
        images: { create: { url: "assets/images/shirt.jpg", alt: "Áo linen" } },
      },
    });
    for (let i = 0; i < 23; i++)
      variants.push(
        await db.productVariant.create({
          data: {
            productId: product.id,
            sku: marker + "-" + String(i).padStart(2, "0"),
            size: String(i),
            color: "Trắng",
            colorHex: "#ffffff",
            price: "500000",
            active: i !== 20,
            ...(i < 22 ? { inventory: { create: { quantity: i } } } : {}),
          },
          include: { inventory: true },
        }),
      );
    browser = await chromium.launch({
      executablePath: "C:/Program Files/Google/Chrome/Application/chrome.exe",
      headless: true,
      args: ["--host-resolver-rules=MAP localhost 127.0.0.1"],
    });
    const context = await browser.newContext({
      viewport: { width: 1440, height: 1050 },
      timezoneId: "Asia/Bangkok",
      reducedMotion: "reduce",
    });
    page = await context.newPage();
    page.setDefaultTimeout(18000);
    page.on("pageerror", (e) => report.errors.push(e.message));
    page.on("console", (m) => {
      if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text()))
        report.errors.push(m.text());
    });
    page.on("response", (r) => {
      if (
        /\/api\/v1\/admin\//.test(r.url()) &&
        r.status() >= 400 &&
        !(allowConflict && r.status() === 409)
      )
        report.unexpectedResponses.push({
          path: new URL(r.url()).pathname,
          status: r.status(),
        });
    });
    const snapshot = () => page.locator("body").ariaSnapshot(),
      button = (name) =>
        page.getByRole("button", { name, exact: typeof name === "string" });
    const passed = (text) => {
      report.passed.push(text);
      console.log(text);
    };
    async function contains(text) {
      for (let i = 0; i < 150; i++) {
        if ((await snapshot()).includes(text)) return;
        await page.waitForTimeout(100);
      }
      throw Error("Missing UI: " + text);
    }
    async function semantics() {
      await page.waitForFunction(() =>
        document.querySelector("flt-semantics-placeholder,flt-semantics"),
      );
      await page.evaluate(() =>
        document.querySelector("flt-semantics-placeholder")?.click(),
      );
    }
    async function reveal(node) {
      await node.waitFor({ state: "attached" });
      for (let i = 0; i < 70; i++) {
        const box = await node.boundingBox(),
          v = page.viewportSize();
        if (box && box.y >= 85 && box.y + box.height < v.height - 20) return;
        await page.mouse.move(v.width * 0.8, v.height * 0.7);
        await page.mouse.wheel(0, box?.y < 85 ? -500 : 500);
        await page.waitForTimeout(80);
      }
      throw Error("Control outside viewport: " + node);
    }
    async function click(name) {
      const node = button(name);
      await reveal(node);
      await node.click();
      await page.waitForTimeout(200);
    }
    async function fill(label, value) {
      const node = page.getByRole("textbox", { name: new RegExp("^" + label) });
      await reveal(node);
      await node.click();
      await page.waitForTimeout(100);
      await node.fill(value);
      await page.waitForTimeout(120);
    }
    async function select(label, option) {
      const node = button(new RegExp("^" + label)).last();
      await reveal(node);
      await node.click();
      await page.getByRole("menuitem", { name: option, exact: true }).click();
      await page.waitForTimeout(250);
    }
    async function action(name) {
      const node = button("Thao tác kho").first();
      await reveal(node);
      await node.click();
      await page.getByRole("menuitem", { name, exact: true }).click();
      await page.waitForTimeout(200);
    }
    async function route(target, text) {
      await page.evaluate((v) => (location.hash = "#" + v), target);
      await page.waitForTimeout(300);
      await contains(text);
    }
    async function capture(name) {
      await page.mouse.move(page.viewportSize().width * 0.75, 500);
      await page.mouse.wheel(0, -20000);
      await page.waitForTimeout(300);
      await page.screenshot({ path: path.join(output, name + ".png") });
      fs.writeFileSync(path.join(output, name + ".txt"), await snapshot());
    }
    async function login(username) {
      await fill("Tên đăng nhập", username);
      await fill("Mật khẩu", password);
      await click("Đăng nhập quản trị");
    }
    const inv = variants[3].inventory;
    const read = () =>
      db.inventory.findUniqueOrThrow({ where: { id: inv.id } });
    await page.goto(base + "/#/admin/inventory");
    await semantics();
    await contains("Đăng nhập quản trị");
    await login(marker);
    await contains("Tìm kiếm kho hàng");
    await fill("Tìm kiếm kho hàng", marker);
    await click("Áp dụng");
    await contains("22 SKU phù hợp bộ lọc");
    await contains("231 đơn vị khả dụng trong kết quả");
    await click("Trang sau");
    await contains("Trang 2/2");
    await page.reload();
    await semantics();
    await contains("Trang 2/2");
    await select("Sắp xếp", "Tồn kho ít đến nhiều");
    await select("Danh mục", category.name);
    await select("Tồn kho", "Hết hàng (0)");
    await contains("1 SKU phù hợp bộ lọc");
    await select("Tồn kho", "Sắp hết (1–5)");
    await contains("5 SKU phù hợp bộ lọc");
    await select("Tồn kho", "Tất cả tồn kho");
    await fill("Số lượng từ", "2");
    await fill("Số lượng đến", "4");
    await click("Áp dụng");
    await contains("3 SKU phù hợp bộ lọc");
    await fill("Số lượng đến", "1");
    await click("Áp dụng");
    await contains("Số lượng đến phải lớn hơn hoặc bằng số lượng từ.");
    await click("Xóa bộ lọc");
    await fill("Tìm kiếm kho hàng", marker);
    await click("Áp dụng");
    await select("Trạng thái kinh doanh", "Sản phẩm hoặc SKU đã ẩn");
    await contains("22 SKU phù hợp bộ lọc");
    passed(
      "Real login; search, category, visibility, quantity filters, validation, sorting, pagination and reload",
    );
    await route("/admin/inventory/" + inv.id, "Chi tiết tồn kho");
    await contains("3 đơn vị khả dụng");
    await click("Nhập kho");
    await fill("Số lượng nhập", "5");
    await fill("Lý do", "Nhập kho kiểm thử");
    await contains("Trước: 3 → Sau: 8");
    await click("Lưu thay đổi");
    await contains("8 đơn vị khả dụng");
    assert.equal((await read()).quantity, 8);
    await action("Xuất kho");
    await fill("Số lượng xuất", "9");
    await fill("Lý do", "Xuất kho kiểm thử");
    await click("Lưu thay đổi");
    await contains("Tồn kho không thể âm.");
    assert.equal((await read()).quantity, 8);
    await fill("Số lượng xuất", "2");
    await click("Lưu thay đổi");
    await contains("6 đơn vị khả dụng");
    await action("Kiểm kê tồn kho");
    await fill("Số lượng kiểm kê", "4");
    await fill("Lý do", "Kiểm kê thực tế");
    await click("Lưu thay đổi");
    await contains("4 đơn vị khả dụng");
    const changes = await db.inventoryMovement.findMany({
      where: { inventoryId: inv.id },
      orderBy: { createdAt: "asc" },
    });
    assert.deepEqual(
      changes.map((m) => m.delta),
      [5, -2, -2],
    );
    assert.equal((await read()).version, 3);
    await contains("Quản trị kiểm thử kho");
    await contains("Trước: 6 → Sau: 4");
    await contains("Tăng 5");
    await contains("Giảm 4");
    const auditRows = await db.adminAuditEvent.findMany({
      where: { targetId: inv.id, action: "INVENTORY_ADJUSTED" },
      orderBy: { createdAt: "asc" },
    });
    assert.deepEqual(auditRows.map(a => a.details.after.operation), ["in", "out", "count"]);
    await select("Loại biến động", "Giảm kho");
    await contains("2 bản ghi");
    await fill("Từ ngày", "2026-02-30");
    await click("Lọc lịch sử");
    await contains("Nhập ngày YYYY-MM-DD hợp lệ.");
    await click("Xóa bộ lọc lịch sử");
    passed(
      "Import/export/count persist exact deltas and versions; negative stock blocked; linked actor and before/after balances; history filters",
    );
    await click("Xem sản phẩm");
    await contains("Chi tiết sản phẩm");
    await contains("232 đơn vị trong toàn bộ kho");
    await db.product.update({
      where: { id: product.id },
      data: { active: true },
    });
    const publicProduct = await (
      await fetch("http://localhost:3000/api/v1/products/" + product.slug)
    ).json();
    assert.equal(
      publicProduct.variants.find((v) => v.id === variants[3].id).available,
      4,
    );
    // An order fixture for navigation only; no mail/outbox/payment gateway is invoked.
    order = await db.order.create({
      data: {
        userId: staff.id,
        idempotencyKey: randomUUID(),
        requestHash: marker,
        addressSnapshot: {
          recipient: "Khách kiểm thử",
          phone: "0900000000",
          address: "Địa chỉ thử",
        },
        subtotal: "500000",
        shipping: "0",
        total: "500000",
        items: {
          create: {
            variantId: variants[3].id,
            name: product.name,
            sku: variants[3].sku,
            slug: product.slug,
            size: "3",
            color: "Trắng",
            image: "assets/images/shirt.jpg",
            unitPrice: "500000",
            quantity: 1,
          },
        },
        payment: { create: { provider: "cod", amount: "500000" } },
      },
    });
    await db.$transaction(async (tx) => {
      await tx.inventory.update({
        where: { id: inv.id },
        data: { quantity: { decrement: 1 }, version: { increment: 1 } },
      });
      await tx.inventoryMovement.create({
        data: {
          inventoryId: inv.id,
          delta: -1,
          reason: "ORDER",
          orderId: order.id,
        },
      });
    });
    await route("/admin/inventory/" + inv.id, "Chi tiết tồn kho");
    await contains("3 đơn vị khả dụng");
    await click("Đơn " + order.code);
    await contains(order.code);
    await contains(product.name);
    passed(
      "Inventory agrees with product details/public catalog; order-linked movement navigates to original order",
    );
    await route(
      "/admin/inventory?record=missing&q=" + marker,
      "Tìm kiếm kho hàng",
    );
    await contains("1 SKU chưa có bản ghi kho");
    await action("Khởi tạo kho 0");
    await contains("Việc này không nhập thêm hàng.");
    await click("Lưu thay đổi");
    await contains("Không còn SKU cần khởi tạo");
    assert.equal(
      (
        await db.inventory.findUniqueOrThrow({
          where: { variantId: variants[22].id },
        })
      ).quantity,
      0,
    );
    await route("/admin/inventory/" + inv.id, "Chi tiết tồn kho");
    await action("Nhập kho");
    await fill("Số lượng nhập", "2");
    await fill("Lý do", "Phiên cũ");
    await db.$transaction(async (tx) => {
      await tx.inventory.update({
        where: { id: inv.id },
        data: { quantity: { increment: 1 }, version: { increment: 1 } },
      });
      await tx.inventoryMovement.create({
        data: { inventoryId: inv.id, delta: 1, reason: "QA_OTHER_SESSION" },
      });
    });
    allowConflict = true;
    await click("Lưu thay đổi");
    await contains("Dữ liệu đã thay đổi");
    await click("Tải lại dữ liệu");
    await contains("4 đơn vị khả dụng");
    allowConflict = false;
    assert.equal((await read()).quantity, 4);
    for (const width of [1440, 768, 375]) {
      await page.setViewportSize({ width, height: 1050 });
      await route("/admin/inventory?q=" + marker, "Tìm kiếm kho hàng");
      await contains("23 SKU phù hợp bộ lọc");
      await capture("inventory-" + width);
      await route("/admin/inventory/" + inv.id, "Chi tiết tồn kho");
      await capture("inventory-detail-" + width);
      await action("Nhập kho");
      await page.screenshot({
        path: path.join(output, "inventory-adjust-" + width + ".png"),
      });
      await click("Đóng");
    }
    await page.setViewportSize({ width: 1440, height: 1050 });
    await (async()=>{await page.getByRole('button',{name:'Tài khoản quản trị',exact:true}).click();await page.getByRole('menuitem',{name:'Đăng xuất',exact:true}).or(page.getByRole('button',{name:'Đăng xuất',exact:true})).first().click();})();
    await contains("Đăng nhập quản trị");
    await login(marker + "-warehouse");
    await route("/admin/inventory/" + inv.id, "Chi tiết tồn kho");
    await action("Nhập kho");
    await fill("Số lượng nhập", "1");
    await fill("Lý do", "Nhân viên kho xác nhận");
    await click("Lưu thay đổi");
    await contains("5 đơn vị khả dụng");
    await page.reload();
    await semantics();
    await contains("5 đơn vị khả dụng");
    assert.equal((await read()).quantity, 5);
    passed(
      "Missing record initialization; conflict/reload; 1440/768/375 list/detail/dialog; real warehouse login and adjustment, retained after reload",
    );
    assert.deepEqual(report.errors, []);
    assert.deepEqual(report.unexpectedResponses, []);
  } catch (e) {
    report.failure = e.message;
    if (page) {
      await page
        .screenshot({ path: path.join(output, "failure.png") })
        .catch(() => {});
      fs.writeFileSync(
        path.join(output, "failure.txt"),
        await page
          .locator("body")
          .ariaSnapshot()
          .catch(() => ""),
      );
    }
    throw e;
  } finally {
    await browser?.close();
    try {
      if (order) {
        await db.inventoryMovement.deleteMany({ where: { orderId: order.id } });
        await db.orderItem.deleteMany({ where: { orderId: order.id } });
        await db.payment.deleteMany({ where: { orderId: order.id } });
        await db.order.delete({ where: { id: order.id } });
      }
      const actors = [staff?.id, warehouse?.id].filter(Boolean);
      await db.adminAuditEvent.deleteMany({
        where: { actorId: { in: actors } },
      });
      if (product) {
        await db.inventoryMovement.deleteMany({
          where: { inventory: { variant: { productId: product.id } } },
        });
        await db.inventory.deleteMany({
          where: { variant: { productId: product.id } },
        });
        await db.productVariant.deleteMany({
          where: { productId: product.id },
        });
        await db.product.delete({ where: { id: product.id } });
      }
      if (category) await db.category.delete({ where: { id: category.id } });
      if (brand) await db.brand.delete({ where: { id: brand.id } });
      await db.user.deleteMany({ where: { id: { in: actors } } });
      report.cleaned = true;
    } finally {
      await db.$disconnect();
      fs.writeFileSync(
        path.join(output, "report.json"),
        JSON.stringify(report, null, 2),
      );
    }
  }
})().catch((e) => {
  console.error(e.message);
  process.exitCode = 1;
});
