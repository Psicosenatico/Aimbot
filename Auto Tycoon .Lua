-[[
PSICOSENATICO - TYCOON PURCHASE AUTOMATOR - V1.7 + BUNKER TELEPORT + AUTOSAVE
COMPATIBILITY / STABILITY BUILD

Purchase automation + diagnostics - authorized teleport test build.
For the user's own authorized test environment, teleports the local character directly
onto ordinary MAIN_TYCOON purchase buttons instead of walking to them.
Does not alter Money/Rebirths or fake Marketplace receipts.
BUNKER transition remains the game's normal transition instead of long-distance teleport.
Auto-collect in this build uses the character's physical collector/totem interaction.
The character is moved directly to the local Tycoon collector; success is confirmed only if the observed wallet Money becomes greater than before.
When all current purchase targets are blocked by insufficient funds, Collector is rechecked continuously; every time it reaches at least 1000, collection is attempted again.
As soon as Money is sufficient for an available purchase, collection pauses and the purchase queue resumes.
Known ButtonPurchased/ButtonCannotPurchase server-to-client responses are still observed to avoid fixed multi-second waits.

Purchase classes:
- TYCOON_MONEY
- REBIRTH
- KILLS_OR_PREMIUM
- ROBUX_ONLY
- UNKNOWN

Context diagnostics:
- MAIN_TYCOON and BUNKER are tracked separately
- Floor progression 1/2/3 is tracked independently from Zone
- StageUnlocks groups newly observed buttons by progression floor
- Money discovery prefers leaderstats ValueBase, then Player/Tycoon, with PlayerGui as fallback
- Bunker-dependent purchases use MovementPolicy=USE_GAME_TRANSITION
- MAIN_TYCOON test purchases use direct local-character teleport to the button
- BUNKER enter/exit still uses the game's normal ProximityPrompt transition
- Character is teleported to the transition prompt instead of walking/pathing to it
- While inside BUNKER, eligible BUNKER purchases are exhausted before leaving
- Autosave checkpoints preserve already-read data on disconnect/kick when writefile is available

Automation policy:
- TYCOON_MONEY (including Price=0 structural buttons): eligible
- REBIRTH: eligible when requirement is satisfied
- KILLS_OR_PREMIUM: ignored
- ROBUX_ONLY: ignored
- UNKNOWN: ignored
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local VERSION = "AUTO-TP-1.7"
local GUI_NAME = "PsicoTycoonPurchaseAutomatorV1_7"

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

    CurrentZone = "UNKNOWN",
    ZoneEvidence = "not evaluated",
    MainFloor = 1,
    ZoneTransitions = {},
    FloorTransitions = {},
    StageUnlocks = {},
    StageUnlockSeen = {},
    LastTransitionPrompt = nil,
    WatchedTransitionPrompts = setmetatable({}, {__mode = "k"}),

    MoneyObject = nil,
    MoneySourceKind = nil,
    MoneySourceEvidence = nil,
    MoneyCandidates = {},
    LastMoneyDiscoveryClock = 0,
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
    ErrorRepeats = {},

    AutomationEnabled = false,
    AutomationState = "OFF",
    AutomationTarget = nil,
    AutomationTargetStarted = nil,
    AutomationAttempts = {},
    AutomationResets = {},
    AutomationCooldowns = {},
    AutomationBlockedFunds = {},
    AutomationServerSignal = nil,
    AutomationServerSignalSeq = 0,
        TotemCollectAttempts = {},
    TotemCollectSuccessful = 0,
    TotemCollectFailed = 0,
    LastTotemCollectClock = 0,
    IdleCollectChecks = 0,
    IdleCollectTriggers = 0,

    BunkerTransitions = {},
    BunkerSettleRescans = 0,

    AutoSaveCount = 0,
    AutoSaveLastUnix = nil,
    AutoSaveLastReason = nil,
    AutoSaveLastFile = nil,
    AutoSaveLastOk = nil,

    AutomationLastRebirth = nil,
    AutomationRunId = 0,
    AutomationSuccessful = 0,
    AutomationFailed = 0,

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
        Automation = "OFF",
        Zone = "UNKNOWN",
        Floor = "1",
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

    local suffix = string.upper(string.sub(text, -1))
    local multiplier = 1

    if suffix == "K" then
        multiplier = 1e3
        text = string.sub(text, 1, -2)
    elseif suffix == "M" then
        multiplier = 1e6
        text = string.sub(text, 1, -2)
    elseif suffix == "B" then
        multiplier = 1e9
        text = string.sub(text, 1, -2)
    elseif suffix == "T" then
        multiplier = 1e12
        text = string.sub(text, 1, -2)
    end

    local number = tonumber(text)
    if number == nil then
        return nil
    end

    return number * multiplier
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
    ZONE_CHANGED = true,
    FLOOR_CHANGED = true,
    TRANSITION_PROMPT = true,
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
    local message = tostring(err)
    local key = tostring(stage) .. "|" .. message
    local nowClock = os.clock()
    local repeatInfo = State.ErrorRepeats[key]

    if repeatInfo and (nowClock - repeatInfo.LastClock) < 2 then
        repeatInfo.Count = repeatInfo.Count + 1
        repeatInfo.LastClock = nowClock

        if UI.Status and UI.Status.Parent then
            UI.Status.Text =
                "Erro em " .. tostring(stage) .. ": " .. message ..
                " (repetido x" .. tostring(repeatInfo.Count) .. ")"
        end

        return
    end

    State.ErrorRepeats[key] = {
        Count = repeatInfo and (repeatInfo.Count + 1) or 1,
        LastClock = nowClock,
    }

    local item = {
        Time = clockText(),
        Elapsed = elapsed(),
        Stage = stage,
        Error = message,
        RepeatCount = State.ErrorRepeats[key].Count,
    }

    table.insert(State.Errors, item)
    pushEvent("ERROR", stage, {
        Error = message,
        RepeatCount = item.RepeatCount,
    })

    if UI.Status and UI.Status.Parent then
        UI.Status.Text = "Erro em " .. tostring(stage) .. ": " .. message
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
    version.Text = "AUTO V1.7 - bunker teleport + autosave"
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
    scroll.Size = UDim2.new(1, 0, 1, -230)
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
    readToggle.Position = UDim2.new(0, 0, 1, -122)
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


    local autoToggle = Instance.new("TextButton")
    autoToggle.Name = "AutoToggle"
    autoToggle.Position = UDim2.new(0, 0, 1, -80)
    autoToggle.Size = UDim2.new(1, 0, 0, 36)
    autoToggle.BackgroundColor3 = COLORS.Floating
    autoToggle.BorderSizePixel = 0
    autoToggle.Text = "Iniciar automacao de compras"
    autoToggle.TextColor3 = COLORS.Text
    autoToggle.Font = Enum.Font.GothamBold
    autoToggle.TextSize = 11
    autoToggle.ZIndex = 12
    autoToggle.Parent = body
    round(autoToggle, 8)

    local export = Instance.new("TextButton")
    export.Name = "Export"
    export.Position = UDim2.new(0, 0, 1, -38)
    export.Size = UDim2.new(1, 0, 0, 36)
    export.BackgroundColor3 = COLORS.Card
    export.BorderSizePixel = 0
    export.Text = "Exportar relatorio AUTO V1.7 (.txt)"
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
    floating.Text = "AUTO TP"
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
    UI.AutoToggle = autoToggle
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
        State.AutomationEnabled = false
        State.AutomationState = "OFF"
        State.Health.Automation = "OFF"
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
    warn("[Tycoon Automator V1.7] LocalPlayer indisponivel.")
    return
end

local guiOk, guiResult = pcall(createGui)

if not guiOk then
    warn("[Tycoon Automator V1.7] GUI ERROR: " .. tostring(guiResult))
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
    local info = {
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

    local dependency = tostring(info.Dependency or "")
    local name = tostring(info.Name or "")

    if string.find(normalize(dependency), "bunker", 1, true)
    or string.find(normalize(name), "bunker", 1, true) then
        info.Zone = "BUNKER"
        info.MovementPolicy = "USE_GAME_TRANSITION"
    else
        info.Zone = "MAIN_TYCOON"
        info.MovementPolicy = "NORMAL_LOCAL_ACCESS"
    end

    return info
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

    local dependency = tostring(info.Dependency or "")
    local name = tostring(info.Name or "")

    if string.find(normalize(dependency), "bunker", 1, true)
    or string.find(normalize(name), "bunker", 1, true) then
        info.Zone = "BUNKER"
        info.MovementPolicy = "USE_GAME_TRANSITION"
    else
        info.Zone = "MAIN_TYCOON"
        info.MovementPolicy = "NORMAL_LOCAL_ACCESS"
    end

    return info
end


local function textContains(value, needle)
    return string.find(normalize(value), normalize(needle), 1, true) ~= nil
end

local function inferLogicalZone(info)
    info = info or {}

    local name = tostring(info.Name or "")
    local dependency = tostring(info.Dependency or "")
    local path = tostring(info.Path or "")

    if textContains(name, "Bunker")
    or textContains(dependency, "Bunker")
    or textContains(path, ".Bunker") then
        return "BUNKER"
    end

    return "MAIN_TYCOON"
end

local function modelPosition(instance)
    if not instance or not instance.Parent then
        return nil
    end

    local ok, position = pcall(function()
        if instance:IsA("Model") then
            return instance:GetPivot().Position
        end

        if instance:IsA("BasePart") then
            return instance.Position
        end

        local part = instance:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end)

    if ok then
        return position
    end

    return nil
end


local function stageNumberFromDependency(dependency)
    local text = tostring(dependency or "")

    local direct = string.match(text, "[Ff]loor%s*(%d+)")
    if direct then
        return tonumber(direct)
    end

    return nil
end

local function recordStageUnlock(buttonInfo, reason)
    if not buttonInfo then
        return
    end

    local floor = stageNumberFromDependency(buttonInfo.Dependency)
        or tonumber(State.MainFloor)
        or 1

    local stageName = "Floor" .. tostring(floor)
    local name = tostring(buttonInfo.Name or "?")
    local seenKey = stageName .. "|" .. name

    if State.StageUnlockSeen[seenKey] then
        return
    end

    State.StageUnlockSeen[seenKey] = true

    local bucket = nil

    for _, item in ipairs(State.StageUnlocks) do
        if item.Stage == stageName then
            bucket = item
            break
        end
    end

    if not bucket then
        bucket = {
            Stage = stageName,
            Floor = floor,
            FirstObservedUnix = os.time(),
            FirstObservedElapsed = elapsed(),
            Buttons = {},
        }

        table.insert(State.StageUnlocks, bucket)
    end

    table.insert(bucket.Buttons, {
        Name = name,
        Path = buttonInfo.Path,
        Dependency = buttonInfo.Dependency,
        Zone = buttonInfo.Zone or inferLogicalZone(buttonInfo),
        Type = (buttonInfo.RequiredRebirths or buttonInfo.Rebirths)
            and "REBIRTH"
            or ((buttonInfo.Price or buttonInfo.Cost) and "TYCOON_MONEY" or "UNKNOWN"),
        Reason = reason or "BUTTON_AVAILABLE",
        ObservedUnix = os.time(),
        ObservedElapsed = elapsed(),
    })
end

local function detectMainFloor()
    if not State.PurchasesFolder then
        return State.MainFloor or 1, "Purchases folder unavailable"
    end

    if State.PurchasesFolder:FindFirstChild("Floor3") then
        return 3, "Floor3 exists in Purchases"
    end

    if State.PurchasesFolder:FindFirstChild("Floor2") then
        return 2, "Floor2 exists in Purchases"
    end

    return 1, "Floor2/Floor3 not yet purchased"
end

local function setMainFloor(newFloor, evidence)
    newFloor = tonumber(newFloor) or 1

    if State.MainFloor == newFloor then
        State.Health.Floor = tostring(newFloor)
        return
    end

    local previous = State.MainFloor
    State.MainFloor = newFloor
    State.Health.Floor = tostring(newFloor)

    local transition = {
        Time = clockText(),
        Unix = os.time(),
        Elapsed = elapsed(),
        From = previous,
        To = newFloor,
        Evidence = evidence,
    }

    table.insert(State.FloorTransitions, transition)

    if State.Reading then
        pushEvent("FLOOR_CHANGED", "Floor " .. tostring(newFloor), transition)
    end
end

local function setZone(newZone, evidence)
    newZone = tostring(newZone or "UNKNOWN")

    if State.CurrentZone == newZone then
        State.ZoneEvidence = evidence or State.ZoneEvidence
        State.Health.Zone = newZone
        return
    end

    local previous = State.CurrentZone
    State.CurrentZone = newZone
    State.ZoneEvidence = evidence or "no evidence"
    State.Health.Zone = newZone

    local transition = {
        Time = clockText(),
        Unix = os.time(),
        Elapsed = elapsed(),
        From = previous,
        To = newZone,
        Evidence = State.ZoneEvidence,
    }

    table.insert(State.ZoneTransitions, transition)

    if State.Reading then
        pushEvent("ZONE_CHANGED", newZone, transition)
    end
end

local function detectZoneByPosition()
    local character = State.Player and State.Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if not root then
        return "UNKNOWN", "HumanoidRootPart unavailable"
    end

    -- A recent legitimate Enter/Exit prompt is stronger evidence than raw distance.
    if State.LastTransitionPrompt then
        local age = os.clock() - (State.LastTransitionPrompt.Clock or 0)

        if age <= 8 then
            if State.LastTransitionPrompt.Direction == "ENTER_BUNKER" then
                return "BUNKER", "recent Bunker Enter prompt"
            elseif State.LastTransitionPrompt.Direction == "EXIT_BUNKER" then
                return "MAIN_TYCOON", "recent Bunker Exit prompt"
            end
        end
    end

    local nearestBunker = math.huge
    local nearestMain = math.huge

    local function inspectFolder(folder, isButtons)
        if not folder then
            return
        end

        local count = 0

        for _, child in ipairs(folder:GetChildren()) do
            count = count + 1
            if count > 120 then
                break
            end

            if child:IsA("Model") or child:IsA("Folder") then
                local info = isButtons
                    and (State.ButtonCache[child.Name] or describeButton(child))
                    or describePurchase(child)

                local position = modelPosition(child)

                if position then
                    local distance = (root.Position - position).Magnitude

                    if inferLogicalZone(info) == "BUNKER" then
                        if distance < nearestBunker then
                            nearestBunker = distance
                        end
                    else
                        if distance < nearestMain then
                            nearestMain = distance
                        end
                    end
                end
            end
        end
    end

    inspectFolder(State.ButtonsFolder, true)
    inspectFolder(State.PurchasesFolder, false)

    if nearestBunker <= 90 and nearestBunker < nearestMain then
        return "BUNKER",
            "nearest Bunker-related object=" .. tostring(math.floor(nearestBunker)) .. " studs"
    end

    if nearestMain <= 180 then
        return "MAIN_TYCOON",
            "nearest main Tycoon object=" .. tostring(math.floor(nearestMain)) .. " studs"
    end

    if nearestBunker <= 180 then
        return "BUNKER",
            "near Bunker-related objects=" .. tostring(math.floor(nearestBunker)) .. " studs"
    end

    return "OUTSIDE_TYCOON", "far from known Tycoon/Bunker purchase objects"
end

local function classifyTransitionPrompt(prompt)
    local action = normalize(prompt and prompt.ActionText)
    local object = normalize(prompt and prompt.ObjectText)
    local path = normalize(prompt and safeFullName(prompt))

    local bunkerEvidence =
        string.find(object, "bunker", 1, true)
        or string.find(path, "bunker", 1, true)

    if bunkerEvidence and string.find(action, "enter", 1, true) then
        return "ENTER_BUNKER"
    end

    if bunkerEvidence
    and (string.find(action, "exit", 1, true)
        or string.find(action, "leave", 1, true)
        or string.find(action, "return", 1, true)) then
        return "EXIT_BUNKER"
    end

    return nil
end

local function watchTransitionPrompts(instance)
    if not instance then
        return
    end

    local prompts = {}

    if instance:IsA("ProximityPrompt") then
        table.insert(prompts, instance)
    end

    for _, descendant in ipairs(instance:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") then
            table.insert(prompts, descendant)
        end
    end

    for _, prompt in ipairs(prompts) do
        if not State.WatchedTransitionPrompts[prompt] then
            local direction = classifyTransitionPrompt(prompt)

            if direction then
                State.WatchedTransitionPrompts[prompt] = true

                addConnection(prompt.Triggered, function(player)
                    if player ~= State.Player then
                        return
                    end

                    local item = {
                        Direction = direction,
                        Clock = os.clock(),
                        Time = clockText(),
                        Unix = os.time(),
                        Path = safeFullName(prompt),
                        ActionText = prompt.ActionText,
                        ObjectText = prompt.ObjectText,
                    }

                    State.LastTransitionPrompt = item

                    if direction == "ENTER_BUNKER" then
                        setZone("BUNKER", "Bunker Enter prompt triggered by LocalPlayer")
                    elseif direction == "EXIT_BUNKER" then
                        setZone("MAIN_TYCOON", "Bunker Exit prompt triggered by LocalPlayer")
                    end

                    if State.Reading then
                        pushEvent("TRANSITION_PROMPT", direction, item)
                    end
                end, State.TycoonConnections)
            end
        end
    end
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

    if price ~= nil then
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
    elseif price ~= nil and price >= 0 then
        classType = "TYCOON_MONEY"
        confidence = "high"
        score = price == 0 and 11 or 9
        eligible = true
        eligibilityReason = price == 0
            and "Eligible: free structural Tycoon purchase (Price=0)"
            or "Eligible: ordinary Tycoon-money purchase"
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

local MONEY_NAMES = {"Money", "Cash", "Coins", "Coin", "Currency", "Saldo"}


local function readValue(obj)
    if not obj or not obj.Parent then
        return nil
    end

    local ok, value = pcall(function()
        if obj:IsA("ValueBase") then
            return obj.Value
        end

        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            return obj.Text
        end

        return nil
    end)

    if not ok then
        return nil
    end

    return parseNumber(value)
end

local function moneyCandidateScore(instance, rootKind)
    if not instance or not instance.Parent then
        return nil
    end

    local isValue = instance:IsA("ValueBase")
    local isText = instance:IsA("TextLabel")
        or instance:IsA("TextButton")
        or instance:IsA("TextBox")

    if not isValue and not isText then
        return nil
    end

    local nameNorm = normalize(instance.Name)
    local nameMatches = containsAny(instance.Name, MONEY_NAMES)
    local value = readValue(instance)

    if value == nil then
        return nil
    end

    local score = 0
    local evidence = {}

    if nameNorm == "money" then
        score = score + 60
        table.insert(evidence, "exact name=Money")
    elseif nameMatches then
        score = score + 35
        table.insert(evidence, "money-like name")
    elseif isText then
        local text = tostring(instance.Text or "")
        if string.find(text, "$", 1, true) then
            score = score + 8
            table.insert(evidence, "HUD text contains $")
        else
            return nil
        end
    else
        return nil
    end

    if rootKind == "LEADERSTATS" then
        score = score + 100
        table.insert(evidence, "leaderstats")
    elseif rootKind == "PLAYER" then
        score = score + 55
        table.insert(evidence, "Player descendant")
    elseif rootKind == "TYCOON" then
        score = score + 45
        table.insert(evidence, "local Tycoon descendant")
    elseif rootKind == "PLAYERGUI" then
        score = score + 20
        table.insert(evidence, "PlayerGui display fallback")
    end

    if isValue then
        score = score + 25
        table.insert(evidence, "ValueBase")
    else
        table.insert(evidence, "GUI text fallback")
    end

    local pathNorm = normalize(safeFullName(instance))

    if string.find(pathNorm, "price", 1, true)
    or string.find(pathNorm, "cost", 1, true)
    or string.find(pathNorm, "button", 1, true)
    or string.find(pathNorm, "shop", 1, true) then
        score = score - 45
        table.insert(evidence, "penalty: shop/price-like path")
    end

    return score, value, evidence
end

local function discoverMoneySource()
    local candidates = {}
    local seen = setmetatable({}, {__mode = "k"})

    local function consider(instance, rootKind)
        if not instance or seen[instance] then
            return
        end

        seen[instance] = true

        local score, value, evidence = moneyCandidateScore(instance, rootKind)
        if score then
            table.insert(candidates, {
                Instance = instance,
                Path = safeFullName(instance),
                ClassName = instance.ClassName,
                RootKind = rootKind,
                Score = score,
                Value = value,
                Evidence = evidence,
            })
        end
    end

    local function scanRoot(root, rootKind, limit)
        if not root then
            return
        end

        consider(root, rootKind)

        local count = 0
        for _, descendant in ipairs(root:GetDescendants()) do
            count = count + 1
            if count > limit then
                break
            end
            consider(descendant, rootKind)
        end
    end

    local leaderstats = State.Player and State.Player:FindFirstChild("leaderstats")
    scanRoot(leaderstats, "LEADERSTATS", 100)

    if State.Player then
        for _, child in ipairs(State.Player:GetChildren()) do
            if child ~= leaderstats and child.Name ~= "PlayerGui" then
                scanRoot(child, "PLAYER", 600)
            end
        end
    end

    scanRoot(State.Tycoon, "TYCOON", 1200)

    local playerGui = State.Player and State.Player:FindFirstChild("PlayerGui")
    scanRoot(playerGui, "PLAYERGUI", 1200)

    table.sort(candidates, function(a, b)
        if a.Score == b.Score then
            return tostring(a.Path) < tostring(b.Path)
        end
        return a.Score > b.Score
    end)

    local exportCandidates = {}
    for index, candidate in ipairs(candidates) do
        if index > 20 then
            break
        end
        table.insert(exportCandidates, {
            Path = candidate.Path,
            ClassName = candidate.ClassName,
            RootKind = candidate.RootKind,
            Score = candidate.Score,
            Value = candidate.Value,
            Evidence = candidate.Evidence,
        })
    end

    State.MoneyCandidates = exportCandidates
    State.LastMoneyDiscoveryClock = os.clock()

    local best = candidates[1]
    if best then
        State.MoneySourceKind = best.RootKind
        State.MoneySourceEvidence = best.Evidence
        return best.Instance
    end

    State.MoneySourceKind = nil
    State.MoneySourceEvidence = {"no numeric money candidate found"}
    return nil
end

local function refreshStatsObjects()
    if not State.MoneyObject or not State.MoneyObject.Parent then
        State.MoneyObject = discoverMoneySource()
    elseif os.clock() - (State.LastMoneyDiscoveryClock or 0) >= 4 then
        -- Refresh the candidate inventory periodically, but keep a valid
        -- selected source unless a clearly stronger source is discovered.
        local current = State.MoneyObject
        local currentPath = safeFullName(current)
        local discovered = discoverMoneySource()

        if discovered then
            local currentEntry = nil
            local bestEntry = State.MoneyCandidates[1]

            for _, entry in ipairs(State.MoneyCandidates) do
                if entry.Path == currentPath then
                    currentEntry = entry
                    break
                end
            end

            if not currentEntry
            or (bestEntry and bestEntry.Score >= (currentEntry.Score or 0) + 20) then
                State.MoneyObject = discovered
            else
                State.MoneyObject = current
                State.MoneySourceKind = currentEntry.RootKind
                State.MoneySourceEvidence = currentEntry.Evidence
            end
        else
            State.MoneyObject = current
            State.MoneySourceKind = "PRESERVED"
            State.MoneySourceEvidence = {"previous valid source preserved; refresh found no stronger candidate"}
        end
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
        Zone = (pending.Button and pending.Button.Zone)
            or inferLogicalZone(pending.Button or pending.Purchase),
        MainFloorAtTransaction = State.MainFloor,
        MovementPolicy = (pending.Button and pending.Button.MovementPolicy)
            or (inferLogicalZone(pending.Button or pending.Purchase) == "BUNKER"
                and "USE_GAME_TRANSITION"
                or "NORMAL_LOCAL_ACCESS"),

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
    watchTransitionPrompts(button)

    if not State.Reading then
        return
    end

    recordStageUnlock(info, "BUTTON_AVAILABLE")

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

    watchTransitionPrompts(purchase)

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
                watchTransitionPrompts(button)
            end
        end
    end

    if State.PurchasesFolder then
        for _, purchase in ipairs(State.PurchasesFolder:GetChildren()) do
            if purchase:IsA("Model") or purchase:IsA("Folder") then
                table.insert(purchasesSnapshot, describePurchase(purchase))
                watchTransitionPrompts(purchase)
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
        " | Auto: " .. tostring(State.AutomationState) ..
        " | Zona: " .. tostring(State.CurrentZone) ..
        " | Andar: " .. tostring(State.MainFloor) ..
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

    if UI.AutoToggle and UI.AutoToggle.Parent then
        UI.AutoToggle.Text = State.AutomationEnabled
            and "Parar automacao de compras"
            or "Iniciar automacao de compras"

        UI.AutoToggle.BackgroundColor3 = State.AutomationEnabled
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
        " Zona:" .. tostring(State.Health.Zone) ..
        " Andar:" .. tostring(State.Health.Floor) ..
        " Money:" .. tostring(State.Health.Money) ..
        "(" .. tostring(State.MoneySourceKind or "?") .. ")" ..
        " Rebirth:" .. tostring(State.Health.Rebirths) ..
        " Auto:" .. tostring(State.Health.Automation) ..
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
                Zone = info.Zone or inferLogicalZone(info),
                MovementPolicy = info.MovementPolicy or
                    (inferLogicalZone(info) == "BUNKER"
                        and "USE_GAME_TRANSITION"
                        or "NORMAL_LOCAL_ACCESS"),
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
            StartedZone = State.CurrentZone,
            StartedFloor = State.MainFloor,
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
            State.CurrentReadingSession.StoppedZone = State.CurrentZone
            State.CurrentReadingSession.StoppedFloor = State.MainFloor
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


-- ============================================================
-- PURCHASE AUTOMATION V1.6.1
-- MAIN_TYCOON purchase targets and collector use direct local-character positioning.
-- No Money/Rebirth edits and no unknown purchase/collection remote invocation.
-- ============================================================

local AUTO_MOVE_TIMEOUT = 18
local AUTO_SERVER_WAIT = 1.35
local AUTO_RETRY_COOLDOWN = 2.5
local AUTO_IDLE_WAIT = 0.22
local AUTO_POST_RESULT_WAIT = 0.08
local AUTO_ARRIVE_DISTANCE = 5.5
local AUTO_COLLECT_MIN = 1000
local AUTO_COLLECT_CONFIRM_TIMEOUT = 4
local AUTO_COLLECT_RECHECK_INTERVAL = 0.30
local AUTO_COLLECT_MIN_GAP = 0.75
local BUNKER_TRANSITION_TIMEOUT = 5
local BUNKER_POST_PURCHASE_SETTLE = 0.30
local BUNKER_BEFORE_EXIT_RESCAN = 0.45
local AUTOSAVE_INTERVAL = 15

-- Forward declarations used by later runtime paths.
local autoRefreshFundsBlocks
local autoSaveReport

local function autoRecord(kind, details)
    details = details or {}
    details.AutomationState = State.AutomationState
    details.Target = State.AutomationTarget
    pushEvent("AUTOMATION", kind, details)
end

local function autoGetCharacter()
    local character = State.Player and State.Player.Character
    if not character then return nil, nil, nil end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    return character, humanoid, root
end

local function autoTargetPart(container)
    if not container then return nil end

    local touch = container:FindFirstChild("Touch", true)
    if touch and touch:IsA("BasePart") then
        return touch
    end

    if container:IsA("Model") and container.PrimaryPart then
        return container.PrimaryPart
    end

    return container:FindFirstChildWhichIsA("BasePart", true)
end

local function autoTeleportToPart(targetPart)
    local character, humanoid, root = autoGetCharacter()

    if not character or not humanoid or not root or humanoid.Health <= 0 then
        return false, "CHARACTER_UNAVAILABLE"
    end

    if not targetPart or not targetPart.Parent or not targetPart:IsA("BasePart") then
        return false, "TARGET_PART_UNAVAILABLE"
    end

    -- Test-only direct positioning. The server still decides whether the purchase is accepted.
    local destination = targetPart.CFrame * CFrame.new(0, 2.6, 0)

    local ok, err = pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        root.CFrame = destination
    end)

    if not ok then
        return false, "TELEPORT_FAILED:" .. tostring(err)
    end

    task.wait(0.12)

    if not root.Parent then
        return false, "CHARACTER_LOST"
    end

    local distance = (root.Position - targetPart.Position).Magnitude
    if distance <= 7 then
        return true, "TELEPORT_POSITION_CONFIRMED"
    end

    return false, "TELEPORT_NOT_CONFIRMED"
end




local function autoCollectorContainer()
    if not State.Tycoon then
        return nil
    end

    local direct = State.Tycoon:FindFirstChild("Collector", true)
    if direct then
        return direct
    end

    for _, descendant in ipairs(State.Tycoon:GetDescendants()) do
        if normalize(descendant.Name) == "collector" then
            return descendant
        end
    end

    return nil
end

local function autoCollectorAmount()
    local collector = autoCollectorContainer()
    if not collector then
        return nil, nil
    end

    for _, descendant in ipairs(collector:GetDescendants()) do
        if normalize(descendant.Name) == "money" then
            local value = readValue(descendant)
            if value ~= nil then
                return value, safeFullName(descendant)
            end
        end
    end

    return nil, nil
end

local function autoCollectorTouchPart()
    local collector = autoCollectorContainer()
    if not collector then
        return nil
    end

    -- Prefer a physical part that actually owns touch handling.
    for _, descendant in ipairs(collector:GetDescendants()) do
        if descendant:IsA("BasePart")
        and descendant:FindFirstChildWhichIsA("TouchTransmitter") then
            return descendant
        end
    end

    -- Then use common physical collector/totem part naming.
    local preferred = {
        "touch", "collect", "collector", "totem", "pad", "button", "claim"
    }

    for _, wanted in ipairs(preferred) do
        for _, descendant in ipairs(collector:GetDescendants()) do
            if descendant:IsA("BasePart") then
                local n = normalize(descendant.Name)
                if string.find(n, wanted, 1, true) then
                    return descendant
                end
            end
        end
    end

    if collector:IsA("BasePart") then
        return collector
    end

    return collector:FindFirstChildWhichIsA("BasePart", true)
end

local function autoTeleportToCollectorAndConfirm()
    local collectorBefore, collectorPath = autoCollectorAmount()
    local moneyBefore = State.LastMoney

    if collectorBefore == nil then
        return false, "COLLECTOR_AMOUNT_UNAVAILABLE"
    end

    if collectorBefore < AUTO_COLLECT_MIN then
        return false, "COLLECTOR_BELOW_THRESHOLD"
    end

    if moneyBefore == nil then
        return false, "MONEY_UNAVAILABLE"
    end

    local targetPart = autoCollectorTouchPart()
    if not targetPart then
        return false, "COLLECTOR_TOUCH_PART_NOT_FOUND"
    end

    local character, humanoid, root = autoGetCharacter()
    if not character or not humanoid or not root or humanoid.Health <= 0 then
        return false, "CHARACTER_UNAVAILABLE"
    end

    local attempt = {
        Id = #State.TotemCollectAttempts + 1,
        StartedUnix = os.time(),
        StartedElapsed = elapsed(),
        CollectorBefore = collectorBefore,
        CollectorPath = collectorPath,
        MoneyBefore = moneyBefore,
        TargetPart = safeFullName(targetPart),
        Result = "STARTED",
    }
    table.insert(State.TotemCollectAttempts, attempt)

    State.AutomationState = "COLLECTING_TOTEM"
    State.Health.Automation = "COLLECTING_TOTEM"
    State.LastTotemCollectClock = os.clock()

    autoRecord("TOTEM_COLLECT_STARTED", {
        CollectAttemptId = attempt.Id,
        CollectorBefore = collectorBefore,
        MoneyBefore = moneyBefore,
        TargetPart = attempt.TargetPart,
        Movement = "DIRECT_LOCAL_CHARACTER_TELEPORT",
    })

    local ok, teleportReason = autoTeleportToPart(targetPart)
    if not ok then
        attempt.Result = teleportReason or "TELEPORT_FAILED"
        attempt.FinishedUnix = os.time()
        attempt.FinishedElapsed = elapsed()
        State.TotemCollectFailed = State.TotemCollectFailed + 1

        autoRecord("TOTEM_COLLECT_FAILED", {
            CollectAttemptId = attempt.Id,
            Reason = attempt.Result,
        })

        return false, attempt.Result
    end

    -- Do not infer collection from collector text alone.
    -- Success requires the real observed wallet to become greater than its previous value.
    local deadline = os.clock() + AUTO_COLLECT_CONFIRM_TIMEOUT
    local highestMoney = moneyBefore

    while State.Running and State.AutomationEnabled and os.clock() < deadline do
        local currentMoney = State.LastMoney
        if currentMoney ~= nil then
            highestMoney = math.max(highestMoney, currentMoney)

            if currentMoney > moneyBefore then
                local collectorAfter = select(1, autoCollectorAmount())

                attempt.Result = "MONEY_INCREASE_CONFIRMED"
                attempt.MoneyAfter = currentMoney
                attempt.CollectorAfter = collectorAfter
                attempt.FinishedUnix = os.time()
                attempt.FinishedElapsed = elapsed()
                State.TotemCollectSuccessful = State.TotemCollectSuccessful + 1

                -- Do NOT globally clear every blocked purchase.
                -- Release only those whose price is now affordable.
                autoRefreshFundsBlocks()

                autoRecord("TOTEM_COLLECT_SUCCESS_CONFIRMED", {
                    CollectAttemptId = attempt.Id,
                    MoneyBefore = moneyBefore,
                    MoneyAfter = currentMoney,
                    MoneyDelta = currentMoney - moneyBefore,
                    CollectorBefore = collectorBefore,
                    CollectorAfter = collectorAfter,
                    Evidence = "REAL_WALLET_INCREASED",
                })

                return true, "MONEY_INCREASE_CONFIRMED"
            end
        end

        task.wait(0.03)
    end

    attempt.Result = "MONEY_DID_NOT_INCREASE"
    attempt.MoneyAfter = highestMoney
    attempt.CollectorAfter = select(1, autoCollectorAmount())
    attempt.FinishedUnix = os.time()
    attempt.FinishedElapsed = elapsed()
    State.TotemCollectFailed = State.TotemCollectFailed + 1

    autoRecord("TOTEM_COLLECT_FAILED", {
        CollectAttemptId = attempt.Id,
        Reason = "MONEY_DID_NOT_INCREASE",
        MoneyBefore = moneyBefore,
        MoneyAfter = highestMoney,
        CollectorBefore = collectorBefore,
        CollectorAfter = attempt.CollectorAfter,
    })

    return false, "MONEY_DID_NOT_INCREASE"
end

local function autoBindServerResponseSignals()
    local remotes = ReplicatedStorage:FindFirstChild("__remotes")
    local tycoonService = remotes and remotes:FindFirstChild("TycoonService")
    if not tycoonService then
        return
    end

    local purchased = tycoonService:FindFirstChild("ButtonPurchased")
    local rejected = tycoonService:FindFirstChild("ButtonCannotPurchase")

    local function bind(remote, status)
        if not remote or not remote:IsA("RemoteEvent") then
            return
        end

        addConnection(remote.OnClientEvent, function(...)
            if not State.AutomationEnabled or not State.AutomationTarget then
                return
            end

            State.AutomationServerSignalSeq = State.AutomationServerSignalSeq + 1
            State.AutomationServerSignal = {
                Seq = State.AutomationServerSignalSeq,
                Clock = os.clock(),
                Status = status,
                Remote = safeFullName(remote),
                Target = State.AutomationTarget,
                ArgsCount = select("#", ...),
            }

            autoRecord("SERVER_PURCHASE_RESPONSE_OBSERVED", {
                Status = status,
                Remote = safeFullName(remote),
                Target = State.AutomationTarget,
                SignalSeq = State.AutomationServerSignalSeq,
            })
        end)
    end

    bind(purchased, "ACCEPTED")
    bind(rejected, "REJECTED")
end

local function autoWaitForAcceptance(buttonName, originalButton, timeout)
    timeout = timeout or AUTO_SERVER_WAIT
    local started = os.clock()
    local startSeq = State.AutomationServerSignalSeq

    while State.Running and State.AutomationEnabled and os.clock() - started <= timeout do
        local signal = State.AutomationServerSignal

        if signal
        and signal.Seq > startSeq
        and signal.Target == buttonName then
            if signal.Status == "ACCEPTED" then
                return true, "SERVER_BUTTON_PURCHASED"
            elseif signal.Status == "REJECTED" then
                return false, "SERVER_BUTTON_CANNOT_PURCHASE"
            end
        end

        local buttonGone = not originalButton or not originalButton.Parent
        local purchaseExists = State.PurchasesFolder
            and State.PurchasesFolder:FindFirstChild(buttonName) ~= nil

        if buttonGone or purchaseExists then
            return true, buttonGone and "BUTTON_REMOVED" or "PURCHASE_CREATED"
        end

        task.wait(0.03)
    end

    return false, "NO_ACCEPTANCE_OBSERVED"
end


local function autoFindBunkerTransitionPrompt(actionNeedle)
    if not State.PurchasesFolder then return nil end

    local bunker = State.PurchasesFolder:FindFirstChild("Bunker")
    if not bunker then return nil end

    local fallback = nil

    for _, descendant in ipairs(bunker:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") then
            fallback = fallback or descendant

            if actionNeedle
            and textContains(descendant.ActionText, actionNeedle) then
                return descendant
            end
        end
    end

    return fallback
end

local function autoPromptPart(prompt)
    if not prompt then return nil end
    local current = prompt.Parent

    while current and current ~= workspace do
        if current:IsA("BasePart") then
            return current
        end
        current = current.Parent
    end

    return nil
end

local function autoUseBunkerTransition(targetZone)
    targetZone = targetZone == "BUNKER" and "BUNKER" or "MAIN_TYCOON"

    if State.CurrentZone == targetZone then
        return true, "ALREADY_IN_TARGET_ZONE"
    end

    local entering = targetZone == "BUNKER"
    local actionNeedle = entering and "enter" or "exit"
    local stateName = entering and "ENTERING_BUNKER" or "EXITING_BUNKER"

    State.AutomationState = stateName
    State.Health.Automation = stateName

    local prompt = autoFindBunkerTransitionPrompt(actionNeedle)
    if not prompt then
        autoRecord("BUNKER_TRANSITION_PROMPT_NOT_FOUND", {
            TargetZone = targetZone,
            ExpectedAction = actionNeedle,
        })
        return false, "BUNKER_TRANSITION_PROMPT_NOT_FOUND"
    end

    local part = autoPromptPart(prompt)
    if not part then
        autoRecord("BUNKER_TRANSITION_PART_NOT_FOUND", {
            TargetZone = targetZone,
            Prompt = safeFullName(prompt),
        })
        return false, "BUNKER_TRANSITION_PART_NOT_FOUND"
    end

    -- Transition positioning is direct: no Humanoid:MoveTo/path walking.
    local positioned, positionReason = autoTeleportToPart(part)
    if not positioned then
        autoRecord("BUNKER_TRANSITION_TELEPORT_FAILED", {
            TargetZone = targetZone,
            Prompt = safeFullName(prompt),
            TargetPart = safeFullName(part),
            Reason = positionReason,
        })
        return false, positionReason
    end

    local transition = {
        Id = #State.BunkerTransitions + 1,
        StartedUnix = os.time(),
        StartedElapsed = elapsed(),
        FromZone = State.CurrentZone,
        TargetZone = targetZone,
        Prompt = safeFullName(prompt),
        TargetPart = safeFullName(part),
        ActionText = prompt.ActionText,
        HoldDuration = prompt.HoldDuration,
        PositionEvidence = positionReason,
        Result = "STARTED",
    }
    table.insert(State.BunkerTransitions, transition)

    autoRecord(entering and "BUNKER_ENTER_PROMPT_ATTEMPT" or "BUNKER_EXIT_PROMPT_ATTEMPT", {
        TransitionId = transition.Id,
        Prompt = transition.Prompt,
        TargetPart = transition.TargetPart,
        ActionText = transition.ActionText,
        HoldDuration = transition.HoldDuration,
        PositionEvidence = positionReason,
    })

    local triggered = pcall(function()
        prompt:InputHoldBegin()
        task.wait(math.max(0.1, tonumber(prompt.HoldDuration) or 0) + 0.12)
        prompt:InputHoldEnd()
    end)

    if not triggered then
        transition.Result = "PROMPT_TRIGGER_FAILED"
        transition.FinishedUnix = os.time()
        transition.FinishedElapsed = elapsed()

        autoRecord("BUNKER_TRANSITION_PROMPT_FAILED", {
            TransitionId = transition.Id,
            TargetZone = targetZone,
            Prompt = transition.Prompt,
        })
        return false, "PROMPT_TRIGGER_FAILED"
    end

    local deadline = os.clock() + BUNKER_TRANSITION_TIMEOUT
    while State.Running and State.AutomationEnabled and os.clock() < deadline do
        if State.CurrentZone == targetZone then
            transition.Result = "ZONE_CONFIRMED"
            transition.FinishedUnix = os.time()
            transition.FinishedElapsed = elapsed()

            autoRecord(entering and "BUNKER_ENTERED_CONFIRMED" or "BUNKER_EXITED_CONFIRMED", {
                TransitionId = transition.Id,
                FromZone = transition.FromZone,
                ToZone = targetZone,
                Prompt = transition.Prompt,
            })

            return true, entering and "BUNKER_ENTERED" or "BUNKER_EXITED"
        end

        task.wait(0.05)
    end

    transition.Result = "ZONE_NOT_CONFIRMED"
    transition.FinishedUnix = os.time()
    transition.FinishedElapsed = elapsed()

    autoRecord("BUNKER_TRANSITION_NOT_CONFIRMED", {
        TransitionId = transition.Id,
        FromZone = transition.FromZone,
        TargetZone = targetZone,
        CurrentZone = State.CurrentZone,
    })

    return false, "BUNKER_TRANSITION_NOT_CONFIRMED"
end

local function autoEnterBunker()
    return autoUseBunkerTransition("BUNKER")
end

local function autoExitBunker()
    return autoUseBunkerTransition("MAIN_TYCOON")
end

local function autoEffectiveZone(record)
    if normalize(record.Name) == "bunker"
    and (record.Dependency == nil or tostring(record.Dependency) == "") then
        return "MAIN_TYCOON"
    end
    return record.Zone or "MAIN_TYCOON"
end

local function autoCandidateScore(record)
    local score = 100
    local effectiveZone = autoEffectiveZone(record)
    local price = parseNumber(record.Price)
    local required = parseNumber(record.Rebirths)

    if effectiveZone == State.CurrentZone then score = score - 35 end
    if effectiveZone == "MAIN_TYCOON" then score = score - 15 end
    if price ~= nil and price == 0 then score = score - 35 end

    -- Rebirth purchases do not consume Money and should not be starved by
    -- repeatedly rejected ordinary-money buttons.
    if record.Type == "REBIRTH" then
        score = score - 40
    elseif record.Type == "TYCOON_MONEY" then
        if price ~= nil and State.LastMoney ~= nil and State.LastMoney >= price then
            score = score - 30
        else
            score = score - 5
        end
    end

    if required then score = score + required * 0.001 end
    if price then score = score + math.min(price, 9999999) * 0.0000001 end

    return score
end

autoRefreshFundsBlocks = function()
    local money = State.LastMoney

    for key, block in pairs(State.AutomationBlockedFunds) do
        if not block then
            State.AutomationBlockedFunds[key] = nil
        else
            local requiredPrice = tonumber(block.Price)
            if money ~= nil and requiredPrice ~= nil and money >= requiredPrice then
                State.AutomationBlockedFunds[key] = nil
                autoRecord("FUNDS_BLOCK_RELEASED", {
                    Key = key,
                    Name = block.Name,
                    Price = requiredPrice,
                    Money = money,
                    Reason = "BALANCE_NOW_SUFFICIENT",
                })
            end
        end
    end
end


local function autoBlockedFundsSummary()
    local count = 0
    local cheapestPrice = nil
    local cheapestName = nil

    for key, block in pairs(State.AutomationBlockedFunds) do
        if block then
            local price = tonumber(block.Price)
            count = count + 1

            if price ~= nil and (cheapestPrice == nil or price < cheapestPrice) then
                cheapestPrice = price
                cheapestName = block.Name
            end
        end
    end

    return count, cheapestPrice, cheapestName
end

local function autoShouldIdleCollect()
    autoRefreshFundsBlocks()

    local blockedCount, cheapestBlockedPrice, cheapestBlockedName = autoBlockedFundsSummary()
    if blockedCount <= 0 then
        return false, "NO_BLOCKED_FUNDS_PURCHASES"
    end

    local money = State.LastMoney
    if money == nil then
        return false, "MONEY_UNAVAILABLE"
    end

    -- If any blocked purchase is now affordable, let normal candidate selection buy it.
    if cheapestBlockedPrice ~= nil and money >= cheapestBlockedPrice then
        return false, "PURCHASE_NOW_AFFORDABLE"
    end

    local collectorAmount, collectorPath = autoCollectorAmount()
    State.IdleCollectChecks = State.IdleCollectChecks + 1

    if collectorAmount == nil then
        return false, "COLLECTOR_UNAVAILABLE", {
            BlockedCount = blockedCount,
            CheapestBlockedPrice = cheapestBlockedPrice,
            CheapestBlockedName = cheapestBlockedName,
            Money = money,
        }
    end

    if collectorAmount < AUTO_COLLECT_MIN then
        return false, "COLLECTOR_BELOW_THRESHOLD", {
            BlockedCount = blockedCount,
            CheapestBlockedPrice = cheapestBlockedPrice,
            CheapestBlockedName = cheapestBlockedName,
            Money = money,
            CollectorAmount = collectorAmount,
            CollectorPath = collectorPath,
        }
    end

    if os.clock() - (State.LastTotemCollectClock or 0) < AUTO_COLLECT_MIN_GAP then
        return false, "COLLECT_GAP_ACTIVE"
    end

    return true, "BLOCKED_PURCHASES_AND_COLLECTOR_READY", {
        BlockedCount = blockedCount,
        CheapestBlockedPrice = cheapestBlockedPrice,
        CheapestBlockedName = cheapestBlockedName,
        Money = money,
        CollectorAmount = collectorAmount,
        CollectorPath = collectorPath,
    }
end

local function autoTryContinuousIdleCollect()
    local shouldCollect, reason, details = autoShouldIdleCollect()

    if not shouldCollect then
        return false, reason
    end

    State.IdleCollectTriggers = State.IdleCollectTriggers + 1

    autoRecord("CONTINUOUS_COLLECT_TRIGGERED", {
        Reason = reason,
        BlockedCount = details and details.BlockedCount,
        CheapestBlockedPrice = details and details.CheapestBlockedPrice,
        CheapestBlockedName = details and details.CheapestBlockedName,
        Money = details and details.Money,
        CollectorAmount = details and details.CollectorAmount,
        CollectorPath = details and details.CollectorPath,
        Threshold = AUTO_COLLECT_MIN,
    })

    local collected, collectReason = autoTeleportToCollectorAndConfirm()

    if collected then
        autoRefreshFundsBlocks()

        local _, cheapestAfter, cheapestNameAfter = autoBlockedFundsSummary()
        autoRecord("CONTINUOUS_COLLECT_CYCLE_COMPLETE", {
            Result = collectReason,
            Money = State.LastMoney,
            CheapestBlockedPrice = cheapestAfter,
            CheapestBlockedName = cheapestNameAfter,
            NextAction = cheapestAfter and State.LastMoney and State.LastMoney >= cheapestAfter
                and "RESUME_PURCHASES"
                or "WAIT_FOR_COLLECTOR_1000",
        })

        return true, collectReason
    end

    autoRecord("CONTINUOUS_COLLECT_CYCLE_FAILED", {
        Reason = collectReason,
    })

    return false, collectReason
end

local function autoSelectCandidate()
    autoRefreshFundsBlocks()

    local candidates = buildAutomationCandidates().Eligible
    local now = os.clock()
    local filtered = {}

    for _, record in ipairs(candidates) do
        local key = record.Path or record.Name
        local cooldownUntil = State.AutomationCooldowns[key] or 0
        local fundsBlocked = State.AutomationBlockedFunds[key] ~= nil

        if now >= cooldownUntil and not fundsBlocked then
            table.insert(filtered, record)
        end
    end

    table.sort(filtered, function(a, b)
        local sa = autoCandidateScore(a)
        local sb = autoCandidateScore(b)
        if sa == sb then
            return tostring(a.Name) < tostring(b.Name)
        end
        return sa < sb
    end)

    return filtered[1]
end


local function autoSelectCandidateInZone(zone)
    autoRefreshFundsBlocks()

    local candidates = buildAutomationCandidates().Eligible
    local filtered = {}
    local now = os.clock()

    for _, record in ipairs(candidates) do
        local key = record.Path or record.Name
        local blockedByFunds = State.AutomationBlockedFunds[key] ~= nil
        local cooldownUntil = State.AutomationCooldowns[key]

        if autoEffectiveZone(record) == zone
        and not blockedByFunds
        and (not cooldownUntil or now >= cooldownUntil) then
            table.insert(filtered, record)
        end
    end

    table.sort(filtered, function(a, b)
        local sa = autoCandidateScore(a)
        local sb = autoCandidateScore(b)
        if sa == sb then
            return tostring(a.Name) < tostring(b.Name)
        end
        return sa < sb
    end)

    return filtered[1]
end


local function autoFindButton(record)
    if not State.ButtonsFolder or not record then return nil end

    local direct = State.ButtonsFolder:FindFirstChild(record.Name)
    if direct then return direct end

    for _, child in ipairs(State.ButtonsFolder:GetChildren()) do
        if safeFullName(child) == record.Path then
            return child
        end
    end

    return nil
end

local function autoAttemptPurchase(record)
    if not record then return false, "NO_TARGET" end

    local button = autoFindButton(record)
    if not button or not button.Parent then
        return false, "BUTTON_GONE_BEFORE_ATTEMPT"
    end

    local effectiveZone = autoEffectiveZone(record)

    if effectiveZone == "BUNKER" and State.CurrentZone ~= "BUNKER" then
        local entered, reason = autoEnterBunker()
        if not entered then
            return false, reason
        end
    elseif effectiveZone == "MAIN_TYCOON" and State.CurrentZone == "BUNKER" then
        local exited, reason = autoExitBunker()
        if not exited then
            return false, reason
        end
    end

    -- Reacquire after a zone transition because replication may replace references.
    button = autoFindButton(record)
    if not button or not button.Parent then
        return false, "BUTTON_GONE_AFTER_ZONE_TRANSITION"
    end

    local targetPart = autoTargetPart(button)
    if not targetPart then
        return false, "TOUCH_PART_NOT_FOUND"
    end

    State.AutomationState = "TELEPORTING"
    State.Health.Automation = "TELEPORTING"
    State.AutomationTarget = record.Name
    State.AutomationTargetStarted = os.clock()

    local attempt = {
        Id = #State.AutomationAttempts + 1,
        RunId = State.AutomationRunId,
        Name = record.Name,
        Path = record.Path,
        Type = record.Type,
        Zone = record.Zone,
        EffectiveZone = effectiveZone,
        StartedUnix = os.time(),
        StartedElapsed = elapsed(),
        MoneyBefore = State.LastMoney,
        RebirthsBefore = State.LastRebirths,
        FloorBefore = State.MainFloor,
        ZoneBefore = State.CurrentZone,
        Result = "STARTED",
    }
    table.insert(State.AutomationAttempts, attempt)

    autoRecord("PURCHASE_ATTEMPT_STARTED", {
        AttemptId = attempt.Id,
        Name = record.Name,
        Type = record.Type,
        Zone = effectiveZone,
        Price = record.Price,
        Rebirths = record.Rebirths,
    })

    local teleported, teleportReason = autoTeleportToPart(targetPart)
    if not teleported then
        attempt.Result = "TELEPORT_FAILED"
        attempt.Reason = teleportReason
        attempt.FinishedUnix = os.time()
        State.AutomationFailed = State.AutomationFailed + 1
        State.AutomationCooldowns[record.Path or record.Name] = os.clock() + AUTO_RETRY_COOLDOWN

        autoRecord("PURCHASE_ATTEMPT_FAILED", {
            AttemptId = attempt.Id,
            Name = record.Name,
            Stage = "TELEPORT",
            Reason = teleportReason,
        })
        return false, teleportReason
    end

    attempt.TeleportEvidence = teleportReason
    autoRecord("PURCHASE_TARGET_TELEPORTED", {
        AttemptId = attempt.Id,
        Name = record.Name,
        TargetPart = safeFullName(targetPart),
        Evidence = teleportReason,
    })

    State.AutomationState = "WAIT_SERVER"
    State.Health.Automation = "WAIT_SERVER"

    local accepted, acceptanceReason = autoWaitForAcceptance(record.Name, button, AUTO_SERVER_WAIT)

    attempt.FinishedUnix = os.time()
    attempt.FinishedElapsed = elapsed()
    attempt.MoneyAfter = State.LastMoney
    attempt.RebirthsAfter = State.LastRebirths
    attempt.FloorAfter = State.MainFloor
    attempt.ZoneAfter = State.CurrentZone
    attempt.AcceptanceEvidence = acceptanceReason

    if accepted then
        attempt.Result = "ACCEPTED_OBSERVED"
        State.AutomationSuccessful = State.AutomationSuccessful + 1
        State.AutomationCooldowns[record.Path or record.Name] = nil

        autoRecord("PURCHASE_ACCEPTED_OBSERVED", {
            AttemptId = attempt.Id,
            Name = record.Name,
            Evidence = acceptanceReason,
            MoneyBefore = attempt.MoneyBefore,
            MoneyAfter = attempt.MoneyAfter,
            RebirthsBefore = attempt.RebirthsBefore,
            RebirthsAfter = attempt.RebirthsAfter,
        })

        if effectiveZone == "BUNKER" then
            task.wait(BUNKER_POST_PURCHASE_SETTLE)
        else
            task.wait(AUTO_POST_RESULT_WAIT)
        end
        return true, acceptanceReason
    end

    attempt.Result = "NO_ACCEPTANCE_OBSERVED"
    State.AutomationFailed = State.AutomationFailed + 1
    State.AutomationCooldowns[record.Path or record.Name] = os.clock() + AUTO_RETRY_COOLDOWN

    local declaredPrice = parseNumber(record.Price)
    local insufficientBalanceInferred =
        record.Type == "TYCOON_MONEY"
        and declaredPrice ~= nil
        and State.LastMoney ~= nil
        and State.LastMoney < declaredPrice

    autoRecord("PURCHASE_NOT_ACCEPTED_OBSERVED", {
        AttemptId = attempt.Id,
        Name = record.Name,
        Reason = acceptanceReason,
        DeclaredPrice = declaredPrice,
        MoneyObserved = State.LastMoney,
        InsufficientBalanceInferred = insufficientBalanceInferred,
        Note = "No client-visible button removal/purchase creation was observed; exact server internal reason is unknown.",
    })

    if insufficientBalanceInferred then
        local blockKey = record.Path or record.Name
        State.AutomationBlockedFunds[blockKey] = {
            Name = record.Name,
            Path = record.Path,
            Price = declaredPrice,
            MoneyAtBlock = State.LastMoney,
            BlockedUnix = os.time(),
            BlockedElapsed = elapsed(),
            Reason = "PURCHASE_REJECTED_WHILE_MONEY_BELOW_PRICE",
        }

        autoRecord("FUNDS_BLOCK_SAVED", {
            Name = record.Name,
            Path = record.Path,
            Price = declaredPrice,
            Money = State.LastMoney,
            Reason = "DO_NOT_RETRY_UNTIL_BALANCE_SUFFICIENT_OR_COLLECTION_SUCCEEDS",
        })

        local collectorAmount, collectorPath = autoCollectorAmount()

        autoRecord("AUTO_COLLECT_CHECK", {
            AttemptId = attempt.Id,
            PurchaseTarget = record.Name,
            CollectorAmount = collectorAmount,
            CollectorPath = collectorPath,
            Threshold = AUTO_COLLECT_MIN,
            Trigger = "PURCHASE_REJECTED_AND_LOCAL_MONEY_BELOW_DECLARED_PRICE",
        })

        if collectorAmount ~= nil and collectorAmount >= AUTO_COLLECT_MIN then
            local collected, collectReason = autoTeleportToCollectorAndConfirm()

            if collected then
                autoRefreshFundsBlocks()
                task.wait(AUTO_POST_RESULT_WAIT)
                return false, "TOTEM_COLLECTED_AFTER_INSUFFICIENT_BALANCE"
            else
                return false, "AUTO_COLLECT_FAILED:" .. tostring(collectReason)
            end
        end
    end

    return false, acceptanceReason
end

local function autoHandleRebirth(oldValue, newValue)
    State.AutomationState = "RESETTING"
    State.Health.Automation = "RESETTING"
    State.AutomationTarget = nil
    State.AutomationTargetStarted = nil
    State.AutomationCooldowns = {}
    State.AutomationBlockedFunds = {}
    State.AutomationServerSignal = nil
    State.Pending = {}

    local reset = {
        Id = #State.AutomationResets + 1,
        Unix = os.time(),
        Elapsed = elapsed(),
        OldRebirths = oldValue,
        NewRebirths = newValue,
        Money = State.LastMoney,
        FloorBeforeRefresh = State.MainFloor,
        ZoneBeforeRefresh = State.CurrentZone,
    }
    table.insert(State.AutomationResets, reset)

    autoRecord("REBIRTH_RESET_DETECTED", reset)

    if autoSaveReport then
        task.defer(function()
            autoSaveReport("REBIRTH_DETECTED", true)
        end)
    end

    task.wait(0.8)

    reconsiderTycoon()
    scanInitial()

    local floor, floorEvidence = detectMainFloor()
    setMainFloor(floor, "automation reset refresh: " .. tostring(floorEvidence))

    local zone, zoneEvidence = detectZoneByPosition()
    setZone(zone, "automation reset refresh: " .. tostring(zoneEvidence))

    reset.FloorAfterRefresh = State.MainFloor
    reset.ZoneAfterRefresh = State.CurrentZone
    reset.ButtonsAfterRefresh = State.ButtonsFolder and #State.ButtonsFolder:GetChildren() or 0
    reset.PurchasesAfterRefresh = State.PurchasesFolder and #State.PurchasesFolder:GetChildren() or 0

    autoRecord("REBIRTH_RESET_RESCANNED", reset)
end

local function setAutomation(enabled)
    enabled = enabled and true or false
    if State.AutomationEnabled == enabled then return end

    if enabled then
        if not State.Reading then
            setReading(true)
        end

        State.AutomationEnabled = true
        State.AutomationRunId = State.AutomationRunId + 1
        State.AutomationState = "SCANNING"
        State.Health.Automation = "ACTIVE"
        State.AutomationTarget = nil
        State.AutomationCooldowns = {}
        -- Preserve insufficient-funds memory across OFF/ON toggles.
        -- Rebirth reset remains the place that clears this table.
        autoRefreshFundsBlocks()
        State.AutomationServerSignal = nil
        State.AutomationLastRebirth = State.LastRebirths

        autoRecord("AUTOMATION_STARTED", {
            RunId = State.AutomationRunId,
            Money = State.LastMoney,
            Rebirths = State.LastRebirths,
            Floor = State.MainFloor,
            Zone = State.CurrentZone,
            Policy = "Continuous cycle: rejected insufficient-money buttons remain blocked; when no purchase can be made, Collector is checked continuously and collected at >=1000; purchases resume immediately once Money is enough for an available target.",
        })
    else
        autoRecord("AUTOMATION_STOPPED", {
            RunId = State.AutomationRunId,
            Successful = State.AutomationSuccessful,
            Failed = State.AutomationFailed,
            Target = State.AutomationTarget,
        })

        State.AutomationEnabled = false
        State.AutomationState = "OFF"
        State.Health.Automation = "OFF"
        State.AutomationTarget = nil
        State.AutomationTargetStarted = nil
    end

    safeCall("AUTOMATION_UI_REFRESH", refreshUI)
end

autoBindServerResponseSignals()

task.spawn(function()
    while State.Running do
        if State.AutomationEnabled then
            safeCall("AUTOMATION_LOOP", function()
                local currentRebirth = State.LastRebirths

                if State.AutomationLastRebirth ~= nil
                and currentRebirth ~= nil
                and currentRebirth > State.AutomationLastRebirth then
                    autoHandleRebirth(State.AutomationLastRebirth, currentRebirth)
                end

                if currentRebirth ~= nil then
                    State.AutomationLastRebirth = currentRebirth
                end

                if not State.Tycoon or not State.ButtonsFolder or not State.PurchasesFolder then
                    State.AutomationState = "WAIT_TYCOON"
                    State.Health.Automation = "WAIT_TYCOON"
                    reconsiderTycoon()
                    task.wait(AUTO_IDLE_WAIT)
                    return
                end

                State.AutomationState = "SCANNING"
                State.Health.Automation = "ACTIVE"

                local target

                if State.CurrentZone == "BUNKER" then
                    -- Do not leave immediately after a BUNKER purchase.
                    -- First exhaust currently eligible BUNKER targets, then wait once
                    -- for replication and check again before selecting a MAIN target.
                    target = autoSelectCandidateInZone("BUNKER")

                    if not target then
                        State.BunkerSettleRescans = State.BunkerSettleRescans + 1
                        autoRecord("BUNKER_PRE_EXIT_RESCAN", {
                            Rescan = State.BunkerSettleRescans,
                            Wait = BUNKER_BEFORE_EXIT_RESCAN,
                        })
                        task.wait(BUNKER_BEFORE_EXIT_RESCAN)
                        target = autoSelectCandidateInZone("BUNKER")
                    end
                end

                if not target then
                    target = autoSelectCandidate()
                end

                if not target then
                    State.AutomationState = "WAITING_FOR_FUNDS"
                    State.Health.Automation = "WAITING_FOR_FUNDS"

                    local collected = autoTryContinuousIdleCollect()
                    if collected then
                        State.AutomationState = "SCANNING"
                        State.Health.Automation = "ACTIVE"
                        task.wait(AUTO_POST_RESULT_WAIT)
                    else
                        task.wait(AUTO_COLLECT_RECHECK_INTERVAL)
                    end
                    return
                end

                autoAttemptPurchase(target)
                State.AutomationTarget = nil
                State.AutomationTargetStarted = nil
            end)
        end

        task.wait(State.AutomationEnabled and 0.18 or 0.5)
    end
end)


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
        Report = "Tycoon Purchase Automator + Diagnostic",
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

        EconomySources = {
            SelectedMoneyPath = State.MoneyObject and safeFullName(State.MoneyObject) or nil,
            SelectedMoneyKind = State.MoneySourceKind,
            SelectedMoneyEvidence = State.MoneySourceEvidence,
            MoneyCandidates = State.MoneyCandidates,
            Note = "ValueBase sources are preferred. PlayerGui text is fallback evidence only.",
        },

        Context = {
            CurrentZone = State.CurrentZone,
            ZoneEvidence = State.ZoneEvidence,
            MainFloor = State.MainFloor,
            ZoneTransitions = State.ZoneTransitions,
            FloorTransitions = State.FloorTransitions,
            StageUnlocks = State.StageUnlocks,
            MovementSafetyPolicy = {
                Bunker = "USE_GAME_TRANSITION_ONLY",
                MainTycoonDirectTeleport = "TEST_ENABLED",
                LongDistanceBunkerTeleport = "DO_NOT_USE",
                Reason = "Bunker is a separate progression zone; direct long-distance movement can conflict with the game's movement correction.",
            },
        },

        InitialButtons = State.InitialButtons,
        InitialPurchases = State.InitialPurchases,
        ReadingActive = State.Reading,
        ReadingSessions = State.ReadingSessions,

        Automation = {
            Enabled = State.AutomationEnabled,
            State = State.AutomationState,
            RunId = State.AutomationRunId,
            CurrentTarget = State.AutomationTarget,
            SuccessfulAttempts = State.AutomationSuccessful,
            FailedAttempts = State.AutomationFailed,
            TotemCollectAttempts = State.TotemCollectAttempts,
            TotemCollectSuccessful = State.TotemCollectSuccessful,
            TotemCollectFailed = State.TotemCollectFailed,
            IdleCollectChecks = State.IdleCollectChecks,
            IdleCollectTriggers = State.IdleCollectTriggers,
            BunkerTransitions = State.BunkerTransitions,
            BunkerSettleRescans = State.BunkerSettleRescans,
            FundsBlocked = State.AutomationBlockedFunds,
            Attempts = State.AutomationAttempts,
            RebirthResets = State.AutomationResets,
            Policy = {
                PurchaseInteraction = "DIRECT_LOCAL_CHARACTER_TELEPORT_TO_TOUCH_BUTTON_TEST",
                AutoCollectTrigger = "AFTER_REJECTED_TYCOON_MONEY_WHEN_LOCAL_MONEY_BELOW_PRICE_AND_COLLECTOR_AT_LEAST_1000",
                AutoCollectConfirmation = "REAL_WALLET_MONEY_MUST_INCREASE",
                InsufficientFundsMemory = "KEEP_BLOCKED_UNTIL_OBSERVED_MONEY_AT_LEAST_PRICE",
                ContinuousCollectorPolling = true,
                ContinuousCollectorThreshold = 1000,
                CollectorPollingOnlyWhenNoPurchaseCandidate = true,
                AutoCollectMovement = "DIRECT_LOCAL_CHARACTER_TELEPORT_TO_COLLECTOR",
                AutoCollectEndpoint = "PHYSICAL_TOTEM_TOUCH_BY_CHARACTER",
                AutoCollectDirectRemoteInvocation = false,
                AutoCollectUnknownGameRemoteInvocation = false,
                AutoCollectServerMutation = "OBSERVED_ONLY",
                AutoCollectSimulationOnly = false,
                BunkerTransition = "NORMAL_PROXIMITY_PROMPT_WITH_DIRECT_POSITIONING_TO_PROMPT",
                BunkerPurchaseMovement = "DIRECT_LOCAL_CHARACTER_TELEPORT_TO_BUNKER_BUTTON",
                BunkerExitPolicy = "EXHAUST_ELIGIBLE_BUNKER_TARGETS_THEN_PROMPT_EXIT",
                DirectTeleport = true,
                DirectTeleportScope = "AUTHORIZED_TEST_PURCHASE_BUTTONS_COLLECTOR_AND_BUNKER_PROMPT_POSITIONING",
                MoneyBypass = false,
                RebirthBypass = false,
                MarketplaceBypass = false,
                ServerObservation = "Button removal / purchase creation / stat changes are client-visible evidence only.",
            },
        },

        AutoSave = {
            Count = State.AutoSaveCount,
            LastUnix = State.AutoSaveLastUnix,
            LastReason = State.AutoSaveLastReason,
            LastFile = State.AutoSaveLastFile,
            LastOk = State.AutoSaveLastOk,
            IntervalSeconds = AUTOSAVE_INTERVAL,
            DisconnectWatch = "BEST_EFFORT_GUI_ERROR_AND_ERROR_PROMPT",
        },

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
        ErrorRepeats = State.ErrorRepeats,
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


local function sanitizeSaveReason(reason)
    reason = tostring(reason or "UNKNOWN"):upper()
    reason = reason:gsub("[^%w_%-]", "_")
    return string.sub(reason, 1, 48)
end

autoSaveReport = function(reason, timestamped)
    reason = sanitizeSaveReason(reason)

    if type(writefile) ~= "function" then
        State.AutoSaveLastOk = false
        State.AutoSaveLastReason = reason
        return false, "WRITEFILE_UNAVAILABLE"
    end

    State.AutoSaveCount = State.AutoSaveCount + 1
    State.AutoSaveLastUnix = os.time()
    State.AutoSaveLastReason = reason

    local filename
    if timestamped then
        filename =
            "Tycoon_Purchase_Automator_V1_7_AutoSave_" ..
            reason .. "_" ..
            os.date("%Y%m%d_%H%M%S") ..
            ".txt"
    else
        filename = "Tycoon_Purchase_Automator_V1_7_AutoSave_Latest.txt"
    end

    State.AutoSaveLastFile = filename
    State.AutoSaveLastOk = nil

    local content = buildReport()
    local ok, err = pcall(function()
        writefile(filename, content)
    end)

    State.AutoSaveLastOk = ok

    if ok then
        return true, filename
    end

    return false, tostring(err)
end

local function installDisconnectAutoSave()
    -- Best effort: Roblox may tear down the client quickly after a network loss/kick.
    -- Periodic checkpoints below remain the fallback if the final signal arrives too late.

    pcall(function()
        addConnection(GuiService.ErrorMessageChanged:Connect(function(message)
            if tostring(message or "") ~= "" then
                task.defer(function()
                    autoSaveReport("GUI_ERROR_DISCONNECT_OR_KICK", true)
                end)
            end
        end))
    end)

    pcall(function()
        local robloxPromptGui = CoreGui:FindFirstChild("RobloxPromptGui")
        local overlay = robloxPromptGui and robloxPromptGui:FindFirstChild("promptOverlay")

        if overlay then
            addConnection(overlay.ChildAdded:Connect(function(child)
                local n = normalize(child.Name)

                if string.find(n, "error", 1, true)
                or string.find(n, "disconnect", 1, true)
                or string.find(n, "kick", 1, true) then
                    task.defer(function()
                        autoSaveReport("ROBLOX_ERROR_PROMPT", true)
                    end)
                end
            end))
        end
    end)
end

task.spawn(function()
    while State.Running do
        task.wait(AUTOSAVE_INTERVAL)

        if State.Running and State.Reading then
            autoSaveReport("PERIODIC_CHECKPOINT", false)
        end
    end
end)

installDisconnectAutoSave()

local function exportReport()
    local content = buildReport()
    local filename =
        "Tycoon_Purchase_Automator_V1_7_BunkerTeleport_AutoSave_" ..
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

addConnection(UI.AutoToggle.MouseButton1Click, function()
    safeCall("AUTOMATION_TOGGLE", function()
        setAutomation(not State.AutomationEnabled)
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

    local floor, floorEvidence = detectMainFloor()
    setMainFloor(floor, floorEvidence)

    local zone, zoneEvidence = detectZoneByPosition()
    setZone(zone, zoneEvidence)
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

            local floor, floorEvidence = detectMainFloor()
            setMainFloor(floor, floorEvidence)

            local zone, zoneEvidence = detectZoneByPosition()
            setZone(zone, zoneEvidence)
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

UI.Status.Text = "AUTO V1.7 pronta. Leitura PAUSADA. Automacao OFF. GUI=" .. tostring(UI.ParentKind)
safeCall("UI_INITIAL_REFRESH", function()
    refreshUI()
end)
