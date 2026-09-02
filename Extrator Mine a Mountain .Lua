local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer and (LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10))

local GUI_NAME = "MAM2_XGRSScanner_V51"
local PREFIX = "MAM2_XGRS_V51"

local running = false
local startedAt = 0
local events = {}
local connections = {}
local trackedRoots = {}
local watchedText = {}
local semanticObjects = {}
local semanticIndex = {}
local MAX_EVENTS = 1200
local checkpointScheduled = false
local checkpointSaved = false

local ROOT_NAMES = {
    ["XGRS_UniversalLoader"] = true,
    ["PlayerHUD_Overlay"] = true,
    ["PlayerHUD_Status"] = true,
    ["XGRSGlobalToggle"] = true,
    ["UniverseCrystalEsp"] = true,
}

local SEMANTIC_CLASSES = {
    TextLabel = true,
    TextButton = true,
    TextBox = true,
    ScreenGui = true,
    Folder = true,
    ImageButton = true,
}

local function now()
    return os.clock()
end

local function unix()
    return os.time()
end

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
        return nil
    end)
    return ok and value or nil
end

local function isTrackedDescendant(obj)
    local current = obj
    local depth = 0

    while current and depth < 40 do
        if trackedRoots[current] then
            return true, current
        end
        current = current.Parent
        depth += 1
    end

    return false, nil
end

local function sanitize(data, depth)
    depth = depth or 0
    if depth > 5 then
        return "<max-depth>"
    end

    local tv = typeof(data)

    if data == nil or tv == "string" or tv == "number" or tv == "boolean" then
        return data
    elseif tv == "Instance" then
        return pathOf(data)
    elseif tv == "table" then
        local out = {}
        for k, v in pairs(data) do
            out[safeString(k)] = sanitize(v, depth + 1)
        end
        return out
    end

    return safeString(data)
end

local function push(kind, data)
    if not running then return end
    if #events >= MAX_EVENTS then return end

    events[#events + 1] = {
        t = now() - startedAt,
        unix = unix(),
        kind = kind,
        data = sanitize(data or {}),
    }
end

local function semanticKey(obj)
    return safeString(obj)
end

local function rememberSemantic(obj, root)
    if not obj or not SEMANTIC_CLASSES[obj.ClassName] then
        return
    end

    local key = semanticKey(obj)
    local text = getText(obj)

    local entry = {
        path = pathOf(obj),
        name = obj.Name,
        class = obj.ClassName,
        root = root and root.Name or nil,
        text = text,
    }

    if not semanticIndex[key] then
        semanticIndex[key] = #semanticObjects + 1
        semanticObjects[#semanticObjects + 1] = entry
    else
        semanticObjects[semanticIndex[key]] = entry
    end
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

        local newText = getText(obj)
        if newText == previous then return end

        local inside, detectedRoot = isTrackedDescendant(obj)
        if not inside then
            previous = newText
            return
        end

        push("TEXT_CHANGED", {
            root = (detectedRoot or root) and (detectedRoot or root).Name or nil,
            path = pathOf(obj),
            class = obj.ClassName,
            oldText = previous,
            newText = newText,
        })

        rememberSemantic(obj, detectedRoot or root)
        previous = newText
    end)

    connections[#connections + 1] = conn
end

local saveReport

local function registerRoot(obj)
    if trackedRoots[obj] then return end
    trackedRoots[obj] = true

    push("ROOT_ADDED", {
        name = obj.Name,
        class = obj.ClassName,
        path = pathOf(obj),
    })

    rememberSemantic(obj, obj)

    -- Quando o HUD final aparece, salva UM checkpoint leve alguns segundos depois.
    -- O scanner continua rodando e ainda pode ser finalizado manualmente.
    if obj.Name == "PlayerHUD_Overlay" and not checkpointScheduled then
        checkpointScheduled = true
        task.delay(8, function()
            if running and not checkpointSaved then
                checkpointSaved = true
                pcall(function()
                    saveReport("checkpoint")
                end)
            end
        end)
    end
end

local function handleAdded(obj)
    if not running or not obj then return end

    if ROOT_NAMES[obj.Name] and (obj:IsA("ScreenGui") or obj:IsA("Folder")) then
        registerRoot(obj)
        return
    end

    local inside, root = isTrackedDescendant(obj)
    if not inside then
        return
    end

    if not SEMANTIC_CLASSES[obj.ClassName] then
        return
    end

    attachTextWatcher(obj, root)
    rememberSemantic(obj, root)

    local text = getText(obj)

    -- Só registra criação textual quando existe texto; evita centenas de botões vazios.
    if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
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
        return
    end

    local inside, root = isTrackedDescendant(obj)
    if not inside then return end

    if SEMANTIC_CLASSES[obj.ClassName] then
        local text = getText(obj)
        if text ~= nil and text ~= "" then
            push("SEMANTIC_REMOVING", {
                root = root.Name,
                path = pathOf(obj),
                class = obj.ClassName,
                text = text,
            })
        end
    end
end

local function disconnectAll()
    for _, conn in ipairs(connections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    connections = {}
end

local function jsonEncodeSafe(data)
    local clean = sanitize(data)
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(clean)
    end)
    if ok then
        return encoded, nil
    end
    return nil, safeString(encoded)
end

local function makeTxt(report)
    local lines = {
        "Mine a Mountain 2 - XGRS Injection Scanner V5",
        "Eventos: " .. tostring(report.eventCount),
        "Objetos semanticos: " .. tostring(#report.semanticObjects),
        "Duracao: " .. string.format("%.2fs", report.duration),
        "",
        "=== EVENTOS ===",
    }

    for _, ev in ipairs(report.events) do
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

        elseif ev.kind == "SEMANTIC_REMOVING" then
            lines[#lines + 1] = string.format(
                "[%.2fs] SEMANTIC_REMOVING | %s | %s",
                ev.t or 0,
                safeString(d.path),
                safeString(d.text)
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
    lines[#lines + 1] = "=== ARVORE SEMANTICA ACUMULADA ==="

    for _, obj in ipairs(report.semanticObjects) do
        lines[#lines + 1] = string.format(
            "%s | %s | root=%s | text=%s",
            safeString(obj.class),
            safeString(obj.path),
            safeString(obj.root),
            safeString(obj.text or "")
        )
    end

    return table.concat(lines, "\n")
end

saveReport = function(suffix)
    local report = {
        version = "MAM2 XGRS Injection Scanner V5.1",
        startedUnix = events[1] and events[1].unix or unix(),
        endedUnix = unix(),
        duration = now() - startedAt,
        eventCount = #events,
        maxEvents = MAX_EVENTS,
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
            "Observation target: CoreGui only.",
            "Scanner UI is hosted in PlayerGui only to avoid XGRS CoreGui cleanup.",
            "PlayerGui contents are NOT monitored.",
            "No ReplicatedStorage.",
            "No recursive full-tree scan.",
            "No periodic full-state capture.",
            "Purely visual classes are ignored.",
            "Empty TextButtons are not logged as creation events.",
        },
    }

    local encoded, jsonErr = jsonEncodeSafe(report)
    local txt = makeTxt(report)

    local stamp = os.date("!%Y%m%d_%H%M%S")
    local tag = suffix and ("_" .. suffix) or ""
    local jsonName = PREFIX .. "_" .. stamp .. tag .. ".json"
    local txtName = PREFIX .. "_" .. stamp .. tag .. "_report.txt"

    local jsonOK = false
    local txtOK = false

    if writefile then
        if encoded then
            jsonOK = pcall(writefile, jsonName, encoded)
        else
            pcall(
                writefile,
                PREFIX .. "_" .. stamp .. "_json_error.txt",
                safeString(jsonErr)
            )
        end

        txtOK = pcall(writefile, txtName, txt)
    end

    if setclipboard then
        pcall(setclipboard, encoded or txt)
    end

    return jsonOK, txtOK, jsonName, txtName
end

local function startScanner()
    if running then return end

    events = {}
    connections = {}
    trackedRoots = {}
    watchedText = {}
    semanticObjects = {}
    semanticIndex = {}
    checkpointScheduled = false
    checkpointSaved = false

    startedAt = now()
    running = true

    push("SCAN_START", {})

    -- Apenas novos objetos adicionados ao CoreGui.
    connections[#connections + 1] = CoreGui.DescendantAdded:Connect(handleAdded)
    connections[#connections + 1] = CoreGui.DescendantRemoving:Connect(handleRemoving)
end

local function stopScanner()
    if not running then
        return false, false, nil, nil
    end

    push("SCAN_STOP", {})
    running = false
    disconnectAll()

    return saveReport("final")
end

-- Interface isolada do CoreGui observado.
-- Preferimos PlayerGui para que a limpeza/injeção do XGRS em CoreGui
-- não remova o botão do scanner.
pcall(function()
    if PlayerGui then
        local old = PlayerGui:FindFirstChild(GUI_NAME)
        if old then old:Destroy() end
    end
    local oldCore = CoreGui:FindFirstChild(GUI_NAME)
    if oldCore then oldCore:Destroy() end
end)

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

if PlayerGui then
    gui.Parent = PlayerGui
else
    -- fallback apenas se PlayerGui não estiver disponível
    gui.Parent = CoreGui
end

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(320, 170)
frame.Position = UDim2.new(0.5, -160, 0.5, -85)
frame.BackgroundColor3 = Color3.fromRGB(20,20,24)
frame.BorderSizePixel = 0
frame.Parent = gui

local fc = Instance.new("UICorner")
fc.CornerRadius = UDim.new(0,14)
fc.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,-20,0,40)
title.Position = UDim2.fromOffset(10,8)
title.BackgroundTransparency = 1
title.Text = "MAM2 XGRS Scanner V5.1"
title.TextColor3 = Color3.fromRGB(245,245,245)
title.Font = Enum.Font.GothamBold
title.TextSize = 19
title.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1,-20,0,32)
status.Position = UDim2.fromOffset(10,46)
status.BackgroundTransparency = 1
status.Text = "Status: parado"
status.TextColor3 = Color3.fromRGB(190,190,200)
status.Font = Enum.Font.Gotham
status.TextSize = 14
status.Parent = frame

local button = Instance.new("TextButton")
button.Size = UDim2.new(1,-30,0,58)
button.Position = UDim2.fromOffset(15,94)
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

button.MouseButton1Click:Connect(function()
    if not running then
        startScanner()
        button.Text = "Finalizar Scam"
        status.Text = "Status: aguardando XGRS..."
    else
        status.Text = "Status: salvando..."

        local jsonOK, txtOK, jsonName, txtName = stopScanner()

        button.Text = "Iniciar Scam"

        if jsonOK and txtOK then
            status.Text = "Salvo JSON + TXT"
        elseif txtOK then
            status.Text = "TXT salvo"
        else
            status.Text = "Falha ao salvar"
        end

        print("MAM2 V5.1 JSON:", jsonName, jsonOK)
        print("MAM2 V5.1 TXT:", txtName, txtOK)
    end
end)

print("MAM2 XGRS Injection Scanner V5.1 carregado.")
