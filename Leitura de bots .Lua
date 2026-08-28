--[[
    CAFEÍNA • BOT READER V2
    Coletor passivo para estudo de entidades/bots.

    OBJETIVO:
    - Observar Workspace.Soldiers
    - Registrar nascimento/remoção de entidades
    - Registrar Team e a fonte dessa informação
    - Registrar Attributes
    - Registrar ValueObjects relacionados a Team
    - Registrar Highlight como evidência complementar
    - Registrar criação/remoção de objetos relevantes
    - Registrar mudanças de atributos
    - Registrar snapshots periódicos
    - Registrar entrada/saída de Players para contexto
    - Exportar tudo para JSON

    NÃO:
    - Não altera bots
    - Não ataca
    - Não teleporta
    - Não cria bots
    - Não altera Team
    - Não altera Highlight
    - Não executa comandos sobre entidades

    Observação:
    writefile/setclipboard dependem do ambiente em que o script é executado.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- ============================================================
-- PARENT DA INTERFACE
-- ============================================================

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
    if v.Name == "CafeinaBotReader_V2" then
        pcall(function()
            v:Destroy()
        end)
    end
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "CafeinaBotReader_V2"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = true
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = Parent

-- ============================================================
-- CORES
-- ============================================================

local COLORS = {
    bg = Color3.fromRGB(12,12,15),
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

local function new(class, props)
    local x = Instance.new(class)

    for k, v in pairs(props or {}) do
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

-- ============================================================
-- CONFIGURAÇÃO DO COLETOR
-- ============================================================

local CONFIG = {
    SnapshotInterval = 2,
    MaxEvents = 25000,
    MaxSnapshotsPerBot = 1000,

    -- Pasta principal observada.
    CandidateFolderName = "Soldiers",

    -- Caso Soldiers não exista, o scanner pode procurar
    -- Models com Humanoid no Workspace.
    AllowWorkspaceFallback = true,
}

-- ============================================================
-- ESTADO
-- ============================================================

local State = {
    Running = false,
    Scanned = false,

    StartedAtUnix = nil,
    EndedAtUnix = nil,

    StartedAtClock = nil,
    EndedAtClock = nil,

    Records = {},
    ByInstance = {},

    Events = {},
    Players = {},

    Summary = {
        spawned = 0,
        removed = 0,
        army = 0,
        rebels = 0,
        unknown = 0,
    },

    Connections = {},
}

-- ============================================================
-- UTILITÁRIOS
-- ============================================================

local function nowUnix()
    return os.time()
end

local function nowClock()
    return os.clock()
end

local function elapsed()
    if not State.StartedAtClock then
        return 0
    end

    return nowClock() - State.StartedAtClock
end

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

    if ok then
        return tostring(result)
    end

    return safeName(x)
end

local function safeClass(x)
    local ok, result = pcall(function()
        return x.ClassName
    end)

    return ok and tostring(result) or "?"
end

local function isA(x, class)
    local ok, result = pcall(function()
        return x:IsA(class)
    end)

    return ok and result
end

local function getAttribute(x, key)
    local ok, result = pcall(function()
        return x:GetAttribute(key)
    end)

    if ok then
        return result
    end

    return nil
end

local function safeAttributes(x)
    local result = {}

    pcall(function()
        for key, value in pairs(x:GetAttributes()) do
            result[tostring(key)] = tostring(value)
        end
    end)

    return result
end

local function safePosition(model)
    local root =
        model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")

    if not root then
        return nil
    end

    local ok, pos = pcall(function()
        return root.Position
    end)

    if not ok then
        return nil
    end

    return {
        x = pos.X,
        y = pos.Y,
        z = pos.Z,
    }
end

local function getHumanoid(model)
    return model:FindFirstChildOfClass("Humanoid")
end

local function isPlayerCharacter(model)
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character == model then
            return true
        end
    end

    return false
end

-- ============================================================
-- TEAM
-- ============================================================

local function inspectTeam(model)
    local result = {
        value = nil,
        source = nil,
        objectName = nil,
        objectPath = nil,
        objectClass = nil,
    }

    -- 1. Attribute Team
    local attributeTeam = getAttribute(model, "Team")

    if attributeTeam ~= nil then
        result.value = tostring(attributeTeam)
        result.source = "Attribute"
        return result
    end

    -- 2. StringValue / ObjectValue / outros objetos chamados Team
    local teamObject = model:FindFirstChild("Team", true)

    if teamObject then
        result.objectName = safeName(teamObject)
        result.objectPath = safeFullName(teamObject)
        result.objectClass = safeClass(teamObject)

        if isA(teamObject, "StringValue") then
            local ok, value = pcall(function()
                return teamObject.Value
            end)

            if ok then
                result.value = tostring(value)
                result.source = "StringValue"
                return result
            end
        end

        if isA(teamObject, "ObjectValue") then
            local ok, value = pcall(function()
                return teamObject.Value
            end)

            if ok and value then
                result.value = safeName(value)
                result.source = "ObjectValue"
                result.objectPath = safeFullName(value)
                result.objectClass = safeClass(value)
                return result
            end
        end

        local ok, value = pcall(function()
            return teamObject.Value
        end)

        if ok and value ~= nil then
            result.value = tostring(value)
            result.source = "ValueObject"
            return result
        end
    end

    -- 3. Child chamado Team sem Value
    if teamObject then
        result.source = "Object"
        return result
    end

    return result
end

local function normalizeTeam(team)
    if not team then
        return "Unknown"
    end

    local lower = tostring(team):lower()

    if lower == "army" then
        return "Army"
    end

    if lower == "rebels" then
        return "Rebels"
    end

    return tostring(team)
end

-- ============================================================
-- HIGHLIGHT
-- ============================================================

local function inspectHighlight(model)
    local highlight = model:FindFirstChildWhichIsA("Highlight", true)

    if not highlight then
        return {
            exists = false
        }
    end

    local result = {
        exists = true,
        name = safeName(highlight),
        path = safeFullName(highlight),
        enabled = nil,
        depthMode = nil,
        fillTransparency = nil,
        outlineTransparency = nil,
        fillColor = nil,
        outlineColor = nil,
    }

    pcall(function()
        result.enabled = highlight.Enabled
        result.depthMode = tostring(highlight.DepthMode)
        result.fillTransparency = highlight.FillTransparency
        result.outlineTransparency = highlight.OutlineTransparency
        result.fillColor = tostring(highlight.FillColor)
        result.outlineColor = tostring(highlight.OutlineColor)
    end)

    return result
end

-- ============================================================
-- OBJETOS INTERNOS
-- ============================================================

local function collectObjectTree(model)
    local result = {}

    for _, descendant in ipairs(model:GetDescendants()) do
        result[#result + 1] = {
            name = safeName(descendant),
            className = safeClass(descendant),
            path = safeFullName(descendant),
        }
    end

    return result
end

local function buildObjectSet(model)
    local set = {}

    for _, descendant in ipairs(model:GetDescendants()) do
        set[descendant] = true
    end

    return set
end

-- ============================================================
-- SNAPSHOT
-- ============================================================

local function buildSnapshot(record)
    local model = record.instance

    if not model or not model.Parent then
        return nil
    end

    local humanoid = getHumanoid(model)
    local team = inspectTeam(model)
    local highlight = inspectHighlight(model)

    local snapshot = {
        elapsed = elapsed(),
        unix = nowUnix(),

        name = safeName(model),
        path = safeFullName(model),

        team = team.value,
        teamSource = team.source,

        teamObjectName = team.objectName,
        teamObjectPath = team.objectPath,
        teamObjectClass = team.objectClass,

        attributes = safeAttributes(model),

        highlight = highlight,

        humanoid = nil,

        position = safePosition(model),
    }

    if humanoid then
        snapshot.humanoid = {
            health = humanoid.Health,
            maxHealth = humanoid.MaxHealth,
            walkSpeed = humanoid.WalkSpeed,
            jumpPower = humanoid.JumpPower,
            rigType = tostring(humanoid.RigType),
            moveDirection = {
                x = humanoid.MoveDirection.X,
                y = humanoid.MoveDirection.Y,
                z = humanoid.MoveDirection.Z,
            }
        }
    end

    return snapshot
end

-- ============================================================
-- EVENTOS
-- ============================================================

local function addEvent(eventType, record, data)
    if #State.Events >= CONFIG.MaxEvents then
        return
    end

    local event = {
        type = eventType,

        elapsed = elapsed(),
        unix = nowUnix(),

        botId = record and record.id or nil,

        botName = record and record.name or nil,

        botPath = nil,
        data = data or {},
    }

    if record and record.instance then
        pcall(function()
            event.botPath = record.instance:GetFullName()
        end)
    end

    State.Events[#State.Events + 1] = event
end

-- ============================================================
-- REGISTRO DE BOT
-- ============================================================

local NextBotId = 0

local function createBotId()
    NextBotId += 1

    return "BOT_" .. tostring(NextBotId)
end

local function registerBot(model, reason)
    if not model then
        return nil
    end

    if not isA(model, "Model") then
        return nil
    end

    if isPlayerCharacter(model) then
        return nil
    end

    if State.ByInstance[model] then
        return State.ByInstance[model]
    end

    local humanoid = getHumanoid(model)

    if not humanoid then
        return nil
    end

    local team = inspectTeam(model)
    local attributes = safeAttributes(model)
    local highlight = inspectHighlight(model)

    local record = {
        id = createBotId(),

        instance = model,

        name = safeName(model),
        pathAtSpawn = safeFullName(model),
        className = safeClass(model),

        spawnedAtUnix = nowUnix(),
        spawnedAtElapsed = elapsed(),

        spawnReason = reason or "UNKNOWN",

        initialTeam = team.value,
        initialTeamSource = team.source,

        initialAttributes = attributes,
        initialHighlight = highlight,

        snapshots = {},

        lastTeam = team.value,
        lastTeamSource = team.source,

        lastAttributes = attributes,
        lastHighlight = highlight,

        knownObjects = buildObjectSet(model),

        connections = {},

        removed = false,
        removedAtUnix = nil,
        removedAtElapsed = nil,
    }

    State.Records[#State.Records + 1] = record
    State.ByInstance[model] = record

    State.Summary.spawned += 1

    if normalizeTeam(team.value) == "Army" then
        State.Summary.army += 1
    elseif normalizeTeam(team.value) == "Rebels" then
        State.Summary.rebels += 1
    else
        State.Summary.unknown += 1
    end

    addEvent("BOT_SPAWN", record, {
        reason = reason or "UNKNOWN",
        team = team.value,
        teamSource = team.source,
        attributes = attributes,
        highlight = highlight,
    })

    local firstSnapshot = buildSnapshot(record)

    if firstSnapshot then
        record.snapshots[#record.snapshots + 1] = firstSnapshot
    end

    -- ========================================================
    -- ATTRIBUTE CHANGES
    -- ========================================================

    record.connections.attributeChanged =
        model.AttributeChanged:Connect(function(attributeName)
            if not State.Running then
                return
            end

            local currentAttributes = safeAttributes(model)

            addEvent("ATTRIBUTE_CHANGED", record, {
                attribute = tostring(attributeName),
                oldValue = record.lastAttributes[attributeName],
                newValue = currentAttributes[attributeName],
                attributes = currentAttributes,
            })

            record.lastAttributes = currentAttributes
        end)

    -- ========================================================
    -- OBJECTS CRIADOS
    -- ========================================================

    record.connections.childAdded =
        model.DescendantAdded:Connect(function(obj)
            if not State.Running then
                return
            end

            if record.knownObjects[obj] then
                return
            end

            record.knownObjects[obj] = true

            local isHighlight = isA(obj, "Highlight")

            addEvent(
                isHighlight and "HIGHLIGHT_CREATED" or "OBJECT_CREATED",
                record,
                {
                    name = safeName(obj),
                    className = safeClass(obj),
                    path = safeFullName(obj),
                }
            )
        end)

    -- ========================================================
    -- OBJETOS REMOVIDOS
    -- ========================================================

    record.connections.childRemoved =
        model.DescendantRemoving:Connect(function(obj)
            if not State.Running then
                return
            end

            if not record.knownObjects[obj] then
                return
            end

            record.knownObjects[obj] = nil

            addEvent("OBJECT_REMOVED", record, {
                name = safeName(obj),
                className = safeClass(obj),
                path = safeFullName(obj),
            })
        end)

    -- ========================================================
    -- HUMANOID
    -- ========================================================

    if humanoid then
        record.connections.died =
            humanoid.Died:Connect(function()
                addEvent("HUMANOID_DIED", record, {
                    health = humanoid.Health
                })
            end)
    end

    return record
end

-- ============================================================
-- MONITORAMENTO DE BOT
-- ============================================================

local function monitorBot(record)
    if record.removed then
        return
    end

    local model = record.instance

    if not model or not model.Parent then
        return
    end

    local team = inspectTeam(model)
    local highlight = inspectHighlight(model)
    local attributes = safeAttributes(model)

    -- ========================================================
    -- TEAM
    -- ========================================================

    if tostring(team.value) ~= tostring(record.lastTeam)
        or tostring(team.source) ~= tostring(record.lastTeamSource) then

        addEvent("TEAM_CHANGED", record, {
            oldTeam = record.lastTeam,
            newTeam = team.value,

            oldSource = record.lastTeamSource,
            newSource = team.source,

            objectName = team.objectName,
            objectPath = team.objectPath,
            objectClass = team.objectClass,
        })

        record.lastTeam = team.value
        record.lastTeamSource = team.source
    end

    -- ========================================================
    -- ATTRIBUTES
    -- ========================================================

    local changedAttributes = {}

    for key, value in pairs(attributes) do
        if record.lastAttributes[key] ~= value then
            changedAttributes[key] = {
                old = record.lastAttributes[key],
                new = value,
            }
        end
    end

    for key, oldValue in pairs(record.lastAttributes) do
        if attributes[key] == nil then
            changedAttributes[key] = {
                old = oldValue,
                new = nil,
            }
        end
    end

    if next(changedAttributes) then
        addEvent("ATTRIBUTES_CHANGED", record, {
            changes = changedAttributes
        })

        record.lastAttributes = attributes
    end

    -- ========================================================
    -- HIGHLIGHT
    -- ========================================================

    local oldHighlightJson =
        HttpService:JSONEncode(record.lastHighlight)

    local newHighlightJson =
        HttpService:JSONEncode(highlight)

    if oldHighlightJson ~= newHighlightJson then

        local eventType =
            (not record.lastHighlight.exists and highlight.exists)
            and "HIGHLIGHT_CREATED"
            or "HIGHLIGHT_CHANGED"

        addEvent(eventType, record, {
            previous = record.lastHighlight,
            current = highlight,
        })

        record.lastHighlight = highlight
    end

    -- ========================================================
    -- SNAPSHOT PERIÓDICO
    -- ========================================================

    if #record.snapshots < CONFIG.MaxSnapshotsPerBot then
        local snapshot = buildSnapshot(record)

        if snapshot then
            record.snapshots[#record.snapshots + 1] = snapshot
        end
    end
end

-- ============================================================
-- REMOÇÃO
-- ============================================================

local function unregisterBot(record, reason)
    if not record or record.removed then
        return
    end

    record.removed = true
    record.removedAtUnix = nowUnix()
    record.removedAtElapsed = elapsed()
    record.removeReason = reason or "UNKNOWN"

    State.Summary.removed += 1

    addEvent("BOT_REMOVED", record, {
        reason = reason or "UNKNOWN",
        lastTeam = record.lastTeam,
        lastTeamSource = record.lastTeamSource,
        lastAttributes = record.lastAttributes,
        lastHighlight = record.lastHighlight,
    })

    for _, connection in pairs(record.connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    record.connections = {}
end

-- ============================================================
-- DESCOBERTA DE SOLDIERS
-- ============================================================

local function getSoldiersFolder()
    return workspace:FindFirstChild(CONFIG.CandidateFolderName)
end

local function scanExistingSoldiers()
    local folder = getSoldiersFolder()

    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            registerBot(child, "EXISTING_SOLDIER")
        end

        return true
    end

    if CONFIG.AllowWorkspaceFallback then
        for _, inst in ipairs(workspace:GetDescendants()) do
            if isA(inst, "Model") and getHumanoid(inst) then
                registerBot(inst, "WORKSPACE_FALLBACK")
            end
        end
    end

    return false
end

-- ============================================================
-- MONITOR DA PASTA SOLDIERS
-- ============================================================

local function attachSoldiersMonitor()
    local folder = getSoldiersFolder()

    if not folder then
        return
    end

    State.Connections.soldierAdded =
        folder.ChildAdded:Connect(function(child)
            if not State.Running then
                return
            end

            task.defer(function()
                registerBot(child, "SOLDIERS_CHILD_ADDED")
            end)
        end)

    State.Connections.soldierRemoving =
        folder.ChildRemoved:Connect(function(child)
            local record = State.ByInstance[child]

            if record then
                unregisterBot(record, "SOLDIER_REMOVED")
            end
        end)
end

-- ============================================================
-- FALLBACK PARA NOVOS MODELS
-- ============================================================

local function attachWorkspaceFallback()
    if not CONFIG.AllowWorkspaceFallback then
        return
    end

    State.Connections.workspaceAdded =
        workspace.DescendantAdded:Connect(function(obj)
            if not State.Running then
                return
            end

            if not isA(obj, "Model") then
                return
            end

            -- Só aceitar diretamente modelos com Humanoid.
            if getHumanoid(obj) then
                task.defer(function()
                    if not State.ByInstance[obj] then
                        registerBot(obj, "WORKSPACE_MODEL_ADDED")
                    end
                end)
            end
        end)
end

-- ============================================================
-- PLAYER CONTEXT
-- ============================================================

local function registerPlayer(player, eventType)
    local teamName = nil

    pcall(function()
        if player.Team then
            teamName = player.Team.Name
        end
    end)

    State.Players[player.UserId] = {
        userId = player.UserId,
        name = player.Name,
        displayName = player.DisplayName,
        team = teamName,
        firstSeenUnix = State.Players[player.UserId]
            and State.Players[player.UserId].firstSeenUnix
            or nowUnix(),
    }

    addEvent(eventType, nil, {
        userId = player.UserId,
        name = player.Name,
        displayName = player.DisplayName,
        team = teamName,
    })
end

local function attachPlayerMonitor()
    for _, player in ipairs(Players:GetPlayers()) do
        registerPlayer(player, "PLAYER_PRESENT_AT_START")
    end

    State.Connections.playerAdded =
        Players.PlayerAdded:Connect(function(player)
            if not State.Running then
                return
            end

            registerPlayer(player, "PLAYER_JOINED")
        end)

    State.Connections.playerRemoving =
        Players.PlayerRemoving:Connect(function(player)
            if not State.Running then
                return
            end

            local old = State.Players[player.UserId]

            addEvent("PLAYER_LEFT", nil, {
                userId = player.UserId,
                name = player.Name,
                team = old and old.team or nil,
            })

            State.Players[player.UserId] = nil
        end)
end

-- ============================================================
-- PATROL POINTS
-- ============================================================

local function scanPatrolPoints()
    local result = {}

    local folder = workspace:FindFirstChild("BotPatrolPoints")

    if not folder then
        return result
    end

    for _, teamFolder in ipairs(folder:GetChildren()) do
        local points = {}

        for _, obj in ipairs(teamFolder:GetDescendants()) do
            if isA(obj, "BasePart") then
                points[#points + 1] = {
                    name = safeName(obj),
                    path = safeFullName(obj),
                    className = safeClass(obj),

                    teamAttribute = getAttribute(obj, "Team"),

                    position = {
                        x = obj.Position.X,
                        y = obj.Position.Y,
                        z = obj.Position.Z,
                    },

                    anchored = obj.Anchored,
                    transparency = obj.Transparency,
                }
            end
        end

        result[safeName(teamFolder)] = points
    end

    return result
end

-- ============================================================
-- START / STOP
-- ============================================================

local function disconnectAll()
    for _, connection in pairs(State.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    State.Connections = {}
end

local function StartScanner()
    if State.Running then
        return
    end

    State.Running = true
    State.Scanned = false

    State.StartedAtUnix = nowUnix()
    State.StartedAtClock = nowClock()

    State.EndedAtUnix = nil
    State.EndedAtClock = nil

    State.Records = {}
    State.ByInstance = {}
    State.Events = {}
    State.Players = {}

    State.Summary = {
        spawned = 0,
        removed = 0,
        army = 0,
        rebels = 0,
        unknown = 0,
    }

    addEvent("SCAN_STARTED", nil, {
        soldiersFolderExists = getSoldiersFolder() ~= nil,
    })

    attachPlayerMonitor()

    scanExistingSoldiers()

    attachSoldiersMonitor()
    attachWorkspaceFallback()

    State.Connections.monitor =
        task.spawn(function()
            while State.Running do

                for _, record in ipairs(State.Records) do
                    if not record.removed then
                        pcall(function()
                            monitorBot(record)
                        end)
                    end
                end

                task.wait(CONFIG.SnapshotInterval)
            end
        end)

    State.Scanned = true
end

local function StopScanner()
    if not State.Running then
        return
    end

    State.Running = false

    State.EndedAtUnix = nowUnix()
    State.EndedAtClock = nowClock()

    addEvent("SCAN_STOPPED", nil, {
        elapsed = elapsed(),
    })

    for _, record in ipairs(State.Records) do
        if not record.removed then
            unregisterBot(record, "SCAN_STOPPED")
        end
    end

    disconnectAll()
end

-- ============================================================
-- EXPORTAÇÃO
-- ============================================================

local function serializeRecord(record)
    local result = {
        id = record.id,

        name = record.name,
        pathAtSpawn = record.pathAtSpawn,
        className = record.className,

        spawnedAtUnix = record.spawnedAtUnix,
        spawnedAtElapsed = record.spawnedAtElapsed,

        spawnReason = record.spawnReason,

        initialTeam = record.initialTeam,
        initialTeamSource = record.initialTeamSource,

        initialAttributes = record.initialAttributes,
        initialHighlight = record.initialHighlight,

        removed = record.removed,
        removedAtUnix = record.removedAtUnix,
        removedAtElapsed = record.removedAtElapsed,
        removeReason = record.removeReason,

        lastTeam = record.lastTeam,
        lastTeamSource = record.lastTeamSource,

        lastAttributes = record.lastAttributes,
        lastHighlight = record.lastHighlight,

        snapshots = record.snapshots,
    }

    return result
end

local function buildExport()
    local bots = {}

    for _, record in ipairs(State.Records) do
        bots[#bots + 1] = serializeRecord(record)
    end

    local army = 0
    local rebels = 0
    local unknown = 0

    for _, record in ipairs(State.Records) do
        local team = normalizeTeam(record.lastTeam)

        if team == "Army" then
            army += 1
        elseif team == "Rebels" then
            rebels += 1
        else
            unknown += 1
        end
    end

    return {
        format = "Cafeina Bot Reader V2",
        version = 2,

        scan = {
            startedAtUnix = State.StartedAtUnix,
            endedAtUnix = State.EndedAtUnix,

            startedAtClock = State.StartedAtClock,
            endedAtClock = State.EndedAtClock,

            duration =
                State.EndedAtClock
                and State.StartedAtClock
                and (State.EndedAtClock - State.StartedAtClock)
                or elapsed(),
        },

        game = {
            placeId = game.PlaceId,
            gameId = game.GameId,
            jobId = game.JobId,
        },

        collector = {
            candidateFolder = CONFIG.CandidateFolderName,
            snapshotInterval = CONFIG.SnapshotInterval,

            note =
                "Coleta passiva. Team e sua fonte são dados prioritários; " ..
                "Highlight é evidência complementar.",
        },

        summary = {
            totalRecords = #bots,

            spawned = State.Summary.spawned,
            removed = State.Summary.removed,

            currentArmy = army,
            currentRebels = rebels,
            currentUnknown = unknown,

            totalEvents = #State.Events,
        },

        players = State.Players,

        patrolPoints = scanPatrolPoints(),

        events = State.Events,

        bots = bots,
    }
end

local function getJson()
    local ok, result = pcall(function()
        return HttpService:JSONEncode(buildExport())
    end)

    if ok then
        return result
    end

    return nil, result
end

local function exportData()
    if not State.Scanned then
        return false, "Faça uma coleta primeiro."
    end

    if State.Running then
        StopScanner()
    end

    local data, err = getJson()

    if not data then
        return false, "Falha no JSON: " .. tostring(err)
    end

    local filename =
        "Cafeina_BotReader_V2_"
        .. tostring(game.PlaceId)
        .. "_"
        .. tostring(State.StartedAtUnix or nowUnix())
        .. ".json"

    local wrote = false

    if typeof(writefile) == "function" then
        local ok = pcall(function()
            writefile(filename, data)
        end)

        wrote = ok
    end

    if wrote then
        return true, "Arquivo salvo: " .. filename
    end

    if typeof(setclipboard) == "function" then
        local ok = pcall(function()
            setclipboard(data)
        end)

        if ok then
            return true,
                "writefile indisponível. JSON copiado para a área de transferência."
        end
    end

    return false,
        "Ambiente não possui writefile nem setclipboard."
end

-- ============================================================
-- INTERFACE
-- ============================================================

local Main = new("Frame", {
    Parent = Gui,

    Size = UDim2.fromOffset(620, 520),

    Position = UDim2.new(.5, -310, .5, -260),

    BackgroundColor3 = COLORS.bg,
    BorderSizePixel = 0,
})

round(Main, 16)

local Header = new("Frame", {
    Parent = Main,

    Size = UDim2.new(1, 0, 0, 72),

    BackgroundColor3 = COLORS.panel,
    BorderSizePixel = 0,
})

round(Header, 16)

label(
    Header,
    "CAFÉÍNA • BOT READER V2",
    UDim2.new(1, -150, 0, 30),
    UDim2.fromOffset(22, 12),
    18
)

local HeaderSub = label(
    Header,
    "COLETOR PASSIVO • CICLO DE VIDA DOS BOTS",
    UDim2.new(1, -150, 0, 20),
    UDim2.fromOffset(22, 42),
    9
)

HeaderSub.TextColor3 = COLORS.sub

local Min = new("TextButton", {
    Parent = Header,

    Size = UDim2.fromOffset(42, 42),
    Position = UDim2.new(1, -100, 0, 15),

    Text = "—",

    BackgroundColor3 = COLORS.panel2,
    TextColor3 = COLORS.text,

    Font = Enum.Font.GothamBold,
    TextSize = 20,

    BorderSizePixel = 0,
})

round(Min, 10)

local Close = new("TextButton", {
    Parent = Header,

    Size = UDim2.fromOffset(42, 42),
    Position = UDim2.new(1, -50, 0, 15),

    Text = "×",

    BackgroundColor3 = COLORS.red,
    TextColor3 = COLORS.text,

    Font = Enum.Font.GothamBold,
    TextSize = 23,

    BorderSizePixel = 0,
})

round(Close, 10)

-- ============================================================
-- STATUS
-- ============================================================

local Status = label(
    Main,
    "Pronto para iniciar a coleta.",
    UDim2.new(1, -44, 0, 25),
    UDim2.fromOffset(22, 88),
    11
)

Status.TextColor3 = COLORS.sub

-- ============================================================
-- BOTÕES
-- ============================================================

local StartButton = new("TextButton", {
    Parent = Main,

    Size = UDim2.new(.5, -28, 0, 52),
    Position = UDim2.fromOffset(22, 122),

    Text = "INICIAR COLETA",

    BackgroundColor3 = COLORS.blue2,
    TextColor3 = COLORS.text,

    Font = Enum.Font.GothamBold,
    TextSize = 11,

    BorderSizePixel = 0,
})

round(StartButton, 10)

local ExportButton = new("TextButton", {
    Parent = Main,

    Size = UDim2.new(.5, -28, 0, 52),
    Position = UDim2.new(.5, 6, 0, 122),

    Text = "FINALIZAR E EXPORTAR",

    BackgroundColor3 = COLORS.blue,
    TextColor3 = COLORS.text,

    Font = Enum.Font.GothamBold,
    TextSize = 11,

    BorderSizePixel = 0,
})

round(ExportButton, 10)

-- ============================================================
-- RESUMO
-- ============================================================

local Summary = new("TextLabel", {
    Parent = Main,

    Size = UDim2.new(1, -44, 0, 66),
    Position = UDim2.fromOffset(22, 188),

    BackgroundColor3 = COLORS.panel,

    Text = "Nenhuma coleta realizada.",

    TextColor3 = COLORS.text,

    Font = Enum.Font.Gotham,
    TextSize = 11,

    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,

    BorderSizePixel = 0,
})

round(Summary, 10)

-- ============================================================
-- VIEWER
-- ============================================================

local Viewer = new("TextBox", {
    Parent = Main,

    Size = UDim2.new(1, -44, 1, -274),
    Position = UDim2.fromOffset(22, 270),

    BackgroundColor3 = COLORS.panel,

    Text = "",

    TextColor3 = COLORS.text,

    Font = Enum.Font.Code,
    TextSize = 9,

    MultiLine = true,
    ClearTextOnFocus = false,
    TextEditable = false,

    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,

    BorderSizePixel = 0,
})

round(Viewer, 10)

-- ============================================================
-- PREVIEW
-- ============================================================

local function updatePreview()
    local lines = {}

    lines[#lines + 1] = "CAFÉÍNA • BOT READER V2"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "STATUS"
    lines[#lines + 1] = "  Coleta: " .. (State.Running and "ATIVA" or "FINALIZADA")
    lines[#lines + 1] = "  Eventos: " .. tostring(#State.Events)
    lines[#lines + 1] = ""

    lines[#lines + 1] = "ENTIDADES"
    lines[#lines + 1] = "  Spawn registrados: " .. tostring(State.Summary.spawned)
    lines[#lines + 1] = "  Removidos: " .. tostring(State.Summary.removed)

    lines[#lines + 1] = ""

    lines[#lines + 1] = "EQUIPE OBSERVADA"

    local army = 0
    local rebels = 0
    local unknown = 0

    for _, record in ipairs(State.Records) do
        local team = normalizeTeam(record.lastTeam)

        if team == "Army" then
            army += 1
        elseif team == "Rebels" then
            rebels += 1
        else
            unknown += 1
        end
    end

    lines[#lines + 1] = "  Army: " .. tostring(army)
    lines[#lines + 1] = "  Rebels: " .. tostring(rebels)
    lines[#lines + 1] = "  Unknown: " .. tostring(unknown)

    lines[#lines + 1] = ""
    lines[#lines + 1] = "ÚLTIMOS EVENTOS"

    local startIndex = math.max(1, #State.Events - 14)

    for i = startIndex, #State.Events do
        local event = State.Events[i]

        lines[#lines + 1] =
            string.format(
                "[%8.3f] %-24s %s",
                tonumber(event.elapsed) or 0,
                tostring(event.type),
                tostring(event.botId or "")
            )
    end

    Viewer.Text = table.concat(lines, "\n")

    Summary.Text =
        "Bots registrados: "
        .. tostring(#State.Records)
        .. "   •   Army: "
        .. tostring(army)
        .. "   •   Rebels: "
        .. tostring(rebels)
        .. "   •   Eventos: "
        .. tostring(#State.Events)
end

-- ============================================================
-- AÇÕES
-- ============================================================

StartButton.Activated:Connect(function()
    if State.Running then
        Status.Text = "A coleta já está em execução."
        return
    end

    Status.Text = "Iniciando coleta..."

    local ok, err = pcall(StartScanner)

    if ok then
        Status.Text = "Coleta ativa. Monitorando Soldiers, Team, Attributes e Highlight."
        Status.TextColor3 = COLORS.green

        StartButton.Text = "COLETA EM EXECUÇÃO"

        task.spawn(function()
            while State.Running do
                updatePreview()
                task.wait(1)
            end

            updatePreview()
        end)
    else
        Status.Text = "Erro ao iniciar: " .. tostring(err)
        Status.TextColor3 = COLORS.red
    end
end)

ExportButton.Activated:Connect(function()
    if not State.Scanned then
        Status.Text = "Nenhuma coleta foi realizada."
        Status.TextColor3 = COLORS.yellow
        return
    end

    Status.Text = "Finalizando coleta e preparando JSON..."

    local ok, message = pcall(function()
        return exportData()
    end)

    if not ok then
        Status.Text = "Erro na exportação: " .. tostring(message)
        Status.TextColor3 = COLORS.red
        return
    end

    local success, text = message, select(2, exportData)

    if success then
        Status.Text = text
        Status.TextColor3 = COLORS.green
    else
        Status.Text = text
        Status.TextColor3 = COLORS.yellow
    end

    StartButton.Text = "INICIAR NOVA COLETA"

    updatePreview()
end)

-- ============================================================
-- MINIMIZAR
-- ============================================================

local Mini = new("TextButton", {
    Parent = Gui,

    Size = UDim2.fromOffset(60, 60),

    Position = UDim2.new(.5, -30, .5, -30),

    BackgroundColor3 = COLORS.blue,

    Text = "C",

    TextColor3 = COLORS.text,

    Font = Enum.Font.GothamBlack,
    TextSize = 22,

    BorderSizePixel = 0,

    Visible = false,
})

round(Mini, 100)

Min.Activated:Connect(function()
    Main.Visible = false
    Mini.Visible = true
end)

Mini.Activated:Connect(function()
    Main.Visible = true
    Mini.Visible = false
end)

Close.Activated:Connect(function()
    State.Running = false

    pcall(function()
        StopScanner()
    end)

    pcall(function()
        Gui:Destroy()
    end)
end)

-- ============================================================
-- ARRASTAR BOTÃO FLUTUANTE
-- ============================================================

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

        local delta = input.Position - dragStart

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

-- ============================================================
-- FINAL
-- ============================================================

updatePreview()
