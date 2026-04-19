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

function read_json_file(file, fallback) {
  try {
    if (!fs.existsSync(file)) return fallback;
    return read_json(fs.readFileSync(file, "utf8"), fallback);
  } catch {
    return fallback;
  }
}

function write_json_file(file, value) {
  fs.writeFileSync(file, JSON.stringify(value), "utf8");
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
  const b = buffer.subarray(0, 4).toString("ascii");
  if (a === "89504e47") return "png";
  if (buffer.subarray(0, 3).toString("hex") === "474946") return "gif";
  if (a === "ffd8ffe0" || a === "ffd8ffe1" || a === "ffd8ffe8") return "jpg";
  if (b === "RIFF" && buffer.subarray(8, 12).toString("ascii") === "WEBP") return "webp";
  return "bin";
}

async function store_upload(buffer) {
  const hash = sha_num(buffer);
  const folder = path.join(asset_dir, hash);
  const meta_file = path.join(folder, "meta.json");
  if (fs.existsSync(meta_file)) {
    const meta = read_json_file(meta_file, null);
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
  write_json_file(meta_file, meta);
  return meta;
}

function ws_send(ws, obj) {
  if (ws.readyState !== WebSocket.OPEN) return;
  ws.send(JSON.stringify(obj));
}

function log_line(text) {
  process.stdout.write(`[server] ${String(text)}\n`);
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

function db_get_cache_rev() {
  const row = db.prepare("SELECT value FROM kv WHERE key = ?").get("cache_rev");
  if (!row) {
    db.prepare("INSERT INTO kv (key, value) VALUES (?, ?)").run("cache_rev", "1");
    return 1;
  }
  const n = Number(row.value || 1);
  if (!Number.isFinite(n) || n < 1) return 1;
  return Math.floor(n);
}

function db_bump_cache_rev() {
  const next = db_get_cache_rev() + 1;
  db.prepare("INSERT INTO kv (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value")
    .run("cache_rev", String(next));
  return next;
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
  if (!name || !userid || userid < 1) return { ok: false, code: "bad_identity" };
  const key = String(userid);
  const now = Date.now();
  const cached = db_get_user(userid);
  if (cached && now - cached.time < 3600000) {
    if (cached.username.toLowerCase() === name.toLowerCase()) {
      return { ok: true, user: cached };
    }
  }
  if (users_busy.has(key)) return users_busy.get(key);
  const task = (async () => {
    try {
      const one = await fetch_json(`https://users.roblox.com/v1/users/${userid}`);
      const ok_name = one && one.name && one.name.toLowerCase() === name.toLowerCase();
      if (!ok_name) return { ok: false, code: "name_mismatch" };
      const row = {
        userid,
        username: one.name,
        displayname: one.displayName || display || one.name,
        time: Date.now()
      };
      db_set_user(row);
      return { ok: true, user: row };
    } catch (err) {
      return { ok: false, code: "verify_lookup_failed", detail: String(err && err.message || "error") };
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
  const cache_rev = db_get_cache_rev();
  const list = [];
  for (const info of by_userid.values()) {
    list.push(format_tag(info.user));
  }
  for (const ws of clients) {
    ws_send(ws, { type: "state", players: list, defaults, cache_rev });
  }
}

function send_asset(ws, hash) {
  const folder = path.join(asset_dir, hash);
  const meta = read_json_file(path.join(folder, "meta.json"), null);
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
  const cache_rev = db_get_cache_rev();
  res.json({ ok: true, tags: out, defaults, cache_rev });
});

app.post("/api/upload", upload.single("file"), async (req, res) => {
  try {
    if (!req.file || !req.file.buffer) return res.status(400).json({ ok: false, code: "upload_missing_file" });
    const kind = get_mime(req.file.buffer);
    if (kind === "bin") return res.status(400).json({ ok: false, code: "upload_bad_type" });
    const meta = await store_upload(req.file.buffer);
    res.json({ ok: true, hash: meta.hash, count: meta.count, kind });
  } catch (err) {
    res.status(500).json({ ok: false, code: "upload_failed", detail: String(err && err.message || "error") });
  }
});

app.post("/api/defaults", (req, res) => {
  res.status(403).json({ ok: false, code: "defaults_locked" });
});

app.post("/api/set", (req, res) => {
  const username = clean_name(req.body.username).toLowerCase();
  if (!username) return res.status(400).json({ ok: false, code: "bad_username" });
  const defaults = db_get_defaults();
  const row = {
    text: safe_text(req.body.text || "", 40),
    text_color: safe_color(req.body.text_color || "", defaults.text_color),
    line_color: safe_color(req.body.line_color || "", defaults.line_color),
    icon: asset_pick(req.body.icon),
    background: asset_pick(req.body.background)
  };
  db_set_tag(username, row);
  db_bump_cache_rev();
  broadcast_state();
  res.json({ ok: true });
});

app.post("/api/remove", (req, res) => {
  const username = clean_name(req.body.username).toLowerCase();
  if (!username) return res.status(400).json({ ok: false, code: "bad_username" });
  db_remove_tag(username);
  db_bump_cache_rev();
  broadcast_state();
  res.json({ ok: true });
});

app.post("/api/reset-user", (req, res) => {
  const username = clean_name(req.body.username).toLowerCase();
  if (!username) return res.status(400).json({ ok: false, code: "bad_username" });
  db_remove_tag(username);
  db_bump_cache_rev();
  broadcast_state();
  res.json({ ok: true });
});

app.post("/api/reset-all", (req, res) => {
  db.prepare("DELETE FROM tags").run();
  db_bump_cache_rev();
  broadcast_state();
  res.json({ ok: true });
});

const server = http.createServer(app);
const wss = new WebSocket.Server({ noServer: true });

server.on("upgrade", (req, socket, head) => {
  const url = String(req.url || "");
  const ok_live = /^\/live\/[a-z0-9]{12,64}$/i.test(url);
  const ok_flow = /^\/flow\/[0-9]{1,20}\/[a-z0-9_:-]{8,128}$/i.test(url);
  const ok_ws = url === "/ws";
  if (!ok_live && !ok_flow && !ok_ws) {
    log_line(`upgrade reject path=${url}`);
    socket.destroy();
    return;
  }
  log_line(`upgrade accept path=${url}`);
  wss.handleUpgrade(req, socket, head, (ws) => {
    wss.emit("connection", ws, req);
  });
});

wss.on("connection", (ws, req) => {
  const path = String(req && req.url || "");
  log_line(`socket open path=${path}`);
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
      const checked = await verify_user(msg);
      if (!checked.ok) {
        log_line(`hello reject path=${path} userid=${String(msg.userid || "")} username=${String(msg.username || "")} display=${String(msg.displayname || "")} code=${checked.code || "reject"} detail=${String(checked.detail || "")}`);
        ws_send(ws, { type: "bye", code: checked.code || "reject", detail: checked.detail || "" });
        ws.close();
        return;
      }
      const user = checked.user;
      log_line(`hello ok path=${path} userid=${user.userid} username=${user.username}`);
      state = { user };
      by_userid.set(String(user.userid), { ws, user });
      const defaults = db_get_defaults();
      const cache_rev = db_get_cache_rev();
      ws_send(ws, { type: "you", tag: format_tag(user), defaults, cache_rev });
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
    log_line(`socket close path=${path} userid=${state && state.user && state.user.userid ? state.user.userid : "none"}`);
    clients.delete(ws);
    if (state && state.user) by_userid.delete(String(state.user.userid));
    broadcast_state();
  });

  ws.on("error", (err) => {
    log_line(`socket error path=${path} reason=${String(err && err.message || "error")}`);
  });
});

server.listen(port, () => {
  process.stdout.write(`client backend on ${port}\n`);
  log_line(`ready port=${port}`);
});
