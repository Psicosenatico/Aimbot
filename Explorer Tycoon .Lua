
    PSICOSENATICO • TYCOON PURCHASE DIAGNOSTIC • V2.0
    SOMENTE DIAGNÓSTICO / OBSERVAÇÃO CLIENT-SIDE

    Baseado nos dados reais coletados pela V1:
    - Estrutura observada:
        Workspace.Tycoons.[Tycoon].Buttons.[Compra]
        Workspace.Tycoons.[Tycoon].Purchases.[Compra]
    - Atributos relevantes observados:
        Price
        Owner
        LinkedPurchases
        Rebirths
    - Botões podem possuir:
        Touch -> TouchInterest
    - Compras de armas podem criar:
        Purchases.[Item] -> Prim -> PromptAttachment -> ProximityPrompt (Equip)

    Objetivos da V2:
    - Identificar o Tycoon pertencente ao jogador local.
    - Observar APENAS esse Tycoon quando possível.
    - Mapear botões, preços e dependências.
    - Correlacionar Button removido -> Purchase criado.
    - Correlacionar preço -> mudança real de Money.
    - Registrar novos botões liberados após cada compra.
    - Reduzir drasticamente o ruído da V1.
    - Não efetuar compras.
    - Não dispara RemoteEvents/RemoteFunctions.
    - Não altera valores do jogo.

    Interface:
    - Responsiva
    - Arrastável por mouse e touch
    - Botão minimizar
    - Ao minimizar, aparece botão flutuante azul-escuro
    - Botão flutuante arrastável
    - Toque/clique no botão flutuante restaura o menu
    - Exportação .txt via writefile quando disponível
    - Clipboard como fallback quando disponível
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    warn("[Tycoon Diagnostic V2] LocalPlayer indisponível.")
    return
end

local CONFIG = {
    VERSION = "2.0",
    GUI_NAME = "PsicoTycoonPurchaseDiagnosticV2",

    MAX_EVENTS = 500,
    MONEY_SAMPLE_INTERVAL = 0.20,
    TYCOON_RESCAN_INTERVAL = 2.0,
    PURCHASE_CORRELATION_WINDOW = 4.0,
    BUTTON_UNLOCK_WINDOW = 3.0,

    COLORS = {
        Background = Color3.fromRGB(18, 23, 31),
        Header = Color3.fromRGB(25, 32, 44),
        Card = Color3.fromRGB(29, 37, 51),
        Card2 = Color3.fromRGB(14, 19, 27),
        Accent = Color3.fromRGB(83, 226, 169),
        Text = Color3.fromRGB(238, 242, 250),
        Muted = Color3.fromRGB(160, 171, 190),
        Danger = Color3.fromRGB(86, 43, 48),

        -- Azul escuro solicitado para o botão minimizado.
        Floating = Color3.fromRGB(18, 49, 88),
        FloatingHover = Color3.fromRGB(25, 68, 118),
    }
}

local State = {
    Running = true,

    StartedAtUnix = os.time(),
    StartedAtClock = os.clock(),

    Tycoon = nil,
    TycoonPath = nil,
    ButtonsFolder = nil,
    PurchasesFolder = nil,

    MoneyObject = nil,
    LastMoney = nil,

    Events = {},
    Purchases = {},
    Buttons = {},

    LastButtonRemoved = nil,
    LastPurchaseCreated = nil,

    Connections = {},
    TycoonConnections = {},

    Minimized = false,
}

local GUI = {}

local function safeString(value)
    local ok, result = pcall(function()
        return tostring(value)
    end)
    return ok and result or "<erro>"
end

local function getFullNameSafe(inst)
    if not inst then
        return "<nil>"
    end

    local ok, result = pcall(function()
        return inst:GetFullName()
    end)

    return ok and result or "<detached>"
end

local function now()
    return os.date("%H:%M:%S")
end

local function elapsed()
    return math.floor((os.clock() - State.StartedAtClock) * 1000) / 1000
end

local function normalize(value)
    return string.lower(tostring(value or "")):gsub("[%s_%-%./]", "")
end

local function getAttributesSafe(inst)
    if not inst then
        return {}
    end

    local ok, attrs = pcall(function()
        return inst:GetAttributes()
    end)

    if not ok or type(attrs) ~= "table" then
        return {}
    end

    local out = {}
    for key, value in pairs(attrs) do
        out[tostring(key)] = safeString(value)
    end

    return out
end

local function getAttributeCaseInsensitive(inst, wanted)
    if not inst then
        return nil
    end

    local attrs = getAttributesSafe(inst)
    local target = normalize(wanted)

    for key, value in pairs(attrs) do
        if normalize(key) == target then
            return value
        end
    end

    return nil
end

local function parseNumber(value)
    if value == nil then
        return nil
    end

    if type(value) == "number" then
        return value
    end

    local s = tostring(value)
    s = s:gsub(",", "")
    s = s:gsub("%s", "")

    return tonumber(s)
end

local function cloneTable(t)
    local out = {}
    for k, v in pairs(t or {}) do
        out[k] = v
    end
    return out
end

local function disconnectList(list)
    for _, connection in ipairs(list) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(list)
end

local function connect(signal, callback, bucket)
    local ok, connection = pcall(function()
        return signal:Connect(callback)
    end)

    if ok and connection then
        table.insert(bucket or State.Connections, connection)
        return connection
    end

    return nil
end

local function describeButton(model)
    if not model then
        return nil
    end

    return {
        Name = model.Name,
        Path = getFullNameSafe(model),
        Price = getAttributeCaseInsensitive(model, "Price"),
        Owner = getAttributeCaseInsensitive(model, "Owner"),
        LinkedPurchases = getAttributeCaseInsensitive(model, "LinkedPurchases"),
        Rebirths = getAttributeCaseInsensitive(model, "Rebirths"),
        Attributes = getAttributesSafe(model),
        HasTouch = model:FindFirstChild("Touch", true) ~= nil,
        HasTouchInterest = model:FindFirstChildWhichIsA("TouchTransmitter", true) ~= nil,
    }
end

local function describePurchase(model)
    if not model then
        return nil
    end

    local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)

    local result = {
        Name = model.Name,
        Path = getFullNameSafe(model),
        Owner = getAttributeCaseInsensitive(model, "Owner"),
        LinkedPurchases = getAttributeCaseInsensitive(model, "LinkedPurchases"),
        Rebirths = getAttributeCaseInsensitive(model, "Rebirths"),
        Attributes = getAttributesSafe(model),
    }

    if prompt then
        result.ProximityPrompt = {
            Path = getFullNameSafe(prompt),
            ActionText = prompt.ActionText,
            ObjectText = prompt.ObjectText,
            HoldDuration = prompt.HoldDuration,
            MaxActivationDistance = prompt.MaxActivationDistance,
            Enabled = prompt.Enabled,
        }
    end

    return result
end

local function event(kind, label, details)
    local entry = {
        Time = now(),
        Unix = os.time(),
        Elapsed = elapsed(),
        Kind = kind,
        Label = label,
        Details = details or {},
    }

    table.insert(State.Events, entry)

    while #State.Events > CONFIG.MAX_EVENTS do
        table.remove(State.Events, 1)
    end

    return entry
end

local function ownerMatchesLocal(owner)
    if owner == nil then
        return false
    end

    local s = tostring(owner)
    return s == LocalPlayer.Name
        or s == tostring(LocalPlayer.UserId)
        or normalize(s) == normalize(LocalPlayer.Name)
end

local function scoreTycoon(candidate)
    local score = 0

    if not candidate or not candidate:IsA("Model") and not candidate:IsA("Folder") then
        return -100
    end

    local owner = getAttributeCaseInsensitive(candidate, "Owner")
    if ownerMatchesLocal(owner) then
        score += 100
    end

    local buttons = candidate:FindFirstChild("Buttons")
    local purchases = candidate:FindFirstChild("Purchases")

    if buttons then score += 10 end
    if purchases then score += 10 end

    if buttons then
        for _, child in ipairs(buttons:GetChildren()) do
            local childOwner = getAttributeCaseInsensitive(child, "Owner")
            if ownerMatchesLocal(childOwner) then
                score += 20
                break
            end
        end
    end

    if purchases then
        for _, child in ipairs(purchases:GetChildren()) do
            local childOwner = getAttributeCaseInsensitive(child, "Owner")
            if ownerMatchesLocal(childOwner) then
                score += 20
                break
            end
        end
    end

    return score
end

local function findLocalTycoon()
    local tycoons = workspace:FindFirstChild("Tycoons")
    if not tycoons then
        return nil
    end

    local best = nil
    local bestScore = -1

    for _, candidate in ipairs(tycoons:GetChildren()) do
        local score = scoreTycoon(candidate)
        if score > bestScore then
            bestScore = score
            best = candidate
        end
    end

    if bestScore >= 20 then
        return best
    end

    return nil
end

local function findMoneyObject()
    local preferredNames = {
        "Money",
        "Cash",
        "Coins",
        "Coin",
        "Currency",
        "Saldo",
    }

    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        for _, wanted in ipairs(preferredNames) do
            local found = leaderstats:FindFirstChild(wanted)
            if found and found:IsA("ValueBase") then
                return found
            end
        end

        for _, child in ipairs(leaderstats:GetChildren()) do
            if child:IsA("ValueBase") then
                local n = normalize(child.Name)
                if string.find(n, "money", 1, true)
                or string.find(n, "cash", 1, true)
                or string.find(n, "coin", 1, true) then
                    return child
                end
            end
        end
    end

    for _, child in ipairs(LocalPlayer:GetDescendants()) do
        if child:IsA("ValueBase") then
            local n = normalize(child.Name)
            if n == "money" or n == "cash" or n == "coins" then
                return child
            end
        end
    end

    return nil
end

local function getMoneyValue()
    if not State.MoneyObject or not State.MoneyObject.Parent then
        State.MoneyObject = findMoneyObject()
    end

    if not State.MoneyObject then
        return nil
    end

    local ok, value = pcall(function()
        return State.MoneyObject.Value
    end)

    if not ok then
        return nil
    end

    return parseNumber(value)
end

local function listButtonNames()
    local names = {}

    if not State.ButtonsFolder then
        return names
    end

    for _, child in ipairs(State.ButtonsFolder:GetChildren()) do
        names[child.Name] = true
    end

    return names
end

local function buttonDifference(before, after)
    local result = {}

    for name in pairs(after) do
        if not before[name] then
            table.insert(result, name)
        end
    end

    table.sort(result)
    return result
end

local function createOrUpdatePurchaseRecord(name)
    local record = State.Purchases[name]

    if not record then
        record = {
            Name = name,
            FirstSeen = now(),
            FirstSeenElapsed = elapsed(),
            Price = nil,
            MoneyBefore = nil,
            MoneyAfter = nil,
            ActualCost = nil,
            PriceMatchesMoneyDelta = nil,
            Button = nil,
            Purchase = nil,
            LinkedPurchases = nil,
            UnlockedButtons = {},
            CorrelationConfidence = "unknown",
        }
        State.Purchases[name] = record
    end

    return record
end

local function correlateMoneyChange(oldValue, newValue)
    if oldValue == nil or newValue == nil then
        return
    end

    if oldValue == newValue then
        return
    end

    local delta = newValue - oldValue

    event("MONEY_CHANGE", "Money alterado", {
        OldValue = oldValue,
        NewValue = newValue,
        Delta = delta,
        Path = State.MoneyObject and getFullNameSafe(State.MoneyObject) or nil,
    })

    -- Compra normalmente gera delta negativo.
    if delta >= 0 then
        return
    end

    local candidate = State.LastPurchaseCreated or State.LastButtonRemoved

    if not candidate then
        return
    end

    if os.clock() - candidate.Clock > CONFIG.PURCHASE_CORRELATION_WINDOW then
        return
    end

    local name = candidate.Name
    local record = createOrUpdatePurchaseRecord(name)

    record.MoneyBefore = oldValue
    record.MoneyAfter = newValue
    record.ActualCost = math.abs(delta)

    local price = parseNumber(record.Price)

    if price then
        record.PriceMatchesMoneyDelta = (math.abs(price - record.ActualCost) < 0.001)
    end

    if record.Button and record.Purchase then
        record.CorrelationConfidence = "high"
    elseif record.Button or record.Purchase then
        record.CorrelationConfidence = "medium"
    else
        record.CorrelationConfidence = "low"
    end

    event("PURCHASE_COST_CORRELATED", name, {
        Price = record.Price,
        MoneyBefore = oldValue,
        MoneyAfter = newValue,
        ActualCost = record.ActualCost,
        PriceMatchesMoneyDelta = record.PriceMatchesMoneyDelta,
        Confidence = record.CorrelationConfidence,
    })
end

local function captureUnlockedButtons(record, buttonsBefore)
    task.delay(CONFIG.BUTTON_UNLOCK_WINDOW, function()
        if not State.Running or not State.ButtonsFolder then
            return
        end

        local after = listButtonNames()
        local unlocked = buttonDifference(buttonsBefore, after)

        record.UnlockedButtons = unlocked

        if #unlocked > 0 then
            event("BUTTONS_UNLOCKED", record.Name, {
                UnlockedButtons = unlocked,
            })
        end
    end)
end

local function onButtonAdded(button)
    if not button:IsA("Model") and not button:IsA("Folder") then
        return
    end

    local info = describeButton(button)
    State.Buttons[button.Name] = info

    event("BUTTON_AVAILABLE", button.Name, info)
end

local function onButtonRemoved(button)
    if not button then
        return
    end

    local info = State.Buttons[button.Name] or describeButton(button)

    local record = createOrUpdatePurchaseRecord(button.Name)
    record.Button = info

    if info then
        record.Price = info.Price
        record.LinkedPurchases = info.LinkedPurchases
    end

    State.LastButtonRemoved = {
        Name = button.Name,
        Clock = os.clock(),
        Info = info,
    }

    local buttonsBefore = listButtonNames()

    event("BUTTON_REMOVED", button.Name, info or {})

    State.Buttons[button.Name] = nil

    captureUnlockedButtons(record, buttonsBefore)
end

local function onPurchaseAdded(purchase)
    if not purchase:IsA("Model") and not purchase:IsA("Folder") then
        return
    end

    local info = describePurchase(purchase)
    local record = createOrUpdatePurchaseRecord(purchase.Name)

    record.Purchase = info

    if not record.LinkedPurchases then
        record.LinkedPurchases = info.LinkedPurchases
    end

    local previousButton = State.LastButtonRemoved

    if previousButton
    and previousButton.Name == purchase.Name
    and os.clock() - previousButton.Clock <= CONFIG.PURCHASE_CORRELATION_WINDOW then
        record.CorrelationConfidence = "high"
    elseif record.Button then
        record.CorrelationConfidence = "medium"
    end

    State.LastPurchaseCreated = {
        Name = purchase.Name,
        Clock = os.clock(),
        Info = info,
    }

    event("PURCHASE_CREATED", purchase.Name, {
        Purchase = info,
        KnownPrice = record.Price,
        KnownButton = record.Button,
        CorrelationConfidence = record.CorrelationConfidence,
    })
end

local function scanExistingTycoon()
    if not State.ButtonsFolder or not State.PurchasesFolder then
        return
    end

    State.Buttons = {}

    for _, button in ipairs(State.ButtonsFolder:GetChildren()) do
        if button:IsA("Model") or button:IsA("Folder") then
            State.Buttons[button.Name] = describeButton(button)
        end
    end

    event("TYCOON_SNAPSHOT", "Snapshot inicial", {
        Tycoon = State.TycoonPath,
        ButtonCount = #State.ButtonsFolder:GetChildren(),
        PurchaseCount = #State.PurchasesFolder:GetChildren(),
    })
end

local function bindTycoon(tycoon)
    if State.Tycoon == tycoon then
        return true
    end

    disconnectList(State.TycoonConnections)

    State.Tycoon = tycoon
    State.TycoonPath = tycoon and getFullNameSafe(tycoon) or nil
    State.ButtonsFolder = tycoon and tycoon:FindFirstChild("Buttons") or nil
    State.PurchasesFolder = tycoon and tycoon:FindFirstChild("Purchases") or nil

    if not State.Tycoon or not State.ButtonsFolder or not State.PurchasesFolder then
        return false
    end

    scanExistingTycoon()

    connect(State.ButtonsFolder.ChildAdded, onButtonAdded, State.TycoonConnections)
    connect(State.ButtonsFolder.ChildRemoved, onButtonRemoved, State.TycoonConnections)

    connect(State.PurchasesFolder.ChildAdded, onPurchaseAdded, State.TycoonConnections)

    event("TYCOON_BOUND", "Tycoon local identificado", {
        Path = State.TycoonPath,
        Name = State.Tycoon.Name,
    })

    return true
end

local function attemptBindTycoon()
    local found = findLocalTycoon()

    if found then
        return bindTycoon(found)
    end

    return false
end

local function serializePurchases()
    local array = {}

    for _, record in pairs(State.Purchases) do
        table.insert(array, cloneTable(record))
    end

    table.sort(array, function(a, b)
        return (a.FirstSeenElapsed or 0) < (b.FirstSeenElapsed or 0)
    end)

    return array
end

local function buildReport()
    local payload = {
        Report = "Tycoon Purchase Diagnostic",
        Version = CONFIG.VERSION,

        PlaceId = game.PlaceId,
        JobId = game.JobId,

        StartedAtUnix = State.StartedAtUnix,
        FinishedAtUnix = os.time(),

        Player = {
            Name = LocalPlayer.Name,
            UserId = LocalPlayer.UserId,
        },

        Tycoon = {
            Path = State.TycoonPath,
            Name = State.Tycoon and State.Tycoon.Name or nil,
        },

        MoneyPath = State.MoneyObject and getFullNameSafe(State.MoneyObject) or nil,

        Purchases = serializePurchases(),
        Events = State.Events,
    }

    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(payload)
    end)

    if ok then
        return encoded
    end

    return "Falha ao gerar JSON: " .. tostring(encoded)
end

local function exportReport()
    local content = buildReport()
    local filename =
        "Tycoon_Purchase_Diagnostic_V2_" ..
        os.date("%Y%m%d_%H%M%S") ..
        ".txt"

    local saved = false
    local copied = false
    local lastError = nil

    if typeof(writefile) == "function" then
        local ok, err = pcall(function()
            writefile(filename, content)
        end)

        saved = ok
        if not ok then
            lastError = err
        end
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

    if saved then
        return true, "Relatório salvo: " .. filename
    end

    if copied then
        return true, "Relatório copiado para a área de transferência."
    end

    return false,
        "Exportação indisponível neste ambiente."
        .. (lastError and (" Erro: " .. tostring(lastError)) or "")
end

local function rounded(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
end

local function makeDraggable(frame, handle)
    local dragging = false
    local dragStart = nil
    local startPosition = nil
    local dragInput = nil

    connect(handle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then

            dragging = true
            dragStart = input.Position
            startPosition = frame.Position
            dragInput = input

            connect(input.Changed, function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    dragInput = nil
                end
            end)
        end
    end)

    connect(UserInputService.InputChanged, function(input)
        if not dragging or not dragStart or not startPosition then
            return
        end

        local isMouse =
            dragInput
            and dragInput.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseMovement

        local isTouch =
            dragInput
            and dragInput.UserInputType == Enum.UserInputType.Touch
            and input == dragInput

        if isMouse or isTouch then
            local delta = input.Position - dragStart

            frame.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end)
end

local function refreshUi()
    if not GUI.Screen or not GUI.Screen.Parent then
        return
    end

    if GUI.Status then
        if State.Tycoon then
            GUI.Status.Text =
                "Tycoon: " ..
                State.Tycoon.Name ..
                "  •  Compras detectadas: " ..
                tostring(#serializePurchases())
        else
            GUI.Status.Text = "Procurando o Tycoon pertencente ao jogador..."
        end
    end

    if GUI.Money then
        local value = getMoneyValue()
        GUI.Money.Text =
            "Money: " ..
            (value ~= nil and tostring(value) or "não encontrado")
    end

    if GUI.Live then
        local lines = {}
        local startIndex = math.max(1, #State.Events - 17)

        for i = #State.Events, startIndex, -1 do
            local e = State.Events[i]

            table.insert(
                lines,
                ("[%s] %s • %s"):format(
                    e.Time or "--:--:--",
                    e.Kind or "?",
                    e.Label or "?"
                )
            )
        end

        GUI.Live.Text =
            (#lines > 0 and table.concat(lines, "\n"))
            or "Aguardando eventos de compra..."
    end
end

local function setMinimized(minimized)
    State.Minimized = minimized

    if not GUI.Main or not GUI.FloatButton then
        return
    end

    GUI.Main.Visible = not minimized
    GUI.FloatButton.Visible = minimized
end

local function createButton(parent, text)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, 0, 0, 36)
    button.BackgroundColor3 = CONFIG.COLORS.Card
    button.BorderSizePixel = 0
    button.Text = text
    button.TextColor3 = CONFIG.COLORS.Text
    button.Font = Enum.Font.GothamBold
    button.TextSize = 12
    button.Parent = parent
    rounded(button, 8)
    return button
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
    main.Size = UDim2.new(0, 350, 0, 390)
    main.BackgroundColor3 = CONFIG.COLORS.Background
    main.BorderSizePixel = 0
    main.Parent = screen
    rounded(main, 12)

    local constraint = Instance.new("UISizeConstraint")
    constraint.MinSize = Vector2.new(280, 280)
    constraint.MaxSize = Vector2.new(420, 520)
    constraint.Parent = main

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 50)
    header.BackgroundColor3 = CONFIG.COLORS.Header
    header.BorderSizePixel = 0
    header.Parent = main
    rounded(header, 12)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -100, 0, 24)
    title.Position = UDim2.new(0, 12, 0, 5)
    title.BackgroundTransparency = 1
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "TYCOON PURCHASE DIAGNOSTIC"
    title.TextColor3 = CONFIG.COLORS.Accent
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.Parent = header

    local version = Instance.new("TextLabel")
    version.Size = UDim2.new(1, -100, 0, 16)
    version.Position = UDim2.new(0, 12, 0, 28)
    version.BackgroundTransparency = 1
    version.TextXAlignment = Enum.TextXAlignment.Left
    version.Text = "V2.0 • compra / preço / desbloqueios"
    version.TextColor3 = CONFIG.COLORS.Muted
    version.Font = Enum.Font.Gotham
    version.TextSize = 10
    version.Parent = header

    local minimize = Instance.new("TextButton")
    minimize.Size = UDim2.new(0, 34, 0, 34)
    minimize.Position = UDim2.new(1, -78, 0, 8)
    minimize.BackgroundColor3 = CONFIG.COLORS.Floating
    minimize.BorderSizePixel = 0
    minimize.Text = "—"
    minimize.TextColor3 = Color3.new(1, 1, 1)
    minimize.Font = Enum.Font.GothamBold
    minimize.TextSize = 15
    minimize.Parent = header
    rounded(minimize, 8)

    local close = Instance.new("TextButton")
    close.Size = UDim2.new(0, 34, 0, 34)
    close.Position = UDim2.new(1, -40, 0, 8)
    close.BackgroundColor3 = CONFIG.COLORS.Danger
    close.BorderSizePixel = 0
    close.Text = "X"
    close.TextColor3 = Color3.new(1, 1, 1)
    close.Font = Enum.Font.GothamBold
    close.TextSize = 13
    close.Parent = header
    rounded(close, 8)

    local body = Instance.new("Frame")
    body.Size = UDim2.new(1, -16, 1, -66)
    body.Position = UDim2.new(0, 8, 0, 58)
    body.BackgroundTransparency = 1
    body.Parent = main

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 7)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = body

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, 0, 0, 38)
    status.BackgroundColor3 = CONFIG.COLORS.Card
    status.BorderSizePixel = 0
    status.TextColor3 = CONFIG.COLORS.Text
    status.TextWrapped = true
    status.Font = Enum.Font.Gotham
    status.TextSize = 10
    status.Text = "Inicializando..."
    status.Parent = body
    rounded(status, 8)

    local money = Instance.new("TextLabel")
    money.Size = UDim2.new(1, 0, 0, 26)
    money.BackgroundTransparency = 1
    money.TextColor3 = CONFIG.COLORS.Accent
    money.TextXAlignment = Enum.TextXAlignment.Left
    money.Font = Enum.Font.GothamBold
    money.TextSize = 11
    money.Text = "Money: procurando..."
    money.Parent = body

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, -155)
    scroll.BackgroundColor3 = CONFIG.COLORS.Card2
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.new()
    scroll.Parent = body
    rounded(scroll, 8)

    local scrollPadding = Instance.new("UIPadding")
    scrollPadding.PaddingTop = UDim.new(0, 7)
    scrollPadding.PaddingBottom = UDim.new(0, 7)
    scrollPadding.PaddingLeft = UDim.new(0, 8)
    scrollPadding.PaddingRight = UDim.new(0, 8)
    scrollPadding.Parent = scroll

    local live = Instance.new("TextLabel")
    live.Size = UDim2.new(1, 0, 0, 140)
    live.AutomaticSize = Enum.AutomaticSize.Y
    live.BackgroundTransparency = 1
    live.TextColor3 = CONFIG.COLORS.Text
    live.TextXAlignment = Enum.TextXAlignment.Left
    live.TextYAlignment = Enum.TextYAlignment.Top
    live.TextWrapped = true
    live.Font = Enum.Font.Code
    live.TextSize = 10
    live.Text = "Aguardando eventos de compra..."
    live.Parent = scroll

    local export = createButton(body, "Exportar relatório V2 (.txt)")
    export.LayoutOrder = 20

    -- Botão flutuante azul escuro solicitado.
    local floating = Instance.new("TextButton")
    floating.Name = "RestoreFloatingButton"
    floating.Size = UDim2.new(0, 58, 0, 58)
    floating.Position = UDim2.new(0, 18, 0.5, -29)
    floating.BackgroundColor3 = CONFIG.COLORS.Floating
    floating.BorderSizePixel = 0
    floating.Text = "V2"
    floating.TextColor3 = Color3.fromRGB(240, 246, 255)
    floating.Font = Enum.Font.GothamBold
    floating.TextSize = 15
    floating.Visible = false
    floating.ZIndex = 50
    floating.Parent = screen
    rounded(floating, 14)

    GUI.Screen = screen
    GUI.Main = main
    GUI.Header = header
    GUI.Status = status
    GUI.Money = money
    GUI.Live = live
    GUI.Export = export
    GUI.Minimize = minimize
    GUI.Close = close
    GUI.FloatButton = floating

    makeDraggable(main, header)
    makeDraggable(floating, floating)

    connect(minimize.MouseButton1Click, function()
        setMinimized(true)
    end)

    connect(floating.MouseButton1Click, function()
        setMinimized(false)
    end)

    connect(export.MouseButton1Click, function()
        local ok, message = exportReport()
        status.Text = message

        event(
            "SYSTEM",
            ok and "EXPORT_SUCCESS" or "EXPORT_UNAVAILABLE",
            {Message = message}
        )
    end)

    connect(close.MouseButton1Click, function()
        State.Running = false

        disconnectList(State.TycoonConnections)
        disconnectList(State.Connections)

        if screen then
            screen:Destroy()
        end
    end)
end

local function moneyLoop()
    task.spawn(function()
        while State.Running do
            local current = getMoneyValue()

            if State.LastMoney ~= nil
            and current ~= nil
            and current ~= State.LastMoney then
                correlateMoneyChange(State.LastMoney, current)
            end

            if current ~= nil then
                State.LastMoney = current
            end

            task.wait(CONFIG.MONEY_SAMPLE_INTERVAL)
        end
    end)
end

local function tycoonLoop()
    task.spawn(function()
        while State.Running do
            if not State.Tycoon
            or not State.Tycoon.Parent
            or not State.ButtonsFolder
            or not State.PurchasesFolder then
                attemptBindTycoon()
            end

            task.wait(CONFIG.TYCOON_RESCAN_INTERVAL)
        end
    end)
end

local function uiLoop()
    task.spawn(function()
        while State.Running do
            refreshUi()
            task.wait(0.5)
        end
    end)
end

-- Inicialização
createGui()

State.MoneyObject = findMoneyObject()
State.LastMoney = getMoneyValue()

event("SYSTEM", "Diagnostic V2 iniciado", {
    Version = CONFIG.VERSION,
    PlaceId = game.PlaceId,
    Player = LocalPlayer.Name,
})

attemptBindTycoon()
moneyLoop()
tycoonLoop()
uiLoop()

if GUI.Status then
    if State.Tycoon then
        GUI.Status.Text = "V2 ativa e vinculada ao seu Tycoon."
    else
        GUI.Status.Text = "V2 ativa. Procurando seu Tycoon..."
    end
end
