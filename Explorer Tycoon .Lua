--[[
PSICOSENATICO - TYCOON PURCHASE DIAGNOSTIC - V2.3.3
COMPATIBILITY / STABILITY BUILD

Diagnostic only.
Does not buy, fire remotes, change Money, Rebirths or Marketplace state.

Purchase classes:
- TYCOON_MONEY
- REBIRTH
- KILLS_OR_PREMIUM
- ROBUX_ONLY
- UNKNOWN

Automation policy:
- TYCOON_MONEY: eligible
- REBIRTH: eligible when requirement is satisfied
- KILLS_OR_PREMIUM: ignored
- ROBUX_ONLY: ignored
- UNKNOWN: ignored
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local VERSION = "2.3.3"
local GUI_NAME = "PsicoTycoonPurchaseDiagnosticV233"

local MAX_AUX_EVENTS = 2000
local MONEY_INTERVAL = 0.25
local TYCOON_INTERVAL = 1.5
local CORRELATION_WINDOW = 4
local UNLOCK_WINDOW = 3.5
local DRAG_THRESHOLD = 8

local COLORS = {
    Background = Color3.fromRGB(18, 23, 31),
    Header = Color3.fromRGB(24, 31, 43),
    Card = Color3.fromRGB(29, 37, 51),
    CardDark = Color3.fromRGB(14, 19, 27),
    Accent = Color3.fromRGB(83, 226, 169),
    Text = Color3.fromRGB(238, 242, 250),
    Muted = Color3.fromRGB(160, 171, 190),
    Danger = Color3.fromRGB(86, 43, 48),
    Floating = Color3.fromRGB(18, 49, 88),
}

local State = {
    Running = true,
    Reading = false,
    ReadingSessions = {},
    CurrentReadingSession = nil,

    StartedUnix = os.time(),
    StartedClock = os.clock(),

    Player = nil,

    Tycoon = nil,
    TycoonScore = 0,
    ButtonsFolder = nil,
    PurchasesFolder = nil,

    MoneyObject = nil,
    LastMoney = nil,

    RebirthObject = nil,
    LastRebirths = nil,

    InitialButtons = {},
    InitialPurchases = {},
    ButtonCache = {},

    Pending = {},
    Transactions = {},
    Events = {},
    CriticalEvents = {},
    Errors = {},

    DataStats = {
        TotalEventsObserved = 0,
        AuxiliaryEventsStored = 0,
        AuxiliaryEventsDiscarded = 0,
        CriticalEventsStored = 0,
        TransactionsStored = 0,
        TransactionDataDiscarded = 0,
    },

    Connections = {},
    TycoonConnections = {},

    Health = {
        Bootstrap = "STARTING",
        UI = "STARTING",
        Tycoon = "SEARCHING",
        Money = "SEARCHING",
        Rebirths = "SEARCHING",
        Engine = "STARTING",
        Reading = "PAUSED",
    },

    Minimized = false,
}

local UI = {}

local function elapsed()
    return math.floor((os.clock() - State.StartedClock) * 1000) / 1000
end

local function clockText()
    return os.date("%H:%M:%S")
end

local function normalize(value)
    return string.lower(tostring(value or "")):gsub("[%s_%-%./]", "")
end

local function safeFullName(inst)
    if not inst then
        return "<nil>"
    end

    local ok, result = pcall(function()
        return inst:GetFullName()
    end)

    if ok then
        return result
    end

    return "<detached>"
end

local function getAttributes(inst)
    if not inst then
        return {}
    end

    local ok, attrs = pcall(function()
        return inst:GetAttributes()
    end)

    if not ok or type(attrs) ~= "table" then
        return {}
    end

    local result = {}

    for key, value in pairs(attrs) do
        result[tostring(key)] = tostring(value)
    end

    return result
end

local function attrCI(inst, wanted)
    local wantedNorm = normalize(wanted)
    local attrs = getAttributes(inst)

    for key, value in pairs(attrs) do
        if normalize(key) == wantedNorm then
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

    local text = tostring(value)
    text = text:gsub(",", "")
    text = text:gsub("%s", "")
    text = text:gsub("R%$", "")
    text = text:gsub("%$", "")

    return tonumber(text)
end

local function containsAny(value, words)
    local text = normalize(value)

    for _, word in ipairs(words) do
        if string.find(text, normalize(word), 1, true) then
            return true
        end
    end

    return false
end

local CRITICAL_EVENT_KINDS = {
    TRANSACTION_FINALIZED = true,
    MONEY_SPEND = true,
    REBIRTH_CHANGE = true,
    BUTTON_REMOVED = true,
    PURCHASE_CREATED = true,
    BUTTONS_UNLOCKED = true,
    READING_STARTED = true,
    READING_STOPPED = true,
    ERROR = true,
}

local function pushEvent(kind, label, details)
    local item = {
        Time = clockText(),
        Unix = os.time(),
        Elapsed = elapsed(),
        Kind = kind,
        Label = label,
        Details = details or {},
    }

    State.DataStats.TotalEventsObserved = State.DataStats.TotalEventsObserved + 1

    if CRITICAL_EVENT_KINDS[kind] then
        table.insert(State.CriticalEvents, item)
        State.DataStats.CriticalEventsStored = #State.CriticalEvents
    end

    table.insert(State.Events, item)
    State.DataStats.AuxiliaryEventsStored = #State.Events

    while #State.Events > MAX_AUX_EVENTS do
        table.remove(State.Events, 1)
        State.DataStats.AuxiliaryEventsDiscarded =
            State.DataStats.AuxiliaryEventsDiscarded + 1
        State.DataStats.AuxiliaryEventsStored = #State.Events
    end

    return item
end

local function pushError(stage, err)
    local item = {
        Time = clockText(),
        Elapsed = elapsed(),
        Stage = stage,
        Error = tostring(err),
    }

    table.insert(State.Errors, item)
    pushEvent("ERROR", stage, {Error = tostring(err)})

    if UI.Status and UI.Status.Parent then
        UI.Status.Text = "Erro em " .. tostring(stage) .. ": " .. tostring(err)
    end
end

local function safeCall(stage, fn)
    local ok, result = pcall(fn)

    if not ok then
        pushError(stage, result)
        return false, result
    end

    return true, result
end

local function addConnection(signal, callback, bucket)
    local target = bucket or State.Connections

    local ok, connection = pcall(function()
        return signal:Connect(function(...)
            local args = {...}
            local callbackOk, callbackErr = pcall(function()
                callback(unpack(args))
            end)

            if not callbackOk then
                pushError("EVENT_CALLBACK", callbackErr)
            end
        end)
    end)

    if ok and connection then
        table.insert(target, connection)
        return connection
    end

    if not ok then
        pushError("CONNECT", connection)
    end

    return nil
end

local function disconnectAll(list)
    local old = list

    for i = #old, 1, -1 do
        local connection = old[i]
        old[i] = nil

        pcall(function()
            connection:Disconnect()
        end)
    end
end

local function waitForLocalPlayer(timeout)
    local startTime = os.clock()
    local player = Players.LocalPlayer

    while not player and os.clock() - startTime < timeout do
        task.wait(0.1)
        player = Players.LocalPlayer
    end

    return player
end

local function resolveGuiParent(player)
    -- First choice for executor environments.
    local gethuiFn = rawget(_G, "gethui")

    if type(gethuiFn) ~= "function" then
        local ok, env = pcall(function()
            if type(getgenv) == "function" then
                return getgenv()
            end
            return nil
        end)

        if ok and env and type(env.gethui) == "function" then
            gethuiFn = env.gethui
        end
    end

    if type(gethuiFn) == "function" then
        local ok, result = pcall(gethuiFn)
        if ok and result then
            return result, "gethui"
        end
    end

    -- Second choice: CoreGui.
    local coreOk = pcall(function()
        local probe = Instance.new("Folder")
        probe.Name = "__PsicoGuiProbe"
        probe.Parent = CoreGui
        probe:Destroy()
    end)

    if coreOk then
        return CoreGui, "CoreGui"
    end

    -- Final fallback: PlayerGui.
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        playerGui = player:WaitForChild("PlayerGui", 10)
    end

    if playerGui then
        return playerGui, "PlayerGui"
    end

    return nil, "NONE"
end

local function round(gui, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = gui
end

local function clampNumber(value, low, high)
    if value < low then
        return low
    end
    if value > high then
        return high
    end
    return value
end

local function resizeMenu()
    if not UI.Main or not UI.Main.Parent then
        return
    end

    local camera = workspace.CurrentCamera
    if not camera then
        return
    end

    local viewport = camera.ViewportSize
    local width = clampNumber(math.floor(viewport.X * 0.44), 300, 420)
    local height = clampNumber(math.floor(viewport.Y * 0.70), 250, 500)

    UI.Main.Size = UDim2.new(0, width, 0, height)
end

local function setMinimized(value)
    State.Minimized = value and true or false

    if UI.Main and UI.Main.Parent then
        UI.Main.Visible = not State.Minimized
    end

    if UI.Floating and UI.Floating.Parent then
        UI.Floating.Visible = State.Minimized
    end
end

local function setupDrag(frame, handle, isFloating)
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPosition = nil
    local moved = false
    local suppressClick = false

    addConnection(handle.InputBegan, function(input)
        local kind = input.UserInputType

        if kind ~= Enum.UserInputType.MouseButton1
        and kind ~= Enum.UserInputType.Touch then
            return
        end

        dragging = true
        dragInput = input
        dragStart = input.Position
        startPosition = frame.Position
        moved = false

        local endConnection
        endConnection = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false

                if moved and isFloating then
                    suppressClick = true
                    task.delay(0.15, function()
                        suppressClick = false
                    end)
                end

                if endConnection then
                    endConnection:Disconnect()
                    endConnection = nil
                end
            end
        end)
    end)

    addConnection(UserInputService.InputChanged, function(input)
        if not dragging or not dragStart or not startPosition then
            return
        end

        local valid = false

        if dragInput and dragInput.UserInputType == Enum.UserInputType.Touch then
            valid = (input == dragInput)
        elseif input.UserInputType == Enum.UserInputType.MouseMovement then
            valid = true
        end

        if not valid then
            return
        end

        local delta = input.Position - dragStart

        if delta.Magnitude >= DRAG_THRESHOLD then
            moved = true
        end

        frame.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end)

    if isFloating then
        addConnection(handle.MouseButton1Click, function()
            if suppressClick then
                return
            end

            setMinimized(false)
        end)
    end
end

local function createGui()
    local parent, parentKind = resolveGuiParent(State.Player)

    if not parent then
        error("Nenhum parent de GUI disponivel: gethui/CoreGui/PlayerGui falharam")
    end

    -- Remove only this version's GUI.
    local old = parent:FindFirstChild(GUI_NAME)
    if old then
        old:Destroy()
    end

    local screen = Instance.new("ScreenGui")
    screen.Name = GUI_NAME
    screen.Enabled = true
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 1000000
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.Parent = parent

    local main = Instance.new("Frame")
    main.Name = "Main"
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    main.Position = UDim2.new(0.5, 0, 0.5, 0)
    main.Size = UDim2.new(0, 350, 0, 360)
    main.BackgroundColor3 = COLORS.Background
    main.BorderSizePixel = 0
    main.Visible = true
    main.ZIndex = 10
    main.Parent = screen
    round(main, 12)

    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 50)
    header.BackgroundColor3 = COLORS.Header
    header.BorderSizePixel = 0
    header.Active = true
    header.ZIndex = 11
    header.Parent = main
    round(header, 12)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -100, 0, 23)
    title.Position = UDim2.new(0, 12, 0, 5)
    title.BackgroundTransparency = 1
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "TYCOON PURCHASE DIAGNOSTIC"
    title.TextColor3 = COLORS.Accent
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.ZIndex = 12
    title.Parent = header

    local version = Instance.new("TextLabel")
    version.Size = UDim2.new(1, -100, 0, 16)
    version.Position = UDim2.new(0, 12, 0, 28)
    version.BackgroundTransparency = 1
    version.TextXAlignment = Enum.TextXAlignment.Left
    version.Text = "V2.3.3 - stability build"
    version.TextColor3 = COLORS.Muted
    version.Font = Enum.Font.Gotham
    version.TextSize = 10
    version.ZIndex = 12
    version.Parent = header

    local minimize = Instance.new("TextButton")
    minimize.Name = "Minimize"
    minimize.Size = UDim2.new(0, 34, 0, 34)
    minimize.Position = UDim2.new(1, -78, 0, 8)
    minimize.BackgroundColor3 = COLORS.Floating
    minimize.BorderSizePixel = 0
    minimize.Text = "-"
    minimize.TextColor3 = Color3.new(1, 1, 1)
    minimize.Font = Enum.Font.GothamBold
    minimize.TextSize = 18
    minimize.ZIndex = 14
    minimize.Parent = header
    round(minimize, 8)

    local close = Instance.new("TextButton")
    close.Name = "Close"
    close.Size = UDim2.new(0, 34, 0, 34)
    close.Position = UDim2.new(1, -40, 0, 8)
    close.BackgroundColor3 = COLORS.Danger
    close.BorderSizePixel = 0
    close.Text = "X"
    close.TextColor3 = Color3.new(1, 1, 1)
    close.Font = Enum.Font.GothamBold
    close.TextSize = 13
    close.ZIndex = 14
    close.Parent = header
    round(close, 8)

    local body = Instance.new("Frame")
    body.Name = "Body"
    body.Position = UDim2.new(0, 8, 0, 58)
    body.Size = UDim2.new(1, -16, 1, -66)
    body.BackgroundTransparency = 1
    body.ZIndex = 10
    body.Parent = main

    local status = Instance.new("TextLabel")
    status.Name = "Status"
    status.Size = UDim2.new(1, 0, 0, 38)
    status.BackgroundColor3 = COLORS.Card
    status.BorderSizePixel = 0
    status.TextColor3 = COLORS.Text
    status.TextWrapped = true
    status.Text = "Interface aberta. Inicializando analisador..."
    status.Font = Enum.Font.Gotham
    status.TextSize = 10
    status.ZIndex = 11
    status.Parent = body
    round(status, 8)

    local money = Instance.new("TextLabel")
    money.Name = "Money"
    money.Position = UDim2.new(0, 0, 0, 44)
    money.Size = UDim2.new(0.5, -3, 0, 24)
    money.BackgroundTransparency = 1
    money.TextXAlignment = Enum.TextXAlignment.Left
    money.TextColor3 = COLORS.Accent
    money.Text = "Money: procurando..."
    money.Font = Enum.Font.GothamBold
    money.TextSize = 10
    money.ZIndex = 11
    money.Parent = body

    local rebirths = Instance.new("TextLabel")
    rebirths.Name = "Rebirths"
    rebirths.Position = UDim2.new(0.5, 3, 0, 44)
    rebirths.Size = UDim2.new(0.5, -3, 0, 24)
    rebirths.BackgroundTransparency = 1
    rebirths.TextXAlignment = Enum.TextXAlignment.Right
    rebirths.TextColor3 = COLORS.Accent
    rebirths.Text = "Rebirths: procurando..."
    rebirths.Font = Enum.Font.GothamBold
    rebirths.TextSize = 10
    rebirths.ZIndex = 11
    rebirths.Parent = body

    local health = Instance.new("TextLabel")
    health.Name = "Health"
    health.Position = UDim2.new(0, 0, 0, 70)
    health.Size = UDim2.new(1, 0, 0, 30)
    health.BackgroundTransparency = 1
    health.TextXAlignment = Enum.TextXAlignment.Left
    health.TextWrapped = true
    health.TextColor3 = COLORS.Muted
    health.Text = "Motor: iniciando..."
    health.Font = Enum.Font.Gotham
    health.TextSize = 9
    health.ZIndex = 11
    health.Parent = body

    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "Log"
    scroll.Position = UDim2.new(0, 0, 0, 102)
    scroll.Size = UDim2.new(1, 0, 1, -188)
    scroll.BackgroundColor3 = COLORS.CardDark
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.ZIndex = 11
    scroll.Parent = body
    round(scroll, 8)

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 7)
    padding.PaddingBottom = UDim.new(0, 7)
    padding.PaddingLeft = UDim.new(0, 8)
    padding.PaddingRight = UDim.new(0, 8)
    padding.Parent = scroll

    local live = Instance.new("TextLabel")
    live.Name = "LiveText"
    live.Size = UDim2.new(1, 0, 0, 140)
    live.AutomaticSize = Enum.AutomaticSize.Y
    live.BackgroundTransparency = 1
    live.TextWrapped = true
    live.TextXAlignment = Enum.TextXAlignment.Left
    live.TextYAlignment = Enum.TextYAlignment.Top
    live.TextColor3 = COLORS.Text
    live.Text = "[BOOT] GUI criada em " .. parentKind
    live.Font = Enum.Font.Code
    live.TextSize = 10
    live.ZIndex = 12
    live.Parent = scroll

    local readToggle = Instance.new("TextButton")
    readToggle.Name = "ReadToggle"
    readToggle.Position = UDim2.new(0, 0, 1, -80)
    readToggle.Size = UDim2.new(1, 0, 0, 36)
    readToggle.BackgroundColor3 = COLORS.Floating
    readToggle.BorderSizePixel = 0
    readToggle.Text = "Iniciar leitura de dados"
    readToggle.TextColor3 = COLORS.Text
    readToggle.Font = Enum.Font.GothamBold
    readToggle.TextSize = 11
    readToggle.ZIndex = 12
    readToggle.Parent = body
    round(readToggle, 8)

    local export = Instance.new("TextButton")
    export.Name = "Export"
    export.Position = UDim2.new(0, 0, 1, -38)
    export.Size = UDim2.new(1, 0, 0, 36)
    export.BackgroundColor3 = COLORS.Card
    export.BorderSizePixel = 0
    export.Text = "Exportar relatorio V2.3.3 (.txt)"
    export.TextColor3 = COLORS.Text
    export.Font = Enum.Font.GothamBold
    export.TextSize = 11
    export.ZIndex = 12
    export.Parent = body
    round(export, 8)

    local floating = Instance.new("TextButton")
    floating.Name = "RestoreFloatingButton"
    floating.Size = UDim2.new(0, 60, 0, 60)
    floating.Position = UDim2.new(0, 18, 0.5, -30)
    floating.BackgroundColor3 = COLORS.Floating
    floating.BorderSizePixel = 0
    floating.Text = "V2.3.3"
    floating.TextColor3 = Color3.fromRGB(240, 246, 255)
    floating.Font = Enum.Font.GothamBold
    floating.TextSize = 11
    floating.Visible = false
    floating.Active = true
    floating.ZIndex = 100
    floating.Parent = screen
    round(floating, 14)

    UI.Screen = screen
    UI.Main = main
    UI.Header = header
    UI.Status = status
    UI.Money = money
    UI.Rebirths = rebirths
    UI.Health = health
    UI.Live = live
    UI.ReadToggle = readToggle
    UI.Export = export
    UI.Minimize = minimize
    UI.Close = close
    UI.Floating = floating
    UI.ParentKind = parentKind

    setupDrag(main, header, false)
    setupDrag(floating, floating, true)

    addConnection(minimize.MouseButton1Click, function()
        setMinimized(true)
    end)

    addConnection(close.MouseButton1Click, function()
        State.Running = false

        if UI.Screen and UI.Screen.Parent then
            UI.Screen:Destroy()
        end

        disconnectAll(State.TycoonConnections)
        disconnectAll(State.Connections)
    end)

    resizeMenu()

    local camera = workspace.CurrentCamera
    if camera then
        addConnection(camera:GetPropertyChangedSignal("ViewportSize"), function()
            resizeMenu()
        end)
    end

    State.Health.UI = "ACTIVE"

    return parentKind
end

-- ============================================================
-- GUI BOOTSTRAP FIRST
-- ============================================================

State.Player = waitForLocalPlayer(10)

if not State.Player then
    warn("[Tycoon Diagnostic V2.3.3] LocalPlayer indisponivel.")
    return
end

local guiOk, guiResult = pcall(createGui)

if not guiOk then
    warn("[Tycoon Diagnostic V2.3.3] GUI ERROR: " .. tostring(guiResult))
    return
end

State.Health.Bootstrap = "GUI_OK"

pushEvent("SYSTEM", "GUI_READY", {
    Version = VERSION,
    Parent = tostring(guiResult),
})

-- From this point onward, a backend error should not prevent the GUI
-- from having appeared.

local function describeButton(button)
    return {
        Name = button.Name,
        Path = safeFullName(button),
        Price = attrCI(button, "Price"),
        Cost = attrCI(button, "Cost"),
        Owner = attrCI(button, "Owner"),
        Rebirths = attrCI(button, "Rebirths"),
        RequiredRebirths = attrCI(button, "RequiredRebirths"),
        LinkedPurchases = attrCI(button, "LinkedPurchases"),
        ProductId = attrCI(button, "ProductId"),
        DeveloperProductId = attrCI(button, "DeveloperProductId"),
        GamePassId = attrCI(button, "GamePassId"),
        Gamepass = attrCI(button, "Gamepass"),
        DevProduct = attrCI(button, "DevProduct"),
        NonPurchase = attrCI(button, "NonPurchase"),
        Dependency = attrCI(button, "Dependency"),
        Kills = attrCI(button, "Kills"),
        Robux = attrCI(button, "Robux"),
        Attributes = getAttributes(button),
        HasTouch = button:FindFirstChild("Touch", true) ~= nil,
        HasTouchInterest = button:FindFirstChildWhichIsA("TouchTransmitter", true) ~= nil,
        HasPrompt = button:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil,
    }
end

local function describePurchase(purchase)
    local prompt = purchase:FindFirstChildWhichIsA("ProximityPrompt", true)

    local info = {
        Name = purchase.Name,
        Path = safeFullName(purchase),
        Owner = attrCI(purchase, "Owner"),
        Rebirths = attrCI(purchase, "Rebirths"),
        LinkedPurchases = attrCI(purchase, "LinkedPurchases"),
        ProductId = attrCI(purchase, "ProductId"),
        DeveloperProductId = attrCI(purchase, "DeveloperProductId"),
        GamePassId = attrCI(purchase, "GamePassId"),
        Gamepass = attrCI(purchase, "Gamepass"),
        DevProduct = attrCI(purchase, "DevProduct"),
        NonPurchase = attrCI(purchase, "NonPurchase"),
        Dependency = attrCI(purchase, "Dependency"),
        Kills = attrCI(purchase, "Kills"),
        Attributes = getAttributes(purchase),
    }

    if prompt then
        info.ProximityPrompt = {
            Path = safeFullName(prompt),
            ActionText = prompt.ActionText,
            ObjectText = prompt.ObjectText,
            HoldDuration = prompt.HoldDuration,
            MaxActivationDistance = prompt.MaxActivationDistance,
            Enabled = prompt.Enabled,
        }
    end

    return info
end

local function classify(buttonInfo, purchaseInfo)
    local button = buttonInfo or {}
    local purchase = purchaseInfo or {}

    local evidence = {}

    local price = parseNumber(button.Price or button.Cost)
    local requiredRebirths = parseNumber(button.RequiredRebirths or button.Rebirths)
    local killsRequired = parseNumber(button.Kills or purchase.Kills)

    local gamepass = button.Gamepass or purchase.Gamepass
    local devProduct = button.DevProduct or purchase.DevProduct
    local productId = button.ProductId or purchase.ProductId
    local developerProductId = button.DeveloperProductId or purchase.DeveloperProductId
    local gamePassId = button.GamePassId or purchase.GamePassId
    local robux = button.Robux

    local hasMarketplaceMarker =
        (gamepass ~= nil and tostring(gamepass) ~= "")
        or (devProduct ~= nil and tostring(devProduct) ~= "")
        or (productId ~= nil and tostring(productId) ~= "")
        or (developerProductId ~= nil and tostring(developerProductId) ~= "")
        or (gamePassId ~= nil and tostring(gamePassId) ~= "")
        or (robux ~= nil and tostring(robux) ~= "")

    if price and price > 0 then
        table.insert(evidence, "Price/Cost=" .. tostring(price))
    end

    if requiredRebirths and requiredRebirths > 0 then
        table.insert(evidence, "Rebirth requirement=" .. tostring(requiredRebirths))
    end

    if killsRequired and killsRequired > 0 then
        table.insert(evidence, "Kills requirement=" .. tostring(killsRequired))
    end

    if gamepass ~= nil and tostring(gamepass) ~= "" then
        table.insert(evidence, "Gamepass=" .. tostring(gamepass))
    end
    if devProduct ~= nil and tostring(devProduct) ~= "" then
        table.insert(evidence, "DevProduct=" .. tostring(devProduct))
    end
    if productId ~= nil and tostring(productId) ~= "" then
        table.insert(evidence, "ProductId=" .. tostring(productId))
    end
    if developerProductId ~= nil and tostring(developerProductId) ~= "" then
        table.insert(evidence, "DeveloperProductId=" .. tostring(developerProductId))
    end
    if gamePassId ~= nil and tostring(gamePassId) ~= "" then
        table.insert(evidence, "GamePassId=" .. tostring(gamePassId))
    end
    if robux ~= nil and tostring(robux) ~= "" then
        table.insert(evidence, "Robux=" .. tostring(robux))
    end

    local classType = "UNKNOWN"
    local confidence = "unknown"
    local score = 0
    local eligible = false
    local eligibilityReason = "Insufficient evidence"

    if hasMarketplaceMarker and killsRequired and killsRequired > 0 then
        classType = "KILLS_OR_PREMIUM"
        confidence = "high"
        score = 14
        eligible = false
        eligibilityReason = "Ignored: item exposes Kills and Marketplace/premium evidence"
    elseif hasMarketplaceMarker then
        classType = "ROBUX_ONLY"
        confidence = "high"
        score = 12
        eligible = false
        eligibilityReason = "Ignored: Marketplace/premium purchase"
    elseif requiredRebirths and requiredRebirths > 0 then
        classType = "REBIRTH"
        confidence = "high"
        score = 10
        local currentRebirths = State.LastRebirths
        local satisfied = currentRebirths ~= nil and currentRebirths >= requiredRebirths
        eligible = satisfied
        eligibilityReason = satisfied
            and ("Eligible: rebirth requirement satisfied (" .. tostring(currentRebirths) .. "/" .. tostring(requiredRebirths) .. ")")
            or ("Blocked: requires " .. tostring(requiredRebirths) .. " rebirth(s), current=" .. tostring(currentRebirths ~= nil and currentRebirths or "unknown"))
    elseif price and price > 0 then
        classType = "TYCOON_MONEY"
        confidence = "high"
        score = 9
        eligible = true
        eligibilityReason = "Eligible: ordinary Tycoon-money purchase"
    elseif killsRequired and killsRequired > 0 then
        classType = "KILLS_OR_PREMIUM"
        confidence = "medium"
        score = 7
        eligible = false
        eligibilityReason = "Ignored: Kills-based requirement"
    end

    return {
        Type = classType,
        Confidence = confidence,
        Score = score,
        Evidence = evidence,
        AutomationEligible = eligible,
        AutomationReason = eligibilityReason,
        Requirements = {
            Price = price,
            Rebirths = requiredRebirths,
            Kills = killsRequired,
            HasMarketplaceMarker = hasMarketplaceMarker,
        },
    }
end

local function ownerMatches(owner)
    if owner == nil or not State.Player then
        return false
    end

    local text = tostring(owner)

    return text == State.Player.Name
        or text == tostring(State.Player.UserId)
        or normalize(text) == normalize(State.Player.Name)
end

local function scoreTycoon(tycoon)
    if not tycoon then
        return -1, {}
    end

    if not tycoon:IsA("Model") and not tycoon:IsA("Folder") then
        return -1, {}
    end

    local score = 0
    local evidence = {}

    local buttons = tycoon:FindFirstChild("Buttons")
    local purchases = tycoon:FindFirstChild("Purchases")

    if not buttons or not purchases then
        return 0, evidence
    end

    local owner = attrCI(tycoon, "Owner")

    if ownerMatches(owner) then
        score = score + 100
        table.insert(evidence, "Tycoon Owner matches LocalPlayer")
    end

    local folders = {buttons, purchases}

    for _, folder in ipairs(folders) do
        local count = 0

        for _, child in ipairs(folder:GetChildren()) do
            count = count + 1

            if ownerMatches(attrCI(child, "Owner")) then
                score = score + 40
                table.insert(evidence, child.Name .. " Owner matches LocalPlayer")
                break
            end

            if count >= 80 then
                break
            end
        end
    end

    return score, evidence
end

local function findPlayerTycoon()
    local tycoons = workspace:FindFirstChild("Tycoons")

    if not tycoons then
        return nil, 0, {}
    end

    local best = nil
    local bestScore = 0
    local bestEvidence = {}

    for _, tycoon in ipairs(tycoons:GetChildren()) do
        local score, evidence = scoreTycoon(tycoon)

        if score > bestScore then
            best = tycoon
            bestScore = score
            bestEvidence = evidence
        end
    end

    if best and bestScore >= 40 then
        return best, bestScore, bestEvidence
    end

    return nil, bestScore, bestEvidence
end

local function findStat(names)
    local leaderstats = State.Player and State.Player:FindFirstChild("leaderstats")

    if not leaderstats then
        return nil
    end

    for _, wanted in ipairs(names) do
        local direct = leaderstats:FindFirstChild(wanted)
        if direct and direct:IsA("ValueBase") then
            return direct
        end
    end

    for _, child in ipairs(leaderstats:GetChildren()) do
        if child:IsA("ValueBase") and containsAny(child.Name, names) then
            return child
        end
    end

    return nil
end

local function readValue(obj)
    if not obj or not obj.Parent then
        return nil
    end

    local ok, value = pcall(function()
        return obj.Value
    end)

    if not ok then
        return nil
    end

    return parseNumber(value)
end

local function refreshStatsObjects()
    if not State.MoneyObject or not State.MoneyObject.Parent then
        State.MoneyObject = findStat({"Money", "Cash", "Coins", "Coin", "Currency", "Saldo"})
    end

    if not State.RebirthObject or not State.RebirthObject.Parent then
        State.RebirthObject = findStat({"Rebirths", "Rebirth", "Renascimentos", "Renascimento"})
    end
end

local function buttonsSet()
    local result = {}

    if State.ButtonsFolder then
        for _, child in ipairs(State.ButtonsFolder:GetChildren()) do
            result[child.Name] = true
        end
    end

    return result
end

local function pendingFor(name)
    local item = State.Pending[name]

    if not item or item.Completed then
        item = {
            Name = name,
            Started = os.clock(),
            Button = nil,
            Purchase = nil,
            ButtonRemovedAt = nil,
            PurchaseCreatedAt = nil,
            MoneyBefore = State.LastMoney,
            MoneyAfter = nil,
            RebirthsBefore = State.LastRebirths,
            RebirthsAfter = nil,
            Unlocks = {},
            Completed = false,
        }

        State.Pending[name] = item
    end

    return item
end

local function finalize(name)
    local pending = State.Pending[name]

    if not pending or pending.Completed then
        return
    end

    local classification = classify(pending.Button, pending.Purchase)

    local transaction = {
        Id = #State.Transactions + 1,
        Name = name,
        Time = clockText(),
        Elapsed = elapsed(),
        Classification = classification,
        AutomationEligible = classification.AutomationEligible,
        AutomationReason = classification.AutomationReason,

        Button = pending.Button,
        Purchase = pending.Purchase,

        DeclaredPrice = pending.Button and (pending.Button.Price or pending.Button.Cost) or nil,
        RequiredRebirths = pending.Button and (pending.Button.RequiredRebirths or pending.Button.Rebirths) or nil,
        LinkedPurchases = (pending.Button and pending.Button.LinkedPurchases)
            or (pending.Purchase and pending.Purchase.LinkedPurchases) or nil,
        Dependency = (pending.Button and pending.Button.Dependency)
            or (pending.Purchase and pending.Purchase.Dependency) or nil,

        MoneyBefore = pending.MoneyBefore,
        MoneyAfter = pending.MoneyAfter,
        MoneyDelta = (
            pending.MoneyBefore ~= nil and pending.MoneyAfter ~= nil
        ) and (pending.MoneyAfter - pending.MoneyBefore) or nil,

        RebirthsBefore = pending.RebirthsBefore,
        RebirthsAfter = pending.RebirthsAfter,

        UnlockedButtons = pending.Unlocks,

        Timing = {
            ButtonRemovedAt = pending.ButtonRemovedAt,
            PurchaseCreatedAt = pending.PurchaseCreatedAt,
        },
    }

    local declaredPriceNumber = parseNumber(transaction.DeclaredPrice)
    local delta = transaction.MoneyDelta

    transaction.EconomyEvidence = {
        Direction = delta and (delta < 0 and "SPEND" or (delta > 0 and "INCOME" or "NO_CHANGE")) or "UNOBSERVED",
        ExactPriceMatch = (
            declaredPriceNumber ~= nil
            and delta ~= nil
            and delta < 0
            and math.abs(delta) == declaredPriceNumber
        ) or false,
        ObservedSpend = (delta ~= nil and delta < 0) and math.abs(delta) or nil,
        ObservedIncome = (delta ~= nil and delta > 0) and delta or nil,
    }

    if transaction.Classification.Type == "TYCOON_MONEY"
    and transaction.EconomyEvidence.ExactPriceMatch then
        transaction.Classification.Confidence = "confirmed"
        transaction.Classification.Score = math.max(transaction.Classification.Score or 0, 15)
        transaction.AutomationEligible = true
        transaction.AutomationReason = "Eligible: confirmed Tycoon-money purchase"
        transaction.Classification.AutomationEligible = true
        transaction.Classification.AutomationReason = "Eligible: confirmed Tycoon-money purchase"
        table.insert(transaction.Classification.Evidence, "Money deduction exactly matches declared Price")
    elseif transaction.Classification.Type == "TYCOON_MONEY"
    and delta ~= nil and delta > 0 then
        table.insert(transaction.Classification.Evidence, "Positive Money delta is income, not purchase cost")
    end

    table.insert(State.Transactions, transaction)
    State.DataStats.TransactionsStored = #State.Transactions
    pending.Completed = true

    pushEvent("TRANSACTION_FINALIZED", name, transaction)
end

local function watchUnlocks(name, baseline)
    task.spawn(function()
        local seen = {}
        local finishAt = os.clock() + UNLOCK_WINDOW

        while State.Running and os.clock() < finishAt do
            if State.ButtonsFolder then
                for _, child in ipairs(State.ButtonsFolder:GetChildren()) do
                    if not baseline[child.Name] then
                        seen[child.Name] = true
                    end
                end
            end

            task.wait(0.15)
        end

        local pending = State.Pending[name]

        if not pending then
            return
        end

        local list = {}

        for childName in pairs(seen) do
            table.insert(list, childName)
        end

        table.sort(list)
        pending.Unlocks = list

        if #list > 0 then
            pushEvent("BUTTONS_UNLOCKED", name, {
                UnlockedButtons = list,
            })
        end

        finalize(name)
    end)
end

local function watchButtonAttributes(button)
    local attrs = {
        "Price",
        "Cost",
        "Owner",
        "Rebirths",
        "RequiredRebirths",
        "LinkedPurchases",
        "ProductId",
        "DeveloperProductId",
        "GamePassId",
        "Gamepass",
        "DevProduct",
        "NonPurchase",
        "Dependency",
        "Kills",
        "Robux",
    }

    for _, attrName in ipairs(attrs) do
        addConnection(button:GetAttributeChangedSignal(attrName), function()
            local info = describeButton(button)
            State.ButtonCache[button.Name] = info

            if not State.Reading then
                return
            end

            pushEvent("BUTTON_ATTRIBUTE_CHANGED", button.Name, {
                Attribute = attrName,
                Button = info,
                Classification = classify(info, nil),
            })
        end, State.TycoonConnections)
    end
end

local function onButtonAdded(button)
    if not button:IsA("Model") and not button:IsA("Folder") then
        return
    end

    local info = describeButton(button)
    State.ButtonCache[button.Name] = info
    watchButtonAttributes(button)

    if not State.Reading then
        return
    end

    pushEvent("BUTTON_AVAILABLE", button.Name, {
        Button = info,
        Classification = classify(info, nil),
    })
end

local function onButtonRemoved(button)
    local name = button.Name
    local info = State.ButtonCache[name] or describeButton(button)

    State.ButtonCache[name] = nil

    if not State.Reading then
        return
    end

    local pending = pendingFor(name)

    pending.Button = info
    pending.ButtonRemovedAt = os.clock()
    pending.MoneyBefore = State.LastMoney
    pending.RebirthsBefore = State.LastRebirths

    local baseline = buttonsSet()

    pushEvent("BUTTON_REMOVED", name, {
        Button = info,
        Classification = classify(info, nil),
        MoneyBefore = pending.MoneyBefore,
        RebirthsBefore = pending.RebirthsBefore,
    })

    watchUnlocks(name, baseline)
end

local function onPurchaseAdded(purchase)
    if not purchase:IsA("Model") and not purchase:IsA("Folder") then
        return
    end

    if not State.Reading then
        return
    end

    local name = purchase.Name
    local pending = pendingFor(name)
    local info = describePurchase(purchase)

    pending.Purchase = info
    pending.PurchaseCreatedAt = os.clock()

    pushEvent("PURCHASE_CREATED", name, {
        Purchase = info,
        Classification = classify(pending.Button, info),
    })
end

local function scanInitial()
    State.ButtonCache = {}

    local buttonsSnapshot = {}
    local purchasesSnapshot = {}

    if State.ButtonsFolder then
        for _, button in ipairs(State.ButtonsFolder:GetChildren()) do
            if button:IsA("Model") or button:IsA("Folder") then
                local info = describeButton(button)
                table.insert(buttonsSnapshot, info)
                State.ButtonCache[button.Name] = info
                watchButtonAttributes(button)
            end
        end
    end

    if State.PurchasesFolder then
        for _, purchase in ipairs(State.PurchasesFolder:GetChildren()) do
            if purchase:IsA("Model") or purchase:IsA("Folder") then
                table.insert(purchasesSnapshot, describePurchase(purchase))
            end
        end
    end

    if State.Reading then
        State.InitialButtons = buttonsSnapshot
        State.InitialPurchases = purchasesSnapshot

        pushEvent("INITIAL_STATE", "Initial state", {
            Buttons = #State.InitialButtons,
            Purchases = #State.InitialPurchases,
        })
    end
end

local function bindTycoon(tycoon, score, evidence)
    if not tycoon then
        return false
    end

    if State.Tycoon == tycoon
    and State.ButtonsFolder
    and State.PurchasesFolder then
        State.TycoonScore = score
        State.Health.Tycoon = "CONFIRMED"
        return true
    end

    disconnectAll(State.TycoonConnections)

    local buttons = tycoon:FindFirstChild("Buttons")
    local purchases = tycoon:FindFirstChild("Purchases")

    if not buttons or not purchases then
        return false
    end

    State.Tycoon = tycoon
    State.TycoonScore = score or 0
    State.ButtonsFolder = buttons
    State.PurchasesFolder = purchases

    scanInitial()

    addConnection(buttons.ChildAdded, onButtonAdded, State.TycoonConnections)
    addConnection(buttons.ChildRemoved, onButtonRemoved, State.TycoonConnections)
    addConnection(purchases.ChildAdded, onPurchaseAdded, State.TycoonConnections)

    State.Health.Tycoon = "CONFIRMED"

    if State.Reading then
        pushEvent("TYCOON_BOUND", tycoon.Name, {
            Path = safeFullName(tycoon),
            Score = State.TycoonScore,
            Evidence = evidence,
        })
    end

    return true
end

local function reconsiderTycoon()
    local tycoon, score, evidence = findPlayerTycoon()

    if tycoon then
        bindTycoon(tycoon, score, evidence)
    else
        State.Health.Tycoon = "SEARCHING"
    end
end

local function correlateStatChanges(oldMoney, newMoney, oldRebirths, newRebirths)
    local now = os.clock()
    local best = nil
    local bestTime = -1

    for _, pending in pairs(State.Pending) do
        if not pending.Completed then
            local eventTime = pending.PurchaseCreatedAt or pending.ButtonRemovedAt

            if eventTime
            and now - eventTime <= CORRELATION_WINDOW
            and eventTime > bestTime then
                best = pending
                bestTime = eventTime
            end
        end
    end

    if not best then
        return
    end

    -- Only negative Money deltas are purchase-spend evidence.
    -- Positive deltas are income/collection and are deliberately not
    -- attached as MoneyAfter to a purchase.
    if oldMoney ~= nil and newMoney ~= nil and newMoney < oldMoney then
        best.MoneyBefore = best.MoneyBefore or oldMoney
        best.MoneyAfter = newMoney
    end

    if oldRebirths ~= nil
    and newRebirths ~= nil
    and oldRebirths ~= newRebirths then
        best.RebirthsBefore = best.RebirthsBefore or oldRebirths
        best.RebirthsAfter = newRebirths
    end
end

local buildAutomationCandidates

local function refreshUI()
    if not UI.Screen or not UI.Screen.Parent then
        return
    end

    local tycoonName = State.Tycoon and State.Tycoon.Name or "nao identificado"

    local candidates = buildAutomationCandidates()

    UI.Status.Text =
        "Leitura: " .. (State.Reading and "ATIVA" or "PAUSADA") ..
        " | Tycoon: " .. tostring(tycoonName) ..
        " | Compras: " .. tostring(#State.Transactions) ..
        " | Elegiveis: " .. tostring(#candidates.Eligible)

    if UI.ReadToggle and UI.ReadToggle.Parent then
        UI.ReadToggle.Text = State.Reading
            and "Parar leitura de dados"
            or "Iniciar leitura de dados"

        UI.ReadToggle.BackgroundColor3 = State.Reading
            and COLORS.Danger
            or COLORS.Floating
    end

    UI.Money.Text =
        "Money: " ..
        (State.LastMoney ~= nil and tostring(State.LastMoney) or "nao encontrado")

    UI.Rebirths.Text =
        "Rebirths: " ..
        (State.LastRebirths ~= nil and tostring(State.LastRebirths) or "nao encontrado")

    UI.Health.Text =
        "UI:" .. tostring(State.Health.UI) ..
        " Leitura:" .. tostring(State.Health.Reading) ..
        " Tycoon:" .. tostring(State.Health.Tycoon) ..
        " Money:" .. tostring(State.Health.Money) ..
        " Rebirth:" .. tostring(State.Health.Rebirths) ..
        " Tx:" .. tostring(#State.Transactions) ..
        " Ev:" .. tostring(State.DataStats.TotalEventsObserved) ..
        " Desc:" .. tostring(State.DataStats.AuxiliaryEventsDiscarded) ..
        " Errors:" .. tostring(#State.Errors)

    local lines = {}
    local first = #State.Events - 17

    if first < 1 then
        first = 1
    end

    for i = #State.Events, first, -1 do
        local item = State.Events[i]

        table.insert(
            lines,
            "[" .. tostring(item.Time) .. "] " ..
            tostring(item.Kind) .. " - " ..
            tostring(item.Label)
        )
    end

    if #lines == 0 then
        UI.Live.Text = "Aguardando eventos..."
    else
        UI.Live.Text = table.concat(lines, "\n")
    end
end

buildAutomationCandidates = function()
    local result = {Eligible = {}, Ignored = {}}
    if not State.ButtonsFolder then return result end

    for _, button in ipairs(State.ButtonsFolder:GetChildren()) do
        if button:IsA("Model") or button:IsA("Folder") then
            local info = State.ButtonCache[button.Name] or describeButton(button)
            local classification = classify(info, nil)
            local record = {
                Name = button.Name,
                Path = safeFullName(button),
                Type = classification.Type,
                AutomationEligible = classification.AutomationEligible,
                AutomationReason = classification.AutomationReason,
                Requirements = classification.Requirements,
                Dependency = info.Dependency,
                Price = info.Price or info.Cost,
                Rebirths = info.RequiredRebirths or info.Rebirths,
                Kills = info.Kills,
                Gamepass = info.Gamepass,
                DevProduct = info.DevProduct,
            }
            if classification.AutomationEligible then
                table.insert(result.Eligible, record)
            else
                table.insert(result.Ignored, record)
            end
        end
    end

    table.sort(result.Eligible, function(a, b) return tostring(a.Name) < tostring(b.Name) end)
    table.sort(result.Ignored, function(a, b) return tostring(a.Name) < tostring(b.Name) end)
    return result
end

local function setReading(enabled)
    enabled = enabled and true or false

    if State.Reading == enabled then
        return
    end

    if enabled then
        State.Reading = true
        State.Health.Reading = "ACTIVE"
        State.Pending = {}

        refreshStatsObjects()
        State.LastMoney = readValue(State.MoneyObject)
        State.LastRebirths = readValue(State.RebirthObject)

        local session = {
            StartedUnix = os.time(),
            StartedElapsed = elapsed(),
            StartedMoney = State.LastMoney,
            StartedRebirths = State.LastRebirths,
            StartedEventCount = State.DataStats.TotalEventsObserved,
            StartedTransactionCount = #State.Transactions,
        }

        State.CurrentReadingSession = session
        table.insert(State.ReadingSessions, session)

        scanInitial()

        pushEvent("READING_STARTED", "READING_STARTED", {
            Money = State.LastMoney,
            Rebirths = State.LastRebirths,
            Buttons = #State.InitialButtons,
            Purchases = #State.InitialPurchases,
            TransactionsStored = #State.Transactions,
            EventsObserved = State.DataStats.TotalEventsObserved,
        })
    else
        pushEvent("READING_STOPPED", "READING_STOPPED", {
            Money = State.LastMoney,
            Rebirths = State.LastRebirths,
            TransactionsStored = #State.Transactions,
            EventsObserved = State.DataStats.TotalEventsObserved,
            AuxiliaryEventsDiscarded = State.DataStats.AuxiliaryEventsDiscarded,
        })

        if State.CurrentReadingSession then
            State.CurrentReadingSession.StoppedUnix = os.time()
            State.CurrentReadingSession.StoppedElapsed = elapsed()
            State.CurrentReadingSession.StoppedMoney = State.LastMoney
            State.CurrentReadingSession.StoppedRebirths = State.LastRebirths
            State.CurrentReadingSession.StoppedEventCount =
                State.DataStats.TotalEventsObserved
            State.CurrentReadingSession.StoppedTransactionCount =
                #State.Transactions
            State.CurrentReadingSession.EventsObserved =
                State.CurrentReadingSession.StoppedEventCount -
                (State.CurrentReadingSession.StartedEventCount or 0)
            State.CurrentReadingSession.TransactionsRecorded =
                State.CurrentReadingSession.StoppedTransactionCount -
                (State.CurrentReadingSession.StartedTransactionCount or 0)
        end

        State.CurrentReadingSession = nil
        State.Pending = {}
        State.Reading = false
        State.Health.Reading = "PAUSED"
    end

    safeCall("READING_UI_REFRESH", function()
        refreshUI()
    end)
end

local function buildProgressionGraph()
    local edges = {}

    for _, transaction in ipairs(State.Transactions) do
        local source = transaction.Name

        if transaction.Dependency and tostring(transaction.Dependency) ~= "" then
            table.insert(edges, {
                Type = "DEPENDENCY",
                From = tostring(transaction.Dependency),
                To = source,
            })
        end

        if transaction.LinkedPurchases and tostring(transaction.LinkedPurchases) ~= "" then
            for linked in string.gmatch(tostring(transaction.LinkedPurchases), "[^,]+") do
                linked = linked:gsub("^%s+", ""):gsub("%s+$", "")
                if linked ~= "" then
                    table.insert(edges, {
                        Type = "LINKED_PURCHASE",
                        From = source,
                        To = linked,
                    })
                end
            end
        end

        for _, unlocked in ipairs(transaction.UnlockedButtons or {}) do
            table.insert(edges, {
                Type = "OBSERVED_UNLOCK",
                From = source,
                To = unlocked,
            })
        end
    end

    return edges
end

local function buildReport()
    local payload = {
        Report = "Tycoon Purchase Diagnostic",
        Version = VERSION,
        PlaceId = game.PlaceId,
        JobId = game.JobId,

        StartedAtUnix = State.StartedUnix,
        FinishedAtUnix = os.time(),

        Player = {
            Name = State.Player.Name,
            UserId = State.Player.UserId,
        },

        GuiParent = UI.ParentKind,

        Tycoon = {
            Name = State.Tycoon and State.Tycoon.Name or nil,
            Path = State.Tycoon and safeFullName(State.Tycoon) or nil,
            Score = State.TycoonScore,
        },

        MoneyPath = State.MoneyObject and safeFullName(State.MoneyObject) or nil,
        RebirthPath = State.RebirthObject and safeFullName(State.RebirthObject) or nil,

        InitialButtons = State.InitialButtons,
        InitialPurchases = State.InitialPurchases,
        ReadingActive = State.Reading,
        ReadingSessions = State.ReadingSessions,

        StoragePolicy = {
            Transactions = "UNBOUNDED_DURING_SESSION",
            CriticalEvents = "UNBOUNDED_DURING_SESSION",
            AuxiliaryEvents = "RING_BUFFER",
            AuxiliaryEventLimit = MAX_AUX_EVENTS,
            Note = "Only auxiliary history is trimmed. Consolidated transactions and critical purchase evidence are preserved for the full session.",
        },

        DataStats = {
            TotalEventsObserved = State.DataStats.TotalEventsObserved,
            AuxiliaryEventsStored = #State.Events,
            AuxiliaryEventsDiscarded = State.DataStats.AuxiliaryEventsDiscarded,
            CriticalEventsStored = #State.CriticalEvents,
            TransactionsStored = #State.Transactions,
            TransactionDataDiscarded = State.DataStats.TransactionDataDiscarded,
        },

        Transactions = State.Transactions,
        CriticalEvents = State.CriticalEvents,
        AutomationCandidates = buildAutomationCandidates(),
        ProgressionGraph = buildProgressionGraph(),
        Events = State.Events,
        Errors = State.Errors,
        Health = State.Health,
    }

    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(payload)
    end)

    if ok then
        return encoded
    end

    return "JSON ERROR: " .. tostring(encoded)
end

local function exportReport()
    local content = buildReport()
    local filename =
        "Tycoon_Purchase_Diagnostic_V2_3_3_" ..
        os.date("%Y%m%d_%H%M%S") ..
        ".txt"

    local saved = false
    local copied = false

    if type(writefile) == "function" then
        saved = pcall(function()
            writefile(filename, content)
        end)
    end

    if type(setclipboard) == "function" then
        copied = pcall(function()
            setclipboard(content)
        end)
    elseif type(toclipboard) == "function" then
        copied = pcall(function()
            toclipboard(content)
        end)
    end

    if saved then
        return true, "Relatorio salvo: " .. filename
    end

    if copied then
        return true, "Relatorio copiado."
    end

    return false, "writefile/clipboard indisponivel."
end

addConnection(UI.ReadToggle.MouseButton1Click, function()
    safeCall("READING_TOGGLE", function()
        setReading(not State.Reading)
    end)
end)

addConnection(UI.Export.MouseButton1Click, function()
    safeCall("EXPORT", function()
        local ok, message = exportReport()
        UI.Status.Text = message

        pushEvent(
            "SYSTEM",
            ok and "EXPORT_SUCCESS" or "EXPORT_UNAVAILABLE",
            {Message = message}
        )
    end)
end)

-- ============================================================
-- ENGINE START
-- ============================================================

safeCall("INITIAL_STATS", function()
    refreshStatsObjects()
    State.LastMoney = readValue(State.MoneyObject)
    State.LastRebirths = readValue(State.RebirthObject)
end)

safeCall("INITIAL_TYCOON", function()
    reconsiderTycoon()
end)

State.Health.Bootstrap = "OK"
State.Health.Engine = "ACTIVE"
State.Health.Reading = "PAUSED"

pushEvent("SYSTEM", "ENGINE_STARTED", {
    Version = VERSION,
})

task.spawn(function()
    while State.Running do
        safeCall("STAT_LOOP", function()
            refreshStatsObjects()

            local money = readValue(State.MoneyObject)
            local rebirths = readValue(State.RebirthObject)

            if State.MoneyObject and money ~= nil then
                State.Health.Money = "ACTIVE"
            else
                State.Health.Money = "SEARCHING"
            end

            if State.RebirthObject and rebirths ~= nil then
                State.Health.Rebirths = "ACTIVE"
            else
                State.Health.Rebirths = "SEARCHING"
            end

            if State.Reading
            and State.LastMoney ~= nil
            and money ~= nil
            and money ~= State.LastMoney then
                local delta = money - State.LastMoney

                pushEvent(
                    delta < 0 and "MONEY_SPEND" or "MONEY_INCOME",
                    "Money",
                    {
                        OldValue = State.LastMoney,
                        NewValue = money,
                        Delta = delta,
                        Direction = delta < 0 and "SPEND" or "INCOME",
                    }
                )

                correlateStatChanges(
                    State.LastMoney,
                    money,
                    State.LastRebirths,
                    rebirths
                )
            end

            if State.Reading
            and State.LastRebirths ~= nil
            and rebirths ~= nil
            and rebirths ~= State.LastRebirths then
                pushEvent("REBIRTH_CHANGE", "Rebirths", {
                    OldValue = State.LastRebirths,
                    NewValue = rebirths,
                    Delta = rebirths - State.LastRebirths,
                })

                correlateStatChanges(
                    State.LastMoney,
                    money,
                    State.LastRebirths,
                    rebirths
                )
            end

            if money ~= nil then
                State.LastMoney = money
            end

            if rebirths ~= nil then
                State.LastRebirths = rebirths
            end
        end)

        task.wait(MONEY_INTERVAL)
    end
end)

task.spawn(function()
    while State.Running do
        safeCall("TYCOON_LOOP", function()
            reconsiderTycoon()
        end)

        task.wait(TYCOON_INTERVAL)
    end
end)

task.spawn(function()
    while State.Running do
        safeCall("UI_LOOP", function()
            refreshUI()
        end)

        task.wait(0.5)
    end
end)

UI.Status.Text = "V2.3.3 pronta. Leitura PAUSADA. GUI=" .. tostring(UI.ParentKind)
safeCall("UI_INITIAL_REFRESH", function()
    refreshUI()
end)
