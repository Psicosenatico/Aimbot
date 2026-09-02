local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")

local GUI_NAME = "MAM2_RuntimeScanner_V42"
local PREFIX = "MAM2_RUNTIME_V42"

local running = false
local startedAt = 0
local events = {}
local connections = {}
local watchedText = {}
local watchedGui = {}
local injectedObjects = {}
local createdRoots = {}

local TARGET_WORDS = {
    "xgrs",
    "playerhud",
    "inject",
    "universal",
    "loader",
    "free",
    "premium",
    "time left",
    "infinity",
    "crystal",
    "duper",
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

local function pathOf(inst)
    local ok, p = pcall(function()
        return inst:GetFullName()
    end)
    return ok and p or safeString(inst)
end

local function containsTarget(text)
    if type(text) ~= "string" then
        return false
    end
    local low = text:lower()
    for _, word in ipairs(TARGET_WORDS) do
        if low:find(word, 1, true) then
            return true
        end
    end
    return false
end

local function getText(obj)
    local ok, text = pcall(function()
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            return obj.Text
        end
    end)
    return ok and text or nil
end

local function isRelevant(obj)
    if not obj then return false end

    local name = safeString(obj.Name)
    if containsTarget(name) then
        return true
    end

    local text = getText(obj)
    if containsTarget(text) then
        return true
    end

    local parent = obj.Parent
    local depth = 0
    while parent and depth < 8 do
        if containsTarget(safeString(parent.Name)) then
            return true
        end
        parent = parent.Parent
        depth += 1
    end

    return false
end

local function sanitize(v)
    local tv = typeof(v)
    if v == nil or tv == "string" or tv == "number" or tv == "boolean" then
        return v
    elseif tv == "Color3" then
        return {r=v.R, g=v.G, b=v.B}
    elseif tv == "UDim2" then
        return {
            xScale=v.X.Scale, xOffset=v.X.Offset,
            yScale=v.Y.Scale, yOffset=v.Y.Offset
        }
    elseif tv == "Vector2" then
        return {x=v.X, y=v.Y}
    elseif tv == "EnumItem" then
        return safeString(v)
    elseif tv == "Instance" then
        return pathOf(v)
    elseif tv == "table" then
        local out = {}
        for k, val in pairs(v) do
            out[safeString(k)] = sanitize(val)
        end
        return out
    end
    return safeString(v)
end

local function push(kind, data)
    if not running then return end
    events[#events + 1] = {
        t = now() - startedAt,
        unix = unix(),
        kind = kind,
        data = sanitize(data or {})
    }
end

local function objectInfo(obj)
    local info = {
        name = obj.Name,
        class = obj.ClassName,
        path = pathOf(obj),
    }

    local text = getText(obj)
    if text ~= nil then
        info.text = text
    end

    pcall(function()
        if obj:IsA("GuiObject") then
            info.visible = obj.Visible
            info.position = sanitize(obj.Position)
            info.size = sanitize(obj.Size)
        end
    end)

    pcall(function()
        if obj:IsA("ScreenGui") then
            info.enabled = obj.Enabled
            info.displayOrder = obj.DisplayOrder
        end
    end)

    return info
end

local function attachTextWatcher(obj)
    if watchedText[obj] then return end
    if not (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then
        return
    end

    watchedText[obj] = true
    local lastText = getText(obj)

    local conn = obj:GetPropertyChangedSignal("Text"):Connect(function()
        if not running then return end

        local newText = getText(obj)
        if newText ~= lastText and (isRelevant(obj) or containsTarget(newText) or containsTarget(lastText)) then
            push("TEXT_CHANGED", {
                path = pathOf(obj),
                class = obj.ClassName,
                oldText = lastText,
                newText = newText,
            })
        end
        lastText = newText
    end)

    connections[#connections + 1] = conn
end

local function attachGuiWatchers(obj)
    if watchedGui[obj] then return end
    if not (obj:IsA("GuiObject") or obj:IsA("ScreenGui")) then return end

    watchedGui[obj] = true

    local props = obj:IsA("ScreenGui")
        and {"Enabled"}
        or {"Visible"}

    for _, prop in ipairs(props) do
        local conn = obj:GetPropertyChangedSignal(prop):Connect(function()
            if not running or not isRelevant(obj) then return end

            local value
            pcall(function() value = obj[prop] end)

            push("GUI_PROPERTY_CHANGED", {
                path = pathOf(obj),
                class = obj.ClassName,
                property = prop,
                value = sanitize(value),
            })
        end)

        connections[#connections + 1] = conn
    end
end

local function inspectNewObject(obj, source)
    if not running then return end

    -- DescendantAdded só entrega objetos criados/adicionados após o início.
    injectedObjects[obj] = true

    attachTextWatcher(obj)
    attachGuiWatchers(obj)

    if isRelevant(obj) then
        push("OBJECT_ADDED", {
            source = source,
            object = objectInfo(obj),
        })

        if obj:IsA("ScreenGui") or obj:IsA("Folder") then
            createdRoots[obj] = true
        end
    end
end

local function watchRoot(root, label)
    if not root then return end

    local addConn = root.DescendantAdded:Connect(function(obj)
        inspectNewObject(obj, label)
    end)
    connections[#connections + 1] = addConn

    local removeConn = root.DescendantRemoving:Connect(function(obj)
        if not running then return end
        if not injectedObjects[obj] then return end

        if isRelevant(obj) then
            push("OBJECT_REMOVING", {
                source = label,
                object = objectInfo(obj),
            })
        end
    end)
    connections[#connections + 1] = removeConn
end

local function captureRelevantTree()
    local tree = {}

    for root in pairs(createdRoots) do
        if root and root.Parent then
            tree[#tree + 1] = objectInfo(root)

            local ok, descendants = pcall(function()
                return root:GetDescendants()
            end)

            if ok then
                for _, obj in ipairs(descendants) do
                    if isRelevant(obj) then
                        tree[#tree + 1] = objectInfo(obj)
                    end
                end
            end
        end
    end

    return tree
end

local function disconnectAll()
    for _, conn in ipairs(connections) do
        pcall(function() conn:Disconnect() end)
    end
    connections = {}
end

local function saveReport()
    local report = {
        version = "MAM2 Runtime Scanner V4.2 Ultra Lite",
        startedUnix = events[1] and events[1].unix or unix(),
        endedUnix = unix(),
        duration = now() - startedAt,
        eventCount = #events,
        events = events,
        finalInjectedTree = captureRelevantTree(),
        notes = {
            "Monitors only objects created after scanner start.",
            "ReplicatedStorage is not monitored.",
            "No periodic snapshots.",
            "No initial GetDescendants scan and no full-game runtime scan.",
        }
    }

    local clean = sanitize(report)
    local encoded

    local jsonOk, jsonErr = pcall(function()
        encoded = HttpService:JSONEncode(clean)
    end)

    local stamp = os.date("!%Y%m%d_%H%M%S")
    local jsonName = PREFIX .. "_" .. stamp .. ".json"
    local txtName = PREFIX .. "_" .. stamp .. "_report.txt"

    local lines = {
        "Mine a Mountain 2 - Runtime Scanner V4.1 Lite",
        "Eventos: " .. tostring(#events),
        "Duracao: " .. string.format("%.2fs", report.duration),
        "",
        "=== EVENTOS ===",
    }

    for _, ev in ipairs(events) do
        local d = ev.data or {}

        if ev.kind == "TEXT_CHANGED" then
            lines[#lines + 1] = string.format(
                "[%.2fs] TEXT_CHANGED | %s | %s -> %s",
                ev.t or 0,
                safeString(d.path),
                safeString(d.oldText),
                safeString(d.newText)
            )
        elseif ev.kind == "OBJECT_ADDED" or ev.kind == "OBJECT_REMOVING" then
            local o = d.object or {}
            lines[#lines + 1] = string.format(
                "[%.2fs] %s | %s | %s | %s",
                ev.t or 0,
                ev.kind,
                safeString(o.class),
                safeString(o.path),
                safeString(o.text or "")
            )
        elseif ev.kind == "GUI_PROPERTY_CHANGED" then
            lines[#lines + 1] = string.format(
                "[%.2fs] GUI_PROPERTY_CHANGED | %s | %s=%s",
                ev.t or 0,
                safeString(d.path),
                safeString(d.property),
                safeString(d.value)
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
    lines[#lines + 1] = "=== ARVORE FINAL INJETADA ==="

    for _, obj in ipairs(report.finalInjectedTree) do
        lines[#lines + 1] = string.format(
            "%s | %s | %s",
            safeString(obj.class),
            safeString(obj.path),
            safeString(obj.text or "")
        )
    end

    local txt = table.concat(lines, "\n")

    local jsonSaved = false
    local txtSaved = false

    if writefile then
        if jsonOk and encoded then
            jsonSaved = pcall(writefile, jsonName, encoded)
        end
        txtSaved = pcall(writefile, txtName, txt)

        if not jsonOk then
            pcall(writefile, PREFIX .. "_" .. stamp .. "_json_error.txt", safeString(jsonErr))
        end
    end

    if setclipboard then
        pcall(setclipboard, encoded or txt)
    end

    return jsonSaved, txtSaved, jsonName, txtName
end

local function startScanner()
    if running then return end

    events = {}
    connections = {}
    watchedText = {}
    watchedGui = {}
    injectedObjects = {}
    createdRoots = {}

    -- Nenhuma varredura inicial: só escutamos objetos adicionados daqui em diante.
    startedAt = now()
    running = true

    push("SCAN_START", {})

    -- Só escuta novas criações; não varre os conteúdos atuais.
    watchRoot(CoreGui, "CoreGui")
    if PlayerGui then
        watchRoot(PlayerGui, "PlayerGui")
    end
end

local function stopScanner()
    if not running then
        return false, false, nil, nil
    end

    push("SCAN_STOP", {})
    running = false
    disconnectAll()
    return saveReport()
end

-- GUI
pcall(function()
    local old = CoreGui:FindFirstChild(GUI_NAME)
    if old then old:Destroy() end
end)

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

local parented = false
pcall(function()
    if gethui then
        gui.Parent = gethui()
        parented = true
    end
end)
if not parented then
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
title.Text = "MAM2 Scanner V4.2 Ultra Lite"
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
        status.Text = "Status: aguardando injecao..."
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

        print("MAM2 V4.2 JSON:", jsonName, jsonOK)
        print("MAM2 V4.2 TXT:", txtName, txtOK)
    end
end)

print("MAM2 Runtime Scanner V4.2 Ultra Lite carregado.")
