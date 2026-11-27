const http = require("http");

function selected() {
  return "ok";
}

const app = module.exports;
app.selected = selected;

http
  .createServer((req, res) => {
    if (req.url.startsWith("/invoke")) {
      res.writeHead(200, { "Content-Type": "text/plain" });
      res.end(app.selected());
      return;
    }
    res.writeHead(200);
    res.end("ready");
  })
  .listen(3030);
