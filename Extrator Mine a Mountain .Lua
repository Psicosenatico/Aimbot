local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer

local GUI_NAME = "MAM2_RuntimeScanner_V3"
local PREFIX = "MAM2_RUNTIME"
local running = false
local startedAt = 0
local connections = {}
local events = {}
local snapshots = {}
local seenInstances = {}
local lastGuiCount = 0

local function now()
    return os.clock()
end

local function unix()
    return os.time()
end

local function safeStr(v)
    local ok, s = pcall(tostring, v)
    return ok and s or "<tostring error>"
end

local function pushEvent(kind, data)
    if not running then return end
    events[#events + 1] = {
        t = now() - startedAt,
        unix = unix(),
        kind = kind,
        data = data,
    }
end

local function instancePath(inst)
    local ok, full = pcall(function()
        return inst:GetFullName()
    end)
    return ok and full or safeStr(inst)
end

local interestingWords = {
    "xgrs", "key", "premium", "free", "loader", "inject",
    "crystal", "duper", "auth", "license", "luarmor",
}

local function textLooksInteresting(text)
    if type(text) ~= "string" then return false end
    local low = text:lower()
    for _, w in ipairs(interestingWords) do
        if low:find(w, 1, true) then
            return true
        end
    end
    return false
end

local function inspectTextObject(obj)
    local ok, text = pcall(function()
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            return obj.Text
        end
    end)
    if ok and text and textLooksInteresting(text) then
        pushEvent("TEXT_SEEN", {
            path = instancePath(obj),
            class = obj.ClassName,
            text = text,
        })
    end
end

local function inspectInstance(obj, reason)
    if not running or not obj then return end
    local id = tostring(obj)
    if seenInstances[id] then return end
    seenInstances[id] = true

    local path = instancePath(obj)
    local name = safeStr(obj.Name)
    local className = safeStr(obj.ClassName)

    if textLooksInteresting(name) or className:find("Remote") or className:find("Bindable") then
        pushEvent("INSTANCE_SEEN", {
            reason = reason,
            path = path,
            name = name,
            class = className,
        })
    end

    inspectTextObject(obj)
end

local function scanContainer(root, label)
    local ok, descendants = pcall(function()
        return root:GetDescendants()
    end)
    if not ok then return end

    for _, obj in ipairs(descendants) do
        inspectInstance(obj, "scan:" .. label)
    end
end

local function snapshot(reason)
    if not running then return end

    local snap = {
        t = now() - startedAt,
        unix = unix(),
        reason = reason,
        playerGui = {},
        coreGui = {},
        replicatedStorage = {},
    }

    local function collect(root, bucket)
        local ok, children = pcall(function()
            return root:GetChildren()
        end)
        if not ok then return end

        for _, obj in ipairs(children) do
            bucket[#bucket + 1] = {
                name = safeStr(obj.Name),
                class = safeStr(obj.ClassName),
                path = instancePath(obj),
            }
        end
    end

    if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") then
        collect(LocalPlayer.PlayerGui, snap.playerGui)
    end
    collect(CoreGui, snap.coreGui)
    collect(ReplicatedStorage, snap.replicatedStorage)

    snapshots[#snapshots + 1] = snap
end

local function disconnectAll()
    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    connections = {}
end

local function jsonEncodeSafe(data)
    local ok, result = pcall(function()
        return HttpService:JSONEncode(data)
    end)
    if ok then return result end
    return '{"error":"JSONEncode failed"}'
end

local function saveReport()
    local report = {
        version = "MAM2 Runtime Scanner V3",
        purpose = "Client-observable runtime collection only",
        startedUnix = events[1] and events[1].unix or unix(),
        endedUnix = unix(),
        duration = now() - startedAt,
        eventCount = #events,
        snapshotCount = #snapshots,
        events = events,
        snapshots = snapshots,
        notes = {
            "No premium/key bypass is implemented.",
            "No remote response is forged.",
            "No downloaded payload is modified or executed by this collector.",
        }
    }

    local stamp = os.date("!%Y%m%d_%H%M%S")
    local jsonName = PREFIX .. "_" .. stamp .. ".json"
    local txtName = PREFIX .. "_" .. stamp .. "_report.txt"

    local okJson, errJson = false, "writefile unavailable"
    local okTxt, errTxt = false, "writefile unavailable"

    if writefile then
        okJson, errJson = pcall(writefile, jsonName, jsonEncodeSafe(report))

        local lines = {
            "Mine a Mountain 2 — Runtime Scanner V3",
            "Eventos: " .. tostring(#events),
            "Snapshots: " .. tostring(#snapshots),
            "Duração: " .. string.format("%.2fs", now() - startedAt),
            "",
            "Ocorrências relevantes:"
        }

        for _, ev in ipairs(events) do
            if ev.kind == "TEXT_SEEN" then
                lines[#lines + 1] = string.format(
                    "[%.2fs] %s | %s",
                    ev.t or 0,
                    ev.data and ev.data.path or "?",
                    ev.data and ev.data.text or "?"
                )
            elseif ev.kind == "INSTANCE_SEEN" then
                lines[#lines + 1] = string.format(
                    "[%.2fs] %s | %s | %s",
                    ev.t or 0,
                    ev.data and ev.data.class or "?",
                    ev.data and ev.data.path or "?",
                    ev.data and ev.data.reason or "?"
                )
            else
                lines[#lines + 1] = string.format(
                    "[%.2fs] %s",
                    ev.t or 0,
                    ev.kind or "?"
                )
            end
        end

        okTxt, errTxt = pcall(writefile, txtName, table.concat(lines, "\n"))
    end

    if setclipboard then
        pcall(setclipboard, jsonEncodeSafe(report))
    end

    return okJson or okTxt, jsonName, txtName, tostring(errJson), tostring(errTxt)
end

local function startScanner()
    if running then return end

    events = {}
    snapshots = {}
    seenInstances = {}
    connections = {}
    startedAt = now()
    running = true

    pushEvent("SCAN_START", {
        placeId = game.PlaceId,
        jobId = game.JobId,
    })

    snapshot("start")

    local function watchRoot(root, label)
        if not root then return end

        scanContainer(root, label)

        connections[#connections + 1] = root.DescendantAdded:Connect(function(obj)
            inspectInstance(obj, "added:" .. label)

            if textLooksInteresting(obj.Name) or obj:IsA("ScreenGui") then
                task.defer(function()
                    if running then
                        snapshot("descendant_added:" .. label)
                    end
                end)
            end

            if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                local ok, conn = pcall(function()
                    return obj:GetPropertyChangedSignal("Text"):Connect(function()
                        if running and textLooksInteresting(obj.Text) then
                            pushEvent("TEXT_CHANGED", {
                                path = instancePath(obj),
                                class = obj.ClassName,
                                text = obj.Text,
                            })
                        end
                    end)
                end)
                if ok and conn then
                    connections[#connections + 1] = conn
                end
            end
        end)
    end

    watchRoot(CoreGui, "CoreGui")
    watchRoot(ReplicatedStorage, "ReplicatedStorage")

    if LocalPlayer then
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            watchRoot(pg, "PlayerGui")
        end
    end

    task.spawn(function()
        while running do
            task.wait(2)
            if not running then break end

            local count = 0
            pcall(function()
                count += #CoreGui:GetChildren()
            end)
            pcall(function()
                if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") then
                    count += #LocalPlayer.PlayerGui:GetChildren()
                end
            end)

            if count ~= lastGuiCount then
                pushEvent("GUI_COUNT_CHANGED", {
                    previous = lastGuiCount,
                    current = count,
                })
                lastGuiCount = count
                snapshot("gui_count_changed")
            end
        end
    end)
end

local function stopScanner()
    if not running then
        return false, nil, nil
    end

    pushEvent("SCAN_STOP", {})
    snapshot("stop")
    running = false
    disconnectAll()

    local ok, jsonName, txtName = saveReport()
    return ok, jsonName, txtName
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

local parentOk = false
pcall(function()
    if gethui then
        gui.Parent = gethui()
        parentOk = true
    end
end)
if not parentOk then
    gui.Parent = CoreGui
end

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.fromOffset(300, 150)
frame.Position = UDim2.new(0.5, -150, 0.5, -75)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
frame.BorderSizePixel = 0
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 14)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 40)
title.Position = UDim2.fromOffset(10, 8)
title.BackgroundTransparency = 1
title.Text = "Mine a Mountain Scanner"
title.TextColor3 = Color3.fromRGB(245, 245, 245)
title.Font = Enum.Font.GothamBold
title.TextSize = 20
title.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 26)
status.Position = UDim2.fromOffset(10, 46)
status.BackgroundTransparency = 1
status.Text = "Status: parado"
status.TextColor3 = Color3.fromRGB(190, 190, 200)
status.Font = Enum.Font.Gotham
status.TextSize = 14
status.Parent = frame

local button = Instance.new("TextButton")
button.Size = UDim2.new(1, -30, 0, 54)
button.Position = UDim2.fromOffset(15, 82)
button.BackgroundColor3 = Color3.fromRGB(32, 92, 220)
button.BorderSizePixel = 0
button.Text = "Iniciar Scam"
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.Font = Enum.Font.GothamBold
button.TextSize = 18
button.Parent = frame

local bcorner = Instance.new("UICorner")
bcorner.CornerRadius = UDim.new(0, 12)
bcorner.Parent = button

button.MouseButton1Click:Connect(function()
    if not running then
        startScanner()
        button.Text = "Finalizar Scam"
        status.Text = "Status: coletando..."
    else
        status.Text = "Status: salvando..."
        local ok, jsonName, txtName = stopScanner()

        button.Text = "Iniciar Scam"

        if ok then
            status.Text = "Salvo: " .. tostring(txtName)
        else
            status.Text = "Falha ao salvar arquivo"
        end
    end
end)

print("MAM2 Runtime Scanner V3 carregado.")
