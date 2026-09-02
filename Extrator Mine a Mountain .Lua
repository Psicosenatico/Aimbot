local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer and (LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10))

local VERSION = "V5.3 RAW"
local GUI_NAME = "MAM2_XGRSScanner_V53"
local PREFIX = "MAM2_XGRS_V53"
local MAX_UNIQUE_TEXTS = 6000

local ROOT_NAMES = {
    XGRS_UniversalLoader = true,
    PlayerHUD_Overlay = true,
    PlayerHUD_Status = true,
    XGRSGlobalToggle = true,
    UniverseCrystalEsp = true,
}

local running = false
local startedAt = 0

local collectorConnections = {}
local watchedText = {}
local trackedRoots = {}
local rawItems = {}
local seenText = {}
local stats = {
    observedTextEvents = 0,
    savedUniqueTexts = 0,
    duplicatesIgnored = 0,
    noiseIgnored = 0,
}

local function safeString(v)
    local ok, s = pcall(tostring, v)
    return ok and s or "<error>"
end

local function pathOf(obj)
    local ok, p = pcall(function()
        return obj:GetFullName()
    end)
    return ok and p or safeString(obj)
end

local function trim(s)
    s = safeString(s or "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function lower(s)
    return string.lower(trim(s))
end

local function getText(obj)
    local ok, value = pcall(function()
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            return obj.Text
        end
        return nil
    end)
    return ok and value or nil
end

local function getPlaceholder(obj)
    if not obj:IsA("TextBox") then return nil end
    local ok, value = pcall(function()
        return obj.PlaceholderText
    end)
    if ok then return value end
end

local function findTrackedRoot(obj)
    local current = obj
    local depth = 0

    while current and depth < 50 do
        if trackedRoots[current] then
            return current
        end
        current = current.Parent
        depth += 1
    end

    return nil
end

local function normalizeTextForDedup(text)
    local s = trim(text)
    s = s:gsub("%s+", " ")
    return s
end

local function isLikelyUsernamePath(path)
    local p = lower(path)
    return p:find(".row.player.", 1, true) ~= nil
        or p:find(".injectcard.player", 1, true) ~= nil
end

local function isDynamicHudPath(path)
    local p = lower(path)

    return p:find(".row.ping.", 1, true) ~= nil
        or p:find(".row.fps.", 1, true) ~= nil
        or p:find(".row.clock.", 1, true) ~= nil
        or p:find(".row.session.", 1, true) ~= nil
end

local function isPureVisualToken(text)
    local s = trim(text)

    if s == "" then return true end

    local visual = {
        ["+"] = true, ["-"] = true, ["×"] = true, ["x"] = true,
        ["‹"] = true, ["›"] = true, ["<"] = true, [">"] = true,
        ["v"] = true, ["^"] = true, ["✓"] = true, ["⚠"] = true,
        ["•"] = true, ["..."] = true,
    }

    return visual[s] == true
end

local function isDynamicNumberOnly(text)
    local s = trim(text)

    -- Somente numeros / contadores simples / percentuais / tempo curto.
    if s:match("^%d+$") then return true end
    if s:match("^%d+/%d+$") then return true end
    if s:match("^%d+%%%s*/%s*%d+%%$") then return true end
    if s:match("^%d+%s*[Mm][Ss]$") then return true end
    if s:match("^%d+%s*[Ff][Pp][Ss]$") then return true end
    if s:match("^%d+%s*[Ss]$") then return true end
    if s:match("^%d%d:%d%d$") then return true end

    return false
end

local function shouldIgnore(text, path)
    local s = trim(text)
    if s == "" then return true, "empty" end

    if isPureVisualToken(s) then
        return true, "visual-token"
    end

    if isLikelyUsernamePath(path) then
        return true, "player-identity"
    end

    if isDynamicHudPath(path) then
        return true, "dynamic-hud"
    end

    if isDynamicNumberOnly(s) then
        return true, "dynamic-number"
    end

    return false, nil
end

local function addRawText(obj, root, text, sourceKind)
    if not running then return end
    if #rawItems >= MAX_UNIQUE_TEXTS then return end

    stats.observedTextEvents += 1

    local path = pathOf(obj)
    local ignored = shouldIgnore(text, path)
    if ignored then
        stats.noiseIgnored += 1
        return
    end

    local normalized = normalizeTextForDedup(text)
    if normalized == "" then
        stats.noiseIgnored += 1
        return
    end

    -- Deduplica pelo texto, mas preserva a PRIMEIRA origem encontrada.
    if seenText[normalized] then
        stats.duplicatesIgnored += 1
        return
    end

    seenText[normalized] = true

    rawItems[#rawItems + 1] = {
        index = #rawItems + 1,
        root = root and root.Name or nil,
        class = obj.ClassName,
        name = obj.Name,
        path = path,
        source = sourceKind,
        text = normalized,
        t = os.clock() - startedAt,
    }

    stats.savedUniqueTexts += 1
end

local function attachTextWatcher(obj, root)
    if watchedText[obj] then return end
    if not (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then
        return
    end

    watchedText[obj] = true
    local previous = getText(obj)

    local conn = obj:GetPropertyChangedSignal("Text"):Connect(function()
        if not running then return end

        local currentRoot = findTrackedRoot(obj)
        if not currentRoot then return end

        local newText = getText(obj)
        if newText == previous then return end

        addRawText(obj, currentRoot, newText, "TEXT_CHANGED")
        previous = newText
    end)

    collectorConnections[#collectorConnections + 1] = conn
end

local function registerRoot(obj)
    if trackedRoots[obj] then return end
    trackedRoots[obj] = true

    rawItems[#rawItems + 1] = {
        index = #rawItems + 1,
        root = obj.Name,
        class = obj.ClassName,
        name = obj.Name,
        path = pathOf(obj),
        source = "ROOT_ADDED",
        text = "[ROOT] " .. obj.Name,
        t = os.clock() - startedAt,
    }
end

local function handleAdded(obj)
    if not running or not obj then return end

    if ROOT_NAMES[obj.Name] and (obj:IsA("ScreenGui") or obj:IsA("Folder")) then
        registerRoot(obj)
        return
    end

    local root = findTrackedRoot(obj)
    if not root then return end

    if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
        local text = getText(obj)
        if text ~= nil then
            addRawText(obj, root, text, "TEXT_OBJECT_ADDED")
        end

        if obj:IsA("TextBox") then
            local placeholder = getPlaceholder(obj)
            if placeholder and trim(placeholder) ~= "" then
                addRawText(obj, root, placeholder, "PLACEHOLDER")
            end
        end

        attachTextWatcher(obj, root)
    end
end

local function stopCollectorConnections()
    for _, conn in ipairs(collectorConnections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    collectorConnections = {}
end

local function startCollector()
    if running then return end

    stopCollectorConnections()

    rawItems = {}
    seenText = {}
    watchedText = {}
    trackedRoots = {}

    stats = {
        observedTextEvents = 0,
        savedUniqueTexts = 0,
        duplicatesIgnored = 0,
        noiseIgnored = 0,
    }

    startedAt = os.clock()
    running = true

    collectorConnections[#collectorConnections + 1] = CoreGui.DescendantAdded:Connect(handleAdded)
end

local function sanitize(v, depth)
    depth = depth or 0
    if depth > 6 then return "<max-depth>" end

    local tv = typeof(v)

    if v == nil or tv == "string" or tv == "boolean" then
        return v
    elseif tv == "number" then
        if v ~= v then return "nan" end
        if v == math.huge then return "inf" end
        if v == -math.huge then return "-inf" end
        return v
    elseif tv == "table" then
        local out = {}
        for k, value in pairs(v) do
            out[safeString(k)] = sanitize(value, depth + 1)
        end
        return out
    end

    return safeString(v)
end

local function buildReport()
    return {
        version = VERSION,
        duration = os.clock() - startedAt,
        count = #rawItems,
        maxUniqueTexts = MAX_UNIQUE_TEXTS,
        stats = stats,
        items = rawItems,
        notes = {
            "Unique semantic raw text only.",
            "Duplicate text is stored once.",
            "Dynamic HUD/player identity noise is ignored.",
            "Observation target is CoreGui XGRS branches only.",
            "No GetDescendants / Workspace / ReplicatedStorage / PlayerGui scan.",
        }
    }
end

local function buildTxt(report)
    local lines = {
        "Mine a Mountain 2 - XGRS Raw Content Scanner " .. VERSION,
        "Itens salvos: " .. tostring(#rawItems),
        "Textos observados: " .. tostring(stats.observedTextEvents),
        "Duplicados ignorados: " .. tostring(stats.duplicatesIgnored),
        "Ruido ignorado: " .. tostring(stats.noiseIgnored),
        "Duracao: " .. string.format("%.2fs", report.duration),
        "",
        "=== CONTEUDO RAW UNICO ===",
    }

    for _, item in ipairs(rawItems) do
        lines[#lines + 1] = string.format(
            "[%04d] %s | %s | %s",
            item.index or 0,
            safeString(item.source),
            safeString(item.path),
            safeString(item.text)
        )
    end

    return table.concat(lines, "\n")
end

local function saveReport()
    local report = buildReport()

    local okJson, encoded = pcall(function()
        return HttpService:JSONEncode(sanitize(report))
    end)

    local txt = buildTxt(report)
    local stamp = os.date("!%Y%m%d_%H%M%S")

    local jsonName = PREFIX .. "_" .. stamp .. "_raw.json"
    local txtName = PREFIX .. "_" .. stamp .. "_raw.txt"

    local jsonOK, txtOK = false, false

    if writefile then
        if okJson then
            jsonOK = pcall(writefile, jsonName, encoded)
        else
            pcall(writefile, PREFIX .. "_" .. stamp .. "_json_error.txt", safeString(encoded))
        end

        txtOK = pcall(writefile, txtName, txt)
    end

    if setclipboard then
        pcall(setclipboard, okJson and encoded or txt)
    end

    return jsonOK, txtOK, jsonName, txtName
end

local function stopCollector()
    if not running then
        return false, false, nil, nil
    end

    running = false
    stopCollectorConnections()
    return saveReport()
end

-- =========================================================
-- GUI
-- =========================================================

local gui
local frame
local status
local button
local uiConnections = {}

local function disconnectUi()
    for _, conn in ipairs(uiConnections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    uiConnections = {}
end

local function destroyOldScannerGuis()
    for _, parent in ipairs({PlayerGui, CoreGui}) do
        if parent then
            for _, name in ipairs({
                "MAM2_XGRSScanner_V5",
                "MAM2_XGRSScanner_V51",
                "MAM2_XGRSScanner_V52",
                "MAM2_XGRSScanner_V53",
            }) do
                local old = parent:FindFirstChild(name)
                if old then
                    pcall(function() old:Destroy() end)
                end
            end
        end
    end
end

local function makeDraggable(handle, target)
    local dragging = false
    local dragInput
    local dragStart
    local startPos

    uiConnections[#uiConnections + 1] = handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then

            dragging = true
            dragStart = input.Position
            startPos = target.Position

            local changedConn
            changedConn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if changedConn then changedConn:Disconnect() end
                end
            end)
        end
    end)

    uiConnections[#uiConnections + 1] = handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    uiConnections[#uiConnections + 1] = UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput and dragStart and startPos then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
end

local function buildGui()
    disconnectUi()

    if gui then
        pcall(function() gui:Destroy() end)
    end

    gui = Instance.new("ScreenGui")
    gui.Name = GUI_NAME
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 2147483000
    gui.Parent = PlayerGui or CoreGui

    frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(340, 205)
    frame.Position = UDim2.new(0.5, -170, 0.5, -102)
    frame.BackgroundColor3 = Color3.fromRGB(20,20,24)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0,14)
    corner.Parent = frame

    local dragBar = Instance.new("Frame")
    dragBar.Size = UDim2.new(1,0,0,76)
    dragBar.BackgroundTransparency = 1
    dragBar.Active = true
    dragBar.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1,-20,0,32)
    title.Position = UDim2.fromOffset(10,8)
    title.BackgroundTransparency = 1
    title.Text = "MAM2 XGRS Raw Scanner"
    title.TextColor3 = Color3.fromRGB(245,245,245)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = dragBar

    local versionLabel = Instance.new("TextLabel")
    versionLabel.Size = UDim2.new(1,-20,0,22)
    versionLabel.Position = UDim2.fromOffset(10,40)
    versionLabel.BackgroundTransparency = 1
    versionLabel.Text = "Versao: " .. VERSION
    versionLabel.TextColor3 = Color3.fromRGB(120,170,255)
    versionLabel.Font = Enum.Font.GothamBold
    versionLabel.TextSize = 13
    versionLabel.TextXAlignment = Enum.TextXAlignment.Left
    versionLabel.Parent = dragBar

    status = Instance.new("TextLabel")
    status.Size = UDim2.new(1,-20,0,32)
    status.Position = UDim2.fromOffset(10,80)
    status.BackgroundTransparency = 1
    status.Text = "Status: parado"
    status.TextColor3 = Color3.fromRGB(190,190,200)
    status.Font = Enum.Font.Gotham
    status.TextSize = 14
    status.Parent = frame

    button = Instance.new("TextButton")
    button.Size = UDim2.new(1,-30,0,62)
    button.Position = UDim2.fromOffset(15,125)
    button.BackgroundColor3 = Color3.fromRGB(32,92,220)
    button.BorderSizePixel = 0
    button.Text = "Iniciar Scam"
    button.TextColor3 = Color3.fromRGB(255,255,255)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 18
    button.Parent = frame

    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0,12)
    bc.Parent = button

    makeDraggable(dragBar, frame)

    uiConnections[#uiConnections + 1] = button.MouseButton1Click:Connect(function()
        if not running then
            startCollector()
            button.Text = "Finalizar Scam"
            status.Text = "Status: capturando conteudo raw..."
        else
            status.Text = "Status: salvando..."
            local jsonOK, txtOK, jsonName, txtName = stopCollector()
            button.Text = "Iniciar Scam"

            if jsonOK and txtOK then
                status.Text = "Salvo RAW JSON + TXT"
            elseif txtOK then
                status.Text = "RAW TXT salvo"
            else
                status.Text = "Falha ao salvar"
            end

            print("MAM2 V5.3 JSON:", jsonName, jsonOK)
            print("MAM2 V5.3 TXT:", txtName, txtOK)
        end
    end)
end

destroyOldScannerGuis()
buildGui()

-- Watchdog apenas da interface.
task.spawn(function()
    while true do
        task.wait(1)
        if not gui or not gui.Parent or not frame or not frame.Parent then
            pcall(buildGui)
        end
    end
end)

print("MAM2 XGRS Raw Content Scanner " .. VERSION .. " carregado.")
