--[[
    PSICOSENATICO • TYCOON PURCHASE DIAGNOSTIC • V1.0
    SOMENTE DIAGNÓSTICO / OBSERVAÇÃO CLIENT-SIDE

    Objetivo:
    - Observar possíveis botões/objetos de compra em Tycoons.
    - Registrar mudanças de dinheiro/valores visíveis ao cliente.
    - Registrar objetos adicionados/removidos próximos a interações.
    - Capturar Attributes e ValueObjects úteis (Price, Cost, Owner, etc.).
    - NÃO efetua compras.
    - NÃO dispara RemoteEvents/RemoteFunctions.
    - NÃO altera valores do jogo.
    - Exporta relatório quando writefile/setclipboard estiver disponível.

    Compatibilidade:
    - Roblox/Luau
    - Interface arrastável com mouse e touch
    - ScrollingFrame com Canvas automático
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    warn("[Tycoon Diagnostic] LocalPlayer indisponível.")
    return
end

local CONFIG = {
    VERSION = "1.0",
    GUI_NAME = "PsicoTycoonPurchaseDiagnosticV1",
    TITLE = "TYCOON PURCHASE DIAGNOSTIC",
    MAX_EVENTS = 800,
    SAMPLE_INTERVAL = 0.75,
    RESCAN_INTERVAL = 5,
    MAX_SCAN_DESCENDANTS = 12000,
    MAX_VALUE_WATCHERS = 300,
    MAX_INTERACTION_WATCHERS = 300,
    NEARBY_WINDOW_SECONDS = 3.0,

    POSSIBLE_PRICE_KEYS = {
        "price", "cost", "cash", "money", "amount", "value", "purchaseprice",
        "buyprice", "upgradeprice", "requiredcash", "requiredmoney"
    },

    POSSIBLE_OWNER_KEYS = {
        "owner", "ownername", "ownerid", "userid", "player", "claimedby"
    },

    POSSIBLE_TYCOON_WORDS = {
        "tycoon", "purchase", "buy", "button", "upgrade", "dropper", "collector",
        "conveyor", "machine", "unlock", "rebirth", "cash", "money"
    }
}

local State = {
    StartedAtUnix = os.time(),
    StartedAtClock = os.clock(),
    Events = {},
    Counters = {
        Scans = 0,
        InteractionCandidates = 0,
        ValueCandidates = 0,
        Added = 0,
        Removed = 0,
        ValueChanges = 0,
        PromptTriggers = 0,
        Clicks = 0,
    },
    Connections = {},
    WatchedInstances = setmetatable({}, {__mode = "k"}),
    WatchedValues = setmetatable({}, {__mode = "k"}),
    LastInteraction = nil,
    LastMoneySnapshot = {},
    Running = true,
}

local GUI = {}
local dragConnection = nil

local function safeToString(v)
    local ok, result = pcall(function()
        if typeof(v) == "Instance" then
            return v:GetFullName()
        end
        return tostring(v)
    end)
    return ok and result or "<unprintable>"
end

local function nowStamp()
    return os.date("%H:%M:%S")
end

local function elapsed()
    return math.floor((os.clock() - State.StartedAtClock) * 1000) / 1000
end

local function normalize(s)
    return string.lower(tostring(s or "")):gsub("[%s_%-%./]", "")
end

local function containsAnyWord(text, words)
    local n = normalize(text)
    for _, word in ipairs(words) do
        if string.find(n, normalize(word), 1, true) then
            return true
        end
    end
    return false
end

local function tableCloneShallow(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end

local function getAttributesSafe(inst)
    local ok, attrs = pcall(function()
        return inst:GetAttributes()
    end)
    if not ok or type(attrs) ~= "table" then
        return {}
    end

    local out = {}
    for k, v in pairs(attrs) do
        out[tostring(k)] = safeToString(v)
    end
    return out
end

local function getInterestingAttributes(inst)
    local attrs = getAttributesSafe(inst)
    local out = {}

    for k, v in pairs(attrs) do
        local nk = normalize(k)
        if containsAnyWord(nk, CONFIG.POSSIBLE_PRICE_KEYS)
        or containsAnyWord(nk, CONFIG.POSSIBLE_OWNER_KEYS)
        or containsAnyWord(nk, CONFIG.POSSIBLE_TYCOON_WORDS) then
            out[k] = v
        end
    end

    return out
end

local function getValueObjectSnapshot(inst)
    if not inst:IsA("ValueBase") then
        return nil
    end

    local ok, val = pcall(function()
        return inst.Value
    end)

    if not ok then
        return nil
    end

    return {
        Name = inst.Name,
        ClassName = inst.ClassName,
        Path = inst:GetFullName(),
        Value = safeToString(val),
    }
end

local function describeInstance(inst)
    if not inst or not inst.Parent then
        return {
            Name = inst and inst.Name or "<nil>",
            ClassName = inst and inst.ClassName or "<nil>",
            Path = "<detached>",
        }
    end

    local data = {
        Name = inst.Name,
        ClassName = inst.ClassName,
        Path = inst:GetFullName(),
        Attributes = getInterestingAttributes(inst),
    }

    if inst:IsA("BasePart") then
        data.Position = {
            X = math.floor(inst.Position.X * 100) / 100,
            Y = math.floor(inst.Position.Y * 100) / 100,
            Z = math.floor(inst.Position.Z * 100) / 100,
        }
        data.Size = {
            X = math.floor(inst.Size.X * 100) / 100,
            Y = math.floor(inst.Size.Y * 100) / 100,
            Z = math.floor(inst.Size.Z * 100) / 100,
        }
    elseif inst:IsA("ProximityPrompt") then
        data.ActionText = inst.ActionText
        data.ObjectText = inst.ObjectText
        data.HoldDuration = inst.HoldDuration
        data.MaxActivationDistance = inst.MaxActivationDistance
        data.Enabled = inst.Enabled
    elseif inst:IsA("ClickDetector") then
        data.MaxActivationDistance = inst.MaxActivationDistance
    elseif inst:IsA("ValueBase") then
        local snap = getValueObjectSnapshot(inst)
        if snap then
            data.Value = snap.Value
        end
    end

    return data
end

local function pushEvent(kind, label, details)
    local event = {
        Time = nowStamp(),
        Unix = os.time(),
        Elapsed = elapsed(),
        Kind = kind,
        Label = label,
        Details = details or {},
    }

    table.insert(State.Events, event)

    while #State.Events > CONFIG.MAX_EVENTS do
        table.remove(State.Events, 1)
    end

    if GUI.LogLabel and GUI.LogLabel.Parent then
        GUI.LogLabel.Text =
            ("Eventos: %d  |  Interações: %d  |  Valores: %d")
            :format(
                #State.Events,
                State.Counters.InteractionCandidates,
                State.Counters.ValueChanges
            )
    end
end

local function safeConnect(signal, callback)
    local ok, connection = pcall(function()
        return signal:Connect(callback)
    end)
    if ok and connection then
        table.insert(State.Connections, connection)
        return connection
    end
    return nil
end

local function disconnectAll()
    for _, c in ipairs(State.Connections) do
        pcall(function()
            c:Disconnect()
        end)
    end
    table.clear(State.Connections)

    if dragConnection then
        pcall(function()
            dragConnection:Disconnect()
        end)
        dragConnection = nil
    end
end

local function looksTycoonRelated(inst)
    if containsAnyWord(inst.Name, CONFIG.POSSIBLE_TYCOON_WORDS) then
        return true
    end

    local parent = inst.Parent
    local depth = 0
    while parent and depth < 4 do
        if containsAnyWord(parent.Name, CONFIG.POSSIBLE_TYCOON_WORDS) then
            return true
        end
        parent = parent.Parent
        depth += 1
    end

    local attrs = getInterestingAttributes(inst)
    return next(attrs) ~= nil
end

local function findNearbyPriceData(inst)
    local result = {}
    local seen = {}
    local root = inst.Parent

    for depth = 1, 3 do
        if not root then break end

        for _, child in ipairs(root:GetChildren()) do
            if child:IsA("ValueBase") then
                local n = normalize(child.Name)
                if containsAnyWord(n, CONFIG.POSSIBLE_PRICE_KEYS) and not seen[child] then
                    seen[child] = true
                    table.insert(result, getValueObjectSnapshot(child))
                end
            end

            local attrs = getInterestingAttributes(child)
            if next(attrs) ~= nil then
                table.insert(result, {
                    Name = child.Name,
                    ClassName = child.ClassName,
                    Path = child:GetFullName(),
                    Attributes = attrs,
                })
            end
        end

        root = root.Parent
    end

    return result
end

local function markInteraction(kind, inst)
    State.LastInteraction = {
        TimeClock = os.clock(),
        Kind = kind,
        Instance = inst,
        Description = describeInstance(inst),
        NearbyPriceData = findNearbyPriceData(inst),
    }

    if kind == "ProximityPrompt" then
        State.Counters.PromptTriggers += 1
    elseif kind == "ClickDetector" then
        State.Counters.Clicks += 1
    end

    pushEvent("INTERACTION", kind, {
        Target = describeInstance(inst),
        NearbyPriceData = State.LastInteraction.NearbyPriceData,
    })
end

local function watchInteraction(inst)
    if State.WatchedInstances[inst] then
        return
    end

    if State.Counters.InteractionCandidates >= CONFIG.MAX_INTERACTION_WATCHERS then
        return
    end

    if not looksTycoonRelated(inst) then
        return
    end

    if inst:IsA("ProximityPrompt") then
        State.WatchedInstances[inst] = true
        State.Counters.InteractionCandidates += 1

        safeConnect(inst.Triggered, function(player)
            if player == LocalPlayer then
                markInteraction("ProximityPrompt", inst)
            end
        end)

        pushEvent("DISCOVERY", "ProximityPrompt encontrado", describeInstance(inst))

    elseif inst:IsA("ClickDetector") then
        State.WatchedInstances[inst] = true
        State.Counters.InteractionCandidates += 1

        -- MouseClick é observado; não é acionado pelo script.
        safeConnect(inst.MouseClick, function(player)
            if player == LocalPlayer then
                markInteraction("ClickDetector", inst)
            end
        end)

        pushEvent("DISCOVERY", "ClickDetector encontrado", describeInstance(inst))
    end
end

local function isInterestingValue(inst)
    if not inst:IsA("ValueBase") then
        return false
    end

    local n = normalize(inst.Name)

    if containsAnyWord(n, CONFIG.POSSIBLE_PRICE_KEYS)
    or containsAnyWord(n, CONFIG.POSSIBLE_OWNER_KEYS)
    or containsAnyWord(n, CONFIG.POSSIBLE_TYCOON_WORDS) then
        return true
    end

    return looksTycoonRelated(inst)
end

local function watchValue(inst)
    if State.WatchedValues[inst] then
        return
    end

    if State.Counters.ValueCandidates >= CONFIG.MAX_VALUE_WATCHERS then
        return
    end

    if not isInterestingValue(inst) then
        return
    end

    State.WatchedValues[inst] = true
    State.Counters.ValueCandidates += 1

    local oldValue
    pcall(function()
        oldValue = inst.Value
    end)

    safeConnect(inst.Changed, function(newValue)
        State.Counters.ValueChanges += 1

        local previous = oldValue
        oldValue = newValue

        local details = {
            Target = describeInstance(inst),
            OldValue = safeToString(previous),
            NewValue = safeToString(newValue),
        }

        if State.LastInteraction
        and (os.clock() - State.LastInteraction.TimeClock) <= CONFIG.NEARBY_WINDOW_SECONDS then
            details.RecentInteraction = tableCloneShallow(State.LastInteraction)
        end

        pushEvent("VALUE_CHANGE", inst.Name, details)
    end)
end

local function scanRoot(root)
    if not root then
        return
    end

    State.Counters.Scans += 1
    local descendants = root:GetDescendants()
    local limit = math.min(#descendants, CONFIG.MAX_SCAN_DESCENDANTS)

    for i = 1, limit do
        local inst = descendants[i]

        if inst:IsA("ProximityPrompt") or inst:IsA("ClickDetector") then
            watchInteraction(inst)
        elseif inst:IsA("ValueBase") then
            watchValue(inst)
        end
    end
end

local function collectMoneyLikeValues()
    local found = {}

    local containers = {
        LocalPlayer:FindFirstChild("leaderstats"),
        LocalPlayer:FindFirstChild("PlayerGui"),
        LocalPlayer:FindFirstChild("Backpack"),
    }

    for _, container in ipairs(containers) do
        if container then
            for _, inst in ipairs(container:GetDescendants()) do
                if inst:IsA("ValueBase") then
                    local n = normalize(inst.Name)
                    if containsAnyWord(n, {"money", "cash", "coin", "coins", "currency", "saldo"}) then
                        local ok, val = pcall(function()
                            return inst.Value
                        end)
                        if ok then
                            found[inst:GetFullName()] = {
                                Instance = inst,
                                Value = val,
                            }
                        end
                    end
                end
            end
        end
    end

    return found
end

local function sampleMoney()
    local current = collectMoneyLikeValues()

    for path, info in pairs(current) do
        local previous = State.LastMoneySnapshot[path]
        if previous ~= nil and previous ~= info.Value then
            local details = {
                Path = path,
                OldValue = safeToString(previous),
                NewValue = safeToString(info.Value),
            }

            if State.LastInteraction
            and (os.clock() - State.LastInteraction.TimeClock) <= CONFIG.NEARBY_WINDOW_SECONDS then
                details.RecentInteraction = tableCloneShallow(State.LastInteraction)
            end

            pushEvent("MONEY_CHANGE", "Mudança de moeda", details)
        end

        State.LastMoneySnapshot[path] = info.Value
    end
end

local function snapshotCandidate(inst, reason)
    if not inst then return end

    local details = {
        Reason = reason,
        Instance = describeInstance(inst),
    }

    if State.LastInteraction
    and (os.clock() - State.LastInteraction.TimeClock) <= CONFIG.NEARBY_WINDOW_SECONDS then
        details.RecentInteraction = tableCloneShallow(State.LastInteraction)
    end

    pushEvent("OBJECT_" .. string.upper(reason), inst.Name, details)
end

local function buildReport()
    local payload = {
        Report = "Tycoon Purchase Diagnostic",
        Version = CONFIG.VERSION,
        PlaceId = game.PlaceId,
        JobId = game.JobId,
        StartedAtUnix = State.StartedAtUnix,
        FinishedAtUnix = os.time(),
        Counters = State.Counters,
        Events = State.Events,
    }

    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(payload)
    end)

    if ok then
        return encoded
    end

    return "Falha ao serializar relatório: " .. tostring(encoded)
end

local function exportReport()
    local content = buildReport()
    local filename = "Tycoon_Purchase_Diagnostic_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"

    local wroteFile = false
    local copied = false
    local writeErr = nil

    if typeof(writefile) == "function" then
        local ok, err = pcall(function()
            writefile(filename, content)
        end)
        wroteFile = ok
        writeErr = err
    end

    if typeof(setclipboard) == "function" then
        copied = pcall(function()
            setclipboard(content)
        end)
    elseif typeof(toclipboard) == "function" then
        copied = pcall(function()
            toclipboard(content)
        end)
    end

    if wroteFile then
        return true, "Arquivo salvo: " .. filename
    elseif copied then
        return true, "Relatório copiado para a área de transferência."
    else
        return false,
            "O ambiente atual não oferece writefile/setclipboard. " ..
            "Os dados continuam disponíveis no painel e em memória."
            .. (writeErr and (" | Erro: " .. tostring(writeErr)) or "")
    end
end

local function createRounded(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
end

local function createButton(parent, text)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 34)
    btn.BackgroundColor3 = Color3.fromRGB(34, 43, 58)
    btn.BorderSizePixel = 0
    btn.TextColor3 = Color3.fromRGB(240, 244, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.Text = text
    btn.AutoButtonColor = true
    btn.Parent = parent
    createRounded(btn, 8)
    return btn
end

local function makeDraggable(frame, handle)
    local dragging = false
    local dragStart = nil
    local startPos = nil
    local activeInput = nil

    safeConnect(handle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then

            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            activeInput = input

            safeConnect(input.Changed, function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    activeInput = nil
                end
            end)
        end
    end)

    safeConnect(UserInputService.InputChanged, function(input)
        if not dragging or not dragStart or not startPos then
            return
        end

        local validMouse =
            activeInput
            and activeInput.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseMovement

        local validTouch =
            activeInput
            and activeInput.UserInputType == Enum.UserInputType.Touch
            and input == activeInput

        if validMouse or validTouch then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
end

local function createGui()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")

    local old = playerGui:FindFirstChild(CONFIG.GUI_NAME)
    if old then
        old:Destroy()
    end

    local screen = Instance.new("ScreenGui")
    screen.Name = CONFIG.GUI_NAME
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = false
    screen.Parent = playerGui

    local main = Instance.new("Frame")
    main.Name = "Main"
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    main.Position = UDim2.fromScale(0.5, 0.5)
    main.Size = UDim2.new(0, 340, 0, 370)
    main.BackgroundColor3 = Color3.fromRGB(19, 23, 31)
    main.BorderSizePixel = 0
    main.Parent = screen
    createRounded(main, 12)

    local sizeConstraint = Instance.new("UISizeConstraint")
    sizeConstraint.MinSize = Vector2.new(280, 260)
    sizeConstraint.MaxSize = Vector2.new(420, 520)
    sizeConstraint.Parent = main

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 48)
    header.BackgroundColor3 = Color3.fromRGB(25, 31, 43)
    header.BorderSizePixel = 0
    header.Parent = main
    createRounded(header, 12)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -86, 0, 24)
    title.Position = UDim2.new(0, 12, 0, 5)
    title.BackgroundTransparency = 1
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = CONFIG.TITLE
    title.TextColor3 = Color3.fromRGB(127, 255, 202)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.Parent = header

    local version = Instance.new("TextLabel")
    version.Size = UDim2.new(1, -86, 0, 16)
    version.Position = UDim2.new(0, 12, 0, 27)
    version.BackgroundTransparency = 1
    version.TextXAlignment = Enum.TextXAlignment.Left
    version.Text = "V" .. CONFIG.VERSION .. " • somente diagnóstico"
    version.TextColor3 = Color3.fromRGB(155, 164, 180)
    version.Font = Enum.Font.Gotham
    version.TextSize = 10
    version.Parent = header

    local close = Instance.new("TextButton")
    close.Size = UDim2.new(0, 34, 0, 34)
    close.Position = UDim2.new(1, -40, 0, 7)
    close.BackgroundColor3 = Color3.fromRGB(72, 38, 43)
    close.Text = "X"
    close.TextColor3 = Color3.new(1, 1, 1)
    close.Font = Enum.Font.GothamBold
    close.TextSize = 13
    close.BorderSizePixel = 0
    close.Parent = header
    createRounded(close, 8)

    local body = Instance.new("Frame")
    body.Size = UDim2.new(1, -16, 1, -64)
    body.Position = UDim2.new(0, 8, 0, 56)
    body.BackgroundTransparency = 1
    body.Parent = main

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 7)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = body

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, 0, 0, 34)
    status.BackgroundColor3 = Color3.fromRGB(28, 35, 48)
    status.BorderSizePixel = 0
    status.TextColor3 = Color3.fromRGB(232, 236, 244)
    status.Font = Enum.Font.Gotham
    status.TextSize = 11
    status.TextWrapped = true
    status.Text = "Monitorando objetos e valores visíveis ao cliente..."
    status.Parent = body
    createRounded(status, 8)

    local counters = Instance.new("TextLabel")
    counters.Size = UDim2.new(1, 0, 0, 28)
    counters.BackgroundTransparency = 1
    counters.TextColor3 = Color3.fromRGB(169, 180, 198)
    counters.Font = Enum.Font.Gotham
    counters.TextSize = 10
    counters.TextXAlignment = Enum.TextXAlignment.Left
    counters.Text = "Eventos: 0  |  Interações: 0  |  Valores: 0"
    counters.Parent = body

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, -150)
    scroll.BackgroundColor3 = Color3.fromRGB(15, 19, 26)
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.new()
    scroll.Parent = body
    createRounded(scroll, 8)

    local scrollPad = Instance.new("UIPadding")
    scrollPad.PaddingTop = UDim.new(0, 6)
    scrollPad.PaddingBottom = UDim.new(0, 6)
    scrollPad.PaddingLeft = UDim.new(0, 7)
    scrollPad.PaddingRight = UDim.new(0, 7)
    scrollPad.Parent = scroll

    local scrollLayout = Instance.new("UIListLayout")
    scrollLayout.Padding = UDim.new(0, 4)
    scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
    scrollLayout.Parent = scroll

    local live = Instance.new("TextLabel")
    live.Size = UDim2.new(1, 0, 0, 120)
    live.AutomaticSize = Enum.AutomaticSize.Y
    live.BackgroundTransparency = 1
    live.TextColor3 = Color3.fromRGB(216, 222, 232)
    live.TextXAlignment = Enum.TextXAlignment.Left
    live.TextYAlignment = Enum.TextYAlignment.Top
    live.TextWrapped = true
    live.Font = Enum.Font.Code
    live.TextSize = 10
    live.Text = "Aguardando eventos..."
    live.Parent = scroll

    local export = createButton(body, "Exportar relatório .txt")
    export.LayoutOrder = 20

    GUI.Screen = screen
    GUI.Main = main
    GUI.Header = header
    GUI.Status = status
    GUI.LogLabel = counters
    GUI.Live = live
    GUI.Export = export

    makeDraggable(main, header)

    safeConnect(export.MouseButton1Click, function()
        local ok, message = exportReport()
        status.Text = message
        pushEvent("SYSTEM", ok and "Exportação concluída" or "Exportação indisponível", {
            Message = message
        })
    end)

    safeConnect(close.MouseButton1Click, function()
        State.Running = false
        disconnectAll()
        if screen then
            screen:Destroy()
        end
    end)
end

local function refreshLiveUi()
    if not GUI.Live or not GUI.Live.Parent then
        return
    end

    local lines = {}
    local startIndex = math.max(1, #State.Events - 14)

    for i = #State.Events, startIndex, -1 do
        local e = State.Events[i]
        table.insert(lines,
            ("[%s] %s • %s"):format(
                e.Time or "--:--:--",
                e.Kind or "?",
                e.Label or "?"
            )
        )
    end

    if #lines == 0 then
        GUI.Live.Text = "Aguardando eventos..."
    else
        GUI.Live.Text = table.concat(lines, "\n")
    end
end

local function installWorldListeners()
    safeConnect(workspace.DescendantAdded, function(inst)
        State.Counters.Added += 1

        task.defer(function()
            if not State.Running or not inst or not inst.Parent then
                return
            end

            if inst:IsA("ProximityPrompt") or inst:IsA("ClickDetector") then
                watchInteraction(inst)
            elseif inst:IsA("ValueBase") then
                watchValue(inst)
            end

            if looksTycoonRelated(inst) then
                snapshotCandidate(inst, "added")
            elseif State.LastInteraction
            and (os.clock() - State.LastInteraction.TimeClock) <= CONFIG.NEARBY_WINDOW_SECONDS then
                snapshotCandidate(inst, "added_after_interaction")
            end
        end)
    end)

    safeConnect(workspace.DescendantRemoving, function(inst)
        State.Counters.Removed += 1

        if looksTycoonRelated(inst) then
            snapshotCandidate(inst, "removed")
        elseif State.LastInteraction
        and (os.clock() - State.LastInteraction.TimeClock) <= CONFIG.NEARBY_WINDOW_SECONDS then
            snapshotCandidate(inst, "removed_after_interaction")
        end
    end)
end

local function startLoops()
    task.spawn(function()
        while State.Running do
            sampleMoney()
            refreshLiveUi()
            task.wait(CONFIG.SAMPLE_INTERVAL)
        end
    end)

    task.spawn(function()
        while State.Running do
            scanRoot(workspace)
            task.wait(CONFIG.RESCAN_INTERVAL)
        end
    end)
end

-- Inicialização
createGui()
pushEvent("SYSTEM", "Diagnostic iniciado", {
    Version = CONFIG.VERSION,
    PlaceId = game.PlaceId,
    JobId = game.JobId,
})

scanRoot(workspace)
sampleMoney()
installWorldListeners()
startLoops()

if GUI.Status then
    GUI.Status.Text =
        "Ativo: observando interações, valores, dinheiro e mudanças no Tycoon."
end
