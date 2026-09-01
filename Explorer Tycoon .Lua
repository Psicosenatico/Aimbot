
    PSICOSENATICO • TYCOON PURCHASE DIAGNOSTIC • V2.1
    SOMENTE DIAGNÓSTICO / OBSERVAÇÃO CLIENT-SIDE

    CLASSIFICAÇÕES:
        TYCOON_MONEY
        REBIRTH
        ROBUX
        UNKNOWN

    OBJETIVOS:
    - Identificar com mais segurança o Tycoon do jogador local.
    - Observar Buttons e Purchases do Tycoon correto.
    - Classificar cada compra por evidências reais.
    - Registrar Price, Rebirths, Owner, LinkedPurchases.
    - Registrar mudanças reais de Money.
    - Registrar novos botões desbloqueados.
    - Detectar sinais de MarketplaceService sem tentar comprar nada.
    - Produzir relatório .txt/JSON.
    - Ter bootstrap protegido e painel de saúde.
    - Interface responsiva, arrastável e compatível com touch.
    - Botão minimizar + botão flutuante azul-escuro arrastável.

    IMPORTANTE:
    - NÃO realiza compras.
    - NÃO dispara RemoteEvents/RemoteFunctions.
    - NÃO tenta contornar preço, saldo, renascimento ou Robux.
    - NÃO altera valores do jogo.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local CONFIG = {
    VERSION = "2.1",
    GUI_NAME = "PsicoTycoonPurchaseDiagnosticV21",

    MAX_EVENTS = 1500,
    MONEY_SAMPLE_INTERVAL = 0.25,
    TYCOON_RESCAN_INTERVAL = 1.5,
    HEALTH_INTERVAL = 1.0,

    CORRELATION_WINDOW = 4.0,
    UNLOCK_WINDOW = 3.5,

    MIN_DRAG_DISTANCE = 8,

    COLORS = {
        Background = Color3.fromRGB(18, 23, 31),
        Header = Color3.fromRGB(24, 31, 43),
        Card = Color3.fromRGB(29, 37, 51),
        Card2 = Color3.fromRGB(14, 19, 27),
        Accent = Color3.fromRGB(83, 226, 169),
        Text = Color3.fromRGB(238, 242, 250),
        Muted = Color3.fromRGB(160, 171, 190),
        Danger = Color3.fromRGB(86, 43, 48),
        Floating = Color3.fromRGB(18, 49, 88),
    }
}

local State = {
    Running = true,
    StartedAtUnix = os.time(),
    StartedAtClock = os.clock(),

    LocalPlayer = nil,

    Tycoon = nil,
    TycoonPath = nil,
    TycoonConfidence = 0,
    ButtonsFolder = nil,
    PurchasesFolder = nil,

    MoneyObject = nil,
    LastMoney = nil,
    MoneyHistory = {},

    Events = {},
    Transactions = {},
    InitialButtons = {},
    InitialPurchases = {},

    ButtonSnapshots = {},
    Pending = {},

    Connections = {},
    TycoonConnections = {},

    Errors = {},
    Health = {
        Bootstrap = "STARTING",
        UI = "STARTING",
        Tycoon = "SEARCHING",
        Money = "SEARCHING",
        EventEngine = "STARTING",
        LastMoneyTick = 0,
        LastTycoonTick = 0,
        LastUiTick = 0,
    },

    Minimized = false,
}

local GUI = {}

local function nowClock()
    return os.clock()
end

local function elapsed()
    return math.floor((os.clock() - State.StartedAtClock) * 1000) / 1000
end

local function stamp()
    return os.date("%H:%M:%S")
end

local function normalize(v)
    return string.lower(tostring(v or "")):gsub("[%s_%-%./]", "")
end

local function safeString(v)
    local ok, result = pcall(function()
        return tostring(v)
    end)
    return ok and result or "<erro>"
end

local function safeFullName(inst)
    if not inst then
        return "<nil>"
    end
    local ok, result = pcall(function()
        return inst:GetFullName()
    end)
    return ok and result or "<detached>"
end

local function recordError(stage, err)
    local entry = {
        Time = stamp(),
        Elapsed = elapsed(),
        Stage = stage,
        Error = tostring(err),
    }
    table.insert(State.Errors, entry)

    table.insert(State.Events, {
        Time = stamp(),
        Unix = os.time(),
        Elapsed = elapsed(),
        Kind = "ERROR",
        Label = stage,
        Details = {Error = tostring(err)},
    })

    while #State.Events > CONFIG.MAX_EVENTS do
        table.remove(State.Events, 1)
    end

    return entry
end

local function protected(stage, fn, ...)
    local args = table.pack(...)
    local results

    local ok, err = xpcall(function()
        results = table.pack(fn(table.unpack(args, 1, args.n)))
    end, function(message)
        return debug.traceback(tostring(message), 2)
    end)

    if not ok then
        recordError(stage, err)
        return false, err
    end

    return true, table.unpack(results, 1, results.n)
end

local function connect(signal, callback, bucket)
    local target = bucket or State.Connections

    local ok, connection = pcall(function()
        return signal:Connect(function(...)
            local args = table.pack(...)
            local success, err = xpcall(function()
                callback(table.unpack(args, 1, args.n))
            end, function(message)
                return debug.traceback(tostring(message), 2)
            end)

            if not success then
                recordError("ConnectionCallback", err)
            end
        end)
    end)

    if ok and connection then
        table.insert(target, connection)
        return connection
    end

    if not ok then
        recordError("Connect", connection)
    end

    return nil
end

local function disconnectList(list)
    local copy = {}
    for _, c in ipairs(list) do
        table.insert(copy, c)
    end
    table.clear(list)

    for _, c in ipairs(copy) do
        pcall(function()
            c:Disconnect()
        end)
    end
end

local function event(kind, label, details)
    local entry = {
        Time = stamp(),
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
    for k, v in pairs(attrs) do
        out[tostring(k)] = safeString(v)
    end
    return out
end

local function getAttributeCI(inst, wanted)
    local target = normalize(wanted)
    for k, v in pairs(getAttributesSafe(inst)) do
        if normalize(k) == target then
            return v
        end
    end
    return nil
end

local function parseNumber(v)
    if v == nil then
        return nil
    end

    if type(v) == "number" then
        return v
    end

    local s = tostring(v)
    s = s:gsub(",", "")
    s = s:gsub("%s", "")
    s = s:gsub("R%$", "")
    s = s:gsub("%$", "")

    return tonumber(s)
end

local function containsText(value, candidates)
    local n = normalize(value)

    for _, candidate in ipairs(candidates) do
        if string.find(n, normalize(candidate), 1, true) then
            return true
        end
    end

    return false
end

local function ownerMatchesLocal(owner)
    local player = State.LocalPlayer
    if not player or owner == nil then
        return false
    end

    local s = tostring(owner)

    return s == player.Name
        or s == tostring(player.UserId)
        or normalize(s) == normalize(player.Name)
end

local function describeButton(model)
    if not model then
        return nil
    end

    return {
        Name = model.Name,
        Path = safeFullName(model),
        Price = getAttributeCI(model, "Price"),
        Cost = getAttributeCI(model, "Cost"),
        Owner = getAttributeCI(model, "Owner"),
        Rebirths = getAttributeCI(model, "Rebirths"),
        RequiredRebirths = getAttributeCI(model, "RequiredRebirths"),
        LinkedPurchases = getAttributeCI(model, "LinkedPurchases"),
        ProductId = getAttributeCI(model, "ProductId"),
        DeveloperProductId = getAttributeCI(model, "DeveloperProductId"),
        GamePassId = getAttributeCI(model, "GamePassId"),
        Robux = getAttributeCI(model, "Robux"),
        Attributes = getAttributesSafe(model),
        HasTouch = model:FindFirstChild("Touch", true) ~= nil,
        HasTouchInterest = model:FindFirstChildWhichIsA("TouchTransmitter", true) ~= nil,
        HasPrompt = model:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil,
    }
end

local function describePurchase(model)
    if not model then
        return nil
    end

    local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)

    local info = {
        Name = model.Name,
        Path = safeFullName(model),
        Owner = getAttributeCI(model, "Owner"),
        Rebirths = getAttributeCI(model, "Rebirths"),
        LinkedPurchases = getAttributeCI(model, "LinkedPurchases"),
        ProductId = getAttributeCI(model, "ProductId"),
        GamePassId = getAttributeCI(model, "GamePassId"),
        Attributes = getAttributesSafe(model),
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

local function classifyPurchase(buttonInfo, purchaseInfo)
    local evidence = {}
    local score = {
        TYCOON_MONEY = 0,
        REBIRTH = 0,
        ROBUX = 0,
    }

    local function add(kind, points, message)
        score[kind] += points
        table.insert(evidence, {
            Type = kind,
            Weight = points,
            Evidence = message,
        })
    end

    local b = buttonInfo or {}
    local p = purchaseInfo or {}

    local price = parseNumber(b.Price or b.Cost)
    local rebirth = parseNumber(b.RequiredRebirths or b.Rebirths)

    if price and price > 0 then
        add("TYCOON_MONEY", 5, "Atributo Price/Cost numérico encontrado: " .. tostring(price))
    end

    if rebirth and rebirth > 0 then
        add("REBIRTH", 8, "Atributo Rebirths/RequiredRebirths encontrado: " .. tostring(rebirth))
    end

    local robuxIds = {
        b.ProductId,
        b.DeveloperProductId,
        b.GamePassId,
        p.ProductId,
        p.GamePassId,
    }

    for _, id in ipairs(robuxIds) do
        if parseNumber(id) then
            add("ROBUX", 10, "ID de Marketplace encontrado: " .. tostring(id))
        end
    end

    if parseNumber(b.Robux) then
        add("ROBUX", 8, "Atributo Robux encontrado: " .. tostring(b.Robux))
    end

    local combinedName = tostring(b.Name or p.Name or "")
    if containsText(combinedName, {"robux", "gamepass", "developerproduct", "product"}) then
        add("ROBUX", 2, "Nome sugere compra via Marketplace")
    end

    if containsText(combinedName, {"rebirth", "renascimento"}) and rebirth then
        add("REBIRTH", 2, "Nome + requisito de renascimento")
    end

    local bestType = "UNKNOWN"
    local bestScore = 0

    for kind, value in pairs(score) do
        if value > bestScore then
            bestScore = value
            bestType = kind
        end
    end

    local confidence
    if bestScore >= 10 then
        confidence = "high"
    elseif bestScore >= 5 then
        confidence = "medium"
    elseif bestScore > 0 then
        confidence = "low"
    else
        confidence = "unknown"
    end

    return {
        Type = bestType,
        Confidence = confidence,
        Score = bestScore,
        Evidence = evidence,
    }
end

local function scoreTycoon(candidate)
    if not candidate then
        return -100, {}
    end

    if not candidate:IsA("Model") and not candidate:IsA("Folder") then
        return -100, {}
    end

    local score = 0
    local evidence = {}

    local function add(points, message)
        score += points
        table.insert(evidence, message)
    end

    local buttons = candidate:FindFirstChild("Buttons")
    local purchases = candidate:FindFirstChild("Purchases")

    if buttons then
        add(2, "possui Buttons")
    end

    if purchases then
        add(2, "possui Purchases")
    end

    if not buttons or not purchases then
        return score, evidence
    end

    local owner = getAttributeCI(candidate, "Owner")
    if ownerMatchesLocal(owner) then
        add(100, "Owner do Tycoon corresponde ao jogador")
    end

    for _, folder in ipairs({buttons, purchases}) do
        local checked = 0

        for _, child in ipairs(folder:GetChildren()) do
            checked += 1
            local childOwner = getAttributeCI(child, "Owner")

            if ownerMatchesLocal(childOwner) then
                add(40, "Owner de item interno corresponde ao jogador")
                break
            end

            if checked >= 50 then
                break
            end
        end
    end

    return score, evidence
end

local function findLocalTycoon()
    local tycoons = workspace:FindFirstChild("Tycoons")
    if not tycoons then
        return nil, 0, {}
    end

    local best
    local bestScore = -1
    local bestEvidence = {}

    for _, candidate in ipairs(tycoons:GetChildren()) do
        local score, evidence = scoreTycoon(candidate)

        if score > bestScore then
            best = candidate
            bestScore = score
            bestEvidence = evidence
        end
    end

    -- Estrutura sozinha vale 4. Exigimos evidência real de ownership.
    if best and bestScore >= 40 then
        return best, bestScore, bestEvidence
    end

    return nil, bestScore, bestEvidence
end

local function findMoneyObject()
    local player = State.LocalPlayer
    if not player then
        return nil
    end

    local names = {"Money", "Cash", "Coins", "Coin", "Currency", "Saldo"}
    local leaderstats = player:FindFirstChild("leaderstats")

    if leaderstats then
        for _, name in ipairs(names) do
            local obj = leaderstats:FindFirstChild(name)
            if obj and obj:IsA("ValueBase") then
                return obj
            end
        end

        for _, child in ipairs(leaderstats:GetChildren()) do
            if child:IsA("ValueBase")
            and containsText(child.Name, {"money", "cash", "coin", "saldo"}) then
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

local function pushMoneySample(value)
    table.insert(State.MoneyHistory, {
        Clock = nowClock(),
        Elapsed = elapsed(),
        Value = value,
    })

    while #State.MoneyHistory > 50 do
        table.remove(State.MoneyHistory, 1)
    end
end

local function getButtonsSet()
    local set = {}
    if not State.ButtonsFolder then
        return set
    end

    for _, child in ipairs(State.ButtonsFolder:GetChildren()) do
        set[child.Name] = true
    end
    return set
end

local function ensurePending(name)
    local pending = State.Pending[name]

    if not pending then
        pending = {
            Name = name,
            CreatedAtClock = nowClock(),
            ButtonRemovedAt = nil,
            PurchaseCreatedAt = nil,
            Button = nil,
            Purchase = nil,
            Classification = nil,
            Unlocks = {},
            MoneyBefore = nil,
            MoneyAfter = nil,
            ActualMoneyDelta = nil,
            Completed = false,
        }
        State.Pending[name] = pending
    end

    return pending
end

local function finalizeTransaction(name)
    local pending = State.Pending[name]
    if not pending or pending.Completed then
        return
    end

    pending.Classification = classifyPurchase(pending.Button, pending.Purchase)

    local typeName = pending.Classification.Type

    if typeName == "TYCOON_MONEY"
    and pending.MoneyBefore ~= nil
    and pending.MoneyAfter ~= nil then
        pending.ActualMoneyDelta = pending.MoneyAfter - pending.MoneyBefore
    end

    local record = {
        Id = #State.Transactions + 1,
        Name = name,
        Time = stamp(),
        Elapsed = elapsed(),

        Classification = pending.Classification,

        Button = pending.Button,
        Purchase = pending.Purchase,

        MoneyBefore = pending.MoneyBefore,
        MoneyAfter = pending.MoneyAfter,
        ActualMoneyDelta = pending.ActualMoneyDelta,

        DeclaredPrice = pending.Button and (pending.Button.Price or pending.Button.Cost) or nil,
        RequiredRebirths = pending.Button and (pending.Button.RequiredRebirths or pending.Button.Rebirths) or nil,
        LinkedPurchases = pending.Button and pending.Button.LinkedPurchases or nil,

        UnlockedButtons = pending.Unlocks,

        Evidence = {
            ButtonRemovedAt = pending.ButtonRemovedAt,
            PurchaseCreatedAt = pending.PurchaseCreatedAt,
        }
    }

    table.insert(State.Transactions, record)
    pending.Completed = true

    event("TRANSACTION_FINALIZED", name, record)
end

local function captureUnlocks(name, baseline)
    task.spawn(function()
        local seen = {}
        local endAt = nowClock() + CONFIG.UNLOCK_WINDOW

        while State.Running and nowClock() < endAt do
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
        for buttonName in pairs(seen) do
            table.insert(list, buttonName)
        end
        table.sort(list)

        pending.Unlocks = list

        if #list > 0 then
            event("BUTTONS_UNLOCKED", name, {
                UnlockedButtons = list,
            })
        end

        finalizeTransaction(name)
    end)
end

local function onButtonAdded(button)
    if not button:IsA("Model") and not button:IsA("Folder") then
        return
    end

    local info = describeButton(button)
    State.ButtonSnapshots[button.Name] = info

    event("BUTTON_AVAILABLE", button.Name, {
        Button = info,
        Classification = classifyPurchase(info, nil),
    })

    for _, attr in ipairs({
        "Price",
        "Cost",
        "Owner",
        "Rebirths",
        "RequiredRebirths",
        "LinkedPurchases",
        "ProductId",
        "DeveloperProductId",
        "GamePassId",
        "Robux",
    }) do
        connect(button:GetAttributeChangedSignal(attr), function()
            local updated = describeButton(button)
            State.ButtonSnapshots[button.Name] = updated

            event("BUTTON_ATTRIBUTE_CHANGED", button.Name, {
                Attribute = attr,
                Button = updated,
                Classification = classifyPurchase(updated, nil),
            })
        end, State.TycoonConnections)
    end
end

local function onButtonRemoved(button)
    local name = button.Name
    local snapshot = State.ButtonSnapshots[name] or describeButton(button)

    local pending = ensurePending(name)
    pending.ButtonRemovedAt = nowClock()
    pending.Button = snapshot
    pending.MoneyBefore = State.LastMoney

    local baseline = getButtonsSet()

    event("BUTTON_REMOVED", name, {
        Button = snapshot,
        MoneyBefore = pending.MoneyBefore,
        Classification = classifyPurchase(snapshot, nil),
    })

    State.ButtonSnapshots[name] = nil

    captureUnlocks(name, baseline)
end

local function onPurchaseAdded(purchase)
    if not purchase:IsA("Model") and not purchase:IsA("Folder") then
        return
    end

    local name = purchase.Name
    local info = describePurchase(purchase)
    local pending = ensurePending(name)

    pending.PurchaseCreatedAt = nowClock()
    pending.Purchase = info

    event("PURCHASE_CREATED", name, {
        Purchase = info,
        Classification = classifyPurchase(pending.Button, info),
    })

    -- Não finalizamos imediatamente, pois queremos capturar unlocks e Money.
end

local function correlateMoneyChange(oldValue, newValue)
    event("MONEY_CHANGE", "Money alterado", {
        OldValue = oldValue,
        NewValue = newValue,
        Delta = newValue - oldValue,
        Path = State.MoneyObject and safeFullName(State.MoneyObject) or nil,
    })

    local nowC = nowClock()
    local bestName
    local bestTime = -math.huge

    for name, pending in pairs(State.Pending) do
        if not pending.Completed then
            local candidateTime = pending.PurchaseCreatedAt or pending.ButtonRemovedAt

            if candidateTime
            and nowC - candidateTime <= CONFIG.CORRELATION_WINDOW
            and candidateTime > bestTime then
                bestTime = candidateTime
                bestName = name
            end
        end
    end

    if not bestName then
        return
    end

    local pending = State.Pending[bestName]
    pending.MoneyBefore = pending.MoneyBefore or oldValue
    pending.MoneyAfter = newValue
    pending.ActualMoneyDelta = newValue - pending.MoneyBefore

    event("MONEY_CORRELATED", bestName, {
        MoneyBefore = pending.MoneyBefore,
        MoneyAfter = pending.MoneyAfter,
        Delta = pending.ActualMoneyDelta,
    })
end

local function scanInitialState()
    table.clear(State.InitialButtons)
    table.clear(State.InitialPurchases)
    table.clear(State.ButtonSnapshots)

    if State.ButtonsFolder then
        for _, child in ipairs(State.ButtonsFolder:GetChildren()) do
            if child:IsA("Model") or child:IsA("Folder") then
                local info = describeButton(child)
                table.insert(State.InitialButtons, info)
                State.ButtonSnapshots[child.Name] = info
            end
        end
    end

    if State.PurchasesFolder then
        for _, child in ipairs(State.PurchasesFolder:GetChildren()) do
            if child:IsA("Model") or child:IsA("Folder") then
                table.insert(State.InitialPurchases, describePurchase(child))
            end
        end
    end

    event("INITIAL_STATE", "Estado inicial capturado", {
        Buttons = #State.InitialButtons,
        Purchases = #State.InitialPurchases,
    })
end

local function bindTycoon(tycoon, confidence, evidence)
    if State.Tycoon == tycoon and State.ButtonsFolder and State.PurchasesFolder then
        State.TycoonConfidence = confidence or State.TycoonConfidence
        return true
    end

    disconnectList(State.TycoonConnections)

    State.Tycoon = tycoon
    State.TycoonPath = tycoon and safeFullName(tycoon) or nil
    State.TycoonConfidence = confidence or 0

    State.ButtonsFolder = tycoon and tycoon:FindFirstChild("Buttons") or nil
    State.PurchasesFolder = tycoon and tycoon:FindFirstChild("Purchases") or nil

    if not State.Tycoon or not State.ButtonsFolder or not State.PurchasesFolder then
        State.Health.Tycoon = "SEARCHING"
        return false
    end

    scanInitialState()

    connect(State.ButtonsFolder.ChildAdded, onButtonAdded, State.TycoonConnections)
    connect(State.ButtonsFolder.ChildRemoved, onButtonRemoved, State.TycoonConnections)
    connect(State.PurchasesFolder.ChildAdded, onPurchaseAdded, State.TycoonConnections)

    State.Health.Tycoon = "CONFIRMED"

    event("TYCOON_BOUND", "Tycoon do jogador identificado", {
        Path = State.TycoonPath,
        Confidence = State.TycoonConfidence,
        Evidence = evidence,
    })

    return true
end

local function reconsiderTycoon()
    State.Health.LastTycoonTick = elapsed()

    local found, confidence, evidence = findLocalTycoon()

    if found then
        if found ~= State.Tycoon or confidence > State.TycoonConfidence then
            bindTycoon(found, confidence, evidence)
        else
            State.Health.Tycoon = "CONFIRMED"
        end
    else
        State.Health.Tycoon = "SEARCHING"
    end
end

local function serializeReport()
    local payload = {
        Report = "Tycoon Purchase Diagnostic",
        Version = CONFIG.VERSION,

        PlaceId = game.PlaceId,
        JobId = game.JobId,

        StartedAtUnix = State.StartedAtUnix,
        FinishedAtUnix = os.time(),

        Player = State.LocalPlayer and {
            Name = State.LocalPlayer.Name,
            UserId = State.LocalPlayer.UserId,
        } or nil,

        Tycoon = {
            Path = State.TycoonPath,
            Confidence = State.TycoonConfidence,
        },

        MoneyPath = State.MoneyObject and safeFullName(State.MoneyObject) or nil,

        InitialButtons = State.InitialButtons,
        InitialPurchases = State.InitialPurchases,

        Transactions = State.Transactions,
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

    return "Falha ao gerar JSON: " .. tostring(encoded)
end

local function exportReport()
    local content = serializeReport()
    local filename =
        "Tycoon_Purchase_Diagnostic_V2_1_" ..
        os.date("%Y%m%d_%H%M%S") ..
        ".txt"

    local saved = false
    local copied = false
    local errMessage

    if typeof(writefile) == "function" then
        local ok, err = pcall(function()
            writefile(filename, content)
        end)
        saved = ok
        if not ok then
            errMessage = err
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
        return true, "Relatório copiado."
    end

    return false, "Exportação indisponível."
        .. (errMessage and (" Erro: " .. tostring(errMessage)) or "")
end

local function rounded(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
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

local function clampFrameToScreen(frame)
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end

    local viewport = camera.ViewportSize
    local absoluteSize = frame.AbsoluteSize
    local absolutePosition = frame.AbsolutePosition

    local x = math.clamp(
        absolutePosition.X,
        0,
        math.max(0, viewport.X - absoluteSize.X)
    )

    local y = math.clamp(
        absolutePosition.Y,
        0,
        math.max(0, viewport.Y - absoluteSize.Y)
    )

    frame.AnchorPoint = Vector2.new(0, 0)
    frame.Position = UDim2.fromOffset(x, y)
end

local function makeDraggable(frame, handle, onTap)
    local dragging = false
    local startInput
    local startPos
    local moved = false

    connect(handle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            startInput = input.Position
            startPos = frame.Position
            moved = false

            local tempConnection
            tempConnection = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if tempConnection then
                        tempConnection:Disconnect()
                    end

                    clampFrameToScreen(frame)

                    if not moved and onTap then
                        onTap()
                    end
                end
            end)
        end
    end)

    connect(UserInputService.InputChanged, function(input)
        if not dragging or not startInput or not startPos then
            return
        end

        local valid =
            input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch

        if not valid then
            return
        end

        local delta = input.Position - startInput

        if delta.Magnitude >= CONFIG.MIN_DRAG_DISTANCE then
            moved = true
        end

        frame.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end)
end

local function resizeResponsive()
    if not GUI.Main then
        return
    end

    local camera = workspace.CurrentCamera
    if not camera then
        return
    end

    local viewport = camera.ViewportSize

    local width = math.clamp(math.floor(viewport.X * 0.42), 300, 420)
    local height = math.clamp(math.floor(viewport.Y * 0.70), 260, 520)

    GUI.Main.Size = UDim2.fromOffset(width, height)
end

local function setMinimized(value)
    State.Minimized = value

    if GUI.Main then
        GUI.Main.Visible = not value
    end

    if GUI.FloatButton then
        GUI.FloatButton.Visible = value
    end
end

local function refreshUi()
    State.Health.LastUiTick = elapsed()

    if not GUI.Screen or not GUI.Screen.Parent then
        return
    end

    if GUI.Status then
        local tycoonText = State.Tycoon and State.Tycoon.Name or "não identificado"
        GUI.Status.Text =
            "Tycoon: " .. tycoonText ..
            " | Confiança: " .. tostring(State.TycoonConfidence) ..
            " | Compras: " .. tostring(#State.Transactions)
    end

    if GUI.Money then
        local money = getMoneyValue()
        GUI.Money.Text =
            "Money: " ..
            (money ~= nil and tostring(money) or "não encontrado")
    end

    if GUI.Health then
        GUI.Health.Text =
            "Motor: " .. tostring(State.Health.EventEngine) ..
            " | Tycoon: " .. tostring(State.Health.Tycoon) ..
            " | Money: " .. tostring(State.Health.Money) ..
            " | Erros: " .. tostring(#State.Errors)
    end

    if GUI.Live then
        local lines = {}
        local first = math.max(1, #State.Events - 18)

        for i = #State.Events, first, -1 do
            local e = State.Events[i]
            table.insert(lines,
                ("[%s] %s • %s"):format(
                    e.Time or "--:--:--",
                    e.Kind or "?",
                    e.Label or "?"
                )
            )
        end

        GUI.Live.Text =
            #lines > 0
            and table.concat(lines, "\n")
            or "Aguardando eventos..."
    end
end

local function createGui()
    local player = State.LocalPlayer
    if not player then
        error("LocalPlayer indisponível")
    end

    local playerGui = player:FindFirstChildOfClass("PlayerGui")
        or player:WaitForChild("PlayerGui", 10)

    if not playerGui then
        error("PlayerGui não encontrado após 10 segundos")
    end

    local old = playerGui:FindFirstChild(CONFIG.GUI_NAME)
    if old then
        old:Destroy()
    end

    local screen = Instance.new("ScreenGui")
    screen.Name = CONFIG.GUI_NAME
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = false
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.Parent = playerGui

    local main = Instance.new("Frame")
    main.Name = "Main"
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    main.Position = UDim2.fromScale(0.5, 0.5)
    main.Size = UDim2.fromOffset(350, 390)
    main.BackgroundColor3 = CONFIG.COLORS.Background
    main.BorderSizePixel = 0
    main.Parent = screen
    rounded(main, 12)

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
    version.Text = "V2.1 • Money / Rebirth / Robux"
    version.TextColor3 = CONFIG.COLORS.Muted
    version.Font = Enum.Font.Gotham
    version.TextSize = 10
    version.Parent = header

    local minimize = Instance.new("TextButton")
    minimize.Size = UDim2.fromOffset(34, 34)
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
    close.Size = UDim2.fromOffset(34, 34)
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
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = body

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, 0, 0, 38)
    status.BackgroundColor3 = CONFIG.COLORS.Card
    status.BorderSizePixel = 0
    status.TextWrapped = true
    status.TextColor3 = CONFIG.COLORS.Text
    status.Font = Enum.Font.Gotham
    status.TextSize = 10
    status.Text = "Inicializando..."
    status.Parent = body
    rounded(status, 8)

    local money = Instance.new("TextLabel")
    money.Size = UDim2.new(1, 0, 0, 24)
    money.BackgroundTransparency = 1
    money.TextXAlignment = Enum.TextXAlignment.Left
    money.TextColor3 = CONFIG.COLORS.Accent
    money.Font = Enum.Font.GothamBold
    money.TextSize = 11
    money.Text = "Money: procurando..."
    money.Parent = body

    local health = Instance.new("TextLabel")
    health.Size = UDim2.new(1, 0, 0, 28)
    health.BackgroundTransparency = 1
    health.TextWrapped = true
    health.TextXAlignment = Enum.TextXAlignment.Left
    health.TextColor3 = CONFIG.COLORS.Muted
    health.Font = Enum.Font.Gotham
    health.TextSize = 9
    health.Text = "Motor: iniciando..."
    health.Parent = body

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, -166)
    scroll.BackgroundColor3 = CONFIG.COLORS.Card2
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.new()
    scroll.Parent = body
    rounded(scroll, 8)

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 7)
    padding.PaddingBottom = UDim.new(0, 7)
    padding.PaddingLeft = UDim.new(0, 8)
    padding.PaddingRight = UDim.new(0, 8)
    padding.Parent = scroll

    local live = Instance.new("TextLabel")
    live.Size = UDim2.new(1, 0, 0, 150)
    live.AutomaticSize = Enum.AutomaticSize.Y
    live.BackgroundTransparency = 1
    live.TextWrapped = true
    live.TextXAlignment = Enum.TextXAlignment.Left
    live.TextYAlignment = Enum.TextYAlignment.Top
    live.TextColor3 = CONFIG.COLORS.Text
    live.Font = Enum.Font.Code
    live.TextSize = 10
    live.Text = "Aguardando eventos..."
    live.Parent = scroll

    local export = createButton(body, "Exportar relatório V2.1 (.txt)")
    export.LayoutOrder = 20

    local floating = Instance.new("TextButton")
    floating.Name = "RestoreFloatingButton"
    floating.Size = UDim2.fromOffset(58, 58)
    floating.Position = UDim2.new(0, 18, 0.5, -29)
    floating.BackgroundColor3 = CONFIG.COLORS.Floating
    floating.BorderSizePixel = 0
    floating.Text = "V2.1"
    floating.TextColor3 = Color3.fromRGB(240, 246, 255)
    floating.Font = Enum.Font.GothamBold
    floating.TextSize = 12
    floating.Visible = false
    floating.ZIndex = 50
    floating.Parent = screen
    rounded(floating, 14)

    GUI.Screen = screen
    GUI.Main = main
    GUI.Header = header
    GUI.Status = status
    GUI.Money = money
    GUI.Health = health
    GUI.Live = live
    GUI.Export = export
    GUI.Minimize = minimize
    GUI.Close = close
    GUI.FloatButton = floating

    makeDraggable(main, header)
    makeDraggable(floating, floating, function()
        setMinimized(false)
    end)

    connect(minimize.MouseButton1Click, function()
        setMinimized(true)
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

        task.defer(function()
            disconnectList(State.TycoonConnections)
            disconnectList(State.Connections)

            if screen and screen.Parent then
                screen:Destroy()
            end
        end)
    end)

    resizeResponsive()

    local camera = workspace.CurrentCamera
    if camera then
        connect(camera:GetPropertyChangedSignal("ViewportSize"), function()
            resizeResponsive()
        end)
    end

    State.Health.UI = "ACTIVE"
end

local function moneyLoop()
    task.spawn(function()
        while State.Running do
            local ok, err = xpcall(function()
                State.Health.LastMoneyTick = elapsed()

                local current = getMoneyValue()

                if current ~= nil then
                    State.Health.Money = "ACTIVE"
                    pushMoneySample(current)

                    if State.LastMoney ~= nil and current ~= State.LastMoney then
                        correlateMoneyChange(State.LastMoney, current)
                    end

                    State.LastMoney = current
                else
                    State.Health.Money = "SEARCHING"
                end
            end, function(message)
                return debug.traceback(tostring(message), 2)
            end)

            if not ok then
                recordError("MoneyLoop", err)
                State.Health.Money = "ERROR"
            end

            task.wait(CONFIG.MONEY_SAMPLE_INTERVAL)
        end
    end)
end

local function tycoonLoop()
    task.spawn(function()
        while State.Running do
            local ok, err = xpcall(function()
                reconsiderTycoon()
            end, function(message)
                return debug.traceback(tostring(message), 2)
            end)

            if not ok then
                recordError("TycoonLoop", err)
                State.Health.Tycoon = "ERROR"
            end

            task.wait(CONFIG.TYCOON_RESCAN_INTERVAL)
        end
    end)
end

local function uiLoop()
    task.spawn(function()
        while State.Running do
            local ok, err = xpcall(function()
                refreshUi()
            end, function(message)
                return debug.traceback(tostring(message), 2)
            end)

            if not ok then
                recordError("UiLoop", err)
                State.Health.UI = "ERROR"
            end

            task.wait(0.5)
        end
    end)
end

local function bootstrap()
    State.Health.Bootstrap = "STARTING"

    local player = Players.LocalPlayer

    if not player then
        player = Players:GetPropertyChangedSignal("LocalPlayer") and nil
    end

    local started = nowClock()
    while not player and nowClock() - started < 10 do
        player = Players.LocalPlayer
        task.wait(0.1)
    end

    if not player then
        error("LocalPlayer não ficou disponível em 10 segundos")
    end

    State.LocalPlayer = player

    createGui()

    State.MoneyObject = findMoneyObject()
    State.LastMoney = getMoneyValue()

    reconsiderTycoon()

    State.Health.Bootstrap = "OK"
    State.Health.EventEngine = "ACTIVE"

    event("SYSTEM", "Diagnostic V2.1 iniciado", {
        Version = CONFIG.VERSION,
        PlaceId = game.PlaceId,
        Player = player.Name,
    })

    moneyLoop()
    tycoonLoop()
    uiLoop()
end

local ok, err = protected("BOOTSTRAP", bootstrap)

if not ok then
    warn("[Tycoon Diagnostic V2.1] Falha no bootstrap:\n" .. tostring(err))
end
