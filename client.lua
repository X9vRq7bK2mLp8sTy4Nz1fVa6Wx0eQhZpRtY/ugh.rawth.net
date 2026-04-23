local players = game:GetService("Players")
local run = game:GetService("RunService")
local input = game:GetService("UserInputService")
local local_player = players.LocalPlayer
local ui_folder_name = "_client_remote_tags"
local player_gui = local_player:FindFirstChildOfClass("PlayerGui") or local_player:WaitForChild("PlayerGui")

local function pick_ui_parent()
    local options = { gethui, get_hidden_gui, gethiddengui }
    for _, fn in ipairs(options) do
        if type(fn) == "function" then
            local ok, parent = pcall(fn)
            if ok and parent then
                return parent
            end
        end
    end
    local folder = player_gui:FindFirstChild(ui_folder_name)
    if not folder then
        folder = Instance.new("ScreenGui")
        folder.Name = ui_folder_name
        folder.ResetOnSpawn = false
        folder.Parent = player_gui
    end
    return folder
end

local gui_parent = pick_ui_parent()

local ws_host = "wss://ugh.rawth.net"
local ws_urls = {}
local ws = nil
local ws_last = 0
local ws_next_try = 1
local ws_last_fail_log = 0
local ws_last_no_api_log = 0
local cache_rev = 1

local folder_root = "client_cache"
local folder_asset = folder_root .. "/asset_1"
if not isfolder(folder_root) then makefolder(folder_root) end
if not isfolder(folder_asset) then makefolder(folder_asset) end

local get_asset = getcustomasset
local screen = Instance.new("ScreenGui")
screen.Name = "client_tags"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = gui_parent

local cfg_default = {
    text = "NOVOLINE",
    text_color = Color3.fromRGB(255, 255, 255),
    line_color = Color3.fromRGB(143, 143, 145),
    icon = { mode = "rbx", value = "rbxassetid://134633682532885" },
    background = { mode = "rbx", value = "rbxassetid://91753130662474" }
}

local cfg_you = nil
local net_players = {}
local cache_known = {}
local tags = {}
local gif_jobs = {}
local gif_cache = {}
local asset_ids = {}
local pending_asset = {}

local function clear_gif_cache_for_hash(hash)
    local h = ":" .. tostring(hash)
    for key in pairs(gif_cache) do
        if string.sub(tostring(key), -#h) == h then
            gif_cache[key] = nil
        end
    end
end
local function log(text)
    print("[client] " .. tostring(text))
end
local b64_map = {}
do
    local set = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #set do
        b64_map[set:sub(i, i)] = i - 1
    end
end

local function b64_decode(raw)
    local text = tostring(raw or ""):gsub("%s+", "")
    local out = {}
    local i = 1
    while i <= #text do
        local a = text:sub(i, i)
        local b = text:sub(i + 1, i + 1)
        local c = text:sub(i + 2, i + 2)
        local d = text:sub(i + 3, i + 3)
        local av = b64_map[a] or 0
        local bv = b64_map[b] or 0
        local cv = c == "=" and 0 or (b64_map[c] or 0)
        local dv = d == "=" and 0 or (b64_map[d] or 0)
        local triple = av * 262144 + bv * 4096 + cv * 64 + dv
        local n1 = math.floor(triple / 65536) % 256
        local n2 = math.floor(triple / 256) % 256
        local n3 = triple % 256
        out[#out + 1] = string.char(n1)
        if c ~= "=" then out[#out + 1] = string.char(n2) end
        if d ~= "=" then out[#out + 1] = string.char(n3) end
        i += 4
    end
    return table.concat(out)
end

local function make_session()
    local seed = tostring(local_player.UserId) .. ":" .. tostring(game.GameId) .. ":" .. tostring(game.JobId) .. ":" .. tostring(tick()) .. ":" .. tostring(os.clock())
    local mix = 17
    local out = {}
    for i = 1, #seed do
        local code = seed:byte(i)
        mix = (mix * 131 + code * (i + 11)) % 2147483629
        local val = (mix % 26) + 97
        out[#out + 1] = string.char(val)
    end
    return table.concat(out):sub(1, 24)
end

local session_id = make_session()
ws_urls = {
    ws_host .. "/live/" .. session_id,
    ws_host .. "/flow/" .. tostring(local_player.UserId) .. "/" .. session_id,
    ws_host .. "/ws"
}
log("loaded")
log("default tags ready")

local function parse_color(hex, fallback)
    local raw = tostring(hex or ""):gsub("#", "")
    if #raw ~= 6 then return fallback end
    local r = tonumber(raw:sub(1, 2), 16)
    local g = tonumber(raw:sub(3, 4), 16)
    local b = tonumber(raw:sub(5, 6), 16)
    if not r or not g or not b then return fallback end
    return Color3.fromRGB(r, g, b)
end

local function deep_copy(data)
    local out = {}
    for k, v in pairs(data) do
        if type(v) == "table" then
            local t = {}
            for a, b in pairs(v) do t[a] = b end
            out[k] = t
        else
            out[k] = v
        end
    end
    return out
end

local function normalize_tag(raw)
    local out = deep_copy(cfg_default)
    if type(raw) ~= "table" then return out end
    out.text = tostring(raw.text or out.text):sub(1, 40)
    out.text_color = parse_color(raw.text_color, out.text_color)
    out.line_color = parse_color(raw.line_color, out.line_color)
    if type(raw.icon) == "table" and raw.icon.mode and raw.icon.value then
        out.icon = { mode = tostring(raw.icon.mode), value = tostring(raw.icon.value) }
    end
    if type(raw.background) == "table" and raw.background.mode and raw.background.value then
        out.background = { mode = tostring(raw.background.mode), value = tostring(raw.background.value) }
    end
    return out
end

local function frame_folder(hash)
    return folder_asset .. "/" .. tostring(hash)
end

local function switch_cache_rev(next_rev)
    local n = tonumber(next_rev) or 1
    if n < 1 then n = 1 end
    n = math.floor(n)
    if n == cache_rev then return end
    cache_rev = n
    folder_asset = folder_root .. "/asset_" .. tostring(cache_rev)
    if not isfolder(folder_asset) then makefolder(folder_asset) end
    gif_cache = {}
    asset_ids = {}
    pending_asset = {}
    for key, job in pairs(gif_jobs) do
        if job then
            job.live = false
        end
        gif_jobs[key] = nil
    end
    log("cache rev " .. tostring(cache_rev))
end

local function frame_meta_file(hash)
    return frame_folder(hash) .. "/meta.json"
end

local function decode_json(raw)
    local ok, out = pcall(function()
        return game:GetService("HttpService"):JSONDecode(raw)
    end)
    if ok then return out end
    return nil
end

local function encode_json(raw)
    local ok, out = pcall(function()
        return game:GetService("HttpService"):JSONEncode(raw)
    end)
    if ok then return out end
    return ""
end

local function asset_path_from_hash(hash)
    if not hash then return nil end
    local meta_file = frame_meta_file(hash)
    if not isfile(meta_file) then return nil end
    local meta = decode_json(readfile(meta_file))
    if type(meta) ~= "table" or type(meta.frames) ~= "table" then return nil end
    local list = {}
    for _, row in ipairs(meta.frames) do
        local one = frame_folder(hash) .. "/" .. tostring(row.file)
        if isfile(one) then
            list[#list + 1] = { file = one, delay = tonumber(row.delay) or 100 }
        end
    end
    if #list == 0 then return nil end
    return list
end

local function asset_id(file)
    local hit = asset_ids[file]
    if hit then return hit end
    local out = get_asset(file)
    asset_ids[file] = out
    return out
end

local function resolve_asset(raw)
    if type(raw) ~= "table" then return nil, nil end
    if raw.mode == "rbx" then
        return tostring(raw.value), nil
    end
    if raw.mode == "hash" then
        local frames = asset_path_from_hash(raw.value)
        if not frames then
            return nil, tostring(raw.value)
        end
        local first = asset_id(frames[1].file)
        return first, nil
    end
    return nil, nil
end

local function stop_gif(key)
    local job = gif_jobs[key]
    if not job then return end
    job.live = false
    gif_jobs[key] = nil
end

local function play_gif(key, image_obj, raw, item, slot, gen, slot_name)
    if type(raw) ~= "table" or raw.mode ~= "hash" then return end
    local hash = tostring(raw.value or "")
    local cache_key = tostring(slot_name or "slot") .. ":" .. hash
    local entry = gif_cache[cache_key]
    if not entry then
        local frames = asset_path_from_hash(hash)
        if not frames or #frames <= 1 then return end
        local ids = {}
        local delays = {}
        for i, row in ipairs(frames) do
            ids[i] = asset_id(row.file)
            delays[i] = math.max(0.04, (tonumber(row.delay) or 100) / 1000)
            if i % 8 == 0 then task.wait() end
        end
        entry = { ids = ids, delays = delays, count = #ids }
        gif_cache[cache_key] = entry
    end
    if entry.count <= 1 then return end
    stop_gif(key)
    local job = { live = true }
    gif_jobs[key] = job
    task.spawn(function()
        local index = 1
        while job.live and image_obj and image_obj.Parent and item[slot] == gen do
            image_obj.Image = entry.ids[index]
            task.wait(entry.delays[index])
            index += 1
            if index > entry.count then index = 1 end
        end
    end)
end

local function build_gui(name)
    local bb = Instance.new("BillboardGui")
    bb.Name = "client_tag_" .. name
    bb.Size = UDim2.new(0, 170, 0, 42)
    bb.AlwaysOnTop = true
    bb.MaxDistance = 0
    bb.LightInfluence = 0
    bb.ResetOnSpawn = false
    bb.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
    bg.BorderSizePixel = 0
    bg.ZIndex = 1
    bg.Parent = bb
    Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 9)

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1.5
    stroke.Parent = bg

    local background = Instance.new("ImageLabel")
    background.Name = "background"
    background.Size = UDim2.new(1, 0, 1, 0)
    background.BackgroundTransparency = 1
    background.ImageTransparency = 0.22
    background.ScaleType = Enum.ScaleType.Crop
    background.ZIndex = 1
    background.Parent = bg
    Instance.new("UICorner", background).CornerRadius = UDim.new(0, 9)

    local icon = Instance.new("ImageLabel")
    icon.Name = "icon"
    icon.Size = UDim2.new(0, 28, 0, 28)
    icon.Position = UDim2.new(0, 7, 0.5, -14)
    icon.BackgroundTransparency = 1
    icon.ScaleType = Enum.ScaleType.Crop
    icon.ZIndex = 3
    icon.Parent = bg
    Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)

    local title = Instance.new("TextLabel")
    title.Name = "title"
    title.Size = UDim2.new(1, -46, 0, 18)
    title.Position = UDim2.new(0, 40, 0, 4)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 4
    title.Parent = bg

    local user = Instance.new("TextLabel")
    user.Name = "user"
    user.Size = UDim2.new(1, -46, 0, 13)
    user.Position = UDim2.new(0, 40, 0, 20)
    user.BackgroundTransparency = 1
    user.Font = Enum.Font.GothamBold
    user.TextSize = 10
    user.TextXAlignment = Enum.TextXAlignment.Left
    user.ZIndex = 4
    user.Parent = bg

    return {
        bb = bb,
        bg = bg,
        stroke = stroke,
        background = background,
        icon = icon,
        title = title,
        user = user,
        icon_sig = "",
        bg_sig = "",
        icon_gen = 0,
        bg_gen = 0
    }
end

local function apply_gui(item, row)
    local merged = normalize_tag(row)
    item.stroke.Color = merged.line_color
    item.title.Text = merged.text
    item.title.TextColor3 = merged.text_color
    item.user.Text = "@" .. tostring(row.username or "?")
    item.user.TextColor3 = Color3.fromRGB(180, 180, 180)
    local icon_sig = tostring(merged.icon.mode or "") .. ":" .. tostring(merged.icon.value or "")
    local bg_sig = tostring(merged.background.mode or "") .. ":" .. tostring(merged.background.value or "")

    local icon_image, need_icon = resolve_asset(merged.icon)
    local icon_ready = icon_image ~= nil or merged.icon.mode ~= "hash"
    if icon_image and item.icon_sig ~= icon_sig then item.icon.Image = icon_image end
    if need_icon then cache_known[need_icon] = true end

    local bg_image, need_bg = resolve_asset(merged.background)
    local bg_ready = bg_image ~= nil or merged.background.mode ~= "hash"
    if bg_image and item.bg_sig ~= bg_sig then item.background.Image = bg_image end
    if need_bg then cache_known[need_bg] = true end

    if icon_ready then
        if item.icon_sig ~= icon_sig then
            item.icon_gen += 1
            if merged.icon.mode == "hash" then
                play_gif("icon_" .. tostring(row.userid), item.icon, merged.icon, item, "icon_gen", item.icon_gen, "icon")
            else
                stop_gif("icon_" .. tostring(row.userid))
            end
            item.icon_sig = icon_sig
        end
    else
        if item.icon_sig ~= "" then
            item.icon_gen += 1
            stop_gif("icon_" .. tostring(row.userid))
            item.icon.Image = ""
            item.icon_sig = ""
        end
    end
    if bg_ready then
        if item.bg_sig ~= bg_sig then
            item.bg_gen += 1
            if merged.background.mode == "hash" then
                play_gif("bg_" .. tostring(row.userid), item.background, merged.background, item, "bg_gen", item.bg_gen, "bg")
                item.background.ImageTransparency = 0
            else
                stop_gif("bg_" .. tostring(row.userid))
                item.background.ImageTransparency = 0.12
            end
            item.bg_sig = bg_sig
        end
    else
        if item.bg_sig ~= "" then
            item.bg_gen += 1
            stop_gif("bg_" .. tostring(row.userid))
            item.background.Image = ""
            item.background.ImageTransparency = 0
            item.bg_sig = ""
        end
    end
end

local function find_head(player)
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
end

local function hide_default_name(player)
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    hum.NameDisplayDistance = 0
    hum.HealthDisplayDistance = 0
end

local function is_valid_row(row)
    if type(row) ~= "table" then return false end
    local uid = tonumber(row.userid)
    if not uid or uid < 1 then return false end
    local username = tostring(row.username or "")
    if username == "" then return false end
    return true
end

local function ensure_tag(row)
    if not is_valid_row(row) then return end
    local id = tostring(row.userid)
    local one = tags[id]
    if not one then
        one = build_gui(id)
        one.bb.Enabled = false
        one.bb.Parent = screen
        tags[id] = one
    end
    apply_gui(one, row)
end

local function clear_missing(current)
    local keep = {}
    for _, row in ipairs(current) do
        if is_valid_row(row) then
            keep[tostring(row.userid)] = true
        end
    end
    for id, one in pairs(tags) do
        if not keep[id] or tonumber(id) == nil then
            stop_gif("icon_" .. id)
            stop_gif("bg_" .. id)
            one.bb:Destroy()
            tags[id] = nil
        end
    end
end

local function pull_missing_hashes()
    local need = {}
    for hash in pairs(cache_known) do
        if not asset_path_from_hash(hash) then
            need[#need + 1] = hash
        end
    end
    if #need > 0 and ws then
        ws:Send(encode_json({ type = "asset_need", hashes = need }))
    end
end

local function queue_missing_from_asset(raw)
    if type(raw) ~= "table" or raw.mode ~= "hash" then return end
    local hash = tostring(raw.value or "")
    if hash == "" then return end
    if not asset_path_from_hash(hash) then
        cache_known[hash] = true
    end
end

local function queue_missing_from_tag(tag)
    if type(tag) ~= "table" then return end
    queue_missing_from_asset(tag.icon)
    queue_missing_from_asset(tag.background)
end

local function save_asset_blob(hash, frames)
    local folder = frame_folder(hash)
    if not isfolder(folder) then makefolder(folder) end
    local saved = {}
    for i, row in ipairs(frames) do
        local name = tostring(i - 1) .. ".png"
        local full = folder .. "/" .. name
        writefile(full, b64_decode(row.png64))
        saved[#saved + 1] = { file = name, delay = tonumber(row.delay) or 100 }
        if i % 4 == 0 then task.wait() end
    end
    writefile(frame_meta_file(hash), encode_json({ frames = saved }))
end

local function begin_asset(hash, count)
    pending_asset[hash] = { count = tonumber(count) or 0, saved = {} }
    local folder = frame_folder(hash)
    if not isfolder(folder) then makefolder(folder) end
end

local function save_asset_chunk(hash, start, frames)
    local state = pending_asset[hash]
    if not state then return end
    local base = tonumber(start) or 0
    for i, row in ipairs(frames) do
        local idx = base + i - 1
        local name = tostring(idx) .. ".png"
        local full = frame_folder(hash) .. "/" .. name
        writefile(full, b64_decode(row.png64))
        state.saved[#state.saved + 1] = { file = name, delay = tonumber(row.delay) or 100, idx = idx }
        if i % 4 == 0 then task.wait() end
    end
end

local function finish_asset(hash)
    local state = pending_asset[hash]
    if not state then return end
    table.sort(state.saved, function(a, b) return a.idx < b.idx end)
    local frames = {}
    for i, row in ipairs(state.saved) do
        frames[i] = { file = row.file, delay = row.delay }
    end
    writefile(frame_meta_file(hash), encode_json({ frames = frames }))
    pending_asset[hash] = nil
end

local function ws_pick()
    if WebSocket and WebSocket.connect then return WebSocket.connect end
    return nil
end

local function hello_payload()
    local char = local_player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return {
        type = "hello",
        userid = local_player.UserId,
        username = local_player.Name,
        displayname = local_player.DisplayName,
        account_age = local_player.AccountAge,
        has_humanoid = hum ~= nil,
        placeid = game.PlaceId,
        gameid = game.GameId,
        jobid = game.JobId
    }
end

local function bind_socket(sock)
    ws = sock
    ws_last = tick()
    log("websocket connected")
    sock.OnMessage:Connect(function(raw)
        ws_last = tick()
        local msg = decode_json(raw)
        if type(msg) ~= "table" then return end
        if msg.type == "state" and type(msg.players) == "table" then
            local list = {}
            for _, row in ipairs(msg.players) do
                if is_valid_row(row) then
                    list[#list + 1] = row
                end
            end
            net_players = list
            log("found " .. tostring(#net_players) .. " total users connected to websocket")
            switch_cache_rev(msg.cache_rev)
            if type(msg.defaults) == "table" then
                cfg_default = normalize_tag(msg.defaults)
                log("loaded default tags")
            end
            for _, row in ipairs(net_players) do
                queue_missing_from_tag(row)
                ensure_tag(row)
            end
            clear_missing(net_players)
            pull_missing_hashes()
        elseif msg.type == "you" and type(msg.tag) == "table" then
            cfg_you = normalize_tag(msg.tag)
            queue_missing_from_tag(msg.tag)
            switch_cache_rev(msg.cache_rev)
            pull_missing_hashes()
            log("found custom nametag for localplayer")
        elseif msg.type == "asset_start" and msg.hash then
            begin_asset(tostring(msg.hash), msg.count)
            log("receiving asset hash " .. tostring(msg.hash) .. " frames " .. tostring(msg.count or 0))
        elseif msg.type == "asset_chunk" and msg.hash and msg.frames then
            save_asset_chunk(tostring(msg.hash), msg.start, msg.frames)
        elseif msg.type == "asset_done" and msg.hash then
            finish_asset(tostring(msg.hash))
            clear_gif_cache_for_hash(tostring(msg.hash))
            log("asset ready hash " .. tostring(msg.hash))
            for _, row in ipairs(net_players) do
                ensure_tag(row)
            end
            pull_missing_hashes()
        elseif msg.type == "asset_blob" and msg.hash and msg.frames then
            log("received asset hash " .. tostring(msg.hash) .. " with " .. tostring(#msg.frames) .. " frames")
            task.spawn(function()
                save_asset_blob(tostring(msg.hash), msg.frames)
                clear_gif_cache_for_hash(tostring(msg.hash))
                for _, row in ipairs(net_players) do
                    ensure_tag(row)
                    task.wait()
                end
                pull_missing_hashes()
            end)
        elseif msg.type == "bye" then
            log("server rejected hello code " .. tostring(msg.code or "reject") .. " detail " .. tostring(msg.detail or ""))
            pcall(function() sock:Close() end)
        end
    end)
    sock.OnClose:Connect(function()
        if ws == sock then
            ws = nil
            log("websocket closed")
        end
    end)
    sock:Send(encode_json(hello_payload()))
    log("hello sent")
end

local function connect_loop()
    task.spawn(function()
        while task.wait(2) do
            if ws then
                if tick() - ws_last > 25 then
                    ws:Send(encode_json({ type = "ping" }))
                end
            else
                local fn = ws_pick()
                if fn then
                    local pick = ws_urls[ws_next_try] or ws_urls[1]
                    ws_next_try += 1
                    if ws_next_try > #ws_urls then ws_next_try = 1 end
                    local ok, sock = pcall(function()
                        return fn(pick)
                    end)
                    if ok and sock then
                        log("connect route " .. tostring(pick))
                        bind_socket(sock)
                    else
                        local now = tick()
                        if now - ws_last_fail_log > 8 then
                            ws_last_fail_log = now
                            log("connect failed route " .. tostring(pick) .. " reason " .. tostring(sock))
                        end
                    end
                else
                    local now = tick()
                    if now - ws_last_no_api_log > 12 then
                        ws_last_no_api_log = now
                        log("connect failed no websocket api")
                    end
                end
            end
        end
    end)
end

run.RenderStepped:Connect(function()
    for _, row in ipairs(net_players) do
        local one = tags[tostring(row.userid)]
        if one then
            local player = players:FindFirstChild(row.username)
            if player then
                hide_default_name(player)
                local head = find_head(player)
                if head then
                    one.bb.Enabled = true
                    one.bb.Adornee = head
                    one.bb.StudsOffsetWorldSpace = Vector3.new(0, 1.9, 0)
                    local cam = workspace.CurrentCamera
                    if cam then
                        local depth = (cam.CFrame.Position - head.Position).Magnitude
                        local mini = depth > 60
                        if mini then
                            one.bb.Size = UDim2.new(0, 44, 0, 44)
                            one.title.Visible = false
                            one.user.Visible = false
                            one.icon.Size = UDim2.new(0, 32, 0, 32)
                            one.icon.Position = UDim2.new(0.5, -16, 0.5, -16)
                        else
                            one.bb.Size = UDim2.new(0, 170, 0, 42)
                            one.title.Visible = true
                            one.user.Visible = true
                            one.icon.Size = UDim2.new(0, 28, 0, 28)
                            one.icon.Position = UDim2.new(0, 7, 0.5, -14)
                        end
                    end
                else
                    one.bb.Enabled = false
                    one.bb.Adornee = nil
                end
            else
                one.bb.Enabled = false
                one.bb.Adornee = nil
            end
        end
    end
end)

local_player.CharacterAdded:Connect(function()
    task.wait(0.4)
    for _, row in ipairs(net_players) do
        ensure_tag(row)
    end
end)

connect_loop()

run.Heartbeat:Connect(function()
    if player_gui.Parent == nil then
        player_gui = local_player:FindFirstChildOfClass("PlayerGui") or local_player:WaitForChild("PlayerGui")
    end
    if not screen.Parent or screen.Parent.Parent == nil then
        screen.Parent = pick_ui_parent()
    end
end)
