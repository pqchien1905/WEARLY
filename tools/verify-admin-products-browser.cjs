// Chrome + local API/PostgreSQL/S3 acceptance. Mutates only uniquely owned QA
// products and accounts; never checks out, sends mail or invokes AI/payments.
const fs = require("node:fs"),
  path = require("node:path"),
  assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { chromium } = require("../.tools/browser/node_modules/playwright");
const argon2 = require("../backend/node_modules/argon2");
const { localDatabase } = require("./seed-customer-account.cjs");
const { ConfigService } = require("../backend/node_modules/@nestjs/config");
const {
  StorageService,
} = require("../backend/dist/integrations/storage/storage.service");
const dotenv = require("../backend/node_modules/dotenv");
const base = process.env.ADMIN_TEST_BASE || "http://localhost:8080";
if (!/^http:\/\/localhost:(8080|5173)$/.test(base))
  throw Error("Local frontend required");
const output = path.resolve(__dirname, "../.tools/products-acceptance");
(async () => {
  fs.mkdirSync(output, { recursive: true });
  const db = localDatabase(),
    report = { passed: [], errors: [], unexpectedResponses: [] },
    fixtures = [];
  let browser,
    page,
    staff,
    buyer,
    category,
    brand,
    created,
    order,
    allowConflict = false,
    storage;
  const marker = "products-qa-" + randomUUID().slice(0, 8),
    password = randomUUID() + "-Aa1";
  try {
    const env = dotenv.parse(
      fs.readFileSync(path.resolve(__dirname, "../backend/.env")),
    );
    if (!["localhost", "127.0.0.1"].includes(new URL(env.S3_ENDPOINT).hostname))
      throw Error("Local S3 required");
    storage = new StorageService(new ConfigService(env));
    const passwordHash = await argon2.hash(password);
    staff = await db.user.create({
      data: {
        username: marker,
        email: marker + "@example.invalid",
        name: "Quản trị kiểm thử",
        role: "ADMIN",
        passwordHash,
      },
    });
    buyer = await db.user.create({
      data: {
        email: marker + "-buyer@example.invalid",
        name: "Khách mua kiểm thử",
        passwordHash,
      },
    });
    category = await db.category.create({
      data: { slug: marker, name: "Danh mục kiểm thử " + marker },
    });
    brand = await db.brand.create({
      data: { slug: marker, name: "Thương hiệu kiểm thử " + marker },
    });
    for (let i = 0; i < 22; i++)
      fixtures.push(
        await db.product.create({
          data: {
            slug: marker + "-" + i,
            name: `Áo sơ mi linen ${String(i + 1).padStart(2, "0")} ${marker}`,
            description: "Sản phẩm riêng của kiểm thử.",
            material: "Linen",
            style: "Casual",
            active: false,
            categoryId: category.id,
            brandId: brand.id,
            createdAt: new Date(Date.now() - i * 86400000),
            images: {
              create: [
                { url: "assets/images/shirt.jpg", alt: "Áo sơ mi linen" },
              ],
            },
            variants: {
              create: {
                sku: marker + "-" + i,
                size: "M",
                color: "Trắng",
                colorHex: "#ffffff",
                price: String(300000 + i * 10000),
                inventory: { create: { quantity: i === 1 ? 0 : i + 1 } },
              },
            },
          },
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
        !(allowConflict && [400, 409, 413].includes(r.status()))
      )
        report.unexpectedResponses.push({
          path: new URL(r.url()).pathname,
          status: r.status(),
        });
    });
    const snapshot = () => page.locator("body").ariaSnapshot();
    const button = (name) => {
      const locator = page.getByRole("button", { name, exact: typeof name === "string" });
      return name === "Lưu thông tin sản phẩm" ? locator.first() : locator;
    };
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
      await page.waitForTimeout(180);
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
    async function route(target, text) {
      await page.evaluate((v) => (location.hash = "#" + v), target);
      await page.waitForTimeout(260);
      await contains(text);
    }
    async function capture(name) {
      await page.mouse.move(page.viewportSize().width * 0.75, 500);
      await page.mouse.wheel(0, -20000);
      await page.waitForTimeout(250);
      await page.screenshot({ path: path.join(output, name + ".png") });
      fs.writeFileSync(path.join(output, name + ".txt"), await snapshot());
    }
    async function publicProduct(slug) {
      return fetch("http://localhost:3000/api/v1/products/" + slug);
    }
    async function editProduct() {
      await route(
        "/admin/products/" + created.id + "/edit",
        "Chỉnh sửa sản phẩm",
      );
      await contains("Lưu thông tin sản phẩm");
    }

    await page.goto(base + "/#/admin/products");
    await semantics();
    await contains("Đăng nhập quản trị");
    await fill("Tên đăng nhập", marker);
    await fill("Mật khẩu", password);
    await click("Đăng nhập quản trị");
    await contains("Tìm kiếm sản phẩm");
    await fill("Tìm kiếm sản phẩm", marker);
    await click("Áp dụng");
    await contains("22 sản phẩm phù hợp bộ lọc");
    await click("Trang sau");
    await contains("Trang 2/2");
    await page.reload();
    await semantics();
    await contains("Trang 2/2");
    await select("Sắp xếp", "Giá cao đến thấp");
    assert(!page.url().includes("page=2"));
    await select("Danh mục", category.name);
    await select("Thương hiệu", brand.name);
    await select("Tồn kho SKU đang bán", "Hết toàn bộ hàng");
    await contains("1 sản phẩm phù hợp bộ lọc");
    await select("Tồn kho SKU đang bán", "Tất cả tồn kho");
    await fill("Giá từ", "400000");
    await fill("Giá đến", "450000");
    await click("Áp dụng");
    await contains("6 sản phẩm phù hợp bộ lọc");
    await fill("Giá từ", "500000");
    await fill("Giá đến", "1");
    await click("Áp dụng");
    await contains("Giá đến phải lớn hơn hoặc bằng giá từ.");
    await click("Xóa bộ lọc");
    await fill("Tìm kiếm sản phẩm", marker);
    await click("Áp dụng");
    await contains("22 sản phẩm phù hợp bộ lọc");
    await capture("products-desktop");
    passed(
      "Real login; search, category/brand/stock/price filters, range validation, sorting, pagination and reload",
    );

    await click("Thêm sản phẩm");
    await contains("Thông tin cơ bản");
    await click("Lưu thông tin sản phẩm");
    await contains("Vui lòng nhập thông tin.");
    await fill("Tên sản phẩm", "Áo sơ mi mới " + marker);
    await fill("Đường dẫn sản phẩm", fixtures[0].slug);
    await select("Danh mục", category.name);
    await select("Thương hiệu", brand.name);
    await fill("Chất liệu", "Linen tự nhiên");
    await fill("Phong cách", "Casual");
    await fill(
      "Mô tả",
      "Thông tin sản phẩm được tạo và lưu qua giao diện quản trị.",
    );
    allowConflict = true;
    await click("Lưu thông tin sản phẩm");
    await contains("Đường dẫn sản phẩm đã được sử dụng.");
    allowConflict = false;
    await fill("Đường dẫn sản phẩm", marker + "-created");
    await click("Lưu thông tin sản phẩm");
    await contains("Chỉnh sửa sản phẩm");
    created = await db.product.findUniqueOrThrow({
      where: { slug: marker + "-created" },
    });
    assert.equal(created.active, false);
    assert.equal(await db.product.count({ where: { slug: created.slug } }), 1);
    await click("Thêm biến thể");
    await fill("Mã SKU", marker + "-sku");
    await fill("Kích cỡ", "M");
    await fill("Màu sắc", "Trắng");
    await fill("Mã màu HEX", "#ffffff");
    await fill("Giá bán", "-1");
    await click("Lưu thay đổi");
    await contains("Nhập số tiền nguyên");
    await fill("Giá bán", "500000");
    await click("Lưu thay đổi");
    await contains("Đã lưu biến thể.");
    let variant = await db.productVariant.findFirstOrThrow({
      where: { productId: created.id },
      include: { inventory: true },
    });
    assert.equal(variant.inventory.quantity, 0);
    await click("Điều chỉnh kho");
    await fill("Số lượng thay đổi", "7");
    await fill("Lý do", "Nhập kho kiểm thử");
    await click("Lưu thay đổi");
    await contains("Đã cập nhật tồn kho.");
    assert.equal(
      (
        await db.inventory.findUniqueOrThrow({
          where: { id: variant.inventory.id },
        })
      ).quantity,
      7,
    );
    await click("Điều chỉnh kho");
    await fill("Số lượng thay đổi", "-8");
    await fill("Lý do", "Không cho âm kho");
    await click("Lưu thay đổi");
    await contains("Tồn kho không thể âm.");
    await click("Đóng");
    passed(
      "Create with validation and duplicate slug protection; create SKU, reject negative price, adjust real stock and block negative stock",
    );

    const chooser = page.waitForEvent("filechooser");
    await click("Tải ảnh từ máy");
    await (
      await chooser
    ).setFiles(path.resolve(__dirname, "../frontend/assets/images/shirt.jpg"));
    await contains("Đã tải và lưu ảnh sản phẩm.");
    let saved = await db.product.findUniqueOrThrow({
      where: { id: created.id },
      include: { images: true, variants: { include: { inventory: true } } },
    });
    assert.equal(saved.images.length, 1);
    const imageUrl = saved.images[0].url;
    assert.match(imageUrl, /^catalog\/images\//);
    const imageResponse = await fetch(
      "http://localhost:3000/api/v1/" + imageUrl,
    );
    assert.equal(imageResponse.status, 200);
    assert.match(
      imageResponse.headers.get("content-type"),
      /image\/(jpeg|png)/,
    );
    assert.equal((await publicProduct(created.slug)).status, 404);
    await route("/admin/products/" + created.id, "Chi tiết sản phẩm");
    await click("Bật sản phẩm");
    await click("Lưu thay đổi");
    await contains("Đã bật sản phẩm.");
    const storefront = await (await publicProduct(created.slug)).json();
    assert.equal(storefront.priceFrom.amount, "500000");
    assert.equal(storefront.variants[0].available, 7);
    assert.equal(storefront.images[0].url, imageUrl);
    passed(
      "Upload to real local S3, serve verified image bytes and publish only after image/active SKU/product conditions are met",
    );

    order = await db.order.create({
      data: {
        userId: buyer.id,
        idempotencyKey: randomUUID(),
        requestHash: marker,
        addressSnapshot: {
          recipient: "Khách mua kiểm thử",
          phone: "0900000000",
          address: "Địa chỉ kiểm thử",
        },
        subtotal: "500000",
        shipping: "0",
        total: "500000",
        items: {
          create: {
            variantId: variant.id,
            name: created.name,
            sku: variant.sku,
            slug: created.slug,
            size: "M",
            color: "Trắng",
            image: imageUrl,
            unitPrice: "500000",
            quantity: 1,
          },
        },
        payment: { create: { provider: "cod", amount: "500000" } },
        history: {
          create: { status: "PENDING", version: 0, actorId: staff.id },
        },
      },
    });
    await click("Sửa giá / trạng thái");
    await fill("Giá bán", "600000");
    await click("Lưu thay đổi");
    await contains("Đã lưu biến thể.");
    assert.equal(
      (await (await publicProduct(created.slug)).json()).priceFrom.amount,
      "600000",
    );
    await editProduct();
    await fill("Tên sản phẩm", "Tên cập nhật " + marker);
    await click("Lưu thông tin sản phẩm");
    await contains("Đã lưu thông tin sản phẩm.");
    await click("Bỏ ảnh");
    await page
      .getByRole("alertdialog")
      .getByRole("button", { name: "Bỏ ảnh", exact: true })
      .click();
    await click("Lưu thông tin sản phẩm");
    await contains("Đã lưu thông tin sản phẩm.");
    assert.equal((await publicProduct(created.slug)).status, 404);
    assert.equal(
      (await fetch("http://localhost:3000/api/v1/" + imageUrl)).status,
      200,
    );
    await click("Thêm ảnh");
    await fill("Đường dẫn ảnh", imageUrl);
    await fill("Mô tả ảnh", "Ảnh được khôi phục");
    await click("Lưu thông tin sản phẩm");
    await contains("Đã lưu thông tin sản phẩm.");
    assert.equal((await publicProduct(created.slug)).status, 200);
    const frozen = await db.orderItem.findFirstOrThrow({
      where: { orderId: order.id },
    });
    assert.equal(frozen.name, created.name);
    assert.equal(frozen.unitPrice.toString(), "500000");
    assert.equal(frozen.image, imageUrl);
    await route("/admin/orders/" + order.id, "Đơn hàng");
    await contains(created.name);
    await contains("500.000");
    await route("/admin/customers/" + buyer.id, "Hồ sơ khách hàng");
    await contains(order.code);
    await contains("500.000");
    passed(
      "Price/name/image changes update the storefront while original order image, name, amount and customer purchase history remain intact",
    );

    for (const width of [1440, 768, 375]) {
      await page.setViewportSize({ width, height: 1050 });
      await route("/admin/products?q=" + marker, "Tìm kiếm sản phẩm");
      await contains("23 sản phẩm phù hợp bộ lọc");
      await capture("products-" + width);
      await route("/admin/products/" + created.id, "Chi tiết sản phẩm");
      await contains("600.000");
      await capture("product-detail-" + width);
      await editProduct();
      await capture("product-edit-" + width);
    }
    await page.setViewportSize({ width: 1440, height: 1050 });
    await editProduct();
    await fill("Tên sản phẩm", "Bản nháp cũ");
    await db.product.update({
      where: { id: created.id },
      data: {
        name: "Tên từ phiên khác " + marker,
        updatedAt: new Date(Date.now() + 5),
      },
    });
    allowConflict = true;
    await click("Lưu thông tin sản phẩm");
    await contains("Sản phẩm hoặc biến thể đã thay đổi.");
    await click("Tải lại dữ liệu sản phẩm");
    const reloadedName = page.getByRole("textbox", {
      name: "Tên sản phẩm",
      exact: true,
    });
    await reveal(reloadedName);
    await reloadedName.click();
    await page.waitForTimeout(250);
    assert.equal(
      await reloadedName.inputValue(),
      "Tên từ phiên khác " + marker,
    );
    allowConflict = false;
    await route("/admin/products/" + created.id, "Chi tiết sản phẩm");
    await click("Ẩn sản phẩm");
    await click("Lưu thay đổi");
    await contains("Đã ẩn sản phẩm.");
    assert.equal((await publicProduct(created.slug)).status, 404);
    assert.equal(await db.orderItem.count({ where: { orderId: order.id } }), 1);
    await page.reload();
    await semantics();
    await contains("Đã ẩn");
    passed(
      "List/detail/editor at 1440, 768 and 375px; stale-write protection, reload, hide confirmation and preserved transaction history",
    );
    assert.deepEqual(report.errors, []);
    assert.deepEqual(report.unexpectedResponses, []);
  } catch (error) {
    report.failure = error.message;
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
    throw error;
  } finally {
    await browser?.close();
    try {
      const ids = category
        ? (
            await db.product.findMany({
              where: { categoryId: category.id },
              select: { id: true },
            })
          ).map((p) => p.id)
        : [];
      const assets = await db.catalogAsset.findMany({
        where: { productId: { in: ids } },
      });
      if (assets.length)
        await storage.deleteObjects(assets.map((a) => a.objectKey));
      await db.catalogAsset.deleteMany({ where: { productId: { in: ids } } });
      if (order) {
        await db.orderItem.deleteMany({ where: { orderId: order.id } });
        await db.payment.deleteMany({ where: { orderId: order.id } });
        await db.order.delete({ where: { id: order.id } });
      }
      if (staff)
        await db.adminAuditEvent.deleteMany({ where: { actorId: staff.id } });
      await db.inventoryMovement.deleteMany({
        where: { inventory: { variant: { productId: { in: ids } } } },
      });
      await db.inventory.deleteMany({
        where: { variant: { productId: { in: ids } } },
      });
      await db.productVariant.deleteMany({ where: { productId: { in: ids } } });
      await db.product.deleteMany({ where: { id: { in: ids } } });
      if (category) await db.category.delete({ where: { id: category.id } });
      if (brand) await db.brand.delete({ where: { id: brand.id } });
      await db.user.deleteMany({
        where: { id: { in: [staff?.id, buyer?.id].filter(Boolean) } },
      });
      report.cleaned = true;
    } finally {
      storage?.onModuleDestroy();
      await db.$disconnect();
      fs.writeFileSync(
        path.join(output, "report.json"),
        JSON.stringify(report, null, 2),
      );
    }
  }
})().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
