local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer and (LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10))

local VERSION = "V5.2 CLEAN"
local GUI_NAME = "MAM2_XGRSScanner_V52"
local PREFIX = "MAM2_XGRS_V52"
local MAX_EVENTS = 1000

-- =========================================================
-- COLETOR (independente da GUI)
-- =========================================================

local running = false
local startedAt = 0
local events = {}
local collectorConnections = {}
local trackedRoots = {}
local watchedText = {}
local semanticObjects = {}
local semanticIndex = {}
local checkpointScheduled = false

local ROOT_NAMES = {
    XGRS_UniversalLoader = true,
    PlayerHUD_Overlay = true,
    PlayerHUD_Status = true,
    XGRSGlobalToggle = true,
    UniverseCrystalEsp = true,
}

local SEMANTIC_CLASSES = {
    TextLabel = true,
    TextButton = true,
    TextBox = true,
    ScreenGui = true,
    Folder = true,
    ImageButton = true,
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

local function getText(obj)
    local ok, value = pcall(function()
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            return obj.Text
        end
    end)
    return ok and value or nil
end

local function sanitize(v, depth)
    depth = depth or 0
    if depth > 5 then return "<max-depth>" end

    local tv = typeof(v)

    if v == nil or tv == "string" or tv == "boolean" then
        return v
    elseif tv == "number" then
        if v ~= v then return "nan" end
        if v == math.huge then return "inf" end
        if v == -math.huge then return "-inf" end
        return v
    elseif tv == "Instance" then
        return pathOf(v)
    elseif tv == "table" then
        local out = {}
        for k, value in pairs(v) do
            out[safeString(k)] = sanitize(value, depth + 1)
        end
        return out
    end

    return safeString(v)
end

local function push(kind, data)
    if not running then return end
    if #events >= MAX_EVENTS then return end

    events[#events + 1] = {
        t = os.clock() - startedAt,
        unix = os.time(),
        kind = kind,
        data = sanitize(data or {}),
    }
end

local function findTrackedRoot(obj)
    local current = obj
    local depth = 0

    while current and depth < 40 do
        if trackedRoots[current] then
            return current
        end
        current = current.Parent
        depth += 1
    end

    return nil
end

local function rememberSemantic(obj, root)
    if not obj or not SEMANTIC_CLASSES[obj.ClassName] then return end

    local key = safeString(obj)
    local item = {
        root = root and root.Name or nil,
        class = obj.ClassName,
        name = obj.Name,
        path = pathOf(obj),
        text = getText(obj),
    }

    if semanticIndex[key] then
        semanticObjects[semanticIndex[key]] = item
    else
        semanticObjects[#semanticObjects + 1] = item
        semanticIndex[key] = #semanticObjects
    end
end

local function buildReport()
    return {
        version = VERSION,
        eventCount = #events,
        duration = running and (os.clock() - startedAt) or 0,
        events = events,
        semanticObjects = semanticObjects,
        monitoredRoots = {
            "XGRS_UniversalLoader",
            "PlayerHUD_Overlay",
            "PlayerHUD_Status",
            "XGRSGlobalToggle",
            "UniverseCrystalEsp",
        },
        notes = {
            "Collector rebuilt from scratch.",
            "Observation target: CoreGui only.",
            "No GetDescendants.",
            "No ReplicatedStorage or Workspace scan.",
            "Pure visual classes ignored.",
        }
    }
end

local function encodeReport(report)
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(sanitize(report))
    end)
    return ok and encoded or nil, ok and nil or safeString(encoded)
end

local function buildTxt(report)
    local lines = {
        "Mine a Mountain 2 - XGRS Injection Scanner " .. VERSION,
        "Eventos: " .. tostring(report.eventCount),
        "Duracao: " .. string.format("%.2fs", os.clock() - startedAt),
        "",
        "=== EVENTOS ===",
    }

    for _, ev in ipairs(events) do
        local d = ev.data or {}

        if ev.kind == "ROOT_ADDED" or ev.kind == "ROOT_REMOVING" then
            lines[#lines + 1] = string.format(
                "[%.2fs] %s | %s | %s",
                ev.t or 0,
                ev.kind,
                safeString(d.name),
                safeString(d.path)
            )
        elseif ev.kind == "TEXT_OBJECT_ADDED" then
            lines[#lines + 1] = string.format(
                "[%.2fs] TEXT_OBJECT_ADDED | %s | %s",
                ev.t or 0,
                safeString(d.path),
                safeString(d.text)
            )
        elseif ev.kind == "TEXT_CHANGED" then
            lines[#lines + 1] = string.format(
                "[%.2fs] TEXT_CHANGED | %s | %s -> %s",
                ev.t or 0,
                safeString(d.path),
                safeString(d.oldText),
                safeString(d.newText)
            )
        elseif ev.kind == "SEMANTIC_OBJECT_ADDED" then
            lines[#lines + 1] = string.format(
                "[%.2fs] SEMANTIC_OBJECT_ADDED | %s | %s",
                ev.t or 0,
                safeString(d.class),
                safeString(d.path)
            )
        else
            lines[#lines + 1] = string.format(
                "[%.2fs] %s",
                ev.t or 0,
                safeString(ev.kind)
            )
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "=== OBJETOS SEMANTICOS ==="

    for _, item in ipairs(semanticObjects) do
        lines[#lines + 1] = string.format(
            "%s | %s | root=%s | text=%s",
            safeString(item.class),
            safeString(item.path),
            safeString(item.root),
            safeString(item.text or "")
        )
    end

    return table.concat(lines, "\n")
end

local function saveReport(tag)
    local report = buildReport()
    local encoded, jsonErr = encodeReport(report)
    local txt = buildTxt(report)

    local stamp = os.date("!%Y%m%d_%H%M%S")
    local suffix = tag and ("_" .. tag) or ""

    local jsonName = PREFIX .. "_" .. stamp .. suffix .. ".json"
    local txtName = PREFIX .. "_" .. stamp .. suffix .. "_report.txt"

    local jsonOK, txtOK = false, false

    if writefile then
        if encoded then
            jsonOK = pcall(writefile, jsonName, encoded)
        else
            pcall(writefile, PREFIX .. "_" .. stamp .. "_json_error.txt", safeString(jsonErr))
        end

        txtOK = pcall(writefile, txtName, txt)
    end

    if setclipboard then
        pcall(setclipboard, encoded or txt)
    end

    return jsonOK, txtOK, jsonName, txtName
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

        push("TEXT_CHANGED", {
            root = currentRoot.Name,
            path = pathOf(obj),
            class = obj.ClassName,
            oldText = previous,
            newText = newText,
        })

        rememberSemantic(obj, currentRoot)
        previous = newText
    end)

    collectorConnections[#collectorConnections + 1] = conn
end

local function scheduleCheckpoint()
    if checkpointScheduled then return end
    checkpointScheduled = true

    task.delay(8, function()
        if running then
            pcall(function()
                saveReport("checkpoint")
            end)
        end
    end)
end

local function registerRoot(obj)
    if trackedRoots[obj] then return end

    trackedRoots[obj] = true

    push("ROOT_ADDED", {
        name = obj.Name,
        class = obj.ClassName,
        path = pathOf(obj),
    })

    rememberSemantic(obj, obj)

    if obj.Name == "PlayerHUD_Overlay" then
        scheduleCheckpoint()
    end
end

local function handleAdded(obj)
    if not running or not obj then return end

    if ROOT_NAMES[obj.Name] and (obj:IsA("ScreenGui") or obj:IsA("Folder")) then
        registerRoot(obj)
        return
    end

    local root = findTrackedRoot(obj)
    if not root then return end
    if not SEMANTIC_CLASSES[obj.ClassName] then return end

    rememberSemantic(obj, root)
    attachTextWatcher(obj, root)

    if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
        local text = getText(obj)
        if text ~= nil and text ~= "" then
            push("TEXT_OBJECT_ADDED", {
                root = root.Name,
                path = pathOf(obj),
                class = obj.ClassName,
                text = text,
            })
        end
    else
        push("SEMANTIC_OBJECT_ADDED", {
            root = root.Name,
            path = pathOf(obj),
            class = obj.ClassName,
            name = obj.Name,
        })
    end
end

local function handleRemoving(obj)
    if not running or not obj then return end

    if trackedRoots[obj] then
        push("ROOT_REMOVING", {
            name = obj.Name,
            class = obj.ClassName,
            path = pathOf(obj),
        })
        trackedRoots[obj] = nil
    end
end

local function stopCollectorConnections()
    for _, conn in ipairs(collectorConnections) do
        pcall(function() conn:Disconnect() end)
    end
    collectorConnections = {}
end

local function startCollector()
    if running then return end

    stopCollectorConnections()

    events = {}
    trackedRoots = {}
    watchedText = {}
    semanticObjects = {}
    semanticIndex = {}
    checkpointScheduled = false

    startedAt = os.clock()
    running = true

    push("SCAN_START", {})

    collectorConnections[#collectorConnections + 1] = CoreGui.DescendantAdded:Connect(handleAdded)
    collectorConnections[#collectorConnections + 1] = CoreGui.DescendantRemoving:Connect(handleRemoving)
end

local function stopCollector()
    if not running then
        return false, false, nil, nil
    end

    push("SCAN_STOP", {})
    running = false

    stopCollectorConnections()

    return saveReport("final")
end

-- =========================================================
-- GUI (separada do coletor)
-- =========================================================

local gui
local frame
local status
local actionButton
local uiConnections = {}
local rebuildingGui = false

local function disconnectUiConnections()
    for _, conn in ipairs(uiConnections) do
        pcall(function() conn:Disconnect() end)
    end
    uiConnections = {}
end

local function destroyOldScannerGuis()
    local possibleParents = {CoreGui, PlayerGui}

    for _, parent in ipairs(possibleParents) do
        if parent then
            for _, name in ipairs({
                "MAM2_XGRSScanner_V5",
                "MAM2_XGRSScanner_V51",
                "MAM2_XGRSScanner_V52",
                GUI_NAME,
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
    local dragStart
    local startPos
    local dragInput

    uiConnections[#uiConnections + 1] = handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then

            dragging = true
            dragStart = input.Position
            startPos = target.Position

            local ended
            ended = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if ended then
                        ended:Disconnect()
                    end
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
    if rebuildingGui then return end
    rebuildingGui = true

    disconnectUiConnections()

    if gui then
        pcall(function() gui:Destroy() end)
    end

    gui = Instance.new("ScreenGui")
    gui.Name = GUI_NAME
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 2147483000

    if PlayerGui then
        gui.Parent = PlayerGui
    else
        gui.Parent = CoreGui
    end

    frame = Instance.new("Frame")
    frame.Name = "Main"
    frame.Size = UDim2.fromOffset(330, 194)
    frame.Position = UDim2.new(0.5, -165, 0.5, -97)
    frame.BackgroundColor3 = Color3.fromRGB(20,20,24)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Parent = gui

    local fc = Instance.new("UICorner")
    fc.CornerRadius = UDim.new(0,14)
    fc.Parent = frame

    local dragBar = Instance.new("Frame")
    dragBar.Name = "DragBar"
    dragBar.Size = UDim2.new(1,0,0,70)
    dragBar.BackgroundTransparency = 1
    dragBar.Active = true
    dragBar.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1,-20,0,32)
    title.Position = UDim2.fromOffset(10,8)
    title.BackgroundTransparency = 1
    title.Text = "MAM2 XGRS Scanner"
    title.TextColor3 = Color3.fromRGB(245,245,245)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = dragBar

    local versionLabel = Instance.new("TextLabel")
    versionLabel.Size = UDim2.new(1,-20,0,22)
    versionLabel.Position = UDim2.fromOffset(10,38)
    versionLabel.BackgroundTransparency = 1
    versionLabel.Text = "Versao: " .. VERSION
    versionLabel.TextColor3 = Color3.fromRGB(120,170,255)
    versionLabel.Font = Enum.Font.GothamBold
    versionLabel.TextSize = 13
    versionLabel.TextXAlignment = Enum.TextXAlignment.Left
    versionLabel.Parent = dragBar

    status = Instance.new("TextLabel")
    status.Size = UDim2.new(1,-20,0,30)
    status.Position = UDim2.fromOffset(10,74)
    status.BackgroundTransparency = 1
    status.Text = running and "Status: coletando..." or "Status: parado"
    status.TextColor3 = Color3.fromRGB(190,190,200)
    status.Font = Enum.Font.Gotham
    status.TextSize = 14
    status.Parent = frame

    actionButton = Instance.new("TextButton")
    actionButton.Size = UDim2.new(1,-30,0,60)
    actionButton.Position = UDim2.fromOffset(15,117)
    actionButton.BackgroundColor3 = Color3.fromRGB(32,92,220)
    actionButton.BorderSizePixel = 0
    actionButton.Text = running and "Finalizar Scam" or "Iniciar Scam"
    actionButton.TextColor3 = Color3.fromRGB(255,255,255)
    actionButton.Font = Enum.Font.GothamBold
    actionButton.TextSize = 18
    actionButton.Parent = frame

    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0,12)
    bc.Parent = actionButton

    makeDraggable(dragBar, frame)

    uiConnections[#uiConnections + 1] = actionButton.MouseButton1Click:Connect(function()
        if not running then
            startCollector()
            actionButton.Text = "Finalizar Scam"
            status.Text = "Status: aguardando XGRS..."
        else
            status.Text = "Status: salvando..."
            local jsonOK, txtOK, jsonName, txtName = stopCollector()

            actionButton.Text = "Iniciar Scam"

            if jsonOK and txtOK then
                status.Text = "Salvo JSON + TXT"
            elseif txtOK then
                status.Text = "TXT salvo"
            else
                status.Text = "Falha ao salvar"
            end

            print("MAM2 V5.2 JSON:", jsonName, jsonOK)
            print("MAM2 V5.2 TXT:", txtName, txtOK)
        end
    end)

    rebuildingGui = false
end

destroyOldScannerGuis()
buildGui()

-- Watchdog extremamente leve: apenas garante que a interface continue existindo.
-- Nao faz qualquer leitura do jogo.
task.spawn(function()
    while true do
        task.wait(1)

        local invalid = not gui
            or not gui.Parent
            or not frame
            or not frame.Parent

        if invalid then
            pcall(buildGui)
        end
    end
end)

print("MAM2 XGRS Injection Scanner " .. VERSION .. " carregado.")
