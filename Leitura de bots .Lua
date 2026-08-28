--==============================================================
-- CAFÉÍNA • BOT RESEARCH V2
-- Coletor passivo de ciclo de vida de bots
--
-- V2:
--  • Snapshots periódicos individuais
--  • Spawn / remoção / morte
--  • Team por múltiplas fontes
--  • Histórico de Team
--  • Highlight como verificação complementar
--  • Objetos criados/removidos
--  • Attributes alterados
--  • Identidade e caminho
--  • Contexto do jogador
--  • Exportação JSON
--  • Confirmação explícita de exportação
--==============================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

--==============================================================
-- PARENT DA GUI
--==============================================================

local function getParent()
    if typeof(gethui) == "function" then
        local ok, p = pcall(gethui)
        if ok and p then
            return p
        end
    end

    return CoreGui
end

local Parent = getParent()

for _, v in ipairs(Parent:GetChildren()) do
    if v.Name == "CafeinaBotResearchV2" then
        pcall(function()
            v:Destroy()
        end)
    end
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "CafeinaBotResearchV2"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = true
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = Parent

--==============================================================
-- CORES
--==============================================================

local COLORS = {
    bg = Color3.fromRGB(10,10,13),
    panel = Color3.fromRGB(20,20,25),
    panel2 = Color3.fromRGB(29,29,36),

    text = Color3.fromRGB(245,245,248),
    sub = Color3.fromRGB(160,160,172),

    blue = Color3.fromRGB(22,55,105),
    blue2 = Color3.fromRGB(30,75,135),

    green = Color3.fromRGB(65,210,118),
    red = Color3.fromRGB(235,38,52),
    yellow = Color3.fromRGB(242,184,57),
}

--==============================================================
-- HELPERS DE GUI
--==============================================================

local function new(class, props)
    local x = Instance.new(class)

    for k,v in pairs(props or {}) do
        x[k] = v
    end

    return x
end

local function round(x, r)
    new("UICorner", {
        CornerRadius = UDim.new(0, r or 8),
        Parent = x
    })
end

local function label(parent, text, size, pos, textSize)
    return new("TextLabel", {
        Parent = parent,
        BackgroundTransparency = 1,
        Text = text,
        Size = size,
        Position = pos,
        TextColor3 = COLORS.text,
        Font = Enum.Font.Gotham,
        TextSize = textSize or 10,
        TextXAlignment = Enum.TextXAlignment.Left
    })
end

--==============================================================
-- CONFIGURAÇÃO DO COLETOR
--==============================================================

local CONFIG = {
    SnapshotInterval = 5,

    -- Evita arquivos absurdamente grandes.
    MaxSnapshotsPerBot = 300,
    MaxObjectEventsPerBot = 250,
    MaxAttributeEventsPerBot = 250,

    MaxImportantEvents = 1000,
    MaxVisualEvents = 500,

    -- A pasta observada no arquivo anterior.
    PrimaryContainer = "Soldiers",
}

--==============================================================
-- ESTADO
--==============================================================

local State = {
    Running = false,
    Scanned = false,

    StartAt = nil,
    StartAtUnix = nil,

    EndAt = nil,
    EndAtUnix = nil,

    NextBotId = 0,

    Bots = {},
    BotsByInstance = {},

    ImportantEvents = {},
    VisualEvents = {},

    Connections = {},
}

--==============================================================
-- TEMPO
--==============================================================

local function now()
    return os.clock()
end

local function unix()
    return os.time()
end

--==============================================================
-- SEGURANÇA
--==============================================================

local function safeName(x)
    local ok, result = pcall(function()
        return x.Name
    end)

    return ok and tostring(result) or "?"
end

local function safeFullName(x)
    local ok, result = pcall(function()
        return x:GetFullName()
    end)

    return ok and tostring(result) or safeName(x)
end

local function safeClass(x)
    local ok, result = pcall(function()
        return x.ClassName
    end)

    return ok and tostring(result) or "?"
end

local function getAttribute(x, key)
    local ok, result = pcall(function()
        return x:GetAttribute(key)
    end)

    return ok and result or nil
end

local function getAttributes(x)
    local result = {}

    pcall(function()
        for k,v in pairs(x:GetAttributes()) do
            result[tostring(k)] = tostring(v)
        end
    end)

    return result
end

local function isA(x, class)
    local ok, result = pcall(function()
        return x:IsA(class)
    end)

    return ok and result
end

--==============================================================
-- PLAYER CHARACTER
--==============================================================

local function isPlayerCharacter(model)
    if not model or not isA(model, "Model") then
        return false
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character == model then
            return true
        end
    end

    return false
end

--==============================================================
-- HUMANOID / ROOT
--==============================================================

local function getHumanoid(model)
    if not model then
        return nil
    end

    return model:FindFirstChildOfClass("Humanoid")
end

local function getRoot(model)
    if not model then
        return nil
    end

    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")
end

--==============================================================
-- SOLIDERS
--==============================================================

local function isInsideSoldiers(model)
    if not model then
        return false
    end

    local current = model.Parent

    while current and current ~= workspace do
        if current.Name == CONFIG.PrimaryContainer then
            return true
        end

        current = current.Parent
    end

    return false
end

--==============================================================
-- TEAM
--
-- Não depende somente de "Team".
-- Registra também de onde a informação veio.
--==============================================================

local function inspectTeam(model)
    local result = {
        value = nil,
        source = nil,

        attribute = nil,
        stringValue = nil,
        objectValue = nil,

        candidates = {},
    }

    -- -----------------------------------------
    -- Attribute "Team"
    -- -----------------------------------------

    local attributeTeam = getAttribute(model, "Team")

    if attributeTeam ~= nil then
        result.attribute = tostring(attributeTeam)
        result.value = tostring(attributeTeam)
        result.source = "Attribute"
        table.insert(result.candidates, {
            source = "Attribute",
            value = tostring(attributeTeam)
        })
    end

    -- -----------------------------------------
    -- StringValue direto
    -- -----------------------------------------

    local teamValue = model:FindFirstChild("Team")

    if teamValue and teamValue:IsA("StringValue") then
        result.stringValue = tostring(teamValue.Value)

        table.insert(result.candidates, {
            source = "StringValue",
            value = tostring(teamValue.Value)
        })

        if result.value == nil then
            result.value = tostring(teamValue.Value)
            result.source = "StringValue"
        end
    end

    -- -----------------------------------------
    -- ObjectValue direto
    -- -----------------------------------------

    if teamValue and teamValue:IsA("ObjectValue") then
        local object = teamValue.Value

        if object then
            result.objectValue = safeName(object)

            table.insert(result.candidates, {
                source = "ObjectValue",
                value = safeName(object),
                path = safeFullName(object),
                className = safeClass(object)
            })

            if result.value == nil then
                result.value = safeName(object)
                result.source = "ObjectValue"
            end
        end
    end

    -- -----------------------------------------
    -- TeamColor
    -- -----------------------------------------

    local teamColor = getAttribute(model, "TeamColor")

    if teamColor ~= nil then
        table.insert(result.candidates, {
            source = "TeamColorAttribute",
            value = tostring(teamColor)
        })
    end

    -- -----------------------------------------
    -- Container como pista secundária
    -- -----------------------------------------

    local parent = model.Parent

    if parent then
        local parentName = tostring(parent.Name)

        if parentName == "Army"
        or parentName == "Rebels" then

            table.insert(result.candidates, {
                source = "ParentNameHint",
                value = parentName
            })
        end
    end

    return result
end

--==============================================================
-- PLAYER STATE
--==============================================================

local function getPlayerState()
    local result = {
        team = nil,
        teamColor = nil,
        userId = nil,
        name = nil,
    }

    pcall(function()
        result.team = LocalPlayer.Team and LocalPlayer.Team.Name or nil
        result.teamColor =
            LocalPlayer.TeamColor
            and tostring(LocalPlayer.TeamColor.Name)
            or nil

        result.userId = LocalPlayer.UserId
        result.name = LocalPlayer.Name
    end)

    return result
end

--==============================================================
-- HIGHLIGHT
--==============================================================

local function inspectHighlights(model)
    local result = {
        exists = false,
        count = 0,
        items = {},
    }

    pcall(function()
        for _, obj in ipairs(model:GetDescendants()) do
            if obj:IsA("Highlight") then

                result.exists = true
                result.count += 1

                local item = {
                    path = safeFullName(obj),
                    enabled = obj.Enabled,
                    depthMode = tostring(obj.DepthMode),

                    fillColor = {
                        r = obj.FillColor.R,
                        g = obj.FillColor.G,
                        b = obj.FillColor.B,
                    },

                    outlineColor = {
                        r = obj.OutlineColor.R,
                        g = obj.OutlineColor.G,
                        b = obj.OutlineColor.B,
                    },

                    fillTransparency = obj.FillTransparency,
                    outlineTransparency = obj.OutlineTransparency,
                }

                table.insert(result.items, item)
            end
        end
    end)

    return result
end

--==============================================================
-- HUMANOID
--==============================================================

local function inspectHumanoid(hum)
    if not hum then
        return nil
    end

    local result = {
        health = hum.Health,
        maxHealth = hum.MaxHealth,

        walkSpeed = hum.WalkSpeed,
        jumpPower = hum.JumpPower,

        rigType = tostring(hum.RigType),
        state = tostring(hum:GetState()),

        moveDirection = {
            x = hum.MoveDirection.X,
            y = hum.MoveDirection.Y,
            z = hum.MoveDirection.Z,
        },
    }

    return result
end

--==============================================================
-- POSITION
--==============================================================

local function inspectPosition(model)
    local root = getRoot(model)

    if not root then
        return nil
    end

    return {
        x = root.Position.X,
        y = root.Position.Y,
        z = root.Position.Z,
    }
end

--==============================================================
-- INTERESTING OBJECTS
--==============================================================

local function inspectInterestingObjects(model)
    local result = {}

    pcall(function()
        for _, obj in ipairs(model:GetDescendants()) do

            if obj:IsA("Tool")
            or obj:IsA("Highlight")
            or obj:IsA("Humanoid")
            or obj:IsA("ValueBase")
            or obj:IsA("Folder")
            or obj:IsA("ObjectValue") then

                table.insert(result, {
                    name = safeName(obj),
                    className = safeClass(obj),
                    path = safeFullName(obj),
                })
            end
        end
    end)

    return result
end

--==============================================================
-- BOT SNAPSHOT
--==============================================================

local function buildBotSnapshot(bot)
    local model = bot.instance

    if not model or not model.Parent then
        return nil
    end

    local hum = getHumanoid(model)
    local root = getRoot(model)
    local teamInfo = inspectTeam(model)

    local snapshot = {
        time = now(),
        unix = unix(),

        path = safeFullName(model),

        name = safeName(model),
        className = safeClass(model),

        parent = model.Parent and safeFullName(model.Parent) or nil,

        insideSoldiers = isInsideSoldiers(model),

        position = inspectPosition(model),

        team = {
            value = teamInfo.value,
            source = teamInfo.source,
            attribute = teamInfo.attribute,
            stringValue = teamInfo.stringValue,
            objectValue = teamInfo.objectValue,
            candidates = teamInfo.candidates,
        },

        humanoid = inspectHumanoid(hum),

        attributes = getAttributes(model),

        highlight = inspectHighlights(model),

        interestingObjects = inspectInterestingObjects(model),

        playerState = getPlayerState(),
    }

    return snapshot
end

--==============================================================
-- EVENT HELPERS
--==============================================================

local function addImportantEvent(eventType, data)
    if #State.ImportantEvents >= CONFIG.MaxImportantEvents then
        table.remove(State.ImportantEvents, 1)
    end

    table.insert(State.ImportantEvents, {
        type = eventType,
        time = now(),
        unix = unix(),
        data = data,
    })
end

local function addVisualEvent(eventType, data)
    if #State.VisualEvents >= CONFIG.MaxVisualEvents then
        table.remove(State.VisualEvents, 1)
    end

    table.insert(State.VisualEvents, {
        type = eventType,
        time = now(),
        unix = unix(),
        data = data,
    })
end

--==============================================================
-- BOT EVENT STORAGE
--==============================================================

local function addBotObjectEvent(bot, eventType, data)
    if #bot.objectEvents >= CONFIG.MaxObjectEventsPerBot then
        table.remove(bot.objectEvents, 1)
    end

    table.insert(bot.objectEvents, {
        type = eventType,
        time = now(),
        unix = unix(),
        data = data,
    })
end

local function addBotAttributeEvent(bot, data)
    if #bot.attributeEvents >= CONFIG.MaxAttributeEventsPerBot then
        table.remove(bot.attributeEvents, 1)
    end

    table.insert(bot.attributeEvents, {
        time = now(),
        unix = unix(),
        data = data,
    })
end

--==============================================================
-- TEAM HISTORY
--==============================================================

local function addTeamHistory(bot, teamInfo, reason)
    local value = teamInfo and teamInfo.value or nil

    local previous = bot.lastTeam

    if previous == value and bot.teamHistoryInitialized then
        return
    end

    bot.teamHistoryInitialized = true
    bot.lastTeam = value

    local entry = {
        time = now(),
        unix = unix(),

        previous = previous,
        current = value,

        source = teamInfo and teamInfo.source or nil,

        attribute = teamInfo and teamInfo.attribute or nil,
        stringValue = teamInfo and teamInfo.stringValue or nil,
        objectValue = teamInfo and teamInfo.objectValue or nil,

        candidates = teamInfo and teamInfo.candidates or {},

        reason = reason,
    }

    table.insert(bot.teamHistory, entry)

    addImportantEvent("BOT_TEAM_CHANGED", {
        botId = bot.id,
        path = safeFullName(bot.instance),

        previous = previous,
        current = value,

        source = entry.source,
        reason = reason,

        playerState = getPlayerState(),
    })
end

--==============================================================
-- HIGHLIGHT HISTORY
--==============================================================

local function highlightSignature(h)
    if not h then
        return "nil"
    end

    return HttpService:JSONEncode(h)
end

local function checkHighlight(bot, reason)
    local current = inspectHighlights(bot.instance)

    local signature = highlightSignature(current)
    local previous = bot.lastHighlightSignature

    if previous == nil then
        bot.lastHighlightSignature = signature
        bot.highlightInitial = current
        return
    end

    if previous ~= signature then

        bot.lastHighlightSignature = signature

        local event = {
            botId = bot.id,
            path = safeFullName(bot.instance),

            previous = bot.lastHighlight,
            current = current,

            reason = reason,

            playerState = getPlayerState(),
        }

        addVisualEvent("HIGHLIGHT_CHANGED", event)

        addImportantEvent("HIGHLIGHT_CHANGED", event)

        bot.lastHighlight = current
    end
end

--==============================================================
-- BOT REGISTRATION
--==============================================================

local function shouldRegister(model)
    if not model then
        return false
    end

    if not isA(model, "Model") then
        return false
    end

    if isPlayerCharacter(model) then
        return false
    end

    local hum = getHumanoid(model)

    if not hum then
        return false
    end

    -- Principal evidência:
    -- Models dentro de Workspace.Soldiers.
    --
    -- Também aceitamos Models fora de Soldiers
    -- quando possuem sinal explícito de Team.
    local insideSoldiers = isInsideSoldiers(model)

    local teamInfo = inspectTeam(model)

    local hasTeamEvidence =
        teamInfo.value ~= nil
        or #teamInfo.candidates > 0

    return insideSoldiers or hasTeamEvidence
end

--==============================================================
-- MONITORAMENTO DE UM BOT
--==============================================================

local function monitorBot(bot)
    local model = bot.instance

    -- -----------------------------------------
    -- Estado inicial
    -- -----------------------------------------

    local initialTeam = inspectTeam(model)

    bot.initialTeam = {
        value = initialTeam.value,
        source = initialTeam.source,

        attribute = initialTeam.attribute,
        stringValue = initialTeam.stringValue,
        objectValue = initialTeam.objectValue,

        candidates = initialTeam.candidates,
    }

    bot.lastTeam = initialTeam.value
    bot.teamHistoryInitialized = true

    bot.initialAttributes = getAttributes(model)
    bot.lastAttributes = getAttributes(model)

    bot.highlightInitial = inspectHighlights(model)
    bot.lastHighlight = bot.highlightInitial
    bot.lastHighlightSignature = highlightSignature(bot.highlightInitial)

    -- -----------------------------------------
    -- knownObjects
    -- -----------------------------------------

    bot.knownObjects = {}

    pcall(function()
        for _, obj in ipairs(model:GetDescendants()) do
            bot.knownObjects[obj] = true
        end
    end)

    -- -----------------------------------------
    -- Primeiro snapshot
    -- -----------------------------------------

    local firstSnapshot = buildBotSnapshot(bot)

    if firstSnapshot then
        table.insert(bot.snapshots, firstSnapshot)
    end

    -- -----------------------------------------
    -- Team inicial
    -- -----------------------------------------

    table.insert(bot.teamHistory, {
        time = bot.spawn.time,
        unix = bot.spawn.unix,

        previous = nil,
        current = initialTeam.value,

        source = initialTeam.source,

        attribute = initialTeam.attribute,
        stringValue = initialTeam.stringValue,
        objectValue = initialTeam.objectValue,

        candidates = initialTeam.candidates,

        reason = bot.spawn.observedExisting
            and "INITIAL_SCAN"
            or "SPAWN",
    })

    -- -----------------------------------------
    -- ChildAdded
    -- -----------------------------------------

    bot.connections = {}

    table.insert(bot.connections,
        model.DescendantAdded:Connect(function(obj)

            if not bot.active then
                return
            end

            bot.knownObjects[obj] = true

            addBotObjectEvent(bot, "OBJECT_CREATED", {
                name = safeName(obj),
                className = safeClass(obj),
                path = safeFullName(obj),
            })

            if obj:IsA("Highlight") then
                task.defer(function()
                    checkHighlight(bot, "OBJECT_CREATED")
                end)
            end

            if obj.Name == "Team"
            or obj:IsA("StringValue")
            or obj:IsA("ObjectValue") then

                task.defer(function()
                    local teamInfo = inspectTeam(model)
                    addTeamHistory(bot, teamInfo, "OBJECT_CREATED")
                end)
            end
        end)
    )

    -- -----------------------------------------
    -- DescendantRemoving
    -- -----------------------------------------

    table.insert(bot.connections,
        model.DescendantRemoving:Connect(function(obj)

            if not bot.active then
                return
            end

            addBotObjectEvent(bot, "OBJECT_REMOVED", {
                name = safeName(obj),
                className = safeClass(obj),
                path = safeFullName(obj),
            })

            if obj:IsA("Highlight") then
                task.defer(function()
                    checkHighlight(bot, "OBJECT_REMOVED")
                end)
            end
        end)
    )

    -- -----------------------------------------
    -- AttributeChanged
    -- -----------------------------------------

    table.insert(bot.connections,
        model.AttributeChanged:Connect(function(attributeName)

            if not bot.active then
                return
            end

            local currentAttributes = getAttributes(model)
            local oldValue = bot.lastAttributes[attributeName]
            local newValue = currentAttributes[attributeName]

            bot.lastAttributes = currentAttributes

            local eventData = {
                attribute = tostring(attributeName),
                previous = oldValue,
                current = newValue,
            }

            addBotAttributeEvent(bot, eventData)

            if tostring(attributeName) == "Team"
            or tostring(attributeName) == "TeamColor" then

                local teamInfo = inspectTeam(model)

                addTeamHistory(
                    bot,
                    teamInfo,
                    "ATTRIBUTE_CHANGED:" .. tostring(attributeName)
                )
            end
        end)
    )

    -- -----------------------------------------
    -- Humanoid morreu
    -- -----------------------------------------

    local hum = getHumanoid(model)

    if hum then

        table.insert(bot.connections,
            hum.Died:Connect(function()

                if not bot.active then
                    return
                end

                bot.death = {
                    detected = true,
                    time = now(),
                    unix = unix(),
                    health = hum.Health,
                }

                addImportantEvent("BOT_DIED", {
                    botId = bot.id,
                    path = safeFullName(model),
                    name = safeName(model),

                    team = inspectTeam(model),

                    playerState = getPlayerState(),
                })
            end)
        )
    end

    -- -----------------------------------------
    -- Monitoramento periódico
    -- -----------------------------------------

    task.spawn(function()

        while bot.active and State.Running do

            task.wait(CONFIG.SnapshotInterval)

            if not bot.active then
                break
            end

            if not model.Parent then
                break
            end

            -- Team
            local teamInfo = inspectTeam(model)

            addTeamHistory(
                bot,
                teamInfo,
                "PERIODIC_CHECK"
            )

            -- Attributes
            bot.lastAttributes = getAttributes(model)

            -- Highlight
            checkHighlight(bot, "PERIODIC_CHECK")

            -- Snapshot
            local snapshot = buildBotSnapshot(bot)

            if snapshot then

                if #bot.snapshots >= CONFIG.MaxSnapshotsPerBot then
                    table.remove(bot.snapshots, 1)
                end

                table.insert(bot.snapshots, snapshot)
            end
        end
    end)
end

--==============================================================
-- REGISTRA BOT
--==============================================================

local function registerBot(model, observedExisting)

    if State.BotsByInstance[model] then
        return State.BotsByInstance[model]
    end

    if not shouldRegister(model) then
        return nil
    end

    State.NextBotId += 1

    local teamInfo = inspectTeam(model)

    local bot = {
        id = State.NextBotId,

        instance = model,

        name = safeName(model),
        className = safeClass(model),

        spawn = {
            time = now(),
            unix = unix(),

            path = safeFullName(model),
            className = safeClass(model),

            observedExisting = observedExisting == true,
        },

        initialTeam = nil,

        teamHistory = {},

        initialAttributes = {},
        lastAttributes = {},

        initialHighlight = nil,
        lastHighlight = nil,
        lastHighlightSignature = nil,

        knownObjects = {},

        snapshots = {},

        objectEvents = {},
        attributeEvents = {},

        death = {
            detected = false,
        },

        removed = false,

        active = true,

        connections = {},
    }

    State.Bots[#State.Bots + 1] = bot
    State.BotsByInstance[model] = bot

    -- Registro inicial
    addImportantEvent("BOT_SPAWN", {
        botId = bot.id,

        path = safeFullName(model),
        name = safeName(model),
        className = safeClass(model),

        initialTeam = teamInfo,

        insideSoldiers = isInsideSoldiers(model),

        observedExisting = observedExisting == true,

        playerState = getPlayerState(),
    })

    monitorBot(bot)

    return bot
end

--==============================================================
-- REMOVE BOT
--==============================================================

local function removeBot(bot, reason)

    if not bot or not bot.active then
        return
    end

    bot.active = false
    bot.removed = true

    bot.removedAt = {
        time = now(),
        unix = unix(),

        reason = reason,
    }

    addImportantEvent("BOT_REMOVED", {
        botId = bot.id,

        path = bot.spawn.path,
        name = bot.name,

        reason = reason,

        deathDetected =
            bot.death
            and bot.death.detected
            or false,

        team = inspectTeam(bot.instance),

        playerState = getPlayerState(),
    })

    for _, connection in ipairs(bot.connections or {}) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    bot.connections = {}

    State.BotsByInstance[bot.instance] = nil
end

--==============================================================
-- SCAN INICIAL
--==============================================================

local function scanExisting()

    for _, inst in ipairs(workspace:GetDescendants()) do

        if isA(inst, "Model") then
            registerBot(inst, true)
        end
    end
end

--==============================================================
-- MONITORAMENTO GLOBAL
--==============================================================

local function findRegisteredModelFromInstance(inst)

    if State.BotsByInstance[inst] then
        return State.BotsByInstance[inst]
    end

    return nil
end

local function setupGlobalMonitoring()

    -- -----------------------------------------
    -- Novos objetos
    -- -----------------------------------------

    table.insert(State.Connections,
        workspace.DescendantAdded:Connect(function(inst)

            if not State.Running then
                return
            end

            -- Se for Model, tenta imediatamente.
            if inst:IsA("Model") then

                task.defer(function()
                    registerBot(inst, false)
                end)

                -- Pequenos retries:
                -- alguns modelos recebem Humanoid/Team
                -- alguns instantes depois do spawn.

                task.delay(0.15, function()
                    if State.Running and inst.Parent then
                        registerBot(inst, false)
                    end
                end)

                task.delay(0.5, function()
                    if State.Running and inst.Parent then
                        registerBot(inst, false)
                    end
                end)

                task.delay(1, function()
                    if State.Running and inst.Parent then
                        registerBot(inst, false)
                    end
                end)

                return
            end

            -- Se um Humanoid foi adicionado depois,
            -- tenta registrar o Model pai.

            if inst:IsA("Humanoid") then

                local model = inst.Parent

                if model and model:IsA("Model") then
                    task.defer(function()
                        registerBot(model, false)
                    end)
                end
            end
        end)
    )

    -- -----------------------------------------
    -- Remoção global
    -- -----------------------------------------

    table.insert(State.Connections,
        workspace.DescendantRemoving:Connect(function(inst)

            local bot = findRegisteredModelFromInstance(inst)

            if bot then
                removeBot(bot, "DESCENDANT_REMOVING")
            end
        end)
    )
end

--==============================================================
-- SCAN MANUAL
--==============================================================

local function performScan()

    Status.Text = "Realizando leitura..."
    Status.TextColor3 = COLORS.sub

    task.spawn(function()

        local ok, err = pcall(function()

            -- Limpa conexões anteriores
            for _, connection in ipairs(State.Connections) do
                pcall(function()
                    connection:Disconnect()
                end)
            end

            State.Connections = {}

            State.Bots = {}
            State.BotsByInstance = {}

            State.ImportantEvents = {}
            State.VisualEvents = {}

            State.NextBotId = 0

            State.StartAt = now()
            State.StartAtUnix = unix()

            State.EndAt = nil
            State.EndAtUnix = nil

            State.Running = true
            State.Scanned = true

            addImportantEvent("RESEARCH_STARTED", {
                playerState = getPlayerState(),
                primaryContainer = CONFIG.PrimaryContainer,
                snapshotInterval = CONFIG.SnapshotInterval,
            })

            -- Primeiro registra os existentes.
            scanExisting()

            -- Depois começa a observar novos.
            setupGlobalMonitoring()

        end)

        if not ok then

            State.Running = false

            Status.Text = "Erro durante a leitura."
            Status.TextColor3 = COLORS.red

            Summary.Text = tostring(err)

            return
        end

        Status.Text = "Monitoramento ativo."
        Status.TextColor3 = COLORS.green

        Summary.Text =
            "Monitoramento ativo • "
            .. tostring(#State.Bots)
            .. " entidades registradas."
    end)
end

--==============================================================
-- PARAR MONITORAMENTO
--==============================================================

local function stopResearch()

    if not State.Running then
        Status.Text = "Nenhuma pesquisa ativa."
        return
    end

    State.Running = false

    State.EndAt = now()
    State.EndAtUnix = unix()

    addImportantEvent("RESEARCH_STOPPED", {
        playerState = getPlayerState(),
    })

    for _, connection in ipairs(State.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    State.Connections = {}

    for _, bot in ipairs(State.Bots) do

        if bot.active then
            bot.active = false

            for _, connection in ipairs(bot.connections or {}) do
                pcall(function()
                    connection:Disconnect()
                end)
            end

            bot.connections = {}
        end
    end

    Status.Text = "Monitoramento parado."
    Status.TextColor3 = COLORS.yellow

    Summary.Text =
        "Pesquisa encerrada • "
        .. tostring(#State.Bots)
        .. " entidades registradas."
end

--==============================================================
-- RESUMO
--==============================================================

local function getSummary()

    local total = #State.Bots

    local army = 0
    local rebels = 0
    local unknown = 0

    local alive = 0
    local dead = 0
    local removed = 0

    local insideSoldiers = 0
    local highlightBots = 0

    for _, bot in ipairs(State.Bots) do

        local team = bot.lastTeam

        if team == "Army" then
            army += 1
        elseif team == "Rebels" then
            rebels += 1
        else
            unknown += 1
        end

        if bot.death and bot.death.detected then
            dead += 1
        else
            alive += 1
        end

        if bot.removed then
            removed += 1
        end

        if bot.spawn and bot.spawn.path then
            if bot.spawn.path:find("Workspace.Soldiers", 1, true) then
                insideSoldiers += 1
            end
        end

        if bot.initialHighlight
        and bot.initialHighlight.exists then
            highlightBots += 1
        end
    end

    return {
        total = total,

        army = army,
        rebels = rebels,
        unknown = unknown,

        alive = alive,
        dead = dead,
        removed = removed,

        insideSoldiers = insideSoldiers,
        highlightObserved = highlightBots,

        importantEvents = #State.ImportantEvents,
        visualEvents = #State.VisualEvents,
    }
end

--==============================================================
-- EXPORTAÇÃO
--==============================================================

local function buildExport()

    local bots = {}

    for _, bot in ipairs(State.Bots) do

        local output = {
            id = bot.id,

            name = bot.name,
            className = bot.className,

            spawn = bot.spawn,

            initialTeam = bot.initialTeam,

            teamHistory = bot.teamHistory,

            initialAttributes = bot.initialAttributes,

            initialHighlight = bot.initialHighlight,

            snapshots = bot.snapshots,

            objectEvents = bot.objectEvents,

            attributeEvents = bot.attributeEvents,

            death = bot.death,

            removed = bot.removed,
            removedAt = bot.removedAt,

            finalState = nil,
        }

        -- Último estado disponível
        if #bot.snapshots > 0 then
            output.finalState =
                bot.snapshots[#bot.snapshots]
        end

        bots[tostring(bot.id)] = output
    end

    return {
        format = "Cafeina Bot Research",
        version = "2.0",

        session = {
            startedAt = State.StartAt,
            startedAtUnix = State.StartAtUnix,

            endedAt = State.EndAt,
            endedAtUnix = State.EndAtUnix,

            placeId = game.PlaceId,
            gameId = game.GameId,
            jobId = game.JobId,
        },

        playerState = getPlayerState(),

        configuration = {
            snapshotInterval = CONFIG.SnapshotInterval,
            primaryContainer = CONFIG.PrimaryContainer,

            maxSnapshotsPerBot = CONFIG.MaxSnapshotsPerBot,
            maxObjectEventsPerBot = CONFIG.MaxObjectEventsPerBot,
            maxAttributeEventsPerBot = CONFIG.MaxAttributeEventsPerBot,
        },

        summary = getSummary(),

        importantEvents = State.ImportantEvents,

        visualEvents = State.VisualEvents,

        bots = bots,

        notes = {
            "Coleta passiva.",
            "Nenhuma alteração foi realizada nos bots.",
            "Team é registrado por múltiplas fontes.",
            "Highlight é tratado como verificação complementar.",
            "observedExisting=true significa que a entidade já existia quando a pesquisa começou.",
            "observedExisting=false indica que a entidade foi observada após o início da pesquisa.",
            "A presença em Workspace.Soldiers é registrada como evidência estrutural, não como prova isolada de equipe.",
        },
    }
end

local function jsonExport()

    local ok, result = pcall(function()
        return HttpService:JSONEncode(buildExport())
    end)

    if ok then
        return result
    end

    return nil
end

--==============================================================
-- PREVIEW
--==============================================================

local function updatePreview()

    local summary = getSummary()

    local lines = {
        "CAFÉÍNA • BOT RESEARCH V2",
        "",
        "STATUS:",
        State.Running and "  MONITORAMENTO ATIVO"
            or "  MONITORAMENTO PARADO",

        "",
        "ENTIDADES:",
        "  Total: "..summary.total,
        "  Army: "..summary.army,
        "  Rebels: "..summary.rebels,
        "  Unknown: "..summary.unknown,

        "",
        "CICLO DE VIDA:",
        "  Ativos: "..summary.alive,
        "  Mortos: "..summary.dead,
        "  Removidos: "..summary.removed,

        "",
        "ESTRUTURA:",
        "  Dentro de Soldiers: "..summary.insideSoldiers,
        "  Com Highlight inicial: "..summary.highlightObserved,

        "",
        "EVENTOS:",
        "  Importantes: "..summary.importantEvents,
        "  Visuais: "..summary.visualEvents,

        "",
        "BOTS REGISTRADOS:",
    }

    for _, bot in ipairs(State.Bots) do

        local team = bot.lastTeam or "UNKNOWN"

        local status = "ATIVO"

        if bot.death and bot.death.detected then
            status = "MORTO"
        end

        if bot.removed then
            status = "REMOVIDO"
        end

        lines[#lines + 1] =
            "["..tostring(bot.id).."] "
            ..bot.name
            .." | "
            ..team
            .." | "
            ..status
            .." | snapshots="
            ..tostring(#bot.snapshots)
    end

    Viewer.Text = table.concat(lines, "\n")
end

--==============================================================
-- GUI
--==============================================================

local Main = new("Frame", {
    Parent = Gui,

    Size = UDim2.fromOffset(700,560),

    Position = UDim2.new(
        0.5,-350,
        0.5,-280
    ),

    BackgroundColor3 = COLORS.bg,
    BorderSizePixel = 0,
})

round(Main,16)

-- HEADER

local Header = new("Frame", {
    Parent = Main,

    Size = UDim2.new(1,0,0,76),

    BackgroundColor3 = COLORS.panel,
    BorderSizePixel = 0,
})

round(Header,16)

label(
    Header,
    "CAFÉÍNA • BOT RESEARCH V2",
    UDim2.new(1,-150,0,28),
    UDim2.fromOffset(20,12),
    19
)

local SubTitle = label(
    Header,
    "COLETA PASSIVA • CICLO DE VIDA DOS BOTS",
    UDim2.new(1,-150,0,18),
    UDim2.fromOffset(20,43),
    9
)

SubTitle.TextColor3 = COLORS.sub

-- MINIMIZAR

local Min = new("TextButton", {
    Parent = Header,

    Size = UDim2.fromOffset(38,38),

    Position = UDim2.new(
        1,-92,
        0,19
    ),

    Text = "—",

    BackgroundColor3 = COLORS.panel2,

    TextColor3 = COLORS.text,

    Font = Enum.Font.GothamBold,

    TextSize = 19,

    BorderSizePixel = 0,
})

round(Min,9)

-- FECHAR

local Close = new("TextButton", {
    Parent = Header,

    Size = UDim2.fromOffset(38,38),

    Position = UDim2.new(
        1,-47,
        0,19
    ),

    Text = "×",

    BackgroundColor3 = COLORS.red,

    TextColor3 = COLORS.text,

    Font = Enum.Font.GothamBold,

    TextSize = 21,

    BorderSizePixel = 0,
})

round(Close,9)

-- STATUS

Status = label(
    Main,
    "Pronto para iniciar a pesquisa.",
    UDim2.new(1,-40,0,24),
    UDim2.fromOffset(20,91),
    11
)

Status.TextColor3 = COLORS.sub

-- BOTÃO SCAN

local Scan = new("TextButton", {
    Parent = Main,

    Size = UDim2.new(0.5,-25,0,48),

    Position = UDim2.fromOffset(20,122),

    Text = "INICIAR LEITURA",

    BackgroundColor3 = COLORS.blue2,

    TextColor3 = COLORS.text,

    Font = Enum.Font.GothamBold,

    TextSize = 11,

    BorderSizePixel = 0,
})

round(Scan,9)

-- BOTÃO STOP

local Stop = new("TextButton", {
    Parent = Main,

    Size = UDim2.new(0.5,-25,0,48),

    Position = UDim2.new(
        0.5,5,
        0,122
    ),

    Text = "PARAR MONITORAMENTO",

    BackgroundColor3 = COLORS.panel2,

    TextColor3 = COLORS.text,

    Font = Enum.Font.GothamBold,

    TextSize = 11,

    BorderSizePixel = 0,
})

round(Stop,9)

-- SUMMARY

local Summary = label(
    Main,
    "Nenhuma pesquisa realizada.",
    UDim2.new(1,-40,0,48),
    UDim2.fromOffset(20,184),
    11
)

Summary.TextColor3 = COLORS.text
Summary.TextWrapped = true

-- VIEWER

local Viewer = new("TextBox", {
    Parent = Main,

    Size = UDim2.new(
        1,-40,
        1,-255
    ),

    Position = UDim2.fromOffset(20,232),

    BackgroundColor3 = COLORS.panel,

    BorderSizePixel = 0,

    Text = "",

    TextColor3 = COLORS.text,

    Font = Enum.Font.Code,

    TextSize = 10,

    MultiLine = true,

    ClearTextOnFocus = false,

    TextEditable = false,

    TextXAlignment = Enum.TextXAlignment.Left,

    TextYAlignment = Enum.TextYAlignment.Top,
})

round(Viewer,9)

-- EXPORTAR

local Export = new("TextButton", {
    Parent = Main,

    Size = UDim2.fromOffset(250,42),

    Position = UDim2.new(
        1,-270,
        1,-58
    ),

    Text = "BAIXAR ARQUIVO DE LEITURA",

    BackgroundColor3 = COLORS.blue,

    TextColor3 = COLORS.text,

    Font = Enum.Font.GothamBold,

    TextSize = 10,

    BorderSizePixel = 0,
})

round(Export,9)

--==============================================================
-- BOTÃO FLUTUANTE
--==============================================================

local Mini = new("TextButton", {
    Parent = Gui,

    Size = UDim2.fromOffset(58,58),

    Position = UDim2.new(
        0.5,-29,
        0.5,-29
    ),

    BackgroundColor3 = COLORS.blue,

    Text = "C",

    TextColor3 = COLORS.text,

    Font = Enum.Font.GothamBlack,

    TextSize = 21,

    BorderSizePixel = 0,

    Visible = false,
})

round(Mini,99)

--==============================================================
-- SCAN
--==============================================================

Scan.Activated:Connect(function()

    if State.Running then

        Status.Text = "O monitoramento já está ativo."
        Status.TextColor3 = COLORS.yellow

        return
    end

    Scan.Text = "INICIANDO..."

    performScan()

    task.delay(0.5, function()

        Scan.Text = "INICIAR LEITURA"

    end)
end)

--==============================================================
-- STOP
--==============================================================

Stop.Activated:Connect(function()

    stopResearch()

    updatePreview()
end)

--==============================================================
-- PREVIEW AUTOMÁTICO
--==============================================================

task.spawn(function()

    while Gui.Parent do

        task.wait(2)

        if State.Scanned then

            pcall(function()
                updatePreview()
            end)
        end
    end
end)

--==============================================================
-- EXPORTAÇÃO
--==============================================================

Export.Activated:Connect(function()

    if not State.Scanned then

        Status.Text = "Faça a leitura primeiro."
        Status.TextColor3 = COLORS.yellow

        return
    end

    -- Se ainda estiver rodando, encerra primeiro
    -- para registrar corretamente EndAt/EndAtUnix.

    if State.Running then
        stopResearch()
    end

    Status.Text = "Preparando arquivo..."
    Status.TextColor3 = COLORS.sub

    task.spawn(function()

        local data = jsonExport()

        if not data then

            Status.Text = "Erro ao gerar o JSON."
            Status.TextColor3 = COLORS.red

            return
        end

        local filename =
            "Cafeina_BotResearchV2_"
            ..tostring(game.PlaceId)
            .."_"
            ..tostring(os.time())
            ..".json"

        -- -----------------------------------------
        -- WRITEFILE
        -- -----------------------------------------

        if typeof(writefile) == "function" then

            local ok, err = pcall(function()

                writefile(
                    filename,
                    data
                )

            end)

            if ok then

                Status.Text =
                    "Arquivo exportado com sucesso!"

                Status.TextColor3 = COLORS.green

                Summary.Text =
                    "Exportação concluída • "
                    ..filename

                updatePreview()

                return
            end
        end

        -- -----------------------------------------
        -- CLIPBOARD
        -- -----------------------------------------

        if typeof(setclipboard) == "function" then

            local copied = pcall(function()

                setclipboard(data)

            end)

            if copied then

                Status.Text =
                    "Dados copiados para a área de transferência."

                Status.TextColor3 = COLORS.yellow

                Summary.Text =
                    "writefile indisponível • JSON copiado."

                return
            end
        end

        -- -----------------------------------------
        -- SEM MÉTODO
        -- -----------------------------------------

        Status.Text =
            "Não foi possível exportar o arquivo."

        Status.TextColor3 = COLORS.red

        Summary.Text =
            "O ambiente não disponibiliza writefile nem clipboard."

    end)
end)

--==============================================================
-- MINIMIZAR
--==============================================================

Min.Activated:Connect(function()

    Main.Visible = false
    Mini.Visible = true

end)

--==============================================================
-- REABRIR
--==============================================================

Mini.Activated:Connect(function()

    Main.Visible = true
    Mini.Visible = false

end)

--==============================================================
-- FECHAR
--==============================================================

Close.Activated:Connect(function()

    State.Running = false

    for _, connection in ipairs(State.Connections) do

        pcall(function()
            connection:Disconnect()
        end)

    end

    for _, bot in ipairs(State.Bots) do

        bot.active = false

        for _, connection in ipairs(bot.connections or {}) do

            pcall(function()
                connection:Disconnect()
            end)

        end

    end

    pcall(function()
        Gui:Destroy()
    end)

end)

--==============================================================
-- ARRASTAR BOTÃO FLUTUANTE
--==============================================================

do

    local dragging = false

    local dragStart = nil
    local startPos = nil

    Mini.InputBegan:Connect(function(input)

        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then

            dragging = true

            dragStart = input.Position
            startPos = Mini.Position

        end

    end)

    UserInputService.InputChanged:Connect(function(input)

        if not dragging then
            return
        end

        if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then

            return
        end

        local delta =
            input.Position - dragStart

        Mini.Position = UDim2.new(

            startPos.X.Scale,
            startPos.X.Offset + delta.X,

            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y

        )

    end)

    UserInputService.InputEnded:Connect(function(input)

        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then

            dragging = false

        end

    end)

end

--==============================================================
-- ESTADO INICIAL
--==============================================================

Status.Text = "Pronto para iniciar a pesquisa."
Status.TextColor3 = COLORS.sub

Summary.Text =
    "A V2 registra spawn, equipe, alterações, snapshots, "
    .."Highlight, morte e remoção."

Viewer.Text =
    "CAFÉÍNA • BOT RESEARCH V2\n\n"
    .."Coletor passivo pronto.\n\n"
    .."A pesquisa registra:\n"
    .."• Spawn observado\n"
    .."• Identidade e caminho\n"
    .."• Team e fonte da informação\n"
    .."• Histórico de Team\n"
    .."• Attributes\n"
    .."• Objetos criados/removidos\n"
    .."• Highlight (verificação complementar)\n"
    .."• Humanoid\n"
    .."• Snapshots periódicos\n"
    .."• Morte\n"
    .."• Remoção\n\n"
    .."Clique em INICIAR LEITURA para começar."
