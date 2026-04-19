const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const http = require("http");
const https = require("https");
const express = require("express");
const multer = require("multer");
const WebSocket = require("ws");
const gifFrames = require("gif-frames");
const Database = require("better-sqlite3");

const port = Number(process.env.PORT || 3000);
const root = path.resolve(__dirname, "..");
const store_dir = path.join(root, "store");
const asset_dir = path.join(store_dir, "assets");
const db_file = path.join(store_dir, "main.sqlite");

for (const folder of [store_dir, asset_dir]) {
  if (!fs.existsSync(folder)) fs.mkdirSync(folder, { recursive: true });
}

const app = express();
app.use(express.urlencoded({ extended: false, limit: "2mb" }));
app.use(express.json({ limit: "2mb" }));
app.use("/asset", express.static(asset_dir));

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 15 * 1024 * 1024
  }
});

const db = new Database(db_file);
db.pragma("journal_mode = WAL");
db.exec(`
CREATE TABLE IF NOT EXISTS tags (
  username TEXT PRIMARY KEY,
  payload TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS users_cache (
  userid INTEGER PRIMARY KEY,
  username TEXT NOT NULL,
  displayname TEXT NOT NULL,
  time INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS kv (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
`);

function clean_name(text) {
  return String(text || "")
    .trim()
    .replace(/[^a-zA-Z0-9_]/g, "")
    .slice(0, 20);
}

function safe_text(text, max) {
  return String(text || "")
    .replace(/[^\x20-\x7E]/g, "")
    .trim()
    .slice(0, max);
}

function safe_color(text, fallback) {
  const val = String(text || "").trim();
  if (/^#[0-9a-fA-F]{6}$/.test(val)) return val.toUpperCase();
  return fallback;
}

function sha_num(data) {
  const full = crypto.createHash("sha256").update(data).digest("hex");
  const num = BigInt("0x" + full).toString(10);
  return num.slice(0, 24);
}

function read_json(raw, fallback) {
  try {
    return JSON.parse(raw);
  } catch {
    return fallback;
  }
}

async function extract_gif(buffer) {
  const data = await gifFrames({
    url: buffer,
    frames: "all",
    outputType: "png",
    cumulative: true
  });
  const out = [];
  for (const one of data) {
    const chunks = [];
    await new Promise((resolve, reject) => {
      one.getImage()
        .on("data", (c) => chunks.push(c))
        .on("end", resolve)
        .on("error", reject);
    });
    out.push({
      delay: Math.max(40, Number(one.frameInfo.delay || 8) * 10),
      png: Buffer.concat(chunks)
    });
  }
  return out;
}

function get_mime(buffer) {
  const a = buffer.subarray(0, 4).toString("hex");
  const b = buffer.subarray(0, 6).toString("ascii");
  if (a === "89504e47") return "png";
  if (buffer.subarray(0, 3).toString("hex") === "474946") return "gif";
  if (a === "ffd8ffe0" || a === "ffd8ffe1" || a === "ffd8ffe8") return "jpg";
  if (b === "RIFF??".replace("??", "")) return "webp";
  return "bin";
}

async function store_upload(buffer) {
  const hash = sha_num(buffer);
  const folder = path.join(asset_dir, hash);
  const meta_file = path.join(folder, "meta.json");
  if (fs.existsSync(meta_file)) {
    const meta = read_json(meta_file, null);
    if (meta) return meta;
  }
  fs.mkdirSync(folder, { recursive: true });
  const kind = get_mime(buffer);
  let frames = [];
  if (kind === "gif") {
    frames = await extract_gif(buffer);
  } else {
    frames = [{ delay: 1000, png: buffer }];
  }
  const info = [];
  for (let i = 0; i < frames.length; i++) {
    const name = `${i}.png`;
    const full = path.join(folder, name);
    fs.writeFileSync(full, frames[i].png);
    info.push({ file: name, delay: frames[i].delay });
  }
  const meta = { hash, frames: info, count: info.length };
  write_json(meta_file, meta);
  return meta;
}

function ws_send(ws, obj) {
  if (ws.readyState !== WebSocket.OPEN) return;
  ws.send(JSON.stringify(obj));
}

function fetch_json(url) {
  return new Promise((resolve, reject) => {
    const mod = url.startsWith("https://") ? https : http;
    const req = mod.get(url, { timeout: 4000 }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        try {
          resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
        } catch (err) {
          reject(err);
        }
      });
    });
    req.on("error", reject);
    req.on("timeout", () => {
      req.destroy(new Error("timeout"));
    });
  });
}

const defaults_fallback = {
  icon: { mode: "rbx", value: "rbxassetid://134633682532885" },
  background: { mode: "rbx", value: "rbxassetid://91753130662474" },
  text: "NOVOLINE",
  text_color: "#FFFFFF",
  line_color: "#8F8F91"
};
const users_busy = new Map();
const clients = new Set();
const by_userid = new Map();

function db_get_defaults() {
  const row = db.prepare("SELECT value FROM kv WHERE key = ?").get("defaults");
  if (!row) {
    db.prepare("INSERT INTO kv (key, value) VALUES (?, ?)").run("defaults", JSON.stringify(defaults_fallback));
    return defaults_fallback;
  }
  return read_json(row.value, defaults_fallback);
}

function db_set_defaults(value) {
  db.prepare("INSERT INTO kv (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value")
    .run("defaults", JSON.stringify(value));
}

function db_get_tag(username) {
  const row = db.prepare("SELECT payload FROM tags WHERE username = ?").get(username.toLowerCase());
  if (!row) return null;
  return read_json(row.payload, null);
}

function db_set_tag(username, payload) {
  db.prepare("INSERT INTO tags (username, payload) VALUES (?, ?) ON CONFLICT(username) DO UPDATE SET payload = excluded.payload")
    .run(username.toLowerCase(), JSON.stringify(payload));
}

function db_remove_tag(username) {
  db.prepare("DELETE FROM tags WHERE username = ?").run(username.toLowerCase());
}

function db_list_tags() {
  const rows = db.prepare("SELECT username, payload FROM tags ORDER BY username ASC").all();
  const out = [];
  for (const row of rows) {
    out.push({ username: row.username, tag: read_json(row.payload, {}) });
  }
  return out;
}

function db_get_user(userid) {
  return db.prepare("SELECT userid, username, displayname, time FROM users_cache WHERE userid = ?").get(userid);
}

function db_set_user(user) {
  db.prepare(`
    INSERT INTO users_cache (userid, username, displayname, time)
    VALUES (@userid, @username, @displayname, @time)
    ON CONFLICT(userid) DO UPDATE SET
      username = excluded.username,
      displayname = excluded.displayname,
      time = excluded.time
  `).run(user);
}

async function verify_user(input) {
  const name = clean_name(input.username);
  const display = safe_text(input.displayname, 60);
  const userid = Number(input.userid || 0);
  if (!name || !userid || userid < 1) return null;
  const key = String(userid);
  const now = Date.now();
  const cached = db_get_user(userid);
  if (cached && now - cached.time < 3600000) {
    if (
      cached.username.toLowerCase() === name.toLowerCase() &&
      display.length > 0 &&
      cached.displayname.toLowerCase() === display.toLowerCase()
    ) {
      return cached;
    }
  }
  if (users_busy.has(key)) return users_busy.get(key);
  const task = (async () => {
    try {
      const one = await fetch_json(`https://users.roblox.com/v1/users/${userid}`);
      const ok_name = one && one.name && one.name.toLowerCase() === name.toLowerCase();
      const ok_display =
        one && one.displayName && one.displayName.toLowerCase() === display.toLowerCase();
      const back = await fetch_json(
        `https://users.roblox.com/v1/users/${userid}/display-names/validate?displayName=${encodeURIComponent(display)}`
      ).catch(() => ({ code: 0 }));
      const ok_back = back && (back.code === 0 || back.code === 1);
      if (!ok_name || !ok_display || !ok_back) return null;
      const row = {
        userid,
        username: one.name,
        displayname: one.displayName,
        time: Date.now()
      };
      db_set_user(row);
      return row;
    } catch {
      return null;
    } finally {
      users_busy.delete(key);
    }
  })();
  users_busy.set(key, task);
  return task;
}

function asset_pick(raw) {
  if (!raw || typeof raw !== "object") return null;
  if (raw.mode === "hash" && /^[0-9]{6,24}$/.test(String(raw.value || ""))) {
    return { mode: "hash", value: String(raw.value) };
  }
  if (raw.mode === "rbx") {
    const val = String(raw.value || "").trim();
    const id = val.replace("rbxassetid://", "");
    if (/^\d{2,20}$/.test(id)) return { mode: "rbx", value: `rbxassetid://${id}` };
  }
  return null;
}

function format_tag(user) {
  const defaults = db_get_defaults();
  const custom = db_get_tag(user.username) || {};
  const merged = {
    username: user.username,
    displayname: user.displayname,
    userid: user.userid,
    text: safe_text(custom.text || defaults.text, 40),
    text_color: safe_color(custom.text_color || defaults.text_color, "#FFFFFF"),
    line_color: safe_color(custom.line_color || defaults.line_color, "#8F8F91"),
    icon: asset_pick(custom.icon) || defaults.icon,
    background: asset_pick(custom.background) || defaults.background
  };
  return merged;
}

function broadcast_state() {
  const defaults = db_get_defaults();
  const list = [];
  for (const info of by_userid.values()) {
    list.push(format_tag(info.user));
  }
  for (const ws of clients) {
    ws_send(ws, { type: "state", players: list, defaults });
  }
}

function send_asset(ws, hash) {
  const folder = path.join(asset_dir, hash);
  const meta = read_json(path.join(folder, "meta.json"), null);
  if (!meta) return;
  const frames = [];
  for (const row of meta.frames || []) {
    const full = path.join(folder, row.file);
    if (!fs.existsSync(full)) continue;
    frames.push({
      delay: Number(row.delay || 100),
      png64: fs.readFileSync(full).toString("base64")
    });
  }
  ws_send(ws, { type: "asset_blob", hash, frames });
}

app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "web.html"));
});

app.get("/api/list", (req, res) => {
  const out = db_list_tags();
  const defaults = db_get_defaults();
  res.json({ ok: true, tags: out, defaults });
});

app.post("/api/upload", upload.single("file"), async (req, res) => {
  try {
    if (!req.file || !req.file.buffer) return res.status(400).json({ ok: false });
    const meta = await store_upload(req.file.buffer);
    res.json({ ok: true, hash: meta.hash, count: meta.count });
  } catch {
    res.status(500).json({ ok: false });
  }
});

app.post("/api/defaults", (req, res) => {
  const defaults = db_get_defaults();
  const next = {
    icon: asset_pick(req.body.icon) || defaults.icon,
    background: asset_pick(req.body.background) || defaults.background,
    text: safe_text(req.body.text || defaults.text, 40),
    text_color: safe_color(req.body.text_color || defaults.text_color, "#FFFFFF"),
    line_color: safe_color(req.body.line_color || defaults.line_color, "#8F8F91")
  };
  db_set_defaults(next);
  broadcast_state();
  res.json({ ok: true });
});

app.post("/api/set", (req, res) => {
  const username = clean_name(req.body.username).toLowerCase();
  if (!username) return res.status(400).json({ ok: false });
  const defaults = db_get_defaults();
  const row = {
    text: safe_text(req.body.text || "", 40),
    text_color: safe_color(req.body.text_color || "", defaults.text_color),
    line_color: safe_color(req.body.line_color || "", defaults.line_color),
    icon: asset_pick(req.body.icon),
    background: asset_pick(req.body.background)
  };
  db_set_tag(username, row);
  broadcast_state();
  res.json({ ok: true });
});

app.post("/api/remove", (req, res) => {
  const username = clean_name(req.body.username).toLowerCase();
  if (!username) return res.status(400).json({ ok: false });
  db_remove_tag(username);
  broadcast_state();
  res.json({ ok: true });
});

const server = http.createServer(app);
const wss = new WebSocket.Server({ noServer: true });

server.on("upgrade", (req, socket, head) => {
  const url = String(req.url || "");
  if (!/^\/live\/[a-z0-9]{12,64}$/i.test(url)) {
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => {
    wss.emit("connection", ws, req);
  });
});

wss.on("connection", (ws) => {
  clients.add(ws);
  let state = null;

  ws.on("message", async (raw) => {
    if (raw.length > 1024 * 1024) return;
    let msg;
    try {
      msg = JSON.parse(String(raw));
    } catch {
      return;
    }
    if (msg.type === "hello") {
      const user = await verify_user(msg);
      if (!user) {
        ws_send(ws, { type: "bye" });
        ws.close();
        return;
      }
      state = { user };
      by_userid.set(String(user.userid), { ws, user });
      const defaults = db_get_defaults();
      ws_send(ws, { type: "you", tag: format_tag(user), defaults });
      broadcast_state();
      return;
    }
    if (msg.type === "asset_need" && Array.isArray(msg.hashes)) {
      for (const one of msg.hashes) {
        const hash = String(one || "");
        if (/^[0-9]{6,24}$/.test(hash)) send_asset(ws, hash);
      }
      return;
    }
    if (msg.type === "ping") {
      ws_send(ws, { type: "pong", t: Date.now() });
    }
  });

  ws.on("close", () => {
    clients.delete(ws);
    if (state && state.user) by_userid.delete(String(state.user.userid));
    broadcast_state();
  });

  ws.on("error", () => {});
});

server.listen(port, () => {
  process.stdout.write(`client backend on ${port}\n`);
});
