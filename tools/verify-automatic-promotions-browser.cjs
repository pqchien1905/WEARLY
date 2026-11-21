// Local Chrome acceptance. Only a disposable selected-product offer is enabled;
// no customer order is submitted and fixtures are removed in finally.
const fs = require("node:fs");
const path = require("node:path");
const { randomUUID, randomBytes, createHash } = require("node:crypto");
const assert = require("node:assert/strict");
const { localDatabase } = require("./seed-customer-account.cjs");
const { chromium } = require("../.tools/browser/node_modules/playwright");
const out = path.resolve(__dirname, "../.tools/automatic-promotions");
fs.mkdirSync(out, { recursive: true });
(async () => {
  const db = localDatabase();
  let browser, product;
  const users = [];
  const marker = randomUUID().slice(0, 8),
    name = `Ưu đãi tự động QA ${marker}`,
    productName = `Áo kiểm thử ưu đãi ${marker}`;
  const report = { checks: [], errors: [] };
  try {
    const category = await db.category.findFirstOrThrow(),
      brand = await db.brand.findFirstOrThrow();
    product = await db.product.create({
      data: {
        slug: `qa-automatic-${marker}`,
        name: productName,
        description: "Sản phẩm kiểm tra giao diện khuyến mãi.",
        material: "Cotton",
        style: "Tối giản",
        categoryId: category.id,
        brandId: brand.id,
        images: {
          create: { url: "assets/images/shirt.jpg", alt: productName },
        },
        variants: {
          create: {
            sku: `QA-AUTO-${marker}`,
            size: "M",
            color: "Trắng",
            colorHex: "#FFFFFF",
            price: "200000",
            inventory: { create: { quantity: 5 } },
          },
        },
      },
      include: { variants: true },
    });
    browser = await chromium.launch({
      executablePath: "C:/Program Files/Google/Chrome/Application/chrome.exe",
      headless: true,
      args: ["--host-resolver-rules=MAP localhost 127.0.0.1"],
    });
    const ctx = await browser.newContext({
      viewport: { width: 1920, height: 1080 },
      reducedMotion: "reduce",
    });
    for (const scope of ["admin", "customer"]) {
      const user = await db.user.create({
        data: {
          email: `automatic-${scope}-${randomUUID()}@example.invalid`,
          name: "Kiểm thử ưu đãi",
          role: scope === "admin" ? "ADMIN" : "CUSTOMER",
          passwordHash: "disabled-qa-login",
        },
      });
      users.push(user);
      const token = randomBytes(32).toString("base64url");
      await db.refreshToken.create({
        data: {
          userId: user.id,
          familyId: randomUUID(),
          browserScope: scope,
          tokenHash: createHash("sha256").update(token).digest("hex"),
          expiresAt: new Date(Date.now() + 3600000),
        },
      });
      await ctx.addCookies([
        {
          name: `wearly_${scope}_session`,
          value: token,
          domain: "localhost",
          path: `/api/v1/auth/browser/${scope}`,
          httpOnly: true,
          sameSite: "Strict",
        },
      ]);
      if (scope === "customer")
        await db.address.create({
          data: {
            userId: user.id,
            label: "Nhà",
            recipient: "Kiểm thử",
            phone: "0901234567",
            address: "12 Đường thử nghiệm",
            isDefault: true,
          },
        });
    }
    const page = await ctx.newPage();
    page.setDefaultTimeout(20000);
    page.on("pageerror", (e) => report.errors.push(e.message));
    page.on("console", (m) => {
      if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text()))
        report.errors.push(m.text());
    });
    const snap = () => page.locator("body").ariaSnapshot();
    async function contains(text) {
      for (let i = 0; i < 200; i++) {
        if ((await snap()).includes(text)) return;
        await page.waitForTimeout(200);
      }
      throw Error("Missing " + text);
    }
    async function reveal(n) {
      await n.waitFor({ state: "attached" });
      for (let i = 0; i < 100; i++) {
        const b = await n.boundingBox(),
          v = page.viewportSize();
        if (b && b.y >= 20 && b.y + b.height < v.height - 10) return;
        await page.mouse.move(v.width / 2, v.height / 2);
        await page.mouse.wheel(0, b?.y < 20 ? -300 : 300);
        await page.waitForTimeout(70);
      }
      throw Error("Cannot reveal " + n);
    }
    async function click(name) {
      const n = page
        .getByRole("button", { name, exact: typeof name === "string" })
        .last();
      await reveal(n);
      await n.click();
      await page.waitForTimeout(250);
    }
    async function fill(label, value) {
      const n = page
        .getByRole("textbox", { name: new RegExp("^" + label) })
        .last();
      await reveal(n);
      await n.fill(value);
    }
    async function go(route) {
      await page.goto(`http://localhost:8080/#${route}`);
      await page.waitForFunction(() =>
        document.querySelector("flt-semantics-placeholder,flt-semantics"),
      );
      await page.evaluate(() =>
        document.querySelector("flt-semantics-placeholder")?.click(),
      );
    }
    await go("/admin/promotions");
    await contains("Quản lý khuyến mãi");
    await click("Thêm khuyến mãi");
    await fill("Tên chương trình", name);
    await click(/^Phạm vi áp dụng/);
    await page
      .getByRole("menuitem", { name: "Một số sản phẩm", exact: true })
      .click();
    await click("Chọn sản phẩm (0)");
    await fill("Tìm tên sản phẩm hoặc SKU", marker);
    await click("Tìm sản phẩm");
    await contains(productName);
    const checkbox = page.getByRole("checkbox", {
      name: new RegExp(productName),
    });
    await reveal(checkbox);
    await checkbox.click();
    await click("Dùng 1 sản phẩm");
    await fill("Giá trị giảm", "25000");
    fs.writeFileSync(`${out}/editor.txt`, await snap());
    const toggle = page.getByRole("switch", { name: /Bật khuyến mãi/ });
    await reveal(toggle);
    await toggle.click();
    await click("Lưu thay đổi");
    await contains("Đã thêm khuyến mãi tự động.");
    const promotion = await db.coupon.findFirstOrThrow({
      where: { name },
      include: { products: true },
    });
    assert.equal(promotion.application, "AUTOMATIC");
    assert.equal(promotion.scope, "PRODUCTS");
    assert.equal(promotion.active, true);
    assert.equal(promotion.products[0].productId, product.id);
    report.checks.push(
      "Admin UI creates an automatic promotion for the selected product, without entering a code",
    );
    for (const width of [2560, 1920, 1440, 375]) {
      await page.setViewportSize({ width, height: 1080 });
      await page.mouse.move(width * 0.6, 500);
      await page.mouse.wheel(0, -30000);
      await page.waitForTimeout(500);
      await page.screenshot({ path: `${out}/admin-${width}.png` });
    }
    for (const [route, title] of [
      ["collections", "Quản lý bộ sưu tập"],
      ["inventory", "Quản lý kho hàng"],
    ]) {
      await go(`/admin/${route}`);
      await contains(title);
      for (const width of [1920, 375]) {
        await page.setViewportSize({ width, height: 1080 });
        await page.mouse.move(width * 0.6, 500);
        await page.mouse.wheel(0, -30000);
        await page.waitForTimeout(500);
        await page.screenshot({ path: `${out}/${route}-${width}.png` });
      }
    }
    report.checks.push("Collections and inventory fit desktop and mobile without overflow");
    await page.setViewportSize({ width: 1440, height: 1080 });
    await go(`/shop?q=${encodeURIComponent(marker)}`);
    await contains(name);
    await page.screenshot({ path: `${out}/shop.png` });
    await go(`/products/${product.slug}`);
    await contains(name);
    fs.writeFileSync(`${out}/product.txt`, await snap());
    assert((await snap()).includes("175.000"));
    assert((await snap()).includes("200.000"));
    report.checks.push(
      "Shop and product detail show the original price, reduced price and campaign name",
    );
    await page.screenshot({ path: `${out}/product-1440.png` });
    await page.setViewportSize({ width: 375, height: 1080 });
    await page.screenshot({ path: `${out}/product-375.png` });
    await page.setViewportSize({ width: 1440, height: 1080 });
    await click("M");
    await click("Thêm vào giỏ");
    await page
      .getByRole("button", { name: "Đóng giỏ hàng", exact: true })
      .last()
      .click();
    await go("/cart");
    await contains(name);
    await contains("175.000");
    await page.screenshot({ path: `${out}/cart.png` });
    const cart = await db.cart.findUniqueOrThrow({
      where: { userId: users[1].id },
      include: { items: true },
    });
    assert.equal(cart.items.length, 1);
    await go("/checkout");
    await contains("175.000");
    await contains("205.000");
    await contains("25.000");
    await page.screenshot({ path: `${out}/checkout.png` });
    report.checks.push(
      "Customer adds to cart and sees automatic savings and correct checkout total without a coupon",
    );
    await db.coupon.update({
      where: { id: promotion.id },
      data: { active: false, version: { increment: 1 } },
    });
    await go(`/products/${product.slug}`);
    await contains(productName);
    await contains("200.000");
    assert(!(await snap()).includes(name));
    report.checks.push(
      "Disabling the promotion restores the original storefront price",
    );
    assert.deepEqual(report.errors, []);
    console.log(JSON.stringify(report));
  } finally {
    fs.writeFileSync(`${out}/report.json`, JSON.stringify(report, null, 2));
    await browser?.close();
    await db.coupon.deleteMany({ where: { name } });
    for (const user of users) await db.user.delete({ where: { id: user.id } });
    if (product) {
      await db.inventory.deleteMany({
        where: { variant: { productId: product.id } },
      });
      await db.productVariant.deleteMany({ where: { productId: product.id } });
      await db.productImage.deleteMany({ where: { productId: product.id } });
      await db.product.delete({ where: { id: product.id } });
    }
    await db.$disconnect();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
