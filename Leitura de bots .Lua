--==============================================================
-- CAFEÍNA • LEITURA / PESQUISA DE BOTS
-- VERSÃO INTEGRADA • SOMENTE LEITURA
--
-- Registra:
--   • Spawn / despawn
--   • Estrutura do bot
--   • Indicadores de equipe
--   • Alterações de equipe
--   • Attributes
--   • ValueObjects / ObjectValues relevantes
--   • Criação / remoção de objetos
--   • Highlight como verificação complementar
--   • Snapshots periódicos
--   • Estado do jogador no momento dos eventos
--
-- Não modifica bots, equipes, IA, alvos ou spawn.
--==============================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

--==============================================================
-- PARENT
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

-- Remove somente esta interface.
for _, v in ipairs(Parent:GetChildren()) do
    if v.Name == "CafeinaBotResearch_Standalone" then
        pcall(function()
            v:Destroy()
        end)
    end
end

--==============================================================
-- GUI
--==============================================================

local Gui = Instance.new("ScreenGui")
Gui.Name = "CafeinaBotResearch_Standalone"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = true
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = Parent

--==============================================================
-- CORES
--==============================================================

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
    yellow = Color3.fromRGB(242,184,57)
}

--==============================================================
-- HELPERS GUI
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

        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center
    })
end

--==============================================================
-- ESTADO DO PESQUISADOR
--==============================================================

local State = {
    Running = false,

    StartedClock = nil,
    StartedUnix = nil,

    EndedClock = nil,
    EndedUnix = nil,

    NextBotId = 0,

    Bots = {},
    ObjectToBot = {},

    ImportantEvents = {},
    VisualChecks = {},
    Snapshots = {},

    Connections = {},

    SnapshotThread = nil
}

local CONFIG = {
    SnapshotInterval = 5,

    InterestingNames = {
        "team",
        "teamname",
        "teamcolor",

        "target",
        "currenttarget",
        "targetplayer",

        "enemy",
        "ally",

        "patrol",
        "destination",
        "goal",

        "spawn"
    }
}

--==============================================================
-- UTILIDADES
--==============================================================

local function clock()
    return os.clock()
end

local function unix()
    return os.time()
end

local function safeName(obj)
    local ok, value = pcall(function()
        return obj.Name
    end)

    return ok and tostring(value) or "?"
end

local function safeFullName(obj)
    local ok, value = pcall(function()
        return obj:GetFullName()
    end)

    return ok and tostring(value) or safeName(obj)
end

local function safeClass(obj)
    local ok, value = pcall(function()
        return obj.ClassName
    end)

    return ok and tostring(value) or "?"
end

local function safeAttribute(obj, key)
    local ok, value = pcall(function()
        return obj:GetAttribute(key)
    end)

    if ok then
        return value
    end

    return nil
end

local function serializeValue(value)
    local t = typeof(value)

    if t == "Vector3" then
        return {
            x = value.X,
            y = value.Y,
            z = value.Z
        }
    end

    if t == "Color3" then
        return {
            r = value.R,
            g = value.G,
            b = value.B
        }
    end

    if t == "CFrame" then
        local p = value.Position

        return {
            x = p.X,
            y = p.Y,
            z = p.Z
        }
    end

    if t == "Instance" then
        return {
            type = "Instance",
            name = safeName(value),
            path = safeFullName(value),
            className = safeClass(value)
        }
    end

    if t == "string"
        or t == "number"
        or t == "boolean"
        or t == "nil" then

        return value
    end

    return tostring(value)
end

local function jsonEncode(data)
    local ok, result = pcall(function()
        return HttpService:JSONEncode(data)
    end)

    return ok and result or nil
end

--==============================================================
-- PLAYER STATE
--==============================================================

local function getPlayerState()
    local result = {
        name = LocalPlayer and LocalPlayer.Name or nil,
        userId = LocalPlayer and LocalPlayer.UserId or nil,

        team = nil,
        teamColor = nil
    }

    if not LocalPlayer then
        return result
    end

    pcall(function()
        if LocalPlayer.Team then
            result.team = LocalPlayer.Team.Name
        end

        if LocalPlayer.TeamColor then
            result.teamColor = tostring(LocalPlayer.TeamColor)
        end
    end)

    return result
end

--==============================================================
-- EVENTOS
--==============================================================

local function important(typeName, data)
    State.ImportantEvents[#State.ImportantEvents + 1] = {
        type = typeName,

        time = clock(),
        unix = unix(),

        data = data or {}
    }
end

local function visual(typeName, data)
    State.VisualChecks[#State.VisualChecks + 1] = {
        type = typeName,

        time = clock(),
        unix = unix(),

        data = data or {}
    }
end

--==============================================================
-- ATRIBUTOS
--==============================================================

local function readAttributes(model)
    local result = {}

    pcall(function()
        for key, value in pairs(model:GetAttributes()) do
            result[tostring(key)] = serializeValue(value)
        end
    end)

    return result
end

--==============================================================
-- TEAM
--==============================================================

local function inspectTeam(model)

    local result = {
        attribute = nil,
        values = {},
        teamColor = nil
    }

    -- Attribute "Team"
    local teamAttribute = safeAttribute(model, "Team")

    if teamAttribute ~= nil then
        result.attribute = serializeValue(teamAttribute)
    end

    -- Objetos relacionados a Team
    for _, obj in ipairs(model:GetDescendants()) do

        local name = safeName(obj):lower()

        if name == "team"
            or name == "teamname"
            or name == "teamcolor" then

            if obj:IsA("ValueBase") then

                local ok, value = pcall(function()
                    return obj.Value
                end)

                if ok then
                    local record = {
                        name = safeName(obj),
                        path = safeFullName(obj),
                        className = safeClass(obj),

                        value = serializeValue(value)
                    }

                    if obj:IsA("ObjectValue") and obj.Value then
                        record.referencedObject = {
                            name = safeName(obj.Value),
                            path = safeFullName(obj.Value),
                            className = safeClass(obj.Value)
                        }
                    end

                    result.values[#result.values + 1] = record
                end
            end
        end
    end

    return result
end

--==============================================================
-- HUMANOID
--==============================================================

local function inspectHumanoid(model)

    local humanoid = model:FindFirstChildOfClass("Humanoid")

    if not humanoid then
        return nil
    end

    local result = {}

    pcall(function()
        result.health = humanoid.Health
        result.maxHealth = humanoid.MaxHealth

        result.walkSpeed = humanoid.WalkSpeed
        result.jumpPower = humanoid.JumpPower

        result.rigType = tostring(humanoid.RigType)
        result.state = tostring(humanoid:GetState())

        result.moveDirection = serializeValue(
            humanoid.MoveDirection
        )
    end)

    return result
end

--==============================================================
-- HIGHLIGHT
--==============================================================

local function inspectHighlight(model)

    local result = {
        exists = false,

        enabled = nil,

        fillColor = nil,
        outlineColor = nil,

        depthMode = nil,

        adornee = nil
    }

    for _, obj in ipairs(model:GetDescendants()) do

        if obj:IsA("Highlight") then

            result.exists = true

            pcall(function()

                result.enabled = obj.Enabled

                result.fillColor =
                    serializeValue(obj.FillColor)

                result.outlineColor =
                    serializeValue(obj.OutlineColor)

                result.depthMode =
                    tostring(obj.DepthMode)

                if obj.Adornee then
                    result.adornee = {
                        name = safeName(obj.Adornee),
                        path = safeFullName(obj.Adornee),
                        className = safeClass(obj.Adornee)
                    }
                end
            end)

            break
        end
    end

    return result
end

--==============================================================
-- OBJETOS INTERESSANTES
--==============================================================

local function inspectInterestingObjects(model)

    local result = {}

    for _, obj in ipairs(model:GetDescendants()) do

        local name = safeName(obj):lower()

        for _, interesting in ipairs(CONFIG.InterestingNames) do

            if name == interesting then

                local record = {
                    name = safeName(obj),
                    path = safeFullName(obj),
                    className = safeClass(obj)
                }

                if obj:IsA("ValueBase") then

                    pcall(function()
                        record.value =
                            serializeValue(obj.Value)
                    end)

                end

                if obj:IsA("ObjectValue") then

                    pcall(function()

                        if obj.Value then
                            record.referencedObject = {
                                name = safeName(obj.Value),
                                path = safeFullName(obj.Value),
                                className = safeClass(obj.Value)
                            }
                        end

                    end)
                end

                result[#result + 1] = record

                break
            end
        end
    end

    return result
end

--==============================================================
-- ROOT
--==============================================================

local function getRoot(model)

    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")
end

--==============================================================
-- SNAPSHOT DE BOT
--==============================================================

local function buildBotSnapshot(bot)

    local model = bot.model

    if not model or not model.Parent then
        return nil
    end

    local result = {
        time = clock(),
        unix = unix(),

        path = safeFullName(model),

        playerState = getPlayerState(),

        team = inspectTeam(model),

        attributes = readAttributes(model),

        humanoid = inspectHumanoid(model),

        highlight = inspectHighlight(model),

        interestingObjects =
            inspectInterestingObjects(model)
    }

    local root = getRoot(model)

    if root then

        pcall(function()

            result.position =
                serializeValue(root.Position)

        end)
    end

    return result
end

--==============================================================
-- IDENTIFICAÇÃO DE PLAYER
--==============================================================

local function isPlayerCharacter(model)

    for _, player in ipairs(Players:GetPlayers()) do

        if player.Character == model then
            return true
        end

    end

    return false
end

--==============================================================
-- CANDIDATO A BOT
--==============================================================

local function isBotCandidate(obj)

    if not obj:IsA("Model") then
        return false
    end

    if isPlayerCharacter(obj) then
        return false
    end

    if not obj:FindFirstChildOfClass("Humanoid") then
        return false
    end

    return true
end

--==============================================================
-- REGISTRAR BOT
--==============================================================

local function registerBot(model)

    if State.ObjectToBot[model] then
        return State.ObjectToBot[model]
    end

    State.NextBotId += 1

    local botId = State.NextBotId

    local initialTeam = inspectTeam(model)

    local bot = {

        id = botId,

        model = model,

        name = safeName(model),

        spawnPath = safeFullName(model),
        className = safeClass(model),

        firstSeen = clock(),
        firstSeenUnix = unix(),

        initialTeam = initialTeam,

        initialAttributes =
            readAttributes(model),

        teamHistory = {},

        attributeEvents = {},
        objectEvents = {},

        snapshots = {},

        highlightInitial =
            inspectHighlight(model),

        knownObjects = {},

        lastAttributes =
            readAttributes(model),

        lastTeamSignature =
            jsonEncode(initialTeam),

        lastHighlight =
            inspectHighlight(model),

        removed = false,

        removedAt = nil,
        removedAtUnix = nil
    }

    State.Bots[botId] = bot
    State.ObjectToBot[model] = bot

    bot.teamHistory[#bot.teamHistory + 1] = {
        time = clock(),
        unix = unix(),

        team = initialTeam
    }

    -- Evento principal de spawn
    important("BOT_SPAWN", {

        botId = botId,

        name = safeName(model),

        path = safeFullName(model),

        className = safeClass(model),

        initialTeam = initialTeam,

        playerState = getPlayerState()
    })

    -- Highlight é somente verificação complementar.
    visual("HIGHLIGHT_INITIAL", {

        botId = botId,

        highlight =
            bot.highlightInitial,

        playerState =
            getPlayerState()
    })

    -- Captura inicial.
    local snapshot =
        buildBotSnapshot(bot)

    if snapshot then
        bot.snapshots[#bot.snapshots + 1] =
            snapshot
    end

    -- Registra objetos já existentes.
    for _, obj in ipairs(model:GetDescendants()) do

        local path = safeFullName(obj)

        bot.knownObjects[path] = {
            name = safeName(obj),
            path = path,
            className = safeClass(obj)
        }
    end

    return bot
end

--==============================================================
-- TEAM MONITOR
--==============================================================

local function monitorTeam(bot)

    local model = bot.model

    if not model or not model.Parent then
        return
    end

    local current = inspectTeam(model)

    local signature =
        jsonEncode(current)

    if signature ~= bot.lastTeamSignature then

        local previous =
            bot.teamHistory[#bot.teamHistory]

        bot.teamHistory[#bot.teamHistory + 1] = {

            time = clock(),
            unix = unix(),

            team = current
        }

        important("TEAM_CHANGED", {

            botId = bot.id,

            previous =
                previous and previous.team or nil,

            current = current,

            playerState =
                getPlayerState()
        })

        bot.lastTeamSignature = signature
    end
end

--==============================================================
-- ATTRIBUTE MONITOR
--==============================================================

local function monitorAttributes(bot)

    local model = bot.model

    if not model or not model.Parent then
        return
    end

    local current =
        readAttributes(model)

    local previous =
        bot.lastAttributes or {}

    for key, value in pairs(current) do

        if previous[key] ~= value then

            bot.attributeEvents[#bot.attributeEvents + 1] = {

                time = clock(),
                unix = unix(),

                attribute = key,

                previous = previous[key],
                current = value
            }

            important("ATTRIBUTE_CHANGED", {

                botId = bot.id,

                attribute = key,

                previous = previous[key],
                current = value,

                playerState =
                    getPlayerState()
            })
        end
    end

    for key, oldValue in pairs(previous) do

        if current[key] == nil then

            bot.attributeEvents[#bot.attributeEvents + 1] = {

                time = clock(),
                unix = unix(),

                attribute = key,

                previous = oldValue,
                current = nil
            }

            important("ATTRIBUTE_REMOVED", {

                botId = bot.id,

                attribute = key,

                previous = oldValue
            })
        end
    end

    bot.lastAttributes = current
end

--==============================================================
-- OBJECT MONITOR
--==============================================================

local function monitorObjects(bot)

    local model = bot.model

    if not model or not model.Parent then
        return
    end

    local current = {}

    for _, obj in ipairs(model:GetDescendants()) do

        local path =
            safeFullName(obj)

        current[path] = {

            name = safeName(obj),
            path = path,
            className = safeClass(obj)
        }
    end

    local previous =
        bot.knownObjects or {}

    for path, objectData in pairs(current) do

        if not previous[path] then

            bot.objectEvents[#bot.objectEvents + 1] = {

                time = clock(),
                unix = unix(),

                action = "CREATED",

                object = objectData
            }

            important("OBJECT_CREATED", {

                botId = bot.id,

                object = objectData
            })
        end
    end

    for path, objectData in pairs(previous) do

        if not current[path] then

            bot.objectEvents[#bot.objectEvents + 1] = {

                time = clock(),
                unix = unix(),

                action = "REMOVED",

                object = objectData
            }

            important("OBJECT_REMOVED", {

                botId = bot.id,

                object = objectData
            })
        end
    end

    bot.knownObjects = current
end

--==============================================================
-- HIGHLIGHT MONITOR
--==============================================================

local function monitorHighlight(bot)

    local model = bot.model

    if not model or not model.Parent then
        return
    end

    local current =
        inspectHighlight(model)

    local previous =
        bot.lastHighlight

    local oldSignature =
        jsonEncode(previous)

    local newSignature =
        jsonEncode(current)

    if oldSignature ~= newSignature then

        visual("HIGHLIGHT_CHANGED", {

            botId = bot.id,

            previous = previous,
            current = current,

            playerState =
                getPlayerState()
        })

        bot.lastHighlight = current
    end
end

--==============================================================
-- BOT REMOVIDO
--==============================================================

local function removeBot(bot)

    if bot.removed then
        return
    end

    bot.removed = true

    bot.removedAt = clock()
    bot.removedAtUnix = unix()

    important("BOT_REMOVED", {

        botId = bot.id,

        name = bot.name,

        path = bot.spawnPath,

        lifetime =
            bot.removedAt - bot.firstSeen,

        playerState =
            getPlayerState()
    })
end

--==============================================================
-- MONITOR GERAL
--==============================================================

local function monitorBots()

    for _, bot in pairs(State.Bots) do

        if bot.removed then
            continue
        end

        if not bot.model
            or not bot.model.Parent then

            removeBot(bot)

            continue
        end

        monitorTeam(bot)

        monitorAttributes(bot)

        monitorObjects(bot)

        monitorHighlight(bot)
    end
end

--==============================================================
-- SNAPSHOT GLOBAL
--==============================================================

local function createSnapshot()

    local snapshot = {

        time = clock(),
        unix = unix(),

        playerState =
            getPlayerState(),

        bots = {

            total = 0,

            army = 0,
            rebels = 0,

            unknown = 0
        }
    }

    for _, bot in pairs(State.Bots) do

        if not bot.removed then

            snapshot.bots.total += 1

            local team =
                inspectTeam(bot.model)

            local value =
                team.attribute

            if value == "Army" then

                snapshot.bots.army += 1

            elseif value == "Rebels" then

                snapshot.bots.rebels += 1

            else

                snapshot.bots.unknown += 1
            end
        end
    end

    State.Snapshots[#State.Snapshots + 1] =
        snapshot
end

--==============================================================
-- SCAN INICIAL
--==============================================================

local function scanExisting()

    for _, obj in ipairs(
        workspace:GetDescendants()
    ) do

        if isBotCandidate(obj) then
            registerBot(obj)
        end
    end
end

--==============================================================
-- DADOS PARA EXPORTAÇÃO
--==============================================================

local function buildExport()

    local bots = {}

    for id, bot in pairs(State.Bots) do

        bots[tostring(id)] = {

            id = bot.id,

            name = bot.name,

            spawn = {

                time = bot.firstSeen,

                unix = bot.firstSeenUnix,

                path = bot.spawnPath,

                className =
                    bot.className
            },

            initialTeam =
                bot.initialTeam,

            teamHistory =
                bot.teamHistory,

            initialAttributes =
                bot.initialAttributes,

            attributeEvents =
                bot.attributeEvents,

            objectEvents =
                bot.objectEvents,

            highlightInitial =
                bot.highlightInitial,

            snapshots =
                bot.snapshots,

            removed =
                bot.removed,

            removedAt =
                bot.removedAt,

            removedAtUnix =
                bot.removedAtUnix
        }
    end

    return {

        format =
            "Cafeina Bot Research",

        version =
            "Integrated-2.0",

        description =
            "Somente leitura. Dados observados no ambiente do cliente.",

        session = {

            startedAt =
                State.StartedClock,

            startedAtUnix =
                State.StartedUnix,

            endedAt =
                State.EndedClock,

            endedAtUnix =
                State.EndedUnix,

            placeId =
                game.PlaceId,

            gameId =
                game.GameId,

            jobId =
                game.JobId
        },

        player = {

            current =
                getPlayerState()
        },

        importantEvents =
            State.ImportantEvents,

        visualChecks =
            State.VisualChecks,

        snapshots =
            State.Snapshots,

        bots =
            bots
    }
end

--==============================================================
-- EXPORT
--==============================================================

local function exportJSON()

    local data =
        buildExport()

    local ok, json =
        pcall(function()

            return HttpService:JSONEncode(data)

        end)

    if not ok then
        return nil
    end

    return json
end

--==============================================================
-- INTERFACE PRINCIPAL
--==============================================================

local Main = new("Frame", {

    Parent = Gui,

    Size =
        UDim2.fromOffset(520,430),

    Position =
        UDim2.new(
            .5,-260,
            .5,-215
        ),

    BackgroundColor3 =
        COLORS.bg,

    BorderSizePixel = 0
})

round(Main,14)

--==============================================================
-- HEADER
--==============================================================

local Header = new("Frame", {

    Parent = Main,

    Size =
        UDim2.new(1,0,0,55),

    BackgroundColor3 =
        COLORS.panel,

    BorderSizePixel = 0
})

round(Header,14)

label(
    Header,
    "CAFEÍNA • LEITURA DE BOTS",
    UDim2.new(1,-95,0,24),
    UDim2.fromOffset(14,7),
    15
)

local sub =
    label(
        Header,
        "PESQUISA DE COMPORTAMENTO • SOMENTE LEITURA",
        UDim2.new(1,-95,0,16),
        UDim2.fromOffset(14,31),
        9
    )

sub.TextColor3 =
    COLORS.sub

--==============================================================
-- MINIMIZAR
--==============================================================

local Min = new("TextButton", {

    Parent = Header,

    Size =
        UDim2.fromOffset(30,30),

    Position =
        UDim2.new(1,-76,0,11),

    Text = "—",

    BackgroundColor3 =
        COLORS.panel2,

    TextColor3 =
        COLORS.text,

    Font =
        Enum.Font.GothamBold,

    TextSize = 17,

    BorderSizePixel = 0
})

round(Min,8)

--==============================================================
-- FECHAR
--==============================================================

local Close = new("TextButton", {

    Parent = Header,

    Size =
        UDim2.fromOffset(30,30),

    Position =
        UDim2.new(1,-40,0,11),

    Text = "×",

    BackgroundColor3 =
        COLORS.red,

    TextColor3 =
        COLORS.text,

    Font =
        Enum.Font.GothamBold,

    TextSize = 18,

    BorderSizePixel = 0
})

round(Close,8)

--==============================================================
-- STATUS
--==============================================================

local Status =
    label(
        Main,
        "Pronto para iniciar a pesquisa.",
        UDim2.new(1,-28,0,28),
        UDim2.fromOffset(14,66),
        11
    )

Status.TextColor3 =
    COLORS.sub

--==============================================================
-- BOTÃO INICIAR/PARAR
--==============================================================

local Scan = new("TextButton", {

    Parent = Main,

    Size =
        UDim2.new(.5,-20,0,42),

    Position =
        UDim2.fromOffset(14,98),

    Text =
        "INICIAR LEITURA DE BOTS",

    BackgroundColor3 =
        COLORS.blue2,

    TextColor3 =
        COLORS.text,

    Font =
        Enum.Font.GothamBold,

    TextSize = 10,

    BorderSizePixel = 0
})

round(Scan,8)

--==============================================================
-- EXPORTAR
--==============================================================

local Export = new("TextButton", {

    Parent = Main,

    Size =
        UDim2.new(.5,-20,0,42),

    Position =
        UDim2.new(.5,6,0,98),

    Text =
        "BAIXAR ARQUIVO DE LEITURA",

    BackgroundColor3 =
        COLORS.blue,

    TextColor3 =
        COLORS.text,

    Font =
        Enum.Font.GothamBold,

    TextSize = 10,

    BorderSizePixel = 0
})

round(Export,8)

--==============================================================
-- RESUMO
--==============================================================

local Summary =
    label(
        Main,
        "Nenhuma leitura realizada.",
        UDim2.new(1,-28,0,52),
        UDim2.fromOffset(14,150),
        10
    )

Summary.TextWrapped = true
Summary.TextColor3 =
    COLORS.text

--==============================================================
-- VIEWER
--==============================================================

local Viewer = new("TextBox", {

    Parent = Main,

    Size =
        UDim2.new(1,-28,1,-222),

    Position =
        UDim2.fromOffset(14,204),

    BackgroundColor3 =
        COLORS.panel,

    BorderSizePixel = 0,

    Text = "",

    TextColor3 =
        COLORS.text,

    Font =
        Enum.Font.Code,

    TextSize = 9,

    MultiLine = true,

    ClearTextOnFocus = false,

    TextEditable = false,

    TextXAlignment =
        Enum.TextXAlignment.Left,

    TextYAlignment =
        Enum.TextYAlignment.Top
})

round(Viewer,8)

--==============================================================
-- BOTÃO FLUTUANTE
--==============================================================

local Mini = new("TextButton", {

    Parent = Gui,

    Size =
        UDim2.fromOffset(54,54),

    Position =
        UDim2.new(.5,-27,.5,-27),

    BackgroundColor3 =
        COLORS.blue,

    Text = "C",

    TextColor3 =
        COLORS.text,

    Font =
        Enum.Font.GothamBlack,

    TextSize = 19,

    BorderSizePixel = 0,

    Visible = false
})

round(Mini,99)

--==============================================================
-- PREVIEW
--==============================================================

local function updatePreview()

    local lines = {

        "CAFEÍNA • BOT RESEARCH",

        "",

        "STATUS: "
            ..(
                State.Running
                and "COLETANDO"
                or "PARADO"
            ),

        "",

        "EVENTOS IMPORTANTES: "
            ..#State.ImportantEvents,

        "VERIFICAÇÕES VISUAIS: "
            ..#State.VisualChecks,

        "SNAPSHOTS: "
            ..#State.Snapshots,

        "BOTS REGISTRADOS: "
            ..State.NextBotId,

        "",

        "BOTS ATIVOS:"
    }

    local total = 0
    local army = 0
    local rebels = 0
    local unknown = 0

    for _, bot in pairs(State.Bots) do

        if not bot.removed then

            total += 1

            local team =
                inspectTeam(bot.model)

            if team.attribute == "Army" then

                army += 1

            elseif team.attribute == "Rebels" then

                rebels += 1

            else

                unknown += 1
            end
        end
    end

    lines[#lines + 1] =
        "  Total: "..total

    lines[#lines + 1] =
        "  Army: "..army

    lines[#lines + 1] =
        "  Rebels: "..rebels

    lines[#lines + 1] =
        "  Desconhecido: "..unknown

    lines[#lines + 1] = ""

    lines[#lines + 1] =
        "LINHA DO TEMPO RECENTE:"

    local count =
        #State.ImportantEvents

    local start =
        math.max(1,count-12)

    for i = start,count do

        local event =
            State.ImportantEvents[i]

        local botId =
            event.data
            and event.data.botId

        lines[#lines + 1] =
            string.format(
                "[%.2f] %s%s",
                event.time,
                event.type,

                botId
                and (" • Bot #"..botId)
                or ""
            )
    end

    Viewer.Text =
        table.concat(
            lines,
            "\n"
        )
end

--==============================================================
-- STATUS
--==============================================================

local function updateStatus()

    if State.Running then

        Status.Text =
            "Pesquisa ativa • observando spawn, equipe, objetos e Highlight."

        Status.TextColor3 =
            COLORS.green

    else

        Status.Text =
            "Pesquisa parada."

        Status.TextColor3 =
            COLORS.sub
    end
end

--==============================================================
-- INICIAR
--==============================================================

local function startResearch()

    if State.Running then
        return
    end

    State.Running = true

    State.StartedClock =
        clock()

    State.StartedUnix =
        unix()

    important(
        "RESEARCH_STARTED",
        {
            playerState =
                getPlayerState()
        }
    )

    -- Registra bots existentes.
    scanExisting()

    -- Detecta novos modelos.
    State.Connections.DescendantAdded =
        workspace.DescendantAdded:Connect(
            function(obj)

                if not State.Running then
                    return
                end

                if isBotCandidate(obj) then
                    registerBot(obj)
                end
            end
        )

    -- Detecta remoção.
    State.Connections.DescendantRemoving =
        workspace.DescendantRemoving:Connect(
            function(obj)

                local bot =
                    State.ObjectToBot[obj]

                if bot then
                    removeBot(bot)
                end
            end
        )

    -- Loop de observação.
    State.SnapshotThread =
        task.spawn(
            function()

                while State.Running do

                    task.wait(
                        CONFIG.SnapshotInterval
                    )

                    if not State.Running then
                        break
                    end

                    monitorBots()

                    createSnapshot()

                    for _, bot in pairs(State.Bots) do

                        if not bot.removed then

                            local snapshot =
                                buildBotSnapshot(bot)

                            if snapshot then

                                bot.snapshots[
                                    #bot.snapshots + 1
                                ] = snapshot
                            end
                        end
                    end

                    updatePreview()
                end
            end
        )

    createSnapshot()

    updateStatus()
    updatePreview()
end

--==============================================================
-- PARAR
--==============================================================

local function stopResearch()

    if not State.Running then
        return
    end

    State.Running = false

    State.EndedClock =
        clock()

    State.EndedUnix =
        unix()

    monitorBots()

    createSnapshot()

    important(
        "RESEARCH_STOPPED",
        {
            playerState =
                getPlayerState()
        }
    )

    for _, connection in pairs(
        State.Connections
    ) do

        pcall(function()
            connection:Disconnect()
        end)
    end

    State.Connections = {}

    updateStatus()
    updatePreview()
end

--==============================================================
-- BOTÃO LEITURA
--==============================================================

Scan.Activated:Connect(

    function()

        if State.Running then

            Scan.Text =
                "PARAR LEITURA DE BOTS"

            stopResearch()

            Scan.Text =
                "INICIAR LEITURA DE BOTS"

        else

            Scan.Text =
                "PARAR LEITURA DE BOTS"

            startResearch()
        end
    end
)

--==============================================================
-- EXPORTAR ARQUIVO
--==============================================================

Export.Activated:Connect(

    function()

        if #State.ImportantEvents == 0 then

            Status.Text =
                "Nenhuma pesquisa disponível para exportação."

            Status.TextColor3 =
                COLORS.yellow

            return
        end

        -- Para garantir que o último estado seja incluído.
        if State.Running then
            monitorBots()
            createSnapshot()
        end

        local json =
            exportJSON()

        if not json then

            Status.Text =
                "Erro ao gerar JSON."

            Status.TextColor3 =
                COLORS.red

            return
        end

        local filename =
            "Cafeina_BotResearch_"
            ..tostring(game.PlaceId)
            .."_"
            ..tostring(os.time())
            ..".json"

        local wrote = false

        -- Preferência: arquivo.
        if typeof(writefile) == "function" then

            local ok =
                pcall(
                    function()
                        writefile(
                            filename,
                            json
                        )
                    end
                )

            wrote = ok
        end

        if wrote then

            Status.Text =
                "Arquivo salvo: "..filename

            Status.TextColor3 =
                COLORS.green

        elseif typeof(setclipboard) == "function" then

            local ok =
                pcall(
                    function()
                        setclipboard(json)
                    end
                )

            if ok then

                Status.Text =
                    "writefile indisponível • JSON copiado para a área de transferência."

                Status.TextColor3 =
                    COLORS.yellow

            else

                Status.Text =
                    "Não foi possível salvar nem copiar o JSON."

                Status.TextColor3 =
                    COLORS.red
            end

        else

            Status.Text =
                "Ambiente sem writefile e sem clipboard."

            Status.TextColor3 =
                COLORS.red
        end
    end
)

--==============================================================
-- MINIMIZAR
--==============================================================

Min.Activated:Connect(

    function()

        Main.Visible = false

        Mini.Visible = true
    end
)

--==============================================================
-- RESTAURAR
--==============================================================

-- O botão flutuante precisa distinguir clique de arrasto.
local dragging = false
local dragStart = nil
local startPos = nil
local moved = false

Mini.InputBegan:Connect(

    function(input)

        if input.UserInputType
            == Enum.UserInputType.MouseButton1
            or input.UserInputType
            == Enum.UserInputType.Touch then

            dragging = true
            moved = false

            dragStart =
                input.Position

            startPos =
                Mini.Position
        end
    end
)

UserInputService.InputChanged:Connect(

    function(input)

        if not dragging then
            return
        end

        if input.UserInputType
            ~= Enum.UserInputType.MouseMovement
            and input.UserInputType
            ~= Enum.UserInputType.Touch then

            return
        end

        local delta =
            input.Position - dragStart

        if math.abs(delta.X) > 5
            or math.abs(delta.Y) > 5 then

            moved = true
        end

        Mini.Position =
            UDim2.new(

                startPos.X.Scale,
                startPos.X.Offset + delta.X,

                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
    end
)

UserInputService.InputEnded:Connect(

    function(input)

        if input.UserInputType
            == Enum.UserInputType.MouseButton1
            or input.UserInputType
            == Enum.UserInputType.Touch then

            dragging = false
        end
    end
)

Mini.Activated:Connect(

    function()

        if moved then
            moved = false
            return
        end

        Main.Visible = true
        Mini.Visible = false
    end
)

--==============================================================
-- FECHAR
--==============================================================

Close.Activated:Connect(

    function()

        if State.Running then
            stopResearch()
        end

        pcall(function()
            Gui:Destroy()
        end)
    end
)

--==============================================================
-- INICIALIZAÇÃO
--==============================================================

updateStatus()
updatePreview()
