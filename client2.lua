if not LPH_NO_VIRTUALIZE then LPH_NO_VIRTUALIZE = function(f) return f end end
if not gethui then gethui = function() return game:GetService("CoreGui") end end

local tweenService     = game:GetService("TweenService")
local runService       = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")
local players          = game:GetService("Players")
local coreGui          = game:GetService("CoreGui")
local guiParent        = gethui and gethui() or coreGui

local nametagsEnabled  = true

local screen = Instance.new("ScreenGui")
screen.Name           = "NVNametagScreen"
screen.ResetOnSpawn   = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent         = guiParent

;(function()
    local TweenService     = tweenService
    local RunService       = runService
    local UserInputService = userInputService
    local TextService      = game:GetService("TextService")
    local plr  = players.LocalPlayer
    local char = plr.Character or plr.CharacterAdded:Wait()
    local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")

    local cfg = {
        displayName            = "NOVOLINE",
        labelName              = "NOVOLINE",
        userLabel              = "@" .. plr.Name,
        textColor              = Color3.fromRGB(255, 255, 255),
        outlineColor           = Color3.fromRGB(143, 143, 145),
        labelColor             = Color3.new(1, 1, 1),
        labelBorderColor       = Color3.fromRGB(38, 38, 38),
        displayColor           = Color3.fromRGB(180, 180, 180),
        displayBorderColor     = Color3.fromRGB(38, 38, 38),
        backgroundColor        = Color3.fromRGB(8, 8, 12),
        backgroundTransparency = 0,
        iconImage              = "rbxassetid://134633682532885",
        frameAsset             = "rbxassetid://91753130662474",
        bgEffect               = "matrix",
        textEffect             = "gradient",
    }

    local function cloneCfg(source)
        local out = {}
        for k, v in pairs(source) do out[k] = v end
        return out
    end

    local defaultCfg = cloneCfg(cfg)
    local NOVOLINE_TAG_FRAME = "rbxassetid://91753130662474"
    local SELF_TAG_STUDS_Y = 1.65
    local PLAYER_TAG_WORLD_Y = 1.9
    local function normalizeTagFrameAsset(assetId)
        if type(assetId) ~= "string" or assetId == "" then
            return NOVOLINE_TAG_FRAME
        end
        return assetId
    end

    local GLITCH_CHARS = {"!","@","#","$","%","^","&","*","~","?","/","|","Ξ","▓","▒","░"}
    local CUSTOM_TAG_MARKER = "BleedUser"

    local function hideHumanoidOverhead(humanoid)
        if not humanoid then return end
        humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        humanoid.NameDisplayDistance = 0
        humanoid.HealthDisplayDistance = 0
    end

    local function showHumanoidOverhead(humanoid)
        if not humanoid then return end
        humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
        humanoid.NameDisplayDistance = 100
        humanoid.HealthDisplayDistance = 100
    end

    local function hasCustomNametag(character)
        return character and character:FindFirstChild(CUSTOM_TAG_MARKER) ~= nil
    end

    local function startBgEffect(parent, color, effect)
        task.spawn(function()
            if not parent then return end
            local rng = Random.new()
            local e = effect or "matrix"

            local box = Instance.new("Frame")
            box.Size = UDim2.new(1, 0, 1, 0)
            box.BackgroundTransparency = 1
            box.ClipsDescendants = true
            box.ZIndex = 2
            box.Parent = parent
            Instance.new("UICorner", box).CornerRadius = UDim.new(0, 10)

            if e == "matrix" then
                for _ = 1, 6 do
                    local col = Instance.new("TextLabel", box)
                    col.Size = UDim2.new(0, 10, 1, 0)
                    col.Position = UDim2.new(rng:NextNumber(0, 1), 0, -1, 0)
                    col.BackgroundTransparency = 1
                    col.TextColor3 = color
                    col.TextTransparency = 0.6
                    col.TextSize = 7
                    col.Font = Enum.Font.GothamBold
                    col.Text = "1\n0\n1\n0"
                    col.ZIndex = 2
                    local xs = col.Position.X.Scale
                    local function loop()
                        if not (col and col.Parent) then return end
                        col.Position = UDim2.new(xs, 0, -1, 0)
                        local tw = TweenService:Create(col,
                            TweenInfo.new(rng:NextNumber(3, 6), Enum.EasingStyle.Linear),
                            { Position = UDim2.new(xs, 0, 1, 0) })
                        tw.Completed:Connect(loop)
                        tw:Play()
                    end
                    loop()
                end

            elseif e == "pulse" then
                local stroke = parent:FindFirstChildOfClass("UIStroke")
                if stroke then
                    local function loop()
                        if not (stroke and stroke.Parent) then return end
                        local tw = TweenService:Create(stroke,
                            TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 1, true),
                            { Thickness = 3, Transparency = 0 })
                        tw.Completed:Connect(loop)
                        tw:Play()
                    end
                    loop()
                end

            elseif e == "scanline" then
                local line = Instance.new("Frame", box)
                line.Size = UDim2.new(1, 0, 0, 2)
                line.BorderSizePixel = 0
                line.BackgroundColor3 = color
                line.BackgroundTransparency = 0.4
                line.ZIndex = 3
                line.Position = UDim2.new(0, 0, -0.1, 0)
                local function loop()
                    if not (line and line.Parent) then return end
                    line.Position = UDim2.new(0, 0, -0.1, 0)
                    local tw = TweenService:Create(line,
                        TweenInfo.new(2, Enum.EasingStyle.Linear),
                        { Position = UDim2.new(0, 0, 1.1, 0) })
                    tw.Completed:Connect(loop)
                    tw:Play()
                end
                loop()

            elseif e == "fire" then
                local h, s, v = Color3.toHSV(color)
                local palette = {
                    Color3.fromHSV(h, math.max(0, s-0.35), math.min(1, v+0.45)),
                    Color3.fromHSV(h, math.max(0, s-0.18), math.min(1, v+0.25)),
                    color,
                    Color3.fromHSV(h, math.min(1, s+0.10), math.max(0, v-0.20)),
                    Color3.fromHSV(h, math.min(1, s+0.15), math.max(0, v-0.45)),
                }
                task.spawn(function()
                    while parent and parent.Parent do
                        local fc    = palette[rng:NextInteger(1, #palette)]
                        local wFrac = rng:NextNumber(0.10, 0.22)
                        local xPos  = rng:NextNumber(0.04, math.max(0.05, 1-wFrac-0.04))
                        local dur   = rng:NextNumber(0.55, 1.0)
                        local rise  = rng:NextNumber(0.55, 1.1)
                        local drift = rng:NextNumber(-0.04, 0.04)
                        local cx2   = xPos + wFrac * 0.5
                        local tongue = Instance.new("Frame", parent)
                        tongue.AnchorPoint = Vector2.new(0.5, 1)
                        tongue.BackgroundColor3 = fc
                        tongue.BackgroundTransparency = 0.1
                        tongue.BorderSizePixel = 0
                        tongue.ZIndex = 4
                        tongue.Size = UDim2.new(wFrac, 0, 0.40, 0)
                        tongue.Position = UDim2.new(cx2, 0, 1.02, 0)
                        Instance.new("UICorner", tongue).CornerRadius = UDim.new(1, 0)
                        TweenService:Create(tongue, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                            Position               = UDim2.new(cx2+drift, 0, 1.02-rise, 0),
                            Size                   = UDim2.new(wFrac * rng:NextNumber(0.12, 0.30), 0, 0.10, 0),
                            BackgroundTransparency = 1,
                        }):Play()
                        task.wait(rng:NextNumber(0.08, 0.15))
                        task.delay(dur + 0.05, function()
                            if tongue and tongue.Parent then tongue:Destroy() end
                        end)
                    end
                end)

            elseif e == "glitch" then
                task.spawn(function()
                    while box and box.Parent do
                        task.wait(rng:NextNumber(2, 5))
                        if not (box and box.Parent) then break end
                        local slice = Instance.new("Frame", box)
                        slice.Size = UDim2.new(1, 0, 0, rng:NextInteger(3, 8))
                        slice.Position = UDim2.new(rng:NextNumber(-0.05, 0.05), 0, rng:NextNumber(0, 0.85), 0)
                        slice.BackgroundColor3 = color
                        slice.BackgroundTransparency = 0.6
                        slice.BorderSizePixel = 0
                        slice.ZIndex = 3
                        task.delay(0.07, function() if slice and slice.Parent then slice:Destroy() end end)
                    end
                end)

            elseif e == "rainbow" then
                local stroke = parent:FindFirstChildOfClass("UIStroke")
                if stroke then
                    task.spawn(function()
                        local h2 = 0
                        while stroke and stroke.Parent do
                            h2 = (h2 + 0.012) % 1
                            stroke.Color = Color3.fromHSV(h2, 1, 1)
                            task.wait(0.05)
                        end
                    end)
                end

            elseif e == "snow" then
                task.spawn(function()
                    while box and box.Parent do
                        local dot = Instance.new("Frame", box)
                        dot.Size = UDim2.new(0, 2, 0, 2)
                        dot.BackgroundColor3 = Color3.new(1, 1, 1)
                        dot.BackgroundTransparency = rng:NextNumber(0.3, 0.6)
                        dot.BorderSizePixel = 0
                        dot.ZIndex = 3
                        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
                        dot.Position = UDim2.new(rng:NextNumber(0, 1), 0, -0.1, 0)
                        TweenService:Create(dot, TweenInfo.new(rng:NextNumber(2.5, 4.5), Enum.EasingStyle.Linear), {
                            Position               = UDim2.new(rng:NextNumber(0, 1), 0, 1.1, 0),
                            BackgroundTransparency = 1,
                        }):Play()
                        task.wait(rng:NextNumber(0.2, 0.4))
                        task.delay(4.6, function() if dot and dot.Parent then dot:Destroy() end end)
                    end
                end)
            end
        end)
    end

    local function startTextEffect(nameLabel, c)
        local e        = c.textEffect or "gradient"
        local baseText = c.labelName or c.displayName or "BLEED USER"
        nameLabel.TextColor3 = c.labelColor or Color3.new(1, 1, 1)

        if e == "gradient" then
            local grad = Instance.new("UIGradient")
            grad.Color  = ColorSequence.new(c.textColor, c.labelBorderColor or c.outlineColor)
            grad.Parent = nameLabel
            task.spawn(function()
                local t = 0
                while grad and grad.Parent do
                    t = t + 0.03
                    grad.Rotation = math.sin(t) * 45 + 45
                    task.wait(0.08)
                end
            end)

        elseif e == "wave" then
            nameLabel.Text    = ""
            nameLabel.Visible = false
            local container = Instance.new("Frame", nameLabel.Parent)
            container.Name = "WaveContainer"
            container.BackgroundTransparency = 1
            container.Size             = nameLabel.Size
            container.Position         = nameLabel.Position
            container.ZIndex           = nameLabel.ZIndex
            container.ClipsDescendants = false
            local chars = {}
            local cw = math.max(10, math.floor(nameLabel.TextSize * 0.72 + 0.5))
            for i = 1, #baseText do
                local ch = Instance.new("TextLabel", container)
                ch.BackgroundTransparency = 1
                ch.Font                   = nameLabel.Font
                ch.TextSize               = nameLabel.TextSize
                ch.TextColor3             = c.textColor
                ch.TextStrokeTransparency = 0.7
                ch.TextStrokeColor3       = c.labelBorderColor or c.outlineColor
                ch.Size                   = UDim2.new(0, cw, 1, 0)
                ch.Position               = UDim2.new(0, (i-1)*cw, 0, 0)
                ch.Text                   = baseText:sub(i, i)
                ch.ZIndex                 = nameLabel.ZIndex
                chars[i] = ch
            end
            task.spawn(function()
                local t = 0
                while container and container.Parent do
                    t = t + 0.1
                    for i, ch in ipairs(chars) do
                        if ch and ch.Parent then
                            ch.Position = UDim2.new(0, (i-1)*cw, 0, math.sin(t + i*0.6) * 3)
                        end
                    end
                    task.wait(0.07)
                end
            end)

        elseif e == "typewriter" then
            task.spawn(function()
                while nameLabel and nameLabel.Parent do
                    for i = 1, #baseText do
                        if not (nameLabel and nameLabel.Parent) then return end
                        nameLabel.Text = baseText:sub(1, i) .. "▌"
                        task.wait(0.08)
                    end
                    task.wait(1.2)
                    for i = #baseText, 0, -1 do
                        if not (nameLabel and nameLabel.Parent) then return end
                        nameLabel.Text = baseText:sub(1, i) .. "▌"
                        task.wait(0.06)
                    end
                    task.wait(0.4)
                end
            end)

        elseif e == "rainbow" then
            local grad = Instance.new("UIGradient")
            grad.Parent = nameLabel
            task.spawn(function()
                local t = 0
                while grad and grad.Parent do
                    t = t + 0.03
                    local kps = {}
                    for i = 0, 3 do
                        kps[#kps+1] = ColorSequenceKeypoint.new(i/3, Color3.fromHSV((t + i*0.25) % 1, 1, 1))
                    end
                    grad.Color    = ColorSequence.new(kps)
                    grad.Rotation = t*30 % 360
                    task.wait(0.06)
                end
            end)

        elseif e == "glitch" then
            local grad = Instance.new("UIGradient")
            grad.Color  = ColorSequence.new(c.textColor, c.labelBorderColor or c.outlineColor)
            grad.Parent = nameLabel
            task.spawn(function()
                local rng2 = Random.new()
                while nameLabel and nameLabel.Parent do
                    task.wait(rng2:NextNumber(1.2, 3.0))
                    if not (nameLabel and nameLabel.Parent) then break end
                    for _ = 1, rng2:NextInteger(2, 4) do
                        if not (nameLabel and nameLabel.Parent) then break end
                        local out = {}
                        for i = 1, #baseText do
                            out[i] = rng2:NextNumber() < 0.35
                                and GLITCH_CHARS[rng2:NextInteger(1, #GLITCH_CHARS)]
                                or  baseText:sub(i, i)
                        end
                        nameLabel.Text = table.concat(out)
                        task.wait(0.07)
                    end
                    nameLabel.Text = baseText
                end
            end)

        else
            local grad = Instance.new("UIGradient")
            grad.Color  = ColorSequence.new(c.textColor, c.labelBorderColor or c.outlineColor)
            grad.Parent = nameLabel
        end
    end

    local function buildTag(c, targetPlayer, parentGui)
        if parentGui and parentGui:IsA("BillboardGui") then
            parentGui.AlwaysOnTop = true
            parentGui.LightInfluence = 0
            parentGui.MaxDistance = 0
            parentGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        end
        local PRANGE    = 15
        local FULL_RECT = Vector2.new(622, 154)
        local FULL_BASE = Vector2.new(15, 107)
        local MINI_RECT = Vector2.new(338, 338)
        local MINI_BASE = Vector2.new(157, 15)
        local frameAsset = normalizeTagFrameAsset(c.frameAsset)
        local touchDevice = UserInputService.TouchEnabled
        local useFullImageCrop = touchDevice
        local IMG_PAD_X = touchDevice and 0 or PRANGE
        local IMG_PAD_Y = touchDevice and 0 or PRANGE

        local bg = Instance.new("TextButton")
        bg.Name              = "Background"
        bg.Text              = ""
        bg.AutoButtonColor   = false
        bg.AnchorPoint       = Vector2.new(0.5, 0.5)
        bg.Position          = UDim2.new(0.5, 0, 0.5, 0)
        bg.Size              = UDim2.new(0, 170, 0, 42)
        bg.BackgroundColor3  = c.backgroundColor
        bg.BackgroundTransparency = c.backgroundTransparency
        bg.BorderSizePixel   = 0
        bg.ClipsDescendants  = false
        bg.ZIndex            = 10
        bg.Parent            = parentGui
        Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 10)

        local bgImgHost = bg
        local bgImgRound = nil
        local bgImg
        local function setFullImageCrop(dx, dy, mini)
            if not useFullImageCrop then return end
            local px = IMG_PAD_X
            local py = IMG_PAD_Y
            bgImg.Size = UDim2.new(1, px * 2, 1, py * 2)
            bgImg.Position = UDim2.new(
                0, -px + math.round(dx or 0),
                0, -py + math.round(dy or 0)
            )
        end
        if useFullImageCrop then
            local bgImgMask = Instance.new("Frame", bg)
            bgImgMask.Name                   = "BgImgMask"
            bgImgMask.Size                   = UDim2.new(1, 0, 1, 0)
            bgImgMask.Position               = UDim2.new(0, 0, 0, 0)
            bgImgMask.BackgroundTransparency = 1
            bgImgMask.BorderSizePixel        = 0
            bgImgMask.ClipsDescendants       = true
            bgImgMask.ZIndex                 = 1
            bgImgHost = bgImgMask
            bgImgRound = Instance.new("UICorner", bgImgMask)
            bgImgRound.CornerRadius = UDim.new(0, 10)
        end

        bgImg = Instance.new("ImageLabel", bgImgHost)
        bgImg.Name               = "BgImg"
        bgImg.Image              = frameAsset
        bgImg.Size               = useFullImageCrop and UDim2.new(1, IMG_PAD_X * 2, 1, IMG_PAD_Y * 2) or UDim2.new(1, 0, 1, 0)
        bgImg.Position           = useFullImageCrop and UDim2.new(0, -IMG_PAD_X, 0, -IMG_PAD_Y) or UDim2.new(0, 0, 0, 0)
        bgImg.BackgroundTransparency = 1
        bgImg.ImageTransparency  = touchDevice and 0.15 or 0.35
        bgImg.ImageColor3        = Color3.new(1, 1, 1)
        bgImg.ScaleType          = useFullImageCrop and Enum.ScaleType.Crop or Enum.ScaleType.Stretch
        bgImg.ImageRectSize      = useFullImageCrop and Vector2.new(0, 0) or FULL_RECT
        bgImg.ImageRectOffset    = useFullImageCrop and Vector2.new(0, 0) or FULL_BASE
        bgImg.ZIndex             = 1
        local bgImgCorner = Instance.new("UICorner", bgImg)
        bgImgCorner.CornerRadius = UDim.new(0, 10)
        if not bgImgRound then
            bgImgRound = bgImgCorner
        end
        local stroke = Instance.new("UIStroke")
        stroke.Color           = c.outlineColor
        stroke.Thickness       = 1.5
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Parent          = bg

        startBgEffect(bg, c.outlineColor, c.bgEffect)

        local icon = Instance.new("ImageLabel")
        icon.Name               = "Icon"
        icon.Size               = UDim2.new(0, 28, 0, 28)
        icon.Position           = UDim2.new(0, 7, 0.5, -14)
        icon.BackgroundTransparency = 1
        icon.Image              = c.iconImage or "rbxassetid://76835997605807"
        icon.ScaleType          = Enum.ScaleType.Crop
        icon.ZIndex             = 250
        icon.Parent             = bg
        Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name                 = "DisplayName"
        nameLabel.Size                 = UDim2.new(1, -46, 0, 18)
        nameLabel.Position             = UDim2.new(0, 40, 0, 4)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font                 = Enum.Font.GothamBold
        nameLabel.TextSize             = 14
        nameLabel.TextColor3           = c.labelColor or Color3.new(1, 1, 1)
        nameLabel.TextStrokeColor3     = c.labelBorderColor or c.outlineColor
        nameLabel.TextStrokeTransparency = 0.7
        nameLabel.TextXAlignment       = Enum.TextXAlignment.Left
        nameLabel.Text                 = c.labelName or c.displayName or "BLEED USER"
        nameLabel.ZIndex               = 250
        nameLabel.Parent               = bg

        startTextEffect(nameLabel, c)

        local tagLabel = Instance.new("TextLabel")
        tagLabel.Name                 = "Username"
        tagLabel.Size                 = UDim2.new(1, -46, 0, 14)
        tagLabel.Position             = UDim2.new(0, 40, 0, 19)
        tagLabel.BackgroundTransparency = 1
        tagLabel.Font                 = Enum.Font.GothamBold
        tagLabel.TextSize             = 10
        tagLabel.TextColor3           = c.displayColor or Color3.fromRGB(180, 180, 180)
        tagLabel.TextStrokeTransparency = 0.7
        tagLabel.TextStrokeColor3     = c.displayBorderColor or c.outlineColor
        tagLabel.TextXAlignment       = Enum.TextXAlignment.Left
        tagLabel.Text                 = c.userLabel or ("@" .. targetPlayer.Name)
        tagLabel.ZIndex               = 250
        tagLabel.Parent               = bg

        if targetPlayer ~= plr then
            local function teleportToTarget()
                local mine = plr.Character
                local theirs = targetPlayer.Character
                if not mine or not theirs then return end
                local hrp = mine:FindFirstChild("HumanoidRootPart")
                local thrp = theirs:FindFirstChild("HumanoidRootPart")
                if not hrp or not thrp then return end
                local behindPos = thrp.Position - (thrp.CFrame.LookVector * 3)
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                hrp.CFrame = CFrame.new(behindPos, thrp.Position)
            end

            local hit = Instance.new("TextButton")
            hit.Name = "TeleportHit"
            hit.BackgroundTransparency = 1
            hit.BorderSizePixel = 0
            hit.Text = ""
            hit.AutoButtonColor = false
            hit.Size = UDim2.fromScale(1, 1)
            hit.Position = UDim2.new(0, 0, 0, 0)
            hit.ZIndex = 10000
            hit.Active = true
            hit.Parent = bg
            hit.MouseButton1Click:Connect(teleportToTarget)
            hit.Activated:Connect(teleportToTarget)

            if parentGui and parentGui:IsA("BillboardGui") then
                pcall(function()
                    parentGui.Active = true
                    parentGui.Enabled = true
                end)
            end
        end

        local bgCorner  = bg:FindFirstChildOfClass("UICorner")
        local miniState = nil

        local function updateSize()
            if not bg or not bg.Parent then return end
            local adornee = parentGui and parentGui.Adornee
            if not adornee or not adornee.Parent then return end
            local cam  = workspace.CurrentCamera
            local dist = cam and (cam.CFrame.Position - adornee.Position).Magnitude or 0
            local mini = dist >= 60
            if mini == miniState then return end
            miniState = mini
            nameLabel.Visible = not mini
            tagLabel.Visible  = not mini
            local wc = bg:FindFirstChild("WaveContainer")
            if wc then wc.Visible = not mini end
            local wantedCorner = mini and UDim.new(1, 0) or UDim.new(0, 10)
            for _, child in ipairs(bg:GetChildren()) do
                if child:IsA("Frame") then
                    local childCorner = child:FindFirstChildOfClass("UICorner")
                    if childCorner then
                        childCorner.CornerRadius = wantedCorner
                    end
                end
            end
            if mini then
                bg.Size = UDim2.new(0, 44, 0, 44)
                if bgCorner then bgCorner.CornerRadius = wantedCorner end
                icon.Size = UDim2.new(0, 32, 0, 32)
                icon.Position = UDim2.new(0.5, -16, 0.5, -16)
                bgImgCorner.CornerRadius = wantedCorner
                if bgImgRound then bgImgRound.CornerRadius = wantedCorner end
                if useFullImageCrop then
                    if frameAsset == NOVOLINE_TAG_FRAME then
                        bgImg.Image           = NOVOLINE_TAG_FRAME
                        bgImg.ScaleType       = Enum.ScaleType.Stretch
                        bgImg.ImageRectSize   = MINI_RECT
                        bgImg.ImageRectOffset = MINI_BASE
                    else
                        bgImg.Image           = frameAsset
                        bgImg.ScaleType       = Enum.ScaleType.Crop
                        bgImg.ImageRectSize   = Vector2.new(0, 0)
                        bgImg.ImageRectOffset = Vector2.new(0, 0)
                    end
                    setFullImageCrop(0, 0, true)
                else
                    bgImg.ImageRectSize   = MINI_RECT
                    bgImg.ImageRectOffset = MINI_BASE
                end
            else
                bg.Size = UDim2.new(0, 170, 0, 42)
                if bgCorner then bgCorner.CornerRadius = wantedCorner end
                icon.Size = UDim2.new(0, 28, 0, 28)
                icon.Position = UDim2.new(0, 7, 0.5, -14)
                bgImgCorner.CornerRadius = wantedCorner
                if bgImgRound then bgImgRound.CornerRadius = wantedCorner end
                if useFullImageCrop then
                    bgImg.Image           = frameAsset
                    bgImg.ScaleType       = Enum.ScaleType.Crop
                    bgImg.ImageRectSize   = Vector2.new(0, 0)
                    bgImg.ImageRectOffset = Vector2.new(0, 0)
                    setFullImageCrop(0, 0, false)
                else
                    bgImg.ImageRectSize = FULL_RECT
                    bgImg.ImageRectOffset = FULL_BASE
                end
            end
        end

        local spx, spy = 0, 0
        local _camThrottle = 0
        local camConn = RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function(dt)
            if touchDevice then
                _camThrottle = _camThrottle + dt
                if _camThrottle < 0.1 then return end
                _camThrottle = 0
            end
            updateSize()
        end))
        local parConn = RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function(dt)
            if not bgImg.Parent then return end
            if touchDevice then return end
            local cam = workspace.CurrentCamera
            if not cam then return end
            local mouse = UserInputService:GetMouseLocation()
            local vp    = cam.ViewportSize
            local tx    = (mouse.X - vp.X * 0.5) / vp.X
            local ty    = (mouse.Y - vp.Y * 0.5) / vp.Y
            local a     = 1 - math.exp(-6 * dt)
            spx = spx + (tx - spx) * a
            spy = spy + (ty - spy) * a
            if not miniState then
                if useFullImageCrop then
                    setFullImageCrop(spx * PRANGE, spy * PRANGE * 0.6, false)
                else
                    bgImg.ImageRectOffset = Vector2.new(
                        FULL_BASE.X + spx * PRANGE * 2,
                        FULL_BASE.Y + spy * PRANGE * 2
                    )
                end
            end
        end))

        bg.AncestryChanged:Connect(function()
            if not bg.Parent then
                camConn:Disconnect()
                parConn:Disconnect()
            end
        end)

        updateSize()
    end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then hideHumanoidOverhead(hum) end

    _G.cfg      = cfg
    _G.buildTag = buildTag

    ;(function()
        local selfTagGui = nil

        local function hideTag()
            if selfTagGui and selfTagGui.Parent then selfTagGui:Destroy() end
            selfTagGui = nil
        end

        local function showTag()
            hideTag()
            hideHumanoidOverhead(char and char:FindFirstChildOfClass("Humanoid"))
            local bb = Instance.new("BillboardGui")
            bb.Name                  = "BleedSelfTag"
            bb.Adornee               = head
            bb.Size                  = UDim2.new(0, 200, 0, 60)
            bb.StudsOffsetWorldSpace = Vector3.new(0, SELF_TAG_STUDS_Y, 0)
            bb.AlwaysOnTop           = true
            bb.MaxDistance           = 0
            bb.LightInfluence        = 0
            bb.ClipsDescendants      = false
            bb.ZIndexBehavior        = Enum.ZIndexBehavior.Sibling
            bb.ResetOnSpawn          = false
            bb.Enabled               = true
            bb.Parent                = players.LocalPlayer.PlayerGui
            buildTag(cfg, plr, bb)
            selfTagGui = bb
        end

        local function parseHexColor(hex)
            if type(hex) ~= "string" then return nil end
            hex = hex:gsub("#", "")
            if #hex ~= 6 then return nil end
            local r = tonumber(hex:sub(1, 2), 16)
            local g = tonumber(hex:sub(3, 4), 16)
            local b = tonumber(hex:sub(5, 6), 16)
            if not r or not g or not b then return nil end
            return Color3.fromRGB(r, g, b)
        end

        local function applyLiveTag(tag)
            cfg = cloneCfg(defaultCfg)
            _G.cfg = cfg
            if type(tag) ~= "table" then showTag() return end
            if type(tag.display_name) == "string" and tag.display_name ~= "" then cfg.displayName = tag.display_name end
            local col = parseHexColor(tag.text_color)
            if col then cfg.textColor = col; cfg.labelColor = col end
            if type(tag.asset_id) == "string" and tag.asset_id ~= "" then
                cfg.iconImage = "rbxassetid://" .. tag.asset_id:gsub("rbxassetid://", "")
            end
            if type(tag.frame_asset) == "string" and tag.frame_asset ~= "" then
                cfg.frameAsset = normalizeTagFrameAsset(
                    "rbxassetid://" .. tag.frame_asset:gsub("rbxassetid://", "")
                )
            end
            if type(tag.bg_effect) == "string" and tag.bg_effect ~= "" then cfg.bgEffect = tag.bg_effect
            elseif type(tag.effect) == "string" and tag.effect ~= "" then cfg.bgEffect = tag.effect end
            if type(tag.text_effect) == "string" and tag.text_effect ~= "" then cfg.textEffect = tag.text_effect end
            if type(tag.label_text) == "string" and tag.label_text ~= "" then cfg.userLabel = tag.label_text
            else cfg.userLabel = "@" .. plr.Name end
            if type(tag.label_name) == "string" and tag.label_name ~= "" then cfg.labelName = tag.label_name end
            local frameBorder = parseHexColor(tag.frame_border_color)
            if frameBorder then cfg.outlineColor = frameBorder end
            local frameColor = parseHexColor(tag.frame_color)
            if frameColor then cfg.backgroundColor = frameColor end
            local displayColor = parseHexColor(tag.display_color)
            if displayColor then cfg.displayColor = displayColor end
            local displayBorder = parseHexColor(tag.display_border_color)
            if displayBorder then cfg.displayBorderColor = displayBorder end
            local labelColor = parseHexColor(tag.label_color)
            if labelColor then cfg.labelColor = labelColor end
            local labelBorder = parseHexColor(tag.label_border_color)
            if labelBorder then cfg.labelBorderColor = labelBorder end
            showTag()
        end

        local function resetLiveTag()
            cfg = cloneCfg(defaultCfg)
            _G.cfg = cfg
            showTag()
        end

        _G.showTag      = showTag
        _G.hideTag      = hideTag
        _G.applyLiveTag = applyLiveTag
        _G.resetLiveTag = resetLiveTag
        _G.defaultCfg   = cloneCfg(defaultCfg)
        showTag()

        plr.CharacterAdded:Connect(function(newChar)
            task.spawn(function()
                char = newChar
                local ok, newHead = pcall(function()
                    return newChar:WaitForChild("Head", 10)
                end)
                head = (ok and newHead) or newChar:FindFirstChild("HumanoidRootPart")
                if not head then return end
                local hum2 = newChar:FindFirstChildOfClass("Humanoid")
                    or newChar:WaitForChild("Humanoid", 5)
                if hum2 then hideHumanoidOverhead(hum2) end
                if type(_G.resetOverheadState) == "function" then
                    _G.resetOverheadState()
                end
                showTag()
            end)
        end)

        local function stampCharacter(c)
            if c and not c:FindFirstChild(CUSTOM_TAG_MARKER) then
                local v = Instance.new("StringValue")
                v.Name   = CUSTOM_TAG_MARKER
                v.Value  = "1"
                v.Parent = c
            end
        end
        stampCharacter(char)
        plr.CharacterAdded:Connect(stampCharacter)
    end)()

    ;(function()
        local playerGui = plr:WaitForChild("PlayerGui")
        local oldCore = guiParent:FindFirstChild("BleedClickTags")
        local oldPlayer = playerGui:FindFirstChild("BleedClickTags")
        if oldCore then oldCore:Destroy() end
        if oldPlayer then oldPlayer:Destroy() end

        local tagSG = Instance.new("ScreenGui")
        tagSG.Name           = "BleedClickTags"
        tagSG.ResetOnSpawn   = false
        tagSG.IgnoreGuiInset = true
        tagSG.DisplayOrder   = 9999999
        tagSG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        tagSG.Parent         = guiParent

        local playerBtns    = {}
        local overheadState = {}

        local function removeBtn(p)
            local e = playerBtns[p]
            if e then
                pcall(function() e.btn:Destroy() end)
                playerBtns[p] = nil
            end
            overheadState[p] = nil
        end

        local function getOrCreate(p)
            if playerBtns[p] then
                if not playerBtns[p].btn.Parent then
                    removeBtn(p)
                else
                    return playerBtns[p]
                end
            end

            local btn = Instance.new("TextButton")
            btn.Name                   = "BleedTag_" .. p.Name
            btn.Size                   = UDim2.new(0, 170, 0, 42)
            btn.AnchorPoint            = Vector2.new(0.5, 1)
            btn.Position               = UDim2.new(0, -9999, 0, -9999)
            btn.BackgroundColor3       = cfg.backgroundColor
            btn.BackgroundTransparency = cfg.backgroundTransparency
            btn.BorderSizePixel        = 0
            btn.Text                   = ""
            btn.AutoButtonColor        = false
            btn.ClipsDescendants       = false
            btn.ZIndex                 = 20
            btn.Active                 = true
            btn.Selectable             = true
            btn.Visible                = false
            btn.Parent                 = tagSG

            local btnCorner = Instance.new("UICorner", btn)
            btnCorner.CornerRadius = UDim.new(0, 10)

            local bStroke = Instance.new("UIStroke", btn)
            bStroke.Color           = cfg.outlineColor
            bStroke.Thickness       = 1.5
            bStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

            local overlayBgMask = Instance.new("Frame", btn)
            overlayBgMask.Size                   = UDim2.new(1, 0, 1, 0)
            overlayBgMask.BackgroundTransparency = 1
            overlayBgMask.BorderSizePixel        = 0
            overlayBgMask.ClipsDescendants       = true
            overlayBgMask.ZIndex                 = 1
            Instance.new("UICorner", overlayBgMask).CornerRadius = UDim.new(0, 10)
            local overlayBgImg = Instance.new("ImageLabel", overlayBgMask)
            overlayBgImg.Size                 = UDim2.new(1, 0, 1, 0)
            overlayBgImg.BackgroundTransparency = 1
            overlayBgImg.Image                = normalizeTagFrameAsset(cfg.frameAsset)
            overlayBgImg.ScaleType            = Enum.ScaleType.Crop
            overlayBgImg.ImageTransparency    = 0.15
            overlayBgImg.ImageColor3          = Color3.new(1, 1, 1)
            overlayBgImg.ZIndex               = 1
            Instance.new("UICorner", overlayBgImg).CornerRadius = UDim.new(0, 10)

            local icon = Instance.new("ImageLabel", btn)
            icon.Size                   = UDim2.new(0, 28, 0, 28)
            icon.Position               = UDim2.new(0, 7, 0.5, -14)
            icon.BackgroundTransparency = 1
            icon.Image                  = cfg.iconImage or "rbxassetid://76835997605807"
            icon.ScaleType              = Enum.ScaleType.Crop
            icon.ZIndex                 = 12
            Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)

            local nameL = Instance.new("TextLabel", btn)
            nameL.Size                   = UDim2.new(1, -46, 0, 18)
            nameL.Position               = UDim2.new(0, 40, 0, 4)
            nameL.BackgroundTransparency = 1
            nameL.Font                   = Enum.Font.GothamBold
            nameL.TextSize               = 14
            nameL.TextColor3             = cfg.labelColor or Color3.new(1,1,1)
            nameL.TextXAlignment         = Enum.TextXAlignment.Left
            nameL.Text                   = p.DisplayName
            nameL.ZIndex                 = 12

            local tagL = Instance.new("TextLabel", btn)
            tagL.Size                   = UDim2.new(1, -46, 0, 14)
            tagL.Position               = UDim2.new(0, 40, 0, 20)
            tagL.BackgroundTransparency = 1
            tagL.Font                   = Enum.Font.GothamBold
            tagL.TextSize               = 10
            tagL.TextColor3             = cfg.displayColor or Color3.fromRGB(180,180,180)
            tagL.TextXAlignment         = Enum.TextXAlignment.Left
            tagL.Text                   = "@" .. p.Name
            tagL.ZIndex                 = 12

            local baseColor  = btn.BackgroundColor3
            local hoverColor = Color3.new(
                math.min(1, baseColor.R + 0.10),
                math.min(1, baseColor.G + 0.10),
                math.min(1, baseColor.B + 0.12))
            local flashColor = Color3.fromRGB(120, 35, 42)
            local pressProxy = Instance.new("TextButton", btn)
            pressProxy.Name                   = "PressProxy"
            pressProxy.Size                   = UDim2.new(1, 20, 1, 16)
            pressProxy.Position               = UDim2.new(0, -10, 0, -8)
            pressProxy.BackgroundTransparency = 1
            pressProxy.BorderSizePixel        = 0
            pressProxy.AutoButtonColor        = false
            pressProxy.Text                   = ""
            pressProxy.ZIndex                 = 30
            pressProxy.Active                 = true
            pressProxy.Selectable             = false

            local function hoverIn()
                TweenService:Create(btn,    TweenInfo.new(0.10, Enum.EasingStyle.Quad), {BackgroundColor3 = hoverColor, BackgroundTransparency = 0}):Play()
                TweenService:Create(bStroke, TweenInfo.new(0.10), {Thickness = 2.5}):Play()
            end
            local function hoverOut()
                TweenService:Create(btn,    TweenInfo.new(0.15, Enum.EasingStyle.Quad), {BackgroundColor3 = baseColor, BackgroundTransparency = cfg.backgroundTransparency}):Play()
                TweenService:Create(bStroke, TweenInfo.new(0.15), {Thickness = 1.5}):Play()
            end
            btn.MouseEnter:Connect(hoverIn)
            btn.MouseLeave:Connect(hoverOut)
            pressProxy.MouseEnter:Connect(hoverIn)
            pressProxy.MouseLeave:Connect(hoverOut)

            local debounce = false
            local function activateTag()
                if debounce then return end
                debounce = true
                task.delay(0.2, function() debounce = false end)
                local myChar = plr.Character
                local tChar  = p.Character
                if not myChar or not tChar then return end
                local tRoot  = tChar:FindFirstChild("HumanoidRootPart")
                if not tRoot then return end
                TweenService:Create(btn, TweenInfo.new(0.06, Enum.EasingStyle.Quad), {BackgroundColor3 = flashColor}):Play()
                task.delay(0.18, function()
                    if btn and btn.Parent then
                        TweenService:Create(btn, TweenInfo.new(0.20), {BackgroundColor3 = baseColor}):Play()
                    end
                end)
                pcall(function()
                    myChar:PivotTo(CFrame.new(tRoot.Position + Vector3.new(0, 3, 0)))
                    if _G.showAnnouncement then
                        _G.showAnnouncement("Teleported to " .. p.DisplayName, 2)
                    end
                end)
            end
            btn.Activated:Connect(activateTag)
            pressProxy.Activated:Connect(activateTag)
            pressProxy.MouseButton1Click:Connect(activateTag)
            pressProxy.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                    activateTag()
                end
            end)

            local entry = {
                btn       = btn,
                nameL     = nameL,
                tagL      = tagL,
                icon      = icon,
                btnCorner = btnCorner,
                lastMini  = nil,
            }
            playerBtns[p] = entry
            return entry
        end

        runService.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
            local cam = workspace.CurrentCamera
            if not cam then return end

            if not tagSG.Parent or not tagSG:IsDescendantOf(game) then
                for p in pairs(playerBtns) do playerBtns[p] = nil end
                for k in pairs(overheadState) do overheadState[k] = nil end
                local newSG = Instance.new("ScreenGui")
                newSG.Name           = "BleedClickTags"
                newSG.ResetOnSpawn   = false
                newSG.IgnoreGuiInset = true
                newSG.DisplayOrder   = 9999999
                newSG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
                newSG.Parent         = (gethui and gethui()) or coreGui
                tagSG = newSG
            end

            local allPlayers = players:GetPlayers()

            for _, p in ipairs(allPlayers) do
                if p == plr then continue end

                pcall(function()
                    local entry   = getOrCreate(p)
                    local btn     = entry.btn
                    local pChar   = p.Character
                    local hasTag  = hasCustomNametag(pChar)
                    local adornee = pChar and (pChar:FindFirstChild("Head") or pChar:FindFirstChild("HumanoidRootPart"))

                    if pChar then
                        local hum = pChar:FindFirstChildOfClass("Humanoid")
                        if hum then
                            local wantHidden = nametagsEnabled and hasTag
                            if overheadState[p] ~= wantHidden then
                                overheadState[p] = wantHidden
                                if wantHidden then
                                    pcall(function() hideHumanoidOverhead(hum) end)
                                else
                                    pcall(function() showHumanoidOverhead(hum) end)
                                end
                            end
                        end
                    end

                    if not adornee or not nametagsEnabled then
                        btn.Visible = false
                        return
                    end

                    local screenPos, onScreen, depth = cam:WorldToScreenPoint(adornee.Position + Vector3.new(0, PLAYER_TAG_WORLD_Y, 0))
                    btn.Visible = onScreen and depth > 0

                    if btn.Visible then
                        local mini = math.clamp(12 / depth, 0.4, 1.4) < 0.6
                        if mini ~= entry.lastMini then
                            entry.lastMini = mini
                            if mini then
                                btn.Size               = UDim2.new(0, 44, 0, 44)
                                entry.btnCorner.CornerRadius = UDim.new(1, 0)
                                entry.nameL.Visible    = false
                                entry.tagL.Visible     = false
                                entry.icon.Size        = UDim2.new(0, 32, 0, 32)
                                entry.icon.Position    = UDim2.new(0.5, -16, 0.5, -16)
                            else
                                btn.Size               = UDim2.new(0, 170, 0, 42)
                                entry.btnCorner.CornerRadius = UDim.new(0, 10)
                                entry.nameL.Visible    = true
                                entry.tagL.Visible     = true
                                entry.icon.Size        = UDim2.new(0, 28, 0, 28)
                                entry.icon.Position    = UDim2.new(0, 7, 0.5, -14)
                            end
                            local cr = mini and UDim.new(1, 0) or UDim.new(0, 10)
                            entry.btnCorner.CornerRadius = cr
                            local bgMask = btn:FindFirstChildWhichIsA("Frame")
                            if bgMask then
                                local mc = bgMask:FindFirstChildOfClass("UICorner")
                                if mc then mc.CornerRadius = cr end
                                local bi = bgMask:FindFirstChildWhichIsA("ImageLabel")
                                if bi then
                                    local bc = bi:FindFirstChildOfClass("UICorner")
                                    if bc then bc.CornerRadius = cr end
                                end
                            end
                        end
                        btn.Position = UDim2.new(0, screenPos.X, 0, screenPos.Y)
                    end
                end)
            end
        end))

        players.PlayerRemoving:Connect(removeBtn)

        players.PlayerAdded:Connect(function(p)
            p.CharacterAdded:Connect(function()
                overheadState[p] = nil
            end)
        end)
        for _, p in ipairs(players:GetPlayers()) do
            if p ~= plr then
                p.CharacterAdded:Connect(function()
                    overheadState[p] = nil
                end)
            end
        end

        _G.setTagsVisible = function(visible)
            for _, entry in pairs(playerBtns) do
                pcall(function() entry.btn.Visible = visible end)
            end
        end
        _G.resetOverheadState = function()
            for k in pairs(overheadState) do
                overheadState[k] = nil
            end
        end
    end)()

    local function showAnnouncement(msg, durationSec)
        task.spawn(function()
            local mn      = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
            local iconSz  = mn and 28 or 40
            local titleSz = mn and 12 or 15
            local msgSz   = mn and 11 or 13
            local timeSz  = mn and 9  or 10
            local padL    = mn and 46 or 64
            local padR    = mn and 16 or 24
            local W_NOTIF = mn
                and math.floor(workspace.CurrentCamera.ViewportSize.X * 0.88)
                or  math.min(520, workspace.CurrentCamera.ViewportSize.X - 60)

            local msgText   = msg or ""
            local msgBounds = TextService:GetTextSize(
                msgText, msgSz, Enum.Font.RobotoMono,
                Vector2.new(W_NOTIF - padL - padR, 400)
            )
            local msgH   = msgBounds.Y
            local msgTop = mn and 24 or 34
            local H      = msgTop + msgH + (mn and 14 or 18)

            local gAccent = Color3.fromRGB(88,  101, 242)
            local gBg0    = Color3.fromRGB(14,  14,  16)
            local gBg1    = Color3.fromRGB(20,  20,  23)
            local gStk    = Color3.fromRGB(36,  36,  42)
            local gDim    = Color3.fromRGB(110, 110, 128)

            local nf = Instance.new("Frame", screen)
            nf.Size             = UDim2.new(0, W_NOTIF, 0, H)
            nf.AnchorPoint      = Vector2.new(0.5, 0)
            nf.Position         = UDim2.new(0.5, 0, 0, -H - 20)
            nf.BackgroundColor3 = gBg0
            nf.BackgroundTransparency = 1
            nf.BorderSizePixel  = 0
            nf.ZIndex           = 200
            nf.ClipsDescendants = false
            Instance.new("UICorner", nf).CornerRadius = UDim.new(0, 12)

            local nGrad = Instance.new("UIGradient", nf)
            nGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, gBg1),
                ColorSequenceKeypoint.new(1, gBg0),
            })
            nGrad.Rotation = 135

            local nStroke = Instance.new("UIStroke", nf)
            nStroke.Color        = gStk
            nStroke.Thickness    = 1
            nStroke.Transparency = 1

            local bar = Instance.new("Frame", nf)
            bar.Size             = UDim2.new(0, 3, 0.7, 0)
            bar.Position         = UDim2.new(0, 0, 0.15, 0)
            bar.BackgroundColor3 = gAccent
            bar.BackgroundTransparency = 1
            bar.BorderSizePixel  = 0
            Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 2)

            local iconImg = Instance.new("ImageLabel", nf)
            iconImg.Size              = UDim2.new(0, iconSz, 0, iconSz)
            iconImg.Position          = UDim2.new(0, mn and 8 or 14, 0.5, -iconSz/2)
            iconImg.BackgroundTransparency = 1
            iconImg.ImageTransparency = 1
            iconImg.ImageColor3       = gAccent
            iconImg.Image             = "rbxassetid://134633682532885"
            iconImg.ScaleType         = Enum.ScaleType.Fit
            iconImg.ZIndex            = 201

            local titleL = Instance.new("TextLabel", nf)
            titleL.Text               = "Announcement"
            titleL.Font               = Enum.Font.GothamBlack
            titleL.TextSize           = titleSz
            titleL.TextColor3         = Color3.new(1, 1, 1)
            titleL.Position           = UDim2.new(0, padL, 0, mn and 7 or 10)
            titleL.Size               = UDim2.new(0, W_NOTIF - padL - padR, 0, mn and 14 or 18)
            titleL.BackgroundTransparency = 1
            titleL.TextXAlignment     = Enum.TextXAlignment.Left
            titleL.TextTransparency   = 1
            titleL.TextTruncate       = Enum.TextTruncate.AtEnd
            titleL.ZIndex             = 201

            local timeL = Instance.new("TextLabel", nf)
            timeL.Text               = "now"
            timeL.Font               = Enum.Font.Gotham
            timeL.TextSize           = timeSz
            timeL.TextColor3         = gDim
            timeL.Position           = UDim2.new(1, -36, 0, mn and 8 or 12)
            timeL.Size               = UDim2.new(0, 30, 0, 12)
            timeL.BackgroundTransparency = 1
            timeL.TextXAlignment     = Enum.TextXAlignment.Right
            timeL.TextTransparency   = 1
            timeL.ZIndex             = 201

            local msgL = Instance.new("TextLabel", nf)
            msgL.Text               = msgText
            msgL.Font               = Enum.Font.Gotham
            msgL.TextSize           = msgSz
            msgL.TextColor3         = gDim
            msgL.Position           = UDim2.new(0, padL, 0, msgTop)
            msgL.Size               = UDim2.new(0, W_NOTIF - padL - padR, 0, msgH)
            msgL.BackgroundTransparency = 1
            msgL.TextXAlignment     = Enum.TextXAlignment.Left
            msgL.TextWrapped        = true
            msgL.TextTransparency   = 1
            msgL.ZIndex             = 201

            local interact = Instance.new("TextButton", nf)
            interact.Size             = UDim2.new(1, 0, 1, 0)
            interact.BackgroundTransparency = 1
            interact.Text             = ""
            interact.ZIndex           = 202

            task.spawn(function()
                local snd = Instance.new("Sound", screen)
                snd.SoundId = "rbxassetid://4590662766"
                snd.Volume  = 0.8
                snd:Play()
                game:GetService("Debris"):AddItem(snd, 4)
            end)

            TweenService:Create(nf, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Position = UDim2.new(0.5, 0, 0, mn and 12 or 20)
            }):Play()
            task.wait(0.1)
            TweenService:Create(nf,      TweenInfo.new(0.8, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.15}):Play()
            TweenService:Create(nStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0.3}):Play()
            TweenService:Create(bar,     TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
            task.wait(0.05)
            TweenService:Create(iconImg, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {ImageTransparency = 0}):Play()
            task.wait(0.04)
            TweenService:Create(titleL,  TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
            task.wait(0.04)
            TweenService:Create(msgL,    TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {TextTransparency = 0.1}):Play()
            TweenService:Create(timeL,   TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {TextTransparency = 0.5}):Play()

            local dismissed = false
            local function dismiss()
                if dismissed then return end
                dismissed = true
                TweenService:Create(nf, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
                    Position = UDim2.new(0.5, 0, 0, -H - 20)
                }):Play()
                task.wait(0.45)
                nf:Destroy()
            end

            local duration = tonumber(durationSec) or 30
            if duration < 3 then duration = 3 end
            if duration > 120 then duration = 120 end
            interact.MouseButton1Click:Connect(dismiss)
            task.delay(duration, dismiss)
        end)
    end

    _G.showAnnouncement = showAnnouncement

end)()

local function refreshNametags()
    pcall(function()
        if type(_G.setTagsVisible) == "function" then
            _G.setTagsVisible(nametagsEnabled)
        end
    end)
    pcall(function()
        if nametagsEnabled then
            if type(_G.showTag) == "function" then _G.showTag() end
        else
            if type(_G.hideTag) == "function" then _G.hideTag() end
        end
    end)
    if type(_G.resetOverheadState) == "function" then
        _G.resetOverheadState()
    end
end

_G.refreshNametags   = refreshNametags
_G.nametagsEnabled   = nametagsEnabled
_G.setNametagsEnabled = function(v)
    nametagsEnabled = v
    _G.nametagsEnabled = v
    refreshNametags()
end