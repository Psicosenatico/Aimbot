local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local GUI_NAME = "MAM2_RuntimeScanner_V4"
local PREFIX = "MAM2_RUNTIME_V4"

local running = false
local startedAt = 0
local connections = {}
local events = {}
local snapshots = {}
local watchedTextObjects = {}
local watchedGuiObjects = {}
local seenInstances = {}
local snapshotId = 0

local TARGET_WORDS = {
    "xgrs","free","premium","key","loader","inject","crystal","duper",
    "luarmor","playerhud","universal","toggle","time left","infinity"
}

local TARGET_NAME_WORDS = {
    "xgrs","playerhud","inject","crystal","universal","loader","toggle"
}

local function now()
    return os.clock()
end

local function unix()
    return os.time()
end

local function safeString(v)
    local ok, s = pcall(tostring, v)
    if ok then return s end
    return "<tostring-error>"
end

local function sanitize(v, depth)
    depth = depth or 0
    if depth > 7 then
        return "<max-depth>"
    end

    local tv = typeof(v)

    if v == nil then
        return nil
    elseif tv == "string" or tv == "number" or tv == "boolean" then
        return v
    elseif tv == "Instance" then
        local ok, full = pcall(function() return v:GetFullName() end)
        return ok and full or safeString(v)
    elseif tv == "Color3" then
        return {r=v.R, g=v.G, b=v.B}
    elseif tv == "UDim2" then
        return {
            xScale=v.X.Scale, xOffset=v.X.Offset,
            yScale=v.Y.Scale, yOffset=v.Y.Offset
        }
    elseif tv == "UDim" then
        return {scale=v.Scale, offset=v.Offset}
    elseif tv == "Vector2" then
        return {x=v.X, y=v.Y}
    elseif tv == "Vector3" then
        return {x=v.X, y=v.Y, z=v.Z}
    elseif tv == "EnumItem" then
        return safeString(v)
    elseif tv == "table" then
        local out = {}
        local isArray = true
        local maxIndex = 0

        for k in pairs(v) do
            if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
                isArray = false
                break
            end
            if k > maxIndex then maxIndex = k end
        end

        if isArray then
            for i = 1, maxIndex do
                out[i] = sanitize(v[i], depth + 1)
            end
        else
            for k, val in pairs(v) do
                out[safeString(k)] = sanitize(val, depth + 1)
            end
        end
        return out
    end

    return safeString(v)
end

local function pathOf(inst)
    local ok, p = pcall(function()
        return inst:GetFullName()
    end)
    return ok and p or safeString(inst)
end

local function lowerContainsAny(s, words)
    if type(s) ~= "string" then return false end
    local low = string.lower(s)
    for _, w in ipairs(words) do
        if string.find(low, w, 1, true) then
            return true
        end
    end
    return false
end

local function pushEvent(kind, data)
    if not running then return end
    events[#events + 1] = {
        t = now() - startedAt,
        unix = unix(),
        kind = kind,
        data = sanitize(data or {})
    }
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

local function getAttributesSafe(obj)
    local ok, attrs = pcall(function()
        return obj:GetAttributes()
    end)
    return ok and sanitize(attrs) or {}
end

local function getGuiProps(obj)
    local out = {
        name = obj.Name,
        class = obj.ClassName,
        path = pathOf(obj),
        attributes = getAttributesSafe(obj),
    }

    pcall(function()
        if obj:IsA("GuiObject") then
            out.visible = obj.Visible
            out.active = obj.Active
            out.position = sanitize(obj.Position)
            out.size = sanitize(obj.Size)
            out.anchorPoint = sanitize(obj.AnchorPoint)
            out.zIndex = obj.ZIndex
            out.backgroundTransparency = obj.BackgroundTransparency
            out.backgroundColor3 = sanitize(obj.BackgroundColor3)
        end
    end)

    pcall(function()
        if obj:IsA("ScreenGui") then
            out.enabled = obj.Enabled
            out.displayOrder = obj.DisplayOrder
            out.ignoreGuiInset = obj.IgnoreGuiInset
        end
    end)

    local text = getText(obj)
    if text ~= nil then
        out.text = text
        pcall(function()
            out.textSize = obj.TextSize
            out.textTransparency = obj.TextTransparency
            out.textColor3 = sanitize(obj.TextColor3)
            out.richText = obj.RichText
        end)
    end

    return out
end

local function isTargetObject(obj)
    local name = safeString(obj.Name)
    local path = pathOf(obj)
    local text = getText(obj)

    return lowerContainsAny(name, TARGET_NAME_WORDS)
        or lowerContainsAny(path, TARGET_NAME_WORDS)
        or lowerContainsAny(text, TARGET_WORDS)
end

local function attachTextWatcher(obj)
    if watchedTextObjects[obj] then return end
    if not (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then
        return
    end

    watchedTextObjects[obj] = true
    local lastText = getText(obj)

    local ok, conn = pcall(function()
        return obj:GetPropertyChangedSignal("Text"):Connect(function()
            if not running then return end
            local newText = getText(obj)
            if newText ~= lastText then
                pushEvent("TEXT_CHANGED", {
                    path = pathOf(obj),
                    class = obj.ClassName,
                    oldText = lastText,
                    newText = newText,
                    targetMatch = isTargetObject(obj),
                })
                lastText = newText
            end
        end)
    end)

    if ok and conn then
        connections[#connections + 1] = conn
    end
end

local function attachGuiPropertyWatchers(obj)
    if watchedGuiObjects[obj] then return end
    if not (obj:IsA("GuiObject") or obj:IsA("ScreenGui")) then return end
    watchedGuiObjects[obj] = true

    local props = {}
    if obj:IsA("GuiObject") then
        props = {"Visible", "Position", "Size", "BackgroundTransparency"}
    elseif obj:IsA("ScreenGui") then
        props = {"Enabled", "DisplayOrder"}
    end

    for _, prop in ipairs(props) do
        local ok, conn = pcall(function()
            return obj:GetPropertyChangedSignal(prop):Connect(function()
                if not running then return end
                if isTargetObject(obj) then
                    local value
                    pcall(function() value = obj[prop] end)
                    pushEvent("GUI_PROPERTY_CHANGED", {
                        path = pathOf(obj),
                        class = obj.ClassName,
                        property = prop,
                        value = sanitize(value),
                    })
                end
            end)
        end)
        if ok and conn then
            connections[#connections + 1] = conn
        end
    end
end

local function inspectInstance(obj, reason)
    if not obj then return end

    attachTextWatcher(obj)
    attachGuiPropertyWatchers(obj)

    if not running then return end

    local key = safeString(obj)
    if seenInstances[key] then return end
    seenInstances[key] = true

    local target = isTargetObject(obj)

    if target
        or obj:IsA("RemoteEvent")
        or obj:IsA("RemoteFunction")
        or obj:IsA("BindableEvent")
        or obj:IsA("BindableFunction")
    then
        pushEvent("INSTANCE_SEEN", {
            reason = reason,
            targetMatch = target,
            object = getGuiProps(obj),
        })
    end
end

local function collectTargetHierarchy()
    local out = {}

    local function scan(root)
        local ok, descendants = pcall(function()
            return root:GetDescendants()
        end)
        if not ok then return end

        for _, obj in ipairs(descendants) do
            if isTargetObject(obj) then
                out[#out + 1] = getGuiProps(obj)
            end
        end
    end

    scan(CoreGui)

    if LocalPlayer then
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            scan(pg)
        end
    end

    return out
end

local function collectTopLevel(root)
    local out = {}
    local ok, children = pcall(function()
        return root:GetChildren()
    end)
    if not ok then return out end

    for _, obj in ipairs(children) do
        out[#out + 1] = {
            name = obj.Name,
            class = obj.ClassName,
            path = pathOf(obj),
            attributes = getAttributesSafe(obj),
        }
    end
    return out
end

local function snapshot(reason)
    if not running then return end

    snapshotId += 1

    local snap = {
        id = snapshotId,
        t = now() - startedAt,
        unix = unix(),
        reason = reason,
        xgrsHierarchy = collectTargetHierarchy(),
        coreGuiTop = collectTopLevel(CoreGui),
        replicatedStorageTop = collectTopLevel(ReplicatedStorage),
        playerGuiTop = {},
    }

    if LocalPlayer then
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            snap.playerGuiTop = collectTopLevel(pg)
        end
    end

    snapshots[#snapshots + 1] = sanitize(snap)

    pushEvent("SNAPSHOT", {
        id = snapshotId,
        reason = reason,
        targetCount = #snap.xgrsHierarchy,
    })
end

local function disconnectAll()
    for _, conn in ipairs(connections) do
        pcall(function() conn:Disconnect() end)
    end
    connections = {}
end

local function watchRoot(root, label)
    if not root then return end

    local ok, descendants = pcall(function()
        return root:GetDescendants()
    end)
    if ok then
        for _, obj in ipairs(descendants) do
            inspectInstance(obj, "initial_scan:" .. label)
        end
    end

    local addConn = root.DescendantAdded:Connect(function(obj)
        inspectInstance(obj, "added:" .. label)

        if isTargetObject(obj) then
            pushEvent("TARGET_ADDED", {
                root = label,
                object = getGuiProps(obj),
            })

            task.defer(function()
                task.wait(0.15)
                if running then
                    snapshot("target_added:" .. obj.Name)
                end
            end)
        end
    end)
    connections[#connections + 1] = addConn

    local remConn = root.DescendantRemoving:Connect(function(obj)
        if not running then return end

        if isTargetObject(obj) then
            pushEvent("TARGET_REMOVING", {
                root = label,
                object = getGuiProps(obj),
            })
        end
    end)
    connections[#connections + 1] = remConn
end

local function jsonEncodeStrict(data)
    local clean = sanitize(data)
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(clean)
    end)
    if ok then
        return encoded, nil
    end
    return nil, safeString(encoded)
end

local function buildTxtReport(report)
    local lines = {}

    lines[#lines + 1] = "Mine a Mountain 2 — Runtime Scanner V4"
    lines[#lines + 1] = "Eventos: " .. tostring(#report.events)
    lines[#lines + 1] = "Snapshots: " .. tostring(#report.snapshots)
    lines[#lines + 1] = "Duracao: " .. string.format("%.2fs", report.duration or 0)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "=== EVENTOS ==="

    for _, ev in ipairs(report.events) do
        local t = tonumber(ev.t) or 0
        local d = ev.data or {}

        if ev.kind == "TEXT_CHANGED" then
            lines[#lines + 1] = string.format(
                "[%.2fs] TEXT_CHANGED | %s | %s -> %s",
                t,
                safeString(d.path),
                safeString(d.oldText),
                safeString(d.newText)
            )

        elseif ev.kind == "TARGET_ADDED" or ev.kind == "TARGET_REMOVING" then
            local o = d.object or {}
            lines[#lines + 1] = string.format(
                "[%.2fs] %s | %s | %s",
                t,
                ev.kind,
                safeString(o.class),
                safeString(o.path)
            )

        elseif ev.kind == "INSTANCE_SEEN" then
            local o = d.object or {}
            lines[#lines + 1] = string.format(
                "[%.2fs] INSTANCE_SEEN | %s | %s | %s",
                t,
                safeString(o.class),
                safeString(o.path),
                safeString(o.text or "")
            )

        elseif ev.kind == "GUI_PROPERTY_CHANGED" then
            lines[#lines + 1] = string.format(
                "[%.2fs] GUI_PROPERTY_CHANGED | %s | %s=%s",
                t,
                safeString(d.path),
                safeString(d.property),
                safeString(d.value)
            )

        elseif ev.kind == "SNAPSHOT" then
            lines[#lines + 1] = string.format(
                "[%.2fs] SNAPSHOT | id=%s | reason=%s | targets=%s",
                t,
                safeString(d.id),
                safeString(d.reason),
                safeString(d.targetCount)
            )

        else
            lines[#lines + 1] = string.format(
                "[%.2fs] %s",
                t,
                safeString(ev.kind)
            )
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "=== SNAPSHOTS / HIERARQUIA XGRS ==="

    for _, snap in ipairs(report.snapshots) do
        lines[#lines + 1] = string.format(
            "SNAPSHOT #%s | %.2fs | %s | alvos=%d",
            safeString(snap.id),
            tonumber(snap.t) or 0,
            safeString(snap.reason),
            #(snap.xgrsHierarchy or {})
        )

        for _, obj in ipairs(snap.xgrsHierarchy or {}) do
            lines[#lines + 1] = string.format(
                "  %s | %s | text=%s | visible=%s | enabled=%s",
                safeString(obj.class),
                safeString(obj.path),
                safeString(obj.text or ""),
                safeString(obj.visible),
                safeString(obj.enabled)
            )
        end
    end

    return table.concat(lines, "\n")
end

local function saveReport()
    local duration = now() - startedAt

    local report = sanitize({
        version = "MAM2 Runtime Scanner V4",
        startedUnix = events[1] and events[1].unix or unix(),
        endedUnix = unix(),
        duration = duration,
        eventCount = #events,
        snapshotCount = #snapshots,
        events = events,
        snapshots = snapshots,
        notes = {
            "Client-observable runtime collection.",
            "TEXT_CHANGED includes oldText/newText/path.",
            "XGRS target hierarchy captured in snapshots.",
        }
    })

    local stamp = os.date("!%Y%m%d_%H%M%S")
    local jsonName = PREFIX .. "_" .. stamp .. ".json"
    local txtName = PREFIX .. "_" .. stamp .. "_report.txt"

    local encoded, jsonErr = jsonEncodeStrict(report)
    local txt = buildTxtReport(report)

    local jsonOK = false
    local txtOK = false

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

    return jsonOK, txtOK, jsonName, txtName, jsonErr
end

local function startScanner()
    if running then return end

    running = true
    startedAt = now()

    connections = {}
    events = {}
    snapshots = {}
    watchedTextObjects = {}
    watchedGuiObjects = {}
    seenInstances = {}
    snapshotId = 0

    pushEvent("SCAN_START", {
        placeId = game.PlaceId,
        jobId = game.JobId,
    })

    watchRoot(CoreGui, "CoreGui")
    watchRoot(ReplicatedStorage, "ReplicatedStorage")

    if LocalPlayer then
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            watchRoot(pg, "PlayerGui")
        end
    end

    snapshot("start")

    task.spawn(function()
        while running do
            task.wait(2)
            if running then
                snapshot("periodic")
            end
        end
    end)
end

local function stopScanner()
    if not running then
        return false, false, nil, nil, "not running"
    end

    pushEvent("SCAN_STOP", {})
    snapshot("stop")
    running = false
    disconnectAll()

    return saveReport()
end

-- Interface
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

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0,14)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,-20,0,40)
title.Position = UDim2.fromOffset(10,8)
title.BackgroundTransparency = 1
title.Text = "MAM2 Runtime Scanner V4"
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
status.TextWrapped = true
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
        status.Text = "Status: coletando XGRS..."
    else
        status.Text = "Status: salvando..."
        local jsonOK, txtOK, jsonName, txtName, jsonErr = stopScanner()

        button.Text = "Iniciar Scam"

        if jsonOK and txtOK then
            status.Text = "Salvo JSON + TXT"
        elseif txtOK then
            status.Text = "TXT salvo; JSON falhou: " .. safeString(jsonErr)
        else
            status.Text = "Falha ao salvar"
        end

        print("MAM2 V4 JSON:", jsonName, jsonOK)
        print("MAM2 V4 TXT:", txtName, txtOK)
    end
end)

print("MAM2 Runtime Scanner V4 carregado.")
