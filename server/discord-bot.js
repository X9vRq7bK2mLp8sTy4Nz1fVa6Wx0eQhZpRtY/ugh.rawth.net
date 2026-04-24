const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const {
  Client,
  GatewayIntentBits,
  SlashCommandBuilder,
  REST,
  Routes,
  AttachmentBuilder,
  MessageFlags,
  ContainerBuilder,
  TextDisplayBuilder,
  MediaGalleryBuilder,
  MediaGalleryItemBuilder,
  ActionRowBuilder,
  ButtonBuilder,
  ButtonStyle,
  StringSelectMenuBuilder,
  ModalBuilder,
  TextInputBuilder,
  TextInputStyle,
  ChannelType,
  EmbedBuilder
} = require("discord.js");
const { createCanvas, loadImage } = require("@napi-rs/canvas");

const rbxAssetUrlCache = new Map();
const draftStore = new Map();
const approvalStore = new Map();

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

function isDisallowedHost(hostname) {
  const h = String(hostname || "").toLowerCase();
  if (!h || h === "localhost" || h === "0.0.0.0") return true;
  if (h === "::1" || h.startsWith("127.")) return true;
  if (h.startsWith("10.")) return true;
  if (h.startsWith("192.168.")) return true;
  if (/^172\.(1[6-9]|2\d|3[0-1])\./.test(h)) return true;
  return false;
}

async function tryLoadAssetImage(assetDir, rawAsset) {
  if (!rawAsset || typeof rawAsset !== "object") return null;
  if (rawAsset.mode === "rbx") {
    const id = String(rawAsset.value || "").replace("rbxassetid://", "").trim();
    if (!/^\d{2,20}$/.test(id)) return null;
    let imageUrl = rbxAssetUrlCache.get(id);
    if (!imageUrl) {
      try {
        const res = await fetch(`https://thumbnails.roblox.com/v1/assets?assetIds=${encodeURIComponent(id)}&size=420x420&format=Png&isCircular=false`);
        if (res.ok) {
          const body = await res.json();
          const one = body && Array.isArray(body.data) && body.data[0];
          if (one && typeof one.imageUrl === "string" && one.imageUrl) {
            imageUrl = one.imageUrl;
            rbxAssetUrlCache.set(id, imageUrl);
          }
        }
      } catch {}
    }
    if (!imageUrl) return null;
    try {
      return await loadImage(imageUrl);
    } catch {
      return null;
    }
  }
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
    text_effect: safeText((custom && custom.text_effect) || defaults.text_effect || "gradient", 24).toLowerCase(),
    bg_effect: safeText((custom && custom.bg_effect) || defaults.bg_effect || "matrix", 24).toLowerCase(),
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

  const titleX = 40 * scale;
  const titleY = 4 * scale;
  const userX = 40 * scale;
  const userY = 20 * scale;
  ctx.fillStyle = `rgba(${textColor.r},${textColor.g},${textColor.b},1)`;
  ctx.font = `600 ${13 * scale}px "Arial","Helvetica","DejaVu Sans",sans-serif`;
  ctx.textBaseline = "top";
  ctx.textAlign = "left";
  ctx.fillText(merged.text, titleX, titleY + Math.floor(scale * 0.2));

  ctx.fillStyle = "rgba(180,180,180,1)";
  ctx.font = `700 ${10 * scale}px "Arial","Helvetica","DejaVu Sans",sans-serif`;
  ctx.fillText(`@${merged.username}`, userX, userY + Math.floor(scale * 0.7));

  return canvas.toBuffer("image/png");
}

function getDefaults(db, defaultsFallback) {
  const row = db.prepare("SELECT value FROM kv WHERE key = ?").get("defaults");
  if (!row) return defaultsFallback;
  try {
    return JSON.parse(row.value);
  } catch {
    return defaultsFallback;
  }
}

function getTagByUsername(db, username) {
  const row = db.prepare("SELECT payload FROM tags WHERE username = ?").get(String(username).toLowerCase());
  if (!row) return null;
  try {
    return JSON.parse(row.payload);
  } catch {
    return null;
  }
}

function setTagByUsername(db, username, tag) {
  db.prepare("INSERT INTO tags (username, payload) VALUES (?, ?) ON CONFLICT(username) DO UPDATE SET payload = excluded.payload")
    .run(String(username).toLowerCase(), JSON.stringify(tag || {}));
}

function getSetChannelId(db) {
  const row = db.prepare("SELECT value FROM kv WHERE key = ?").get("discord_set_channel");
  if (!row) return "";
  return String(row.value || "");
}

function setSetChannelId(db, channelId) {
  db.prepare("INSERT INTO kv (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value")
    .run("discord_set_channel", String(channelId || ""));
}

function getDraftKey(userId, username) {
  return `${String(userId)}:${String(username).toLowerCase()}`;
}

function shallowClone(obj) {
  const out = {};
  for (const k in obj || {}) out[k] = obj[k];
  return out;
}

function buildEditButtons(username, active) {
  const u = String(username).toLowerCase();
  return [
    new ActionRowBuilder().addComponents(
      new ButtonBuilder().setCustomId(`edit:text:${u}`).setLabel("text").setStyle(ButtonStyle.Secondary),
      new ButtonBuilder().setCustomId(`edit:text_color:${u}`).setLabel("text_color").setStyle(ButtonStyle.Secondary),
      new ButtonBuilder().setCustomId(`edit:line_color:${u}`).setLabel("line_color").setStyle(ButtonStyle.Secondary),
      new ButtonBuilder().setCustomId(`edit:icon:${u}`).setLabel("icon").setStyle(ButtonStyle.Secondary),
      new ButtonBuilder().setCustomId(`edit:background:${u}`).setLabel("background").setStyle(ButtonStyle.Secondary)
    ),
    new ActionRowBuilder().addComponents(
      new ButtonBuilder().setCustomId(`edit:text_effect:${u}`).setLabel("text_effect").setStyle(ButtonStyle.Secondary),
      new ButtonBuilder().setCustomId(`edit:bg_effect:${u}`).setLabel("bg_effect").setStyle(ButtonStyle.Secondary)
    ),
    new ActionRowBuilder().addComponents(
      new ButtonBuilder().setCustomId(`edit:reset:${u}`).setLabel("reset").setStyle(ButtonStyle.Danger),
      new ButtonBuilder().setCustomId(`edit:submit:${u}`).setLabel("submit").setStyle(ButtonStyle.Success),
      new ButtonBuilder().setCustomId(`edit:status:${u}`).setLabel(active ? "active" : "inactive").setStyle(ButtonStyle.Secondary).setDisabled(true)
    )
  ];
}

async function makeEditPayload({ db, assetDir, defaultsFallback, username, tag, active, heading }) {
  const defaults = getDefaults(db, defaultsFallback);
  const merged = mergeTag(defaults, tag, username);
  const png = await renderTagImage(assetDir, merged);
  const fileName = `preview-${String(username).toLowerCase()}-${crypto.randomBytes(4).toString("hex")}.png`;
  return {
    flags: MessageFlags.Ephemeral | MessageFlags.IsComponentsV2,
    components: [
      new ContainerBuilder().addTextDisplayComponents(
        new TextDisplayBuilder().setContent(heading),
        new TextDisplayBuilder().setContent(`user: ${username}`)
      ),
      new MediaGalleryBuilder().addItems(
        new MediaGalleryItemBuilder().setURL(`attachment://${fileName}`)
      ),
      ...buildEditButtons(username, active)
    ],
    files: [new AttachmentBuilder(png, { name: fileName })]
  };
}

async function resolveInputAsset(raw, storeUpload) {
  const text = String(raw || "").trim();
  if (text === "") return null;
  if (/^\d{2,20}$/.test(text)) return { mode: "rbx", value: `rbxassetid://${text}` };
  if (/^rbxassetid:\/\/\d{2,20}$/i.test(text)) return { mode: "rbx", value: text.toLowerCase() };
  let url;
  try {
    url = new URL(text);
  } catch {
    throw new Error("invalid_url");
  }
  if (url.protocol !== "https:") throw new Error("url_must_be_https");
  if (isDisallowedHost(url.hostname)) throw new Error("disallowed_host");
  const res = await fetch(url.toString(), { redirect: "follow" });
  if (!res.ok) throw new Error("download_failed");
  const arr = new Uint8Array(await res.arrayBuffer());
  if (!arr || arr.length < 1 || arr.length > 15 * 1024 * 1024) throw new Error("bad_file_size");
  const meta = await storeUpload(Buffer.from(arr));
  if (!meta || !meta.hash) throw new Error("upload_failed");
  return { mode: "hash", value: String(meta.hash) };
}

function parseCustomId(customId) {
  const parts = String(customId || "").split(":");
  return {
    root: parts[0] || "",
    action: parts[1] || "",
    field: parts[2] || "",
    username: parts[3] || "",
    requestId: parts[2] || ""
  };
}

function buildFieldModal(field, username) {
  const modal = new ModalBuilder().setCustomId(`modal:${field}:${String(username).toLowerCase()}`).setTitle(`edit ${field}`);
  const input = new TextInputBuilder().setCustomId("value").setLabel(field).setStyle(TextInputStyle.Short).setRequired(false);
  if (field === "text") input.setMaxLength(40);
  if (field === "text_color" || field === "line_color") input.setPlaceholder("#FFFFFF");
  if (field === "icon" || field === "background") input.setPlaceholder("https://... or rbxassetid://...");
  modal.addComponents(new ActionRowBuilder().addComponents(input));
  return modal;
}

function buildEffectPicker(field, username, currentValue) {
  const u = String(username).toLowerCase();
  const current = String(currentValue || "").toLowerCase();
  const isText = field === "text_effect";
  const choices = isText
    ? [
        { label: "gradient", value: "gradient" },
        { label: "wave", value: "wave" },
        { label: "typewriter", value: "typewriter" },
        { label: "rainbow", value: "rainbow" },
        { label: "glitch", value: "glitch" },
        { label: "none", value: "none" }
      ]
    : [
        { label: "matrix", value: "matrix" },
        { label: "pulse", value: "pulse" },
        { label: "scanline", value: "scanline" },
        { label: "fire", value: "fire" },
        { label: "glitch", value: "glitch" },
        { label: "rainbow", value: "rainbow" },
        { label: "snow", value: "snow" },
        { label: "glow", value: "glow" },
        { label: "none", value: "none" }
      ];
  const select = new StringSelectMenuBuilder()
    .setCustomId(`select:${field}:${u}`)
    .setPlaceholder(`${field} (${current || "select"})`)
    .setMinValues(1)
    .setMaxValues(1)
    .addOptions(
      choices.map((c) => ({
        label: c.label,
        value: c.value,
        default: c.value === current
      }))
    );
  return new ActionRowBuilder().addComponents(select);
}

function currentActiveByUsername(activeUsers, username) {
  const key = String(username || "").toLowerCase();
  for (const one of activeUsers.values()) {
    const u = String(one.user && one.user.username || "").toLowerCase();
    if (u === key) return true;
  }
  return false;
}

async function notifyDm(client, userId, text, png, username) {
  try {
    const user = await client.users.fetch(userId);
    if (!user) return;
    const fileName = `approved-${String(username).toLowerCase()}.png`;
    await user.send({
      flags: MessageFlags.IsComponentsV2,
      components: [
        new ContainerBuilder().addTextDisplayComponents(new TextDisplayBuilder().setContent(text)),
        new MediaGalleryBuilder().addItems(new MediaGalleryItemBuilder().setURL(`attachment://${fileName}`))
      ],
      files: [new AttachmentBuilder(png, { name: fileName })]
    });
  } catch {}
}

function initDiscordBot({ db, assetDir, defaultsFallback, logLine, storeUpload, bumpCacheRev, broadcastState, activeUsers }) {
  const token = String(process.env.DISCORD_BOT_TOKEN || "").trim();
  const appId = String(process.env.DISCORD_CLIENT_ID || "").trim();
  const guildId = String(process.env.DISCORD_GUILD_ID || "").trim();
  if (!token || !appId) {
    if (typeof logLine === "function") logLine("discord disabled missing DISCORD_BOT_TOKEN or DISCORD_CLIENT_ID");
    return null;
  }

  const client = new Client({ intents: [GatewayIntentBits.Guilds, GatewayIntentBits.DirectMessages], partials: ["CHANNEL"] });
  const commands = [
    new SlashCommandBuilder()
      .setName("lookup")
      .setDescription("Render a user nametag preview")
      .addStringOption((o) => o.setName("username").setDescription("meow").setRequired(true)),
    new SlashCommandBuilder()
      .setName("set")
      .setDescription("Set approval channel")
      .addChannelOption((o) =>
        o.setName("channel").setDescription("meow").addChannelTypes(ChannelType.GuildText).setRequired(true)
      ),
    new SlashCommandBuilder()
      .setName("edit")
      .setDescription("Edit one user tag")
      .addStringOption((o) => o.setName("username").setDescription("meow").setRequired(true))
  ];

  client.once("ready", async () => {
    try {
      const rest = new REST({ version: "10" }).setToken(token);
      const body = commands.map((x) => x.toJSON());
      if (guildId) {
        await rest.put(Routes.applicationGuildCommands(appId, guildId), { body });
        if (typeof logLine === "function") logLine(`discord ready as ${client.user.tag} guild commands synced`);
      } else {
        await rest.put(Routes.applicationCommands(appId), { body });
        if (typeof logLine === "function") logLine(`discord ready as ${client.user.tag} global commands synced`);
      }
    } catch (err) {
      if (typeof logLine === "function") logLine(`discord command sync failed reason=${String(err && err.message || "error")}`);
    }
  });

  client.on("interactionCreate", async (interaction) => {
    try {
      if (interaction.isChatInputCommand()) {
        if (interaction.commandName === "lookup") {
          const username = cleanName(interaction.options.getString("username", true));
          if (!username) {
            await interaction.reply({
              flags: MessageFlags.Ephemeral | MessageFlags.IsComponentsV2,
              components: [new ContainerBuilder().addTextDisplayComponents(new TextDisplayBuilder().setContent("Invalid username."))]
            });
            return;
          }
          const defaults = getDefaults(db, defaultsFallback);
          const custom = getTagByUsername(db, username);
          const merged = mergeTag(defaults || defaultsFallback, custom, username);
          const png = await renderTagImage(assetDir, merged);
          const fileName = `nametag-${username.toLowerCase()}.png`;
          await interaction.reply({
            flags: MessageFlags.IsComponentsV2,
            components: [
              new ContainerBuilder().addTextDisplayComponents(
                new TextDisplayBuilder().setContent(`Found custom nametag for ${username}!`)
              ),
              new MediaGalleryBuilder().addItems(
                new MediaGalleryItemBuilder().setURL(`attachment://${fileName}`)
              )
            ],
            files: [new AttachmentBuilder(png, { name: fileName })]
          });
          return;
        }

        if (interaction.commandName === "set") {
          const channel = interaction.options.getChannel("channel", true);
          setSetChannelId(db, channel.id);
          await interaction.reply({
            flags: MessageFlags.Ephemeral | MessageFlags.IsComponentsV2,
            components: [
              new ContainerBuilder().addTextDisplayComponents(
                new TextDisplayBuilder().setContent(`Set approval channel to <#${channel.id}>`)
              )
            ]
          });
          return;
        }

        if (interaction.commandName === "edit") {
          const username = cleanName(interaction.options.getString("username", true));
          if (!username) {
            await interaction.reply({
              flags: MessageFlags.Ephemeral | MessageFlags.IsComponentsV2,
              components: [new ContainerBuilder().addTextDisplayComponents(new TextDisplayBuilder().setContent("Invalid username."))]
            });
            return;
          }
          const key = getDraftKey(interaction.user.id, username);
          const base = getTagByUsername(db, username) || {};
          draftStore.set(key, { username, tag: shallowClone(base), touchedAt: Date.now() });
          const active = currentActiveByUsername(activeUsers, username);
          const payload = await makeEditPayload({
            db,
            assetDir,
            defaultsFallback,
            username,
            tag: base,
            active,
            heading: `Editing ${username}`
          });
          await interaction.reply(payload);
          return;
        }
      }

      if (interaction.isButton()) {
        const p = parseCustomId(interaction.customId);
        if (p.root === "edit" && p.action === "status") {
          await interaction.deferUpdate();
          return;
        }

        if (p.root === "edit" && p.action === "reset") {
          const key = getDraftKey(interaction.user.id, p.field);
          const empty = {};
          draftStore.set(key, { username: p.field, tag: empty, touchedAt: Date.now() });
          const active = currentActiveByUsername(activeUsers, p.field);
          const payload = await makeEditPayload({
            db,
            assetDir,
            defaultsFallback,
            username: p.field,
            tag: empty,
            active,
            heading: `Editing ${p.field}`
          });
          await interaction.update(payload);
          return;
        }

        if (p.root === "edit" && p.action === "submit") {
          const key = getDraftKey(interaction.user.id, p.field);
          const draft = draftStore.get(key);
          if (!draft) {
            await interaction.reply({
              flags: MessageFlags.Ephemeral | MessageFlags.IsComponentsV2,
              components: [new ContainerBuilder().addTextDisplayComponents(new TextDisplayBuilder().setContent("No draft exists."))]
            });
            return;
          }
          const channelId = getSetChannelId(db);
          if (!channelId) {
            await interaction.reply({
              flags: MessageFlags.Ephemeral | MessageFlags.IsComponentsV2,
              components: [new ContainerBuilder().addTextDisplayComponents(new TextDisplayBuilder().setContent("Set approval channel first with /set."))]
            });
            return;
          }
          const channel = await client.channels.fetch(channelId).catch(() => null);
          if (!channel || !channel.isTextBased()) {
            await interaction.reply({
              flags: MessageFlags.Ephemeral | MessageFlags.IsComponentsV2,
              components: [new ContainerBuilder().addTextDisplayComponents(new TextDisplayBuilder().setContent("Approval channel is invalid."))]
            });
            return;
          }
          const defaults = getDefaults(db, defaultsFallback);
          const merged = mergeTag(defaults, draft.tag, draft.username);
          const png = await renderTagImage(assetDir, merged);
          const reqId = crypto.randomBytes(8).toString("hex");
          approvalStore.set(reqId, {
            requesterId: interaction.user.id,
            username: draft.username,
            tag: shallowClone(draft.tag),
            createdAt: Date.now()
          });
          const fileName = `request-${reqId}.png`;
          const row = new ActionRowBuilder().addComponents(
            new ButtonBuilder().setCustomId(`approval:approve:${reqId}`).setLabel("approve").setStyle(ButtonStyle.Success),
            new ButtonBuilder().setCustomId(`approval:reject:${reqId}`).setLabel("reject").setStyle(ButtonStyle.Danger)
          );
          const embed = new EmbedBuilder()
            .setTitle("Submission requested")
            .setDescription(`username: ${draft.username}\nrequested by: <@${interaction.user.id}>`)
            .setColor(0x6c757d)
            .setImage(`attachment://${fileName}`);
          await channel.send({
            embeds: [embed],
            components: [row],
            files: [new AttachmentBuilder(png, { name: fileName })]
          });
          await interaction.reply({
            flags: MessageFlags.Ephemeral | MessageFlags.IsComponentsV2,
            components: [new ContainerBuilder().addTextDisplayComponents(new TextDisplayBuilder().setContent("Submission requested."))]
          });
          return;
        }

        if (p.root === "edit") {
          const field = p.action;
          if (field === "text_effect" || field === "bg_effect") {
            const key = getDraftKey(interaction.user.id, p.field);
            const draft = draftStore.get(key) || { username: p.field, tag: shallowClone(getTagByUsername(db, p.field) || {}), touchedAt: Date.now() };
            draftStore.set(key, draft);
            const row = buildEffectPicker(field, p.field, draft.tag[field] || "");
            await interaction.reply({
              flags: MessageFlags.Ephemeral | MessageFlags.IsComponentsV2,
              components: [
                new ContainerBuilder().addTextDisplayComponents(
                  new TextDisplayBuilder().setContent(`Pick ${field} for ${p.field}`)
                ),
                row
              ]
            });
            return;
          }
          if (!["text", "text_color", "line_color", "icon", "background"].includes(field)) return;
          const modal = buildFieldModal(field, p.field);
          await interaction.showModal(modal);
          return;
        }

        if (p.root === "approval") {
          const reqId = p.requestId;
          const action = p.action;
          const data = approvalStore.get(reqId);
          if (!data) {
            await interaction.reply({
              flags: MessageFlags.Ephemeral | MessageFlags.IsComponentsV2,
              components: [new ContainerBuilder().addTextDisplayComponents(new TextDisplayBuilder().setContent("Request not found."))]
            });
            return;
          }
          const defaults = getDefaults(db, defaultsFallback);
          const merged = mergeTag(defaults, data.tag, data.username);
          const png = await renderTagImage(assetDir, merged);
          if (action === "approve") {
            setTagByUsername(db, data.username, data.tag);
            bumpCacheRev();
            broadcastState();
            approvalStore.delete(reqId);
            const embed = new EmbedBuilder()
              .setTitle("Approved")
              .setDescription(`username: ${data.username}\napproved by: <@${interaction.user.id}>`)
              .setColor(0x28a745)
              .setImage("attachment://approved.png");
            const row = new ActionRowBuilder().addComponents(
              new ButtonBuilder().setCustomId("noop").setLabel("approved").setStyle(ButtonStyle.Success).setDisabled(true),
              new ButtonBuilder().setCustomId("noop2").setLabel("rejected").setStyle(ButtonStyle.Secondary).setDisabled(true)
            );
            await interaction.update({
              embeds: [embed],
              components: [row],
              files: [new AttachmentBuilder(png, { name: "approved.png" })]
            });
            await notifyDm(client, data.requesterId, `Your edit for ${data.username} was approved.`, png, data.username);
            return;
          }
          if (action === "reject") {
            approvalStore.delete(reqId);
            const embed = new EmbedBuilder()
              .setTitle("Rejected")
              .setDescription(`username: ${data.username}\nrejected by: <@${interaction.user.id}>`)
              .setColor(0xdc3545)
              .setImage("attachment://rejected.png");
            const row = new ActionRowBuilder().addComponents(
              new ButtonBuilder().setCustomId("noop").setLabel("approved").setStyle(ButtonStyle.Secondary).setDisabled(true),
              new ButtonBuilder().setCustomId("noop2").setLabel("rejected").setStyle(ButtonStyle.Danger).setDisabled(true)
            );
            await interaction.update({
              embeds: [embed],
              components: [row],
              files: [new AttachmentBuilder(png, { name: "rejected.png" })]
            });
            await notifyDm(client, data.requesterId, `Your edit for ${data.username} was rejected.`, png, data.username);
            return;
          }
        }
      }

      if (interaction.isStringSelectMenu()) {
        const p = parseCustomId(interaction.customId);
        if (p.root !== "select") return;
        const field = p.action;
        const username = cleanName(p.field);
        if (!username) return;
        if (field !== "text_effect" && field !== "bg_effect") return;
        const value = String(interaction.values && interaction.values[0] || "").toLowerCase();
        const allowed = field === "text_effect"
          ? new Set(["gradient", "wave", "typewriter", "rainbow", "glitch", "none"])
          : new Set(["matrix", "pulse", "scanline", "fire", "glitch", "rainbow", "snow", "glow", "none"]);
        if (!allowed.has(value)) return;
        const key = getDraftKey(interaction.user.id, username);
        const base = draftStore.get(key) || { username, tag: shallowClone(getTagByUsername(db, username) || {}), touchedAt: Date.now() };
        base.tag[field] = value;
        base.touchedAt = Date.now();
        draftStore.set(key, base);
        const active = currentActiveByUsername(activeUsers, username);
        const payload = await makeEditPayload({
          db,
          assetDir,
          defaultsFallback,
          username,
          tag: base.tag,
          active,
          heading: `Editing ${username}`
        });
        await interaction.reply(payload);
        return;
      }

      if (interaction.isModalSubmit()) {
        const parts = String(interaction.customId || "").split(":");
        if (parts[0] !== "modal") return;
        const field = parts[1] || "";
        const username = cleanName(parts[2] || "");
        if (!username) return;
        const key = getDraftKey(interaction.user.id, username);
        const base = draftStore.get(key) || { username, tag: shallowClone(getTagByUsername(db, username) || {}), touchedAt: Date.now() };
        const val = String(interaction.fields.getTextInputValue("value") || "").trim();
        if (field === "text") {
          base.tag.text = safeText(val, 40);
        } else if (field === "text_color") {
          base.tag.text_color = safeColor(val, base.tag.text_color || "#FFFFFF");
        } else if (field === "line_color") {
          base.tag.line_color = safeColor(val, base.tag.line_color || "#8F8F91");
        } else if (field === "icon") {
          base.tag.icon = await resolveInputAsset(val, storeUpload);
        } else if (field === "background") {
          base.tag.background = await resolveInputAsset(val, storeUpload);
        } else {
          return;
        }
        base.touchedAt = Date.now();
        draftStore.set(key, base);
        const active = currentActiveByUsername(activeUsers, username);
        const payload = await makeEditPayload({
          db,
          assetDir,
          defaultsFallback,
          username,
          tag: base.tag,
          active,
          heading: `Editing ${username}`
        });
        await interaction.reply(payload);
      }
    } catch (err) {
      try {
        if (interaction.deferred || interaction.replied) {
          await interaction.followUp({
            flags: MessageFlags.Ephemeral | MessageFlags.IsComponentsV2,
            components: [new ContainerBuilder().addTextDisplayComponents(new TextDisplayBuilder().setContent("Action failed."))]
          });
        } else {
          await interaction.reply({
            flags: MessageFlags.Ephemeral | MessageFlags.IsComponentsV2,
            components: [new ContainerBuilder().addTextDisplayComponents(new TextDisplayBuilder().setContent("Action failed."))]
          });
        }
      } catch {}
      if (typeof logLine === "function") logLine(`discord interaction failed reason=${String(err && err.message || "error")}`);
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

module.exports = { initDiscordBot };
