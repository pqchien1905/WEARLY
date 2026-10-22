const http = require("http");
const fs = require("fs");
const path = require("path");
const mime = {
  ".html": "text/html",
  ".js": "application/javascript",
  ".json": "application/json",
  ".wasm": "application/wasm",
  ".jpg": "image/jpeg",
  ".png": "image/png",
  ".ttf": "font/ttf",
  ".svg": "image/svg+xml",
};
function createStaticServer(directory) {
  const root = fs.realpathSync(directory);
  return http.createServer((req, res) => {
    if (!["GET", "HEAD"].includes(req.method)) {
      res.writeHead(405, { Allow: "GET, HEAD" }).end();
      return;
    }
    let clean;
    try {
      clean = decodeURIComponent(req.url.split("?")[0]);
      if (clean.includes("\0")) throw new URIError("Invalid path");
    } catch {
      res.writeHead(400);
      res.end("Invalid URL");
      return;
    }
    const file = path.resolve(
      root,
      "." + (clean === "/" ? "/index.html" : clean),
    );
    if (!file.startsWith(root + path.sep)) {
      res.writeHead(403);
      res.end();
      return;
    }
    fs.realpath(file, (error, real) => {
      if (error) {
        res.writeHead(404).end("Not found");
        return;
      }
      if (!real.startsWith(root + path.sep)) {
        res.writeHead(403).end();
        return;
      }
      fs.stat(real, (error, stat) => {
        if (error || !stat.isFile()) {
          res.writeHead(404).end("Not found");
          return;
        }
        res.writeHead(200, {
          "Content-Type":
            mime[path.extname(real)] || "application/octet-stream",
          "Content-Length": stat.size,
          "Cache-Control": "no-store",
          "X-Content-Type-Options": "nosniff",
          "X-Robots-Tag": "noindex, nofollow",
        });
        if (req.method === "HEAD") {
          res.end();
          return;
        }
        const stream = fs.createReadStream(real);
        stream.on("error", () => res.destroy());
        res.on("close", () => stream.destroy());
        stream.pipe(res);
      });
    });
  });
}
module.exports = { createStaticServer };
if (require.main === module)
  createStaticServer(path.resolve(__dirname, "../frontend/build/web")).listen(
    4173,
    "127.0.0.1",
    () => console.log("Wearly preview: http://127.0.0.1:4173"),
  );
