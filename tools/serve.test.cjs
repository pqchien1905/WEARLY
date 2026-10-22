const test = require("node:test"),
  assert = require("node:assert/strict"),
  fs = require("node:fs"),
  os = require("node:os"),
  path = require("node:path");
const { createStaticServer } = require("./serve.cjs");
test("static factory serves GET/HEAD and refuses encoded traversal or outside junctions", async (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "wearly-static-test-")),
    web = path.join(root, "web"),
    outside = path.join(root, "outside");
  fs.mkdirSync(web);
  fs.mkdirSync(outside);
  fs.writeFileSync(path.join(web, "index.html"), "<p>Local fixture</p>");
  fs.writeFileSync(path.join(outside, "private.txt"), "must not be served");
  fs.symlinkSync(outside, path.join(web, "escape"), "junction");
  t.after(() => {
    fs.unlinkSync(path.join(web, "escape"));
    fs.unlinkSync(path.join(web, "index.html"));
    fs.unlinkSync(path.join(outside, "private.txt"));
    fs.rmdirSync(web);
    fs.rmdirSync(outside);
    fs.rmdirSync(root);
  });
  const server = createStaticServer(web);
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  t.after(() => new Promise((r) => server.close(r)));
  const url = `http://127.0.0.1:${server.address().port}`;
  assert.equal(await (await fetch(url)).text(), "<p>Local fixture</p>");
  assert.equal(await (await fetch(url, { method: "HEAD" })).text(), "");
  assert.equal((await fetch(url + "/escape/private.txt")).status, 403);
  assert.equal(
    (await fetch(url + "/%2e%2e%5coutside%5cprivate.txt")).status,
    403,
  );
  assert.equal((await fetch(url, { method: "POST" })).status, 405);
});
