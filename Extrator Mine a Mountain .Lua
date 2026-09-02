local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local VERSION = "V5.4 STABLE"
local GUI_NAME = "MAM2_XGRSScanner_V54"
local PREFIX = "MAM2_XGRS_V54"
local STATE_KEY = "__MAM2_XGRS_RAW_SCANNER_STATE"
local MAX_UNIQUE_TEXTS = 6000

local env = (getgenv and getgenv()) or _G

-- =========================================================
-- ENCERRA UMA INSTANCIA ANTERIOR DESTE SCANNER
-- =========================================================

do
    local previous = rawget(env, STATE_KEY)
    if type(previous) == "table" and type(previous.cleanup) == "function" then
        pcall(previous.cleanup)
    end
end

local state = {
    alive = true,
    running = false,
    token = tostring(os.clock()) .. "_" .. tostring(math.random(100000, 999999)),
    collectorConnections = {},
    uiConnections = {},
    gui = nil,
    frame = nil,
    status = nil,
    button = nil,
}

env[STATE_KEY] = state

local function disconnectList(list)
    for i = #list, 1, -1 do
        local conn = list[i]
        pcall(function()
            conn:Disconnect()
        end)
        list[i] = nil
    end
end

local function currentPlayerGui()
    local lp = Players.LocalPlayer
    if not lp then return nil end

    local pg = lp:FindFirstChildOfClass("PlayerGui")
    if pg then return pg end

    local ok, result = pcall(function()
        return lp:WaitForChild("PlayerGui", 2)
    end)

    return ok and result or nil
end

local function destroyGuiObject(g)
    if g then
        pcall(function()
            g:Destroy()
        end)
    end
end

local function destroyNamedOldGuis()
    local parents = {currentPlayerGui(), CoreGui}

    local names = {
        "MAM2_XGRSScanner_V5",
        "MAM2_XGRSScanner_V51",
        "MAM2_XGRSScanner_V52",
        "MAM2_XGRSScanner_V53",
        "MAM2_XGRSScanner_V54",
    }

    for _, parent in ipairs(parents) do
        if parent then
            for _, name in ipairs(names) do
                local old = parent:FindFirstChild(name)
                if old then
                    destroyGuiObject(old)
                end
            end
        end
    end
end

-- =========================================================
-- COLETA RAW
-- =========================================================

local startedAt = 0
local trackedRoots = {}
local seenText = {}
local rawItems = {}
local checkpointScheduled = false

local stats = {
    observedTextEvents = 0,
    savedUniqueTexts = 0,
    duplicatesIgnored = 0,
    noiseIgnored = 0,
}

local ROOT_NAMES = {
    XGRS_UniversalLoader = true,
    PlayerHUD_Overlay = true,
    PlayerHUD_Status = true,
    XGRSGlobalToggle = true,
    UniverseCrystalEsp = true,
}

local function safeString(v)
    local ok, s = pcall(tostring, v)
    return ok and s or "<error>"
end

local function pathOf(obj)
    local ok, result = pcall(function()
        return obj:GetFullName()
    end)
    return ok and result or safeString(obj)
end

local function trim(v)
    local s = safeString(v or "")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function lower(v)
    return string.lower(trim(v))
end

local function normalize(v)
    local s = trim(v)
    s = s:gsub("%s+", " ")
    return s
end

local function getText(obj)
    local ok, value = pcall(function()
        return obj.Text
    end)
    return ok and value or nil
end

local function getPlaceholder(obj)
    if not obj:IsA("TextBox") then return nil end

    local ok, value = pcall(function()
        return obj.PlaceholderText
    end)

    return ok and value or nil
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

local VISUAL_TOKENS = {
    ["+"] = true,
    ["-"] = true,
    ["x"] = true,
    ["X"] = true,
    ["×"] = true,
    ["‹"] = true,
    ["›"] = true,
    ["<"] = true,
    [">"] = true,
    ["v"] = true,
    ["^"] = true,
    ["✓"] = true,
    ["⚠"] = true,
    ["•"] = true,
    ["..."] = true,
}

local function isNoise(text, path)
    local s = trim(text)
    local p = lower(path)

    if s == "" then
        return true
    end

    if VISUAL_TOKENS[s] then
        return true
    end

    -- Identidade do jogador / telemetria do HUD.
    if p:find(".row.player.", 1, true)
        or p:find(".injectcard.player", 1, true)
        or p:find(".row.ping.", 1, true)
        or p:find(".row.fps.", 1, true)
        or p:find(".row.clock.", 1, true)
        or p:find(".row.session.", 1, true) then
        return true
    end

    -- Valores que mudam constantemente e nao descrevem uma funcao.
    if s:match("^%d+$")
        or s:match("^%d+/%d+$")
        or s:match("^%d+%s*[Ff][Pp][Ss]$")
        or s:match("^%d+%s*[Mm][Ss]$")
        or s:match("^%d+%s*[Ss]$")
        or s:match("^%d%d:%d%d$") then
        return true
    end

    return false
end

local function addRaw(obj, root, value, source)
    if not state.alive or not state.running then return end
    if #rawItems >= MAX_UNIQUE_TEXTS then return end

    stats.observedTextEvents += 1

    local text = normalize(value)
    local path = pathOf(obj)

    if isNoise(text, path) then
        stats.noiseIgnored += 1
        return
    end

    if seenText[text] then
        stats.duplicatesIgnored += 1
        return
    end

    seenText[text] = true

    rawItems[#rawItems + 1] = {
        index = #rawItems + 1,
        t = os.clock() - startedAt,
        source = source,
        root = root and root.Name or nil,
        class = obj.ClassName,
        name = obj.Name,
        path = path,
        text = text,
    }

    stats.savedUniqueTexts += 1
end

-- Mudancas de texto so sao acompanhadas onde elas tem valor diagnostico:
-- loader/autorizacao e status final. O menu inteiro nao recebe watchers.
local function shouldWatchTextChanges(root, obj)
    if not root then return false end

    if root.Name == "XGRS_UniversalLoader" then
        return true
    end

    if root.Name == "PlayerHUD_Status" then
        return true
    end

    if root.Name == "PlayerHUD_Overlay" then
        local n = lower(obj.Name)
        return n == "timeleftlabel"
    end

    return false
end

local watchedChangeObjects = {}

local function attachLimitedTextWatcher(obj, root)
    if watchedChangeObjects[obj] then return end
    if not shouldWatchTextChanges(root, obj) then return end

    watchedChangeObjects[obj] = true
    local previous = getText(obj)

    local conn = obj:GetPropertyChangedSignal("Text"):Connect(function()
        if not state.alive or not state.running then return end
        if not obj.Parent then return end

        local currentRoot = findTrackedRoot(obj)
        if not currentRoot then return end

        local nowText = getText(obj)
        if nowText ~= previous then
            addRaw(obj, currentRoot, nowText, "TEXT_CHANGED")
            previous = nowText
        end
    end)

    state.collectorConnections[#state.collectorConnections + 1] = conn
end

local function sanitize(v, depth)
    depth = depth or 0
    if depth > 6 then
        return "<max-depth>"
    end

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
        duration = state.running and (os.clock() - startedAt) or (os.clock() - startedAt),
        itemCount = #rawItems,
        stats = stats,
        maxUniqueTexts = MAX_UNIQUE_TEXTS,
        items = rawItems,
        notes = {
            "CoreGui XGRS branches only.",
            "No GetDescendants.",
            "No Workspace or ReplicatedStorage scan.",
            "Menu text changes are not globally watched.",
            "Only loader/status text changes receive persistent watchers.",
            "Duplicate/noise filtering enabled.",
        },
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

local function saveReport(tag)
    if startedAt == 0 then
        return false, false, nil, nil
    end

    local report = buildReport()

    local jsonOKEncode, encoded = pcall(function()
        return HttpService:JSONEncode(sanitize(report))
    end)

    local txt = buildTxt(report)
    local stamp = os.date("!%Y%m%d_%H%M%S")
    local suffix = tag and ("_" .. tag) or ""

    local jsonName = PREFIX .. "_" .. stamp .. suffix .. "_raw.json"
    local txtName = PREFIX .. "_" .. stamp .. suffix .. "_raw.txt"

    local jsonOK = false
    local txtOK = false

    if writefile then
        if jsonOKEncode then
            jsonOK = pcall(writefile, jsonName, encoded)
        end

        txtOK = pcall(writefile, txtName, txt)
    end

    if setclipboard then
        pcall(setclipboard, jsonOKEncode and encoded or txt)
    end

    return jsonOK, txtOK, jsonName, txtName
end

local function scheduleCheckpoint()
    if checkpointScheduled then return end
    checkpointScheduled = true

    local token = state.token

    task.delay(7, function()
        if not state.alive or state.token ~= token or not state.running then
            return
        end

        pcall(function()
            saveReport("checkpoint")
        end)
    end)
end

local function registerRoot(obj)
    if trackedRoots[obj] then return end

    trackedRoots[obj] = true

    rawItems[#rawItems + 1] = {
        index = #rawItems + 1,
        t = os.clock() - startedAt,
        source = "ROOT_ADDED",
        root = obj.Name,
        class = obj.ClassName,
        name = obj.Name,
        path = pathOf(obj),
        text = "[ROOT] " .. obj.Name,
    }

    if obj.Name == "PlayerHUD_Overlay" then
        scheduleCheckpoint()
    end
end

local function handleAdded(obj)
    if not state.alive or not state.running or not obj then
        return
    end

    if ROOT_NAMES[obj.Name] and (obj:IsA("ScreenGui") or obj:IsA("Folder")) then
        registerRoot(obj)
        return
    end

    local root = findTrackedRoot(obj)
    if not root then
        return
    end

    if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
        local value = getText(obj)

        if value ~= nil then
            addRaw(obj, root, value, "TEXT_OBJECT_ADDED")
        end

        if obj:IsA("TextBox") then
            local placeholder = getPlaceholder(obj)
            if placeholder and trim(placeholder) ~= "" then
                addRaw(obj, root, placeholder, "PLACEHOLDER")
            end
        end

        attachLimitedTextWatcher(obj, root)
    end
end

local function startCollector()
    if not state.alive or state.running then
        return
    end

    disconnectList(state.collectorConnections)

    trackedRoots = {}
    watchedChangeObjects = {}
    seenText = {}
    rawItems = {}
    checkpointScheduled = false

    stats = {
        observedTextEvents = 0,
        savedUniqueTexts = 0,
        duplicatesIgnored = 0,
        noiseIgnored = 0,
    }

    startedAt = os.clock()
    state.running = true

    state.collectorConnections[#state.collectorConnections + 1] =
        CoreGui.DescendantAdded:Connect(handleAdded)
end

local function stopCollector()
    if not state.running then
        return false, false, nil, nil
    end

    state.running = false
    disconnectList(state.collectorConnections)

    return saveReport("final")
end

-- =========================================================
-- GUI
-- =========================================================

local rebuildingGui = false

local function makeDraggable(handle, target)
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPos = nil

    state.uiConnections[#state.uiConnections + 1] =
        handle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then

                dragging = true
                dragStart = input.Position
                startPos = target.Position

                local changedConn
                changedConn = input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                        if changedConn then
                            changedConn:Disconnect()
                        end
                    end
                end)
            end
        end)

    state.uiConnections[#state.uiConnections + 1] =
        handle.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end)

    state.uiConnections[#state.uiConnections + 1] =
        UserInputService.InputChanged:Connect(function(input)
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

local function parentGuiSafely(gui)
    local pg = currentPlayerGui()

    if pg then
        local ok = pcall(function()
            gui.Parent = pg
        end)

        if ok and gui.Parent == pg then
            return true
        end
    end

    local okCore = pcall(function()
        gui.Parent = CoreGui
    end)

    return okCore and gui.Parent == CoreGui
end

local function buildGui()
    if not state.alive or rebuildingGui then
        return
    end

    rebuildingGui = true

    disconnectList(state.uiConnections)

    if state.gui then
        destroyGuiObject(state.gui)
        state.gui = nil
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = GUI_NAME
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 2147483000

    if not parentGuiSafely(gui) then
        destroyGuiObject(gui)
        rebuildingGui = false
        return
    end

    local frame = Instance.new("Frame")
    frame.Name = "Main"
    frame.Size = UDim2.fromOffset(350, 210)
    frame.Position = UDim2.new(0.5, -175, 0.5, -105)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 14)
    corner.Parent = frame

    local dragBar = Instance.new("Frame")
    dragBar.Name = "DragBar"
    dragBar.Size = UDim2.new(1, 0, 0, 78)
    dragBar.BackgroundTransparency = 1
    dragBar.Active = true
    dragBar.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 32)
    title.Position = UDim2.fromOffset(10, 8)
    title.BackgroundTransparency = 1
    title.Text = "MAM2 XGRS Raw Scanner"
    title.TextColor3 = Color3.fromRGB(245, 245, 245)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = dragBar

    local versionLabel = Instance.new("TextLabel")
    versionLabel.Size = UDim2.new(1, -20, 0, 22)
    versionLabel.Position = UDim2.fromOffset(10, 41)
    versionLabel.BackgroundTransparency = 1
    versionLabel.Text = "Versao: " .. VERSION
    versionLabel.TextColor3 = Color3.fromRGB(120, 170, 255)
    versionLabel.Font = Enum.Font.GothamBold
    versionLabel.TextSize = 13
    versionLabel.TextXAlignment = Enum.TextXAlignment.Left
    versionLabel.Parent = dragBar

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -20, 0, 32)
    status.Position = UDim2.fromOffset(10, 82)
    status.BackgroundTransparency = 1
    status.Text = state.running and "Status: capturando conteudo raw..." or "Status: parado"
    status.TextColor3 = Color3.fromRGB(190, 190, 200)
    status.Font = Enum.Font.Gotham
    status.TextSize = 14
    status.Parent = frame

    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, -30, 0, 62)
    button.Position = UDim2.fromOffset(15, 130)
    button.BackgroundColor3 = Color3.fromRGB(32, 92, 220)
    button.BorderSizePixel = 0
    button.Text = state.running and "Finalizar Scam" or "Iniciar Scam"
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 18
    button.Parent = frame

    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 12)
    buttonCorner.Parent = button

    state.gui = gui
    state.frame = frame
    state.status = status
    state.button = button

    makeDraggable(dragBar, frame)

    state.uiConnections[#state.uiConnections + 1] =
        button.MouseButton1Click:Connect(function()
            if not state.alive then return end

            if not state.running then
                startCollector()

                if state.button then
                    state.button.Text = "Finalizar Scam"
                end

                if state.status then
                    state.status.Text = "Status: capturando conteudo raw..."
                end
            else
                if state.status then
                    state.status.Text = "Status: salvando..."
                end

                local jsonOK, txtOK, jsonName, txtName = stopCollector()

                if state.button then
                    state.button.Text = "Iniciar Scam"
                end

                if state.status then
                    if jsonOK and txtOK then
                        state.status.Text = "Salvo RAW JSON + TXT"
                    elseif txtOK then
                        state.status.Text = "RAW TXT salvo"
                    else
                        state.status.Text = "Falha ao salvar"
                    end
                end

                print("MAM2 V5.4 JSON:", jsonName, jsonOK)
                print("MAM2 V5.4 TXT:", txtName, txtOK)
            end
        end)

    rebuildingGui = false
end

-- =========================================================
-- CLEANUP REAL / SINGLETON
-- =========================================================

state.cleanup = function()
    if not state.alive then
        return
    end

    state.alive = false
    state.running = false

    disconnectList(state.collectorConnections)
    disconnectList(state.uiConnections)

    if state.gui then
        destroyGuiObject(state.gui)
        state.gui = nil
    end
end

destroyNamedOldGuis()
buildGui()

-- Watchdog da GUI. Ele termina automaticamente quando outra versao
-- chamar state.cleanup().
task.spawn(function()
    local myToken = state.token

    while state.alive and state.token == myToken do
        task.wait(1)

        if not state.alive or state.token ~= myToken then
            break
        end

        local guiMissing =
            not state.gui
            or not state.gui.Parent
            or not state.frame
            or not state.frame.Parent

        if guiMissing then
            pcall(buildGui)
        end
    end
end)

print("MAM2 XGRS Raw Content Scanner " .. VERSION .. " carregado.")
