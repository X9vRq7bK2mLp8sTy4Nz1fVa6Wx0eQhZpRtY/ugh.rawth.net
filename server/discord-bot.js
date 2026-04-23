const fs = require("fs");
const path = require("path");
const {
  Client,
  GatewayIntentBits,
  SlashCommandBuilder,
  REST,
  Routes,
  AttachmentBuilder,
  MessageFlags,
  ContainerBuilder,
  TextDisplayBuilder
} = require("discord.js");
const { createCanvas, loadImage } = require("@napi-rs/canvas");

function safeText(text, max) {
  return String(text || "")
    .replace(/[^\x20-\x7E]/g, "")
    .trim()
    .slice(0, max);
}

function safeColor(text, fallback) {
  const val = String(text || "").trim();
  if (/^#[0-9a-fA-F]{6}$/.test(val)) return val.toUpperCase();
  return fallback;
}

function cleanName(text) {
  return String(text || "")
    .trim()
    .replace(/[^a-zA-Z0-9_]/g, "")
    .slice(0, 20);
}

function parseHex(hex, fallback) {
  const raw = String(hex || "").replace("#", "");
  if (!/^[0-9a-fA-F]{6}$/.test(raw)) return fallback;
  return {
    r: parseInt(raw.slice(0, 2), 16),
    g: parseInt(raw.slice(2, 4), 16),
    b: parseInt(raw.slice(4, 6), 16)
  };
}

function roundRect(ctx, x, y, w, h, r) {
  const rr = Math.min(r, w * 0.5, h * 0.5);
  ctx.beginPath();
  ctx.moveTo(x + rr, y);
  ctx.arcTo(x + w, y, x + w, y + h, rr);
  ctx.arcTo(x + w, y + h, x, y + h, rr);
  ctx.arcTo(x, y + h, x, y, rr);
  ctx.arcTo(x, y, x + w, y, rr);
  ctx.closePath();
}

async function tryLoadAssetImage(assetDir, rawAsset) {
  if (!rawAsset || typeof rawAsset !== "object") return null;
  if (rawAsset.mode === "hash") {
    const hash = String(rawAsset.value || "");
    if (!/^[0-9]{6,24}$/.test(hash)) return null;
    const metaFile = path.join(assetDir, hash, "meta.json");
    if (!fs.existsSync(metaFile)) return null;
    let meta;
    try {
      meta = JSON.parse(fs.readFileSync(metaFile, "utf8"));
    } catch {
      return null;
    }
    if (!meta || !Array.isArray(meta.frames) || meta.frames.length < 1) return null;
    const first = String(meta.frames[0].file || "");
    if (!/^[a-zA-Z0-9._-]+$/.test(first)) return null;
    const file = path.join(assetDir, hash, first);
    if (!fs.existsSync(file)) return null;
    try {
      return await loadImage(file);
    } catch {
      return null;
    }
  }
  return null;
}

function mergeTag(defaults, custom, username) {
  const icon = custom && custom.icon && typeof custom.icon === "object" ? custom.icon : defaults.icon;
  const background = custom && custom.background && typeof custom.background === "object" ? custom.background : defaults.background;
  return {
    text: safeText((custom && custom.text) || defaults.text || "NOVOLINE", 40),
    text_color: safeColor((custom && custom.text_color) || defaults.text_color || "#FFFFFF", "#FFFFFF"),
    line_color: safeColor((custom && custom.line_color) || defaults.line_color || "#8F8F91", "#8F8F91"),
    icon,
    background,
    username: safeText(username, 20)
  };
}

async function renderTagImage(assetDir, merged) {
  const scale = 4;
  const width = 170 * scale;
  const height = 42 * scale;
  const canvas = createCanvas(width, height);
  const ctx = canvas.getContext("2d");

  const bgColor = parseHex("#08080C", { r: 8, g: 8, b: 12 });
  const strokeColor = parseHex(merged.line_color, { r: 143, g: 143, b: 145 });
  const textColor = parseHex(merged.text_color, { r: 255, g: 255, b: 255 });

  roundRect(ctx, 0, 0, width, height, 9 * scale);
  ctx.fillStyle = `rgba(${bgColor.r},${bgColor.g},${bgColor.b},1)`;
  ctx.fill();

  const bgImg = await tryLoadAssetImage(assetDir, merged.background);
  if (bgImg) {
    ctx.save();
    roundRect(ctx, 0, 0, width, height, 9 * scale);
    ctx.clip();
    const imgRatio = bgImg.width / bgImg.height;
    const rectRatio = width / height;
    let sw = bgImg.width;
    let sh = bgImg.height;
    let sx = 0;
    let sy = 0;
    if (imgRatio > rectRatio) {
      sw = bgImg.height * rectRatio;
      sx = (bgImg.width - sw) * 0.5;
    } else {
      sh = bgImg.width / rectRatio;
      sy = (bgImg.height - sh) * 0.5;
    }
    ctx.globalAlpha = 0.78;
    ctx.drawImage(bgImg, sx, sy, sw, sh, 0, 0, width, height);
    ctx.restore();
  }

  ctx.lineWidth = 1.5 * scale;
  ctx.strokeStyle = `rgba(${strokeColor.r},${strokeColor.g},${strokeColor.b},1)`;
  roundRect(ctx, 0.75 * scale, 0.75 * scale, width - 1.5 * scale, height - 1.5 * scale, 9 * scale);
  ctx.stroke();

  const iconX = 7 * scale;
  const iconY = 7 * scale;
  const iconSize = 28 * scale;
  const iconImg = await tryLoadAssetImage(assetDir, merged.icon);
  if (iconImg) {
    ctx.save();
    ctx.beginPath();
    ctx.arc(iconX + iconSize / 2, iconY + iconSize / 2, iconSize / 2, 0, Math.PI * 2);
    ctx.closePath();
    ctx.clip();
    const imgRatio = iconImg.width / iconImg.height;
    const rectRatio = 1;
    let sw = iconImg.width;
    let sh = iconImg.height;
    let sx = 0;
    let sy = 0;
    if (imgRatio > rectRatio) {
      sw = iconImg.height * rectRatio;
      sx = (iconImg.width - sw) * 0.5;
    } else {
      sh = iconImg.width / rectRatio;
      sy = (iconImg.height - sh) * 0.5;
    }
    ctx.drawImage(iconImg, sx, sy, sw, sh, iconX, iconY, iconSize, iconSize);
    ctx.restore();
  } else {
    ctx.fillStyle = "rgba(255,255,255,0.18)";
    ctx.beginPath();
    ctx.arc(iconX + iconSize / 2, iconY + iconSize / 2, iconSize / 2, 0, Math.PI * 2);
    ctx.fill();
  }

  ctx.fillStyle = `rgba(${textColor.r},${textColor.g},${textColor.b},1)`;
  ctx.font = `bold ${14 * scale}px sans-serif`;
  ctx.textBaseline = "top";
  ctx.fillText(merged.text, 40 * scale, 4 * scale);

  ctx.fillStyle = "rgba(180,180,180,1)";
  ctx.font = `bold ${10 * scale}px sans-serif`;
  ctx.fillText(`@${merged.username}`, 40 * scale, 20 * scale);

  return canvas.toBuffer("image/png");
}

function initDiscordBot({ db, assetDir, defaultsFallback, logLine }) {
  const token = String(process.env.DISCORD_BOT_TOKEN || "").trim();
  const appId = String(process.env.DISCORD_CLIENT_ID || "").trim();
  const guildId = String(process.env.DISCORD_GUILD_ID || "").trim();
  if (!token || !appId) {
    if (typeof logLine === "function") logLine("discord disabled missing DISCORD_BOT_TOKEN or DISCORD_CLIENT_ID");
    return null;
  }

  const client = new Client({ intents: [GatewayIntentBits.Guilds] });

  const command = new SlashCommandBuilder()
    .setName("lookup")
    .setDescription("Render a user nametag preview")
    .addStringOption((o) =>
      o.setName("username").setDescription("Roblox username").setRequired(true)
    );

  client.once("ready", async () => {
    try {
      const rest = new REST({ version: "10" }).setToken(token);
      const body = [command.toJSON()];
      if (guildId) {
        await rest.put(Routes.applicationGuildCommands(appId, guildId), { body });
        if (typeof logLine === "function") logLine(`discord ready as ${client.user.tag} guild command synced`);
      } else {
        await rest.put(Routes.applicationCommands(appId), { body });
        if (typeof logLine === "function") logLine(`discord ready as ${client.user.tag} global command synced`);
      }
    } catch (err) {
      if (typeof logLine === "function") logLine(`discord command sync failed reason=${String(err && err.message || "error")}`);
    }
  });

  client.on("interactionCreate", async (interaction) => {
    if (!interaction.isChatInputCommand()) return;
    if (interaction.commandName !== "lookup") return;
    const rawUser = interaction.options.getString("username", true);
    const username = cleanName(rawUser);
    if (!username) {
      await interaction.reply({
        flags: MessageFlags.Ephemeral | MessageFlags.IsComponentsV2,
        components: [
          new ContainerBuilder().addTextDisplayComponents(
            new TextDisplayBuilder().setContent("Invalid username.")
          )
        ]
      });
      return;
    }
    try {
      const defaultsRow = db.prepare("SELECT value FROM kv WHERE key = ?").get("defaults");
      const defaults = defaultsRow ? JSON.parse(defaultsRow.value) : defaultsFallback;
      const row = db.prepare("SELECT payload FROM tags WHERE username = ?").get(username.toLowerCase());
      const custom = row ? JSON.parse(row.payload) : null;
      const merged = mergeTag(defaults || defaultsFallback, custom, username);
      const png = await renderTagImage(assetDir, merged);
      const file = new AttachmentBuilder(png, { name: `nametag-${username.toLowerCase()}.png` });
      await interaction.reply({
        flags: MessageFlags.IsComponentsV2,
        components: [
          new ContainerBuilder().addTextDisplayComponents(
            new TextDisplayBuilder().setContent(`Found custom nametag for ${username}!`)
          )
        ],
        files: [file]
      });
    } catch (err) {
      await interaction.reply({
        flags: MessageFlags.Ephemeral | MessageFlags.IsComponentsV2,
        components: [
          new ContainerBuilder().addTextDisplayComponents(
            new TextDisplayBuilder().setContent("Lookup failed.")
          )
        ]
      });
      if (typeof logLine === "function") logLine(`discord lookup failed username=${username} reason=${String(err && err.message || "error")}`);
    }
  });

  client.on("error", (err) => {
    if (typeof logLine === "function") logLine(`discord error reason=${String(err && err.message || "error")}`);
  });

  client.login(token).catch((err) => {
    if (typeof logLine === "function") logLine(`discord login failed reason=${String(err && err.message || "error")}`);
  });

  return client;
}

module.exports = {
  initDiscordBot
};
