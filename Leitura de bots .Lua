--==============================================================--
-- CAFEÍNA • BOT READER V1
--
-- LEITURA ESPECÍFICA DE BOTS
--
-- NÃO REALIZA SCAN GERAL DO JOGO
--
-- INVESTIGA:
-- • BotPatrolPoints
-- • Army / Rebels
-- • Pontos de patrulha
-- • Candidatos a NPC/Bot
-- • Player x NPC
-- • Bot ativo x possível manequim
-- • Humanoid / RootPart
-- • Health / movimento
-- • Attributes
-- • Tags
-- • Relação espacial com PatrolPoints
--
-- EXPORTAÇÃO:
-- • JSON
-- • writefile quando disponível
-- • clipboard como fallback
--
-- INTERFACE:
-- • Mantém estrutura do Menu anterior
-- • Minimizar
-- • Fechar
-- • Suporte mobile
--==============================================================--

local Players =
    game:GetService("Players")

local HttpService =
    game:GetService("HttpService")

local UserInputService =
    game:GetService("UserInputService")

local TweenService =
    game:GetService("TweenService")

local CollectionService =
    game:GetService("CollectionService")

local CoreGui =
    game:GetService("CoreGui")

local Workspace =
    game:GetService("Workspace")

local LocalPlayer =
    Players.LocalPlayer

if not LocalPlayer then
    LocalPlayer =
        Players.PlayerAdded:Wait()
end

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {

    VERSION = "BOT-READER-V1",

    MENU_NAME =
        "CafeinaBotReader",

    PATROL_FOLDER =
        "BotPatrolPoints",

    MOVEMENT_SAMPLE_TIME =
        3,

    MOVEMENT_SAMPLE_INTERVAL =
        0.25,

    MAX_BOT_CANDIDATES =
        500,

    MAX_PATROL_POINTS =
        500,

    PATROL_ASSOCIATION_DISTANCE =
        80,

    MAX_VIEW_CHARS =
        120000,

    EXPORT_FOLDER =
        "CafeinaBotReads",

    SERVICES_TO_CHECK = {
        "Workspace",
        "ReplicatedStorage",
        "ServerStorage",
        "ServerScriptService",
    },
}

--==============================================================--
-- COLORS
--==============================================================--

local COLORS = {

    BG =
        Color3.fromRGB(
            12,
            12,
            15
        ),

    PANEL =
        Color3.fromRGB(
            20,
            20,
            24
        ),

    PANEL2 =
        Color3.fromRGB(
            29,
            29,
            35
        ),

    STROKE =
        Color3.fromRGB(
            55,
            55,
            65
        ),

    RED =
        Color3.fromRGB(
            235,
            38,
            52
        ),

    RED_DARK =
        Color3.fromRGB(
            110,
            20,
            30
        ),

    TEXT =
        Color3.fromRGB(
            245,
            245,
            248
        ),

    SUB =
        Color3.fromRGB(
            160,
            160,
            172
        ),

    GREEN =
        Color3.fromRGB(
            65,
            210,
            118
        ),

    YELLOW =
        Color3.fromRGB(
            242,
            184,
            57
        ),

    ORANGE =
        Color3.fromRGB(
            245,
            130,
            55
        ),
}

--==============================================================--
-- REQUEST / FILE HELPERS
--==============================================================--

local SetClipboard =
    typeof(setclipboard) == "function"
    and setclipboard
    or
    (
        typeof(toclipboard) == "function"
        and toclipboard
        or nil
    )

local WriteFile =
    typeof(writefile) == "function"
    and writefile
    or nil

local MakeFolder =
    typeof(makefolder) == "function"
    and makefolder
    or nil

--==============================================================--
-- STATE
--==============================================================--

local State = {

    Reading = false,

    CancelRequested = false,

    ReadComplete = false,

    CurrentArea =
        "Resumo",

    StartedAt = 0,

    PatrolFolderFound =
        false,

    PatrolPoints = {
        Army = {},
        Rebels = {},
        Other = {},
    },

    BotCandidates = {},

    Results = {

        Metadata = {},

        PatrolSystem = {},

        Bots = {},

        Summary = {},
    },

    ExportText = "",

    ExportPath = "",

    LastMessage = "",
}

--==============================================================--
-- SAFE HELPERS
--==============================================================--

local function safeCall(fn)

    local ok, result =
        pcall(fn)

    if ok then
        return result
    end

    return nil
end

local function safeName(object)

    local result =
        safeCall(function()
            return object.Name
        end)

    return tostring(
        result or "?"
    )
end

local function safeClass(object)

    local result =
        safeCall(function()
            return object.ClassName
        end)

    return tostring(
        result or "?"
    )
end

local function safeFullName(object)

    local result =
        safeCall(function()
            return object:GetFullName()
        end)

    return tostring(
        result or safeName(object)
    )
end

local function safeAttribute(
    object,
    name
)

    local result =
        safeCall(function()
            return object:GetAttribute(name)
        end)

    return result
end

local function safeAttributes(
    object
)

    local attributes = {}

    local result =
        safeCall(function()
            return object:GetAttributes()
        end)

    if type(result) ~= "table" then
        return attributes
    end

    for key, value
        in pairs(result)
    do

        local valueType =
            typeof(value)

        if
            valueType == "string"
            or valueType == "number"
            or valueType == "boolean"
        then

            attributes[
                tostring(key)
            ] = value

        else

            attributes[
                tostring(key)
            ] =
                tostring(value)

        end
    end

    return attributes
end

local function safeTags(
    object
)

    local tags = {}

    local ok, result =
        pcall(function()

            return CollectionService:
                GetTags(object)

        end)

    if not ok
        or type(result) ~= "table"
    then
        return tags
    end

    for _, tag
        in ipairs(result)
    do

        tags[
            #tags + 1
        ] =
            tostring(tag)

    end

    return tags
end

local function vectorToTable(
    value
)

    if typeof(value)
        ~= "Vector3"
    then
        return nil
    end

    return {

        x = value.X,

        y = value.Y,

        z = value.Z,
    }
end

local function getPosition(
    object
)

    if not object then
        return nil
    end

    local root

    if object:IsA("BasePart") then

        root = object

    else

        root =
            object:FindFirstChild(
                "HumanoidRootPart"
            )

            or
            object.PrimaryPart

    end

    if not root then
        return nil
    end

    local position =
        safeCall(function()
            return root.Position
        end)

    return vectorToTable(
        position
    )
end

local function distance(
    a,
    b
)

    if not a or not b then
        return math.huge
    end

    return (
        Vector3.new(
            a.x,
            a.y,
            a.z
        )
        -
        Vector3.new(
            b.x,
            b.y,
            b.z
        )
    ).Magnitude
end

local function formatBytes(
    bytes
)

    bytes =
        tonumber(bytes)
        or 0

    if bytes >=
        1024 * 1024
    then

        return string.format(
            "%.2f MB",
            bytes /
            (
                1024 * 1024
            )
        )

    elseif bytes >= 1024 then

        return string.format(
            "%.1f KB",
            bytes / 1024
        )

    end

    return tostring(bytes)
        .. " B"
end

local function countDictionary(
    dictionary
)

    local amount = 0

    for _ in pairs(dictionary) do
        amount += 1
    end

    return amount
end

--==============================================================--
-- PLAYER DETECTION
--==============================================================--

local function getPlayerFromCharacter(
    model
)

    if not model then
        return nil
    end

    local player =
        Players:GetPlayerFromCharacter(
            model
        )

    return player
end

local function isPlayerCharacter(
    model
)

    return
        getPlayerFromCharacter(
            model
        ) ~= nil

end

--==============================================================--
-- PATROL POINT SCANNER
--==============================================================--

local function classifyPatrolGroup(
    point
)

    local parent =
        point.Parent

    if not parent then
        return "Other"
    end

    local parentName =
        string.lower(
            safeName(parent)
        )

    local teamAttribute =
        safeAttribute(
            point,
            "Team"
        )

    if
        typeof(teamAttribute)
        == "string"
    then

        local teamLower =
            string.lower(
                teamAttribute
            )

        if teamLower == "army" then
            return "Army"
        end

        if
            teamLower == "rebels"
        then
            return "Rebels"
        end
    end

    if string.find(
        parentName,
        "army",
        1,
        true
    )
    then
        return "Army"
    end

    if string.find(
        parentName,
        "rebel",
        1,
        true
    )
    then
        return "Rebels"
    end

    return "Other"
end

local function scanPatrolPoints()

    local result = {

        found = false,

        path = nil,

        className = nil,

        children = 0,

        groups = {

            Army = 0,

            Rebels = 0,

            Other = 0,
        },

        points = {},
    }

    local folder

    folder =
        Workspace:FindFirstChild(
            CONFIG.PATROL_FOLDER
        )

    if not folder then

        result.found =
            false

        return result

    end

    result.found =
        true

    result.path =
        safeFullName(folder)

    result.className =
        safeClass(folder)

    local descendants =
        folder:GetDescendants()

    local total = 0

    for _, object
        in ipairs(descendants)
    do

        if State.CancelRequested then
            break
        end

        if total >=
            CONFIG.MAX_PATROL_POINTS
        then
            break
        end

        if object:IsA("BasePart") then

            total += 1

            local group =
                classifyPatrolGroup(
                    object
                )

            local position =
                getPosition(
                    object
                )

            local teamAttribute =
                safeAttribute(
                    object,
                    "Team"
                )

            local parentName =
                object.Parent
                and safeName(
                    object.Parent
                )
                or nil

            local consistency =
                "unknown"

            if
                group == "Army"
                and typeof(
                    teamAttribute
                ) == "string"
            then

                if
                    string.lower(
                        teamAttribute
                    )
                    == "army"
                then

                    consistency =
                        "consistent"

                else

                    consistency =
                        "attribute_mismatch"

                end

            elseif
                group == "Rebels"
                and typeof(
                    teamAttribute
                ) == "string"
            then

                if
                    string.lower(
                        teamAttribute
                    )
                    == "rebels"
                then

                    consistency =
                        "consistent"

                else

                    consistency =
                        "attribute_mismatch"

                end

            end

            local record = {

                name =
                    safeName(object),

                className =
                    safeClass(object),

                path =
                    safeFullName(object),

                parent =
                    parentName,

                group =
                    group,

                teamAttribute =
                    teamAttribute,

                consistency =
                    consistency,

                position =
                    position,

                attributes =
                    safeAttributes(
                        object
                    ),

                tags =
                    safeTags(
                        object
                    ),
            }

            result.points[
                #result.points + 1
            ] = record

            result.groups[group] += 1

            State.PatrolPoints[group][
                #State.PatrolPoints[group] + 1
            ] = record

        end
    end

    result.children =
        total

    return result
end

--==============================================================--
-- PATROL ASSOCIATION
--==============================================================--

local function findNearestPatrol(
    position
)

    local nearest = nil

    local nearestDistance =
        math.huge

    for group, points
        in pairs(
            State.PatrolPoints
        )
    do

        if
            group == "Army"
            or group == "Rebels"
        then

            for _, point
                in ipairs(points)
            do

                local d =
                    distance(
                        position,
                        point.position
                    )

                if d <
                    nearestDistance
                then

                    nearestDistance =
                        d

                    nearest = {

                        group =
                            group,

                        distance =
                            d,

                        point =
                            point,
                    }

                end
            end
        end
    end

    return nearest
end

--==============================================================--
-- CANDIDATE DETECTION
--==============================================================--

local function isInterestingModel(
    model
)

    if not model:IsA("Model") then
        return false
    end

    if isPlayerCharacter(
        model
    ) then
        return false
    end

    local humanoid =
        model:FindFirstChildOfClass(
            "Humanoid"
        )

    if not humanoid then
        return false
    end

    return true
end

local function collectBotCandidates()

    local candidates = {}

    local seen = {}

    for _, serviceName
        in ipairs(
            CONFIG.SERVICES_TO_CHECK
        )
    do

        if State.CancelRequested then
            break
        end

        local service =
            safeCall(function()
                return game:GetService(
                    serviceName
                )
            end)

        if service then

            local descendants =
                safeCall(function()
                    return service:GetDescendants()
                end)

            if type(descendants)
                == "table"
            then

                for _, object
                    in ipairs(
                        descendants
                    )
                do

                    if State.CancelRequested then
                        break
                    end

                    if
                        #candidates
                        >=
                        CONFIG.MAX_BOT_CANDIDATES
                    then
                        break
                    end

                    if
                        isInterestingModel(
                            object
                        )
                    then

                        if not seen[object] then

                            seen[object] =
                                true

                            candidates[
                                #candidates + 1
                            ] =
                                object

                        end
                    end
                end
            end
        end
    end

    return candidates
end

--==============================================================--
-- MOVEMENT OBSERVATION
--==============================================================--

local function observeMovement(
    model
)

    local humanoid =
        model:FindFirstChildOfClass(
            "Humanoid"
        )

    local root =
        model:FindFirstChild(
            "HumanoidRootPart"
        )

    if not humanoid
        or not root
    then

        return {

            observed = false,

            moved = false,

            rotated = false,

            distanceMoved = 0,

            samples = 0,
        }

    end

    local initialPosition =
        root.Position

    local initialLook =
        root.CFrame.LookVector

    local maxDistance =
        0

    local rotationChanged =
        false

    local samples =
        0

    local started =
        os.clock()

    while
        os.clock() - started
        <
        CONFIG.MOVEMENT_SAMPLE_TIME
    do

        if State.CancelRequested then
            break
        end

        if not model.Parent then
            break
        end

        local currentPosition =
            safeCall(function()
                return root.Position
            end)

        local currentLook =
            safeCall(function()
                return root.CFrame.LookVector
            end)

        if currentPosition then

            local movedDistance =
                (
                    currentPosition
                    -
                    initialPosition
                ).Magnitude

            if movedDistance >
                maxDistance
            then

                maxDistance =
                    movedDistance

            end
        end

        if currentLook then

            local dot =
                initialLook:Dot(
                    currentLook
                )

            if dot < 0.999 then
                rotationChanged =
                    true
            end
        end

        samples += 1

        task.wait(
            CONFIG.MOVEMENT_SAMPLE_INTERVAL
        )
    end

    return {

        observed = true,

        moved =
            maxDistance > 1,

        rotated =
            rotationChanged,

        distanceMoved =
            maxDistance,

        samples =
            samples,
    }
end

--==============================================================--
-- BOT ANALYSIS
--==============================================================--

local function analyzeBot(
    model
)

    local humanoid =
        model:FindFirstChildOfClass(
            "Humanoid"
        )

    local root =
        model:FindFirstChild(
            "HumanoidRootPart"
        )

    local position =
        getPosition(
            model
        )

    local nearestPatrol =
        findNearestPatrol(
            position
        )

    local player =
        getPlayerFromCharacter(
            model
        )

    local attributes =
        safeAttributes(
            model
        )

    local tags =
        safeTags(
            model
        )

    local health =
        safeCall(function()
            return humanoid.Health
        end)

    local maxHealth =
        safeCall(function()
            return humanoid.MaxHealth
        end)

    local walkSpeed =
        safeCall(function()
            return humanoid.WalkSpeed
        end)

    local jumpPower =
        safeCall(function()
            return humanoid.JumpPower
        end)

    local rigType =
        safeCall(function()
            return tostring(
                humanoid.RigType
            )
        end)

    local teamAttribute =
        safeAttribute(
            model,
            "Team"
        )

    local teamName =
        nil

    if
        typeof(teamAttribute)
        == "string"
    then

        teamName =
            teamAttribute

    end

    local movement =
        observeMovement(
            model
        )

    local evidence = {

        humanoid =
            humanoid ~= nil,

        rootPart =
            root ~= nil,

        playerAssociation =
            player ~= nil,

        movementObserved =
            movement.observed,

        positionChanged =
            movement.moved,

        rotationChanged =
            movement.rotated,

        patrolAssociation =
            nearestPatrol ~= nil,

        patrolDistance =
            nearestPatrol
            and nearestPatrol.distance
            or nil,

        patrolGroup =
            nearestPatrol
            and nearestPatrol.group
            or nil,

        teamAttribute =
            teamName,

        hasHealth =
            health ~= nil,

        hasMaxHealth =
            maxHealth ~= nil,

        positiveHealth =
            tonumber(health or 0)
            > 0,

        walkSpeed =
            walkSpeed,

        jumpPower =
            jumpPower,
    }

    --==========================================================--
    -- CLASSIFICATION
    --==========================================================--

    local score =
        0

    local reasons = {}

    if not player then

        score += 2

        reasons[
            #reasons + 1
        ] =
            "não associado a Player"

    else

        score -= 5

        reasons[
            #reasons + 1
        ] =
            "associado a Player"

    end

    if humanoid then

        score += 1

    end

    if root then

        score += 1

    end

    if movement.moved then

        score += 3

        reasons[
            #reasons + 1
        ] =
            "posição alterada durante observação"

    end

    if movement.rotated then

        score += 1

        reasons[
            #reasons + 1
        ] =
            "rotação alterada durante observação"

    end

    if nearestPatrol
        and nearestPatrol.distance
        <=
        CONFIG.PATROL_ASSOCIATION_DISTANCE
    then

        score += 3

        reasons[
            #reasons + 1
        ] =
            "próximo de ponto de patrulha"

    end

    if
        typeof(teamName)
        == "string"
    then

        score += 1

        reasons[
            #reasons + 1
        ] =
            "possui atributo Team"

    end

    local classification

    if player then

        classification =
            "PLAYER_CHARACTER"

    elseif score >= 7 then

        classification =
            "ACTIVE_BOT"

    elseif score >= 3 then

        classification =
            "BOT_CANDIDATE"

    else

        classification =
            "POSSIBLE_DUMMY"

    end

    --==========================================================--
    -- TEAM RESOLUTION
    --==========================================================--

    local detectedTeam =
        teamName

    local teamEvidence = {}

    if teamName then

        teamEvidence[
            #teamEvidence + 1
        ] =
            "Model.Attribute.Team"

    end

    if nearestPatrol then

        if
            not detectedTeam
            or
            nearestPatrol.distance
            <
            CONFIG.PATROL_ASSOCIATION_DISTANCE
        then

            detectedTeam =
                nearestPatrol.group

            teamEvidence[
                #teamEvidence + 1
            ] =
                "nearest BotPatrolPoint"

        end
    end

    return {

        name =
            safeName(model),

        className =
            safeClass(model),

        path =
            safeFullName(model),

        classification =
            classification,

        confidenceScore =
            score,

        reasons =
            reasons,

        detectedTeam =
            detectedTeam,

        teamEvidence =
            teamEvidence,

        position =
            position,

        patrolAssociation =
            nearestPatrol
            and {

                group =
                    nearestPatrol.group,

                distance =
                    nearestPatrol.distance,

                point =
                    nearestPatrol.point
                    and nearestPatrol.point.path
                    or nil,

            }
            or nil,

        humanoid = {

            health =
                health,

            maxHealth =
                maxHealth,

            walkSpeed =
                walkSpeed,

            jumpPower =
                jumpPower,

            rigType =
                rigType,
        },

        evidence =
            evidence,

        attributes =
            attributes,

        tags =
            tags,
    }
end

--==============================================================--
-- SUMMARY
--==============================================================--

local function buildSummary()

    local summary = {

        totalCandidates =
            #State.Results.Bots,

        activeBots = 0,

        botCandidates = 0,

        possibleDummies = 0,

        players = 0,

        army = 0,

        rebels = 0,

        unknownTeam = 0,

        patrolPoints = {

            Army =
                #State.PatrolPoints.Army,

            Rebels =
                #State.PatrolPoints.Rebels,

            Other =
                #State.PatrolPoints.Other,
        },
    }

    for _, bot
        in ipairs(
            State.Results.Bots
        )
    do

        if
            bot.classification
            == "ACTIVE_BOT"
        then

            summary.activeBots += 1

        elseif
            bot.classification
            == "BOT_CANDIDATE"
        then

            summary.botCandidates += 1

        elseif
            bot.classification
            == "POSSIBLE_DUMMY"
        then

            summary.possibleDummies += 1

        elseif
            bot.classification
            == "PLAYER_CHARACTER"
        then

            summary.players += 1

        end

        if
            bot.detectedTeam
            == "Army"
        then

            summary.army += 1

        elseif
            bot.detectedTeam
            == "Rebels"
        then

            summary.rebels += 1

        else

            summary.unknownTeam += 1

        end
    end

    return summary
end

--==============================================================--
-- METADATA
--==============================================================--

local function buildMetadata()

    return {

        scanner =
            "CAFEINA BOT READER",

        version =
            CONFIG.VERSION,

        generatedAtUnix =
            os.time(),

        placeId =
            game.PlaceId,

        gameId =
            game.GameId,

        jobId =
            game.JobId,

        placeVersion =
            game.PlaceVersion,

        localPlayer =
            LocalPlayer.Name,

        localUserId =
            LocalPlayer.UserId,

        patrolFolder =
            CONFIG.PATROL_FOLDER,

        movementSampleTime =
            CONFIG.MOVEMENT_SAMPLE_TIME,

        patrolAssociationDistance =
            CONFIG.PATROL_ASSOCIATION_DISTANCE,
    }
end

--==============================================================--
-- COMPLETE SCAN
--==============================================================--

local function runReader()

    if State.Reading then
        return
    end

    State.Reading =
        true

    State.CancelRequested =
        false

    State.ReadComplete =
        false

    State.StartedAt =
        os.clock()

    State.PatrolPoints = {

        Army = {},

        Rebels = {},

        Other = {},
    }

    State.Results = {

        Metadata = {},

        PatrolSystem = {},

        Bots = {},

        Summary = {},
    }

    setStatus(
        "Localizando BotPatrolPoints...",
        COLORS.YELLOW
    )

    setProgress(
        0.05
    )

    --==========================================================--
    -- PATROL
    --==========================================================--

    local patrolResult =
        scanPatrolPoints()

    if State.CancelRequested then

        State.Reading =
            false

        return

    end

    State.Results.PatrolSystem =
        patrolResult

    if patrolResult.found then

        setStatus(
            "BotPatrolPoints encontrado",
            COLORS.GREEN
        )

    else

        setStatus(
            "BotPatrolPoints não encontrado",
            COLORS.ORANGE
        )

    end

    setProgress(
        0.25
    )

    task.wait()

    --==========================================================--
    -- CANDIDATES
    --==========================================================--

    setStatus(
        "Procurando candidatos a bot...",
        COLORS.YELLOW
    )

    local candidates =
        collectBotCandidates()

    State.BotCandidates =
        candidates

    setProgress(
        0.45
    )

    --==========================================================--
    -- ANALYSIS
    --==========================================================--

    local total =
        #candidates

    for index, model
        in ipairs(candidates)
    do

        if State.CancelRequested then
            break
        end

        setStatus(
            "Analisando bot "
            .. tostring(index)
            .. " / "
            .. tostring(total),

            COLORS.YELLOW
        )

        local ok, result =
            pcall(
                analyzeBot,
                model
            )

        if ok
            and type(result)
            == "table"
        then

            State.Results.Bots[
                #State.Results.Bots + 1
            ] =
                result

        end

        setProgress(
            0.45
            +
            (
                (index /
                    math.max(
                        total,
                        1
                    )
                )
                * 0.45
            )
        )

        task.wait()

    end

    --==========================================================--
    -- FINAL
    --==========================================================--

    State.Results.Metadata =
        buildMetadata()

    State.Results.Summary =
        buildSummary()

    State.ReadComplete =
        not State.CancelRequested

    State.Reading =
        false

    setProgress(
        State.ReadComplete
        and 1
        or 0
    )

    if State.ReadComplete then

        setStatus(
            "Leitura concluída • "
            .. tostring(
                #State.Results.Bots
            )
            .. " candidatos",

            COLORS.GREEN
        )

    else

        setStatus(
            "Leitura cancelada",
            COLORS.ORANGE
        )

    end

    openArea(
        "Resumo"
    )
end

--==============================================================--
-- EXPORT
--==============================================================--

local function generateExport()

    local ok, encoded =
        pcall(function()

            return HttpService:
                JSONEncode(
                    State.Results
                )

        end)

    if not ok then

        return false,
            tostring(encoded)

    end

    State.ExportText =
        encoded

    return true,
        encoded
end

local function downloadReading()

    if not State.ReadComplete then

        setStatus(
            "Faça a leitura primeiro",
            COLORS.YELLOW
        )

        return

    end

    local ok, encoded =
        generateExport()

    if not ok then

        setStatus(
            "Erro ao gerar JSON",
            COLORS.RED
        )

        return

    end

    local timestamp =
        os.date(
            "!%Y%m%d_%H%M%S"
        )

    local fileName =
        "Cafeina_BotRead_"
        .. tostring(
            game.PlaceId
        )
        .. "_"
        .. timestamp
        .. ".json"

    --==========================================================--
    -- WRITEFILE
    --==========================================================--

    if WriteFile then

        local success, err =
            pcall(function()

                if MakeFolder then

                    pcall(
                        MakeFolder,
                        CONFIG.EXPORT_FOLDER
                    )

                end

                WriteFile(
                    CONFIG.EXPORT_FOLDER
                    .. "/"
                    .. fileName,

                    encoded
                )

            end)

        if success then

            State.ExportPath =
                CONFIG.EXPORT_FOLDER
                .. "/"
                .. fileName

            if SetClipboard then

                pcall(
                    SetClipboard,
                    encoded
                )

            end

            setStatus(
                "Arquivo salvo: "
                .. fileName,

                COLORS.GREEN
            )

            return
        end

        setStatus(
            "Falha ao salvar arquivo",
            COLORS.RED
        )

        warn(
            "[CAFEINA BOT READER]",
            err
        )

        return
    end

    --==========================================================--
    -- FALLBACK CLIPBOARD
    --==========================================================--

    if SetClipboard then

        local copied =
            pcall(
                SetClipboard,
                encoded
            )

        if copied then

            setStatus(
                "JSON copiado para o clipboard",
                COLORS.GREEN
            )

            return
        end
    end

    Viewer.Text =
        encoded

    setStatus(
        "JSON gerado na área de leitura",
        COLORS.YELLOW
    )
end

--==============================================================--
-- GUI HELPERS
--==============================================================--

local function create(
    className,
    props
)

    local object =
        Instance.new(
            className
        )

    for key, value
        in pairs(
            props or {}
        )
    do

        object[key] =
            value

    end

    return object
end

local function corner(
    parent,
    radius
)

    return create(
        "UICorner",
        {

            CornerRadius =
                UDim.new(
                    0,
                    radius or 10
                ),

            Parent =
                parent,
        }
    )
end

local function stroke(
    parent
)

    return create(
        "UIStroke",
        {

            Color =
                COLORS.STROKE,

            Thickness =
                1,

            Parent =
                parent,
        }
    )
end

--==============================================================--
-- GUI PARENT
--==============================================================--

local GuiParent =
    nil

if typeof(gethui)
    == "function"
then

    local ok, result =
        pcall(gethui)

    if ok then
        GuiParent =
            result
    end
end

local PlayerGui =
    LocalPlayer:WaitForChild(
        "PlayerGui"
    )

local Gui =
    create(
        "ScreenGui",
        {

            Name =
                CONFIG.MENU_NAME,

            ResetOnSpawn =
                false,

            IgnoreGuiInset =
                true,

            ZIndexBehavior =
                Enum.ZIndexBehavior.Sibling,
        }
    )

local parented =
    false

if GuiParent then

    parented =
        pcall(function()

            Gui.Parent =
                GuiParent

        end)
end

if not parented then

    parented =
        pcall(function()

            Gui.Parent =
                CoreGui

        end)
end

if not parented then

    Gui.Parent =
        PlayerGui

end

--==============================================================--
-- REMOVE OLD INSTANCE
--==============================================================--

for _, object
    in ipairs(
        Gui.Parent:GetChildren()
    )
do

    if
        object ~= Gui
        and object.Name
        == CONFIG.MENU_NAME
    then

        pcall(function()
            object:Destroy()
        end)

    end
end

--==============================================================--
-- MAIN
--==============================================================--

local Main =
    create(
        "Frame",
        {

            Size =
                UDim2.fromScale(
                    0.9,
                    0.78
                ),

            AnchorPoint =
                Vector2.new(
                    0.5,
                    0.5
                ),

            Position =
                UDim2.fromScale(
                    0.5,
                    0.5
                ),

            BackgroundColor3 =
                COLORS.BG,

            BorderSizePixel =
                0,

            Parent =
                Gui,
        }
    )

corner(
    Main,
    14
)

stroke(
    Main
)

--==============================================================--
-- HEADER
--==============================================================--

local Header =
    create(
        "Frame",
        {

            Size =
                UDim2.new(
                    1,
                    0,
                    0,
                    56
                ),

            BackgroundColor3 =
                COLORS.PANEL,

            BorderSizePixel =
                0,

            Parent =
                Main,
        }
    )

corner(
    Header,
    14
)

create(
    "TextLabel",
    {

        Position =
            UDim2.fromOffset(
                14,
                7
            ),

        Size =
            UDim2.new(
                1,
                -100,
                0,
                24
            ),

        BackgroundTransparency =
            1,

        Text =
            "CAFEÍNA • LEITURA DE BOTS",

        TextColor3 =
            COLORS.TEXT,

        Font =
            Enum.Font.GothamBold,

        TextSize =
            16,

        TextXAlignment =
            Enum.TextXAlignment.Left,

        Parent =
            Header,
    }
)

create(
    "TextLabel",
    {

        Position =
            UDim2.fromOffset(
                14,
                30
            ),

        Size =
            UDim2.new(
                1,
                -100,
                0,
                16
            ),

        BackgroundTransparency =
            1,

        Text =
            "BOT READER V1 • PATROL / NPC / DUMMY",

        TextColor3 =
            COLORS.SUB,

        Font =
            Enum.Font.Gotham,

        TextSize =
            10,

        TextXAlignment =
            Enum.TextXAlignment.Left,

        Parent =
            Header,
    }
)

local Minimize =
    create(
        "TextButton",
        {

            Position =
                UDim2.new(
                    1,
                    -76,
                    0,
                    11
                ),

            Size =
                UDim2.fromOffset(
                    30,
                    30
                ),

            BackgroundColor3 =
                COLORS.PANEL2,

            Text =
                "—",

            TextColor3 =
                COLORS.TEXT,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                17,

            BorderSizePixel =
                0,

            Parent =
                Header,
        }
    )

corner(
    Minimize,
    8
)

local Close =
    create(
        "TextButton",
        {

            Position =
                UDim2.new(
                    1,
                    -40,
                    0,
                    11
                ),

            Size =
                UDim2.fromOffset(
                    30,
                    30
                ),

            BackgroundColor3 =
                COLORS.RED_DARK,

            Text =
                "×",

            TextColor3 =
                COLORS.TEXT,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                19,

            BorderSizePixel =
                0,

            Parent =
                Header,
        }
    )

corner(
    Close,
    8
)

--==============================================================--
-- STATUS
--==============================================================--

local StatusCard =
    create(
        "Frame",
        {

            Position =
                UDim2.new(
                    0,
                    8,
                    0,
                    64
                ),

            Size =
                UDim2.new(
                    1,
                    -16,
                    0,
                    58
                ),

            BackgroundColor3 =
                COLORS.PANEL,

            BorderSizePixel =
                0,

            Parent =
                Main,
        }
    )

corner(
    StatusCard,
    10
)

local StatusDot =
    create(
        "Frame",
        {

            Position =
                UDim2.fromOffset(
                    11,
                    11
                ),

            Size =
                UDim2.fromOffset(
                    9,
                    9
                ),

            BackgroundColor3 =
                COLORS.GREEN,

            BorderSizePixel =
                0,

            Parent =
                StatusCard,
        }
    )

corner(
    StatusDot,
    99
)

local StatusText =
    create(
        "TextLabel",
        {

            Position =
                UDim2.fromOffset(
                    28,
                    5
                ),

            Size =
                UDim2.new(
                    1,
                    -38,
                    0,
                    22
                ),

            BackgroundTransparency =
                1,

            Text =
                "Pronto",

            TextColor3 =
                COLORS.TEXT,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                11,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            Parent =
                StatusCard,
        }
    )

local DetailText =
    create(
        "TextLabel",
        {

            Position =
                UDim2.fromOffset(
                    11,
                    27
                ),

            Size =
                UDim2.new(
                    1,
                    -22,
                    0,
                    18
                ),

            BackgroundTransparency =
                1,

            Text =
                "0 candidatos • 0 patrol points",

            TextColor3 =
                COLORS.SUB,

            Font =
                Enum.Font.Gotham,

            TextSize =
                9,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            Parent =
                StatusCard,
        }
    )

local ProgressBG =
    create(
        "Frame",
        {

            Position =
                UDim2.new(
                    0,
                    11,
                    1,
                    -9
                ),

            Size =
                UDim2.new(
                    1,
                    -22,
                    0,
                    5
                ),

            BackgroundColor3 =
                COLORS.PANEL2,

            BorderSizePixel =
                0,

            Parent =
                StatusCard,
        }
    )

corner(
    ProgressBG,
    99
)

local ProgressFill =
    create(
        "Frame",
        {

            Size =
                UDim2.new(
                    0,
                    0,
                    1,
                    0
                ),

            BackgroundColor3 =
                COLORS.RED,

            BorderSizePixel =
                0,

            Parent =
                ProgressBG,
        }
    )

corner(
    ProgressFill,
    99
)

--==============================================================--
-- BODY
--==============================================================--

local Sidebar =
    create(
        "Frame",
        {

            Position =
                UDim2.new(
                    0,
                    8,
                    0,
                    130
                ),

            Size =
                UDim2.new(
                    0.29,
                    -5,
                    1,
                    -138
                ),

            BackgroundColor3 =
                COLORS.PANEL,

            BorderSizePixel =
                0,

            Parent =
                Main,
        }
    )

corner(
    Sidebar,
    10
)

local Content =
    create(
        "Frame",
        {

            Position =
                UDim2.new(
                    0.29,
                    7,
                    0,
                    130
                ),

            Size =
                UDim2.new(
                    0.71,
                    -15,
                    1,
                    -138
                ),

            BackgroundColor3 =
                COLORS.PANEL,

            BorderSizePixel =
                0,

            Parent =
                Main,
        }
    )

corner(
    Content,
    10
)

--==============================================================--
-- SIDEBAR
--==============================================================--

local ReadButton =
    create(
        "TextButton",
        {

            Position =
                UDim2.fromOffset(
                    7,
                    7
                ),

            Size =
                UDim2.new(
                    1,
                    -14,
                    0,
                    40
                ),

            BackgroundColor3 =
                COLORS.RED,

            BorderSizePixel =
                0,

            Text =
                "LER BOTS",

            TextColor3 =
                COLORS.TEXT,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                11,

            Parent =
                Sidebar,
        }
    )

corner(
    ReadButton,
    8
)

local AreaList =
    create(
        "ScrollingFrame",
        {

            Position =
                UDim2.fromOffset(
                    7,
                    54
                ),

            Size =
                UDim2.new(
                    1,
                    -14,
                    1,
                    -108
                ),

            BackgroundTransparency =
                1,

            BorderSizePixel =
                0,

            ScrollBarThickness =
                3,

            CanvasSize =
                UDim2.new(),

            AutomaticCanvasSize =
                Enum.AutomaticSize.Y,

            Parent =
                Sidebar,
        }
    )

local AreaLayout =
    create(
        "UIListLayout",
        {

            Padding =
                UDim.new(
                    0,
                    5
                ),

            Parent =
                AreaList,
        }
    )

local DownloadButton =
    create(
        "TextButton",
        {

            Position =
                UDim2.new(
                    0,
                    7,
                    1,
                    -47
                ),

            Size =
                UDim2.new(
                    1,
                    -14,
                    0,
                    40
                ),

            BackgroundColor3 =
                COLORS.RED_DARK,

            BorderSizePixel =
                0,

            Text =
                "BAIXAR LEITURA",

            TextColor3 =
                COLORS.TEXT,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                9,

            Parent =
                Sidebar,
        }
    )

corner(
    DownloadButton,
    8
)

--==============================================================--
-- CONTENT
--==============================================================--

local AreaTitle =
    create(
        "TextLabel",
        {

            Position =
                UDim2.fromOffset(
                    10,
                    6
                ),

            Size =
                UDim2.new(
                    1,
                    -20,
                    0,
                    24
                ),

            BackgroundTransparency =
                1,

            Text =
                "RESUMO",

            TextColor3 =
                COLORS.TEXT,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                13,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            Parent =
                Content,
        }
    )

local Viewer =
    create(
        "TextBox",
        {

            Position =
                UDim2.fromOffset(
                    8,
                    35
                ),

            Size =
                UDim2.new(
                    1,
                    -16,
                    1,
                    -78
                ),

            BackgroundColor3 =
                COLORS.BG,

            BorderSizePixel =
                0,

            Text =
                "Execute \"LER BOTS\" para iniciar a leitura.",

            TextColor3 =
                COLORS.TEXT,

            TextSize =
                10,

            Font =
                Enum.Font.Code,

            TextWrapped =
                false,

            MultiLine =
                true,

            ClearTextOnFocus =
                false,

            TextEditable =
                false,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            TextYAlignment =
                Enum.TextYAlignment.Top,

            Parent =
                Content,
        }
    )

corner(
    Viewer,
    8
)

--==============================================================--
-- UI STATUS
--==============================================================--

local function setStatus(
    text,
    color
)

    StatusText.Text =
        tostring(
            text or ""
        )

    if color then

        StatusDot.BackgroundColor3 =
            color

    end
end

local function setProgress(
    value
)

    value =
        math.clamp(
            tonumber(value)
            or 0,
            0,
            1
        )

    TweenService:Create(

        ProgressFill,

        TweenInfo.new(
            0.12
        ),

        {

            Size =
                UDim2.new(
                    value,
                    0,
                    1,
                    0
                )
        }

    ):Play()
end

local function updateDetails()

    local patrol =
        State.Results
        and State.Results.PatrolSystem

    local army =
        patrol
        and patrol.groups
        and patrol.groups.Army
        or 0

    local rebels =
        patrol
        and patrol.groups
        and patrol.groups.Rebels
        or 0

    DetailText.Text =
        tostring(
            #State.Results.Bots
        )
        .. " candidatos • "
        .. tostring(army)
        .. " Army points • "
        .. tostring(rebels)
        .. " Rebels points"
end

--==============================================================--
-- PREVIEW
--==============================================================--

local function buildPreview(
    area
)

    local output = {}

    if area == "Resumo" then

        local summary =
            State.Results.Summary
            or {}

        local patrol =
            State.Results.PatrolSystem
            or {}

        output[
            #output + 1
        ] =
            "CAFEÍNA • BOT READER"

        output[
            #output + 1
        ] = ""

        output[
            #output + 1
        ] =
            "BotPatrolPoints: "
            .. tostring(
                patrol.found
            )

        output[
            #output + 1
        ] =
            "Army points: "
            .. tostring(
                patrol.groups
                and patrol.groups.Army
                or 0
            )

        output[
            #output + 1
        ] =
            "Rebels points: "
            .. tostring(
                patrol.groups
                and patrol.groups.Rebels
                or 0
            )

        output[
            #output + 1
        ] = ""

        output[
            #output + 1
        ] =
            "Candidates: "
            .. tostring(
                summary.totalCandidates
                or 0
            )

        output[
            #output + 1
        ] =
            "Active Bots: "
            .. tostring(
                summary.activeBots
                or 0
            )

        output[
            #output + 1
        ] =
            "Bot Candidates: "
            .. tostring(
                summary.botCandidates
                or 0
            )

        output[
            #output + 1
        ] =
            "Possible Dummies: "
            .. tostring(
                summary.possibleDummies
                or 0
            )

        output[
            #output + 1
        ] =
            "Players: "
            .. tostring(
                summary.players
                or 0
            )

        output[
            #output + 1
        ] = ""

        output[
            #output + 1
        ] =
            "Army association: "
            .. tostring(
                summary.army
                or 0
            )

        output[
            #output + 1
        ] =
            "Rebels association: "
            .. tostring(
                summary.rebels
                or 0
            )

        output[
            #output + 1
        ] =
            "Unknown team: "
            .. tostring(
                summary.unknownTeam
                or 0
            )

    elseif area == "Patrol" then

        local patrol =
            State.Results.PatrolSystem

        output[
            #output + 1
        ] =
            "BOT PATROL POINTS"

        output[
            #output + 1
        ] = ""

        output[
            #output + 1
        ] =
            "Path: "
            .. tostring(
                patrol.path
                or "não encontrado"
            )

        output[
            #output + 1
        ] =
            "Army: "
            .. tostring(
                patrol.groups.Army
            )

        output[
            #output + 1
        ] =
            "Rebels: "
            .. tostring(
                patrol.groups.Rebels
            )

        output[
            #output + 1
        ] =
            "Other: "
            .. tostring(
                patrol.groups.Other
            )

        output[
            #output + 1
        ] = ""

        for index, point
            in ipairs(
                patrol.points or {}
            )
        do

            output[
                #output + 1
            ] =
                "["
                .. tostring(
                    point.group
                )
                .. "] "
                .. tostring(
                    point.path
                )

            output[
                #output + 1
            ] =
                "Team="
                .. tostring(
                    point.teamAttribute
                    or "nil"
                )
                .. " | consistency="
                .. tostring(
                    point.consistency
                )

            if point.position then

                output[
                    #output + 1
                ] =
                    string.format(
                        "Position: %.2f, %.2f, %.2f",
                        point.position.x,
                        point.position.y,
                        point.position.z
                    )

            end

            output[
                #output + 1
            ] = ""

            if
                #output
                >
                CONFIG.MAX_VIEW_CHARS
            then

                break

            end
        end

    elseif area == "Bots" then

        output[
            #output + 1
        ] =
            "BOT CANDIDATES"

        output[
            #output + 1
        ] = ""

        for index, bot
            in ipairs(
                State.Results.Bots
            )
        do

            output[
                #output + 1
            ] =
                "#"
                .. tostring(index)
                .. " "
                .. tostring(
                    bot.name
                )

            output[
                #output + 1
            ] =
                "Classificação: "
                .. tostring(
                    bot.classification
                )

            output[
                #output + 1
            ] =
                "Score: "
                .. tostring(
                    bot.confidenceScore
                )

            output[
                #output + 1
            ] =
                "Team: "
                .. tostring(
                    bot.detectedTeam
                    or "UNKNOWN"
                )

            output[
                #output + 1
            ] =
                "Path: "
                .. tostring(
                    bot.path
                )

            if bot.patrolAssociation then

                output[
                    #output + 1
                ] =
                    "Patrol: "
                    .. tostring(
                        bot.patrolAssociation
                            .group
                    )
                    .. " | "
                    .. string.format(
                        "%.2f studs",
                        bot.patrolAssociation
                            .distance
                    )

            else

                output[
                    #output + 1
                ] =
                    "Patrol: nenhuma associação"

            end

            output[
                #output + 1
            ] = ""

            if
                #table.concat(output, "\n")
                >
                CONFIG.MAX_VIEW_CHARS
            then

                break

            end
        end

    elseif area == "Dummies" then

        output[
            #output + 1
        ] =
            "POSSÍVEIS MANEQUINS"

        output[
            #output + 1
        ] = ""

        for _, bot
            in ipairs(
                State.Results.Bots
            )
        do

            if
                bot.classification
                == "POSSIBLE_DUMMY"
            then

                output[
                    #output + 1
                ] =
                    bot.name

                output[
                    #output + 1
                ] =
                    bot.path

                output[
                    #output + 1
                ] =
                    "Movement: "
                    .. tostring(
                        bot.evidence
                            .positionChanged
                    )

                output[
                    #output + 1
                ] =
                    "Rotation: "
                    .. tostring(
                        bot.evidence
                            .rotationChanged
                    )

                output[
                    #output + 1
                ] = ""

            end
        end

    elseif area == "Army" then

        output[
            #output + 1
        ] =
            "ARMY BOTS"

        output[
            #output + 1
        ] = ""

        for _, bot
            in ipairs(
                State.Results.Bots
            )
        do

            if
                bot.detectedTeam
                == "Army"
            then

                output[
                    #output + 1
                ] =
                    bot.name
                    .. " • "
                    .. bot.classification

                output[
                    #output + 1
                ] =
                    bot.path

                output[
                    #output + 1
                ] = ""

            end
        end

    elseif area == "Rebels" then

        output[
            #output + 1
        ] =
            "REBELS BOTS"

        output[
            #output + 1
        ] = ""

        for _, bot
            in ipairs(
                State.Results.Bots
            )
        do

            if
                bot.detectedTeam
                == "Rebels"
            then

                output[
                    #output + 1
                ] =
                    bot.name
                    .. " • "
                    .. bot.classification

                output[
                    #output + 1
                ] =
                    bot.path

                output[
                    #output + 1
                ] = ""

            end
        end
    end

    local text =
        table.concat(
            output,
            "\n"
        )

    if #text >
        CONFIG.MAX_VIEW_CHARS
    then

        text =
            string.sub(
                text,
                1,
                CONFIG.MAX_VIEW_CHARS
            )
            .. "\n\n[VISUALIZAÇÃO LIMITADA]"

    end

    return text
end

--==============================================================--
-- AREA NAVIGATION
--==============================================================--

local AreaButtons = {}

local function openArea(
    area
)

    AreaTitle.Text =
        string.upper(
            area
        )

    Viewer.Text =
        buildPreview(
            area
        )

    for name, button
        in pairs(
            AreaButtons
        )
    do

        button.BackgroundColor3 =
            name == area
            and COLORS.RED_DARK
            or COLORS.PANEL2

    end

    State.CurrentArea =
        area

    updateDetails()
end

--==============================================================--
-- AREA BUTTONS
--==============================================================--

local AREAS = {

    "Resumo",

    "Patrol",

    "Bots",

    "Dummies",

    "Army",

    "Rebels",
}

for _, area
    in ipairs(AREAS)
do

    local button =
        create(
            "TextButton",
            {

                Size =
                    UDim2.new(
                        1,
                        0,
                        0,
                        34
                    ),

                BackgroundColor3 =
                    COLORS.PANEL2,

                BorderSizePixel =
                    0,

                Text =
                    string.upper(
                        area
                    ),

                TextColor3 =
                    COLORS.TEXT,

                Font =
                    Enum.Font.GothamMedium,

                TextSize =
                    9,

                Parent =
                    AreaList,
            }
        )

    corner(
        button,
        7
    )

    button.Activated:Connect(
        function()

            openArea(
                area
            )

        end
    )

    AreaButtons[area] =
        button
end

--==============================================================--
-- BUTTON EVENTS
--==============================================================--

ReadButton.Activated:Connect(
    function()

        if State.Reading then

            State.CancelRequested =
                true

            setStatus(
                "Cancelando leitura...",
                COLORS.YELLOW
            )

            return
        end

        task.spawn(
            function()

                local ok, err =
                    pcall(
                        runReader
                    )

                if not ok then

                    State.Reading =
                        false

                    setStatus(
                        "Erro na leitura",
                        COLORS.RED
                    )

                    Viewer.Text =
                        tostring(
                            err
                        )

                end
            end
        )
    end
)

DownloadButton.Activated:Connect(
    function()

        task.spawn(
            downloadReading
        )

    end
)

--==============================================================--
-- MINIMIZE
--==============================================================--

local Mini =
    create(
        "TextButton",
        {

            Visible =
                false,

            Size =
                UDim2.fromOffset(
                    52,
                    52
                ),

            AnchorPoint =
                Vector2.new(
                    0.5,
                    0.5
                ),

            Position =
                UDim2.fromScale(
                    0.5,
                    0.5
                ),

            BackgroundColor3 =
                COLORS.RED,

            BorderSizePixel =
                0,

            Text =
                "C",

            TextColor3 =
                COLORS.TEXT,

            Font =
                Enum.Font.GothamBlack,

            TextSize =
                19,

            Parent =
                Gui,
        }
    )

corner(
    Mini,
    99
)

Minimize.Activated:Connect(
    function()

        Main.Visible =
            false

        Mini.Visible =
            true

    end
)

Mini.Activated:Connect(
    function()

        Mini.Visible =
            false

        Main.Visible =
            true

    end
)

--==============================================================--
-- CLOSE
--==============================================================--

Close.Activated:Connect(
    function()

        State.CancelRequested =
            true

        pcall(function()
            Gui:Destroy()
        end)

    end
)

--==============================================================--
-- DRAG
--==============================================================--

local function makeDraggable(
    target,
    handle
)

    local dragging =
        false

    local dragStart =
        nil

    local startPosition =
        nil

    handle.InputBegan:Connect(
        function(input)

            if
                input.UserInputType
                ==
                Enum.UserInputType.Touch

                or

                input.UserInputType
                ==
                Enum.UserInputType.MouseButton1
            then

                dragging =
                    true

                dragStart =
                    input.Position

                startPosition =
                    target.Position

            end
        end
    )

    UserInputService.InputChanged:Connect(
        function(input)

            if not dragging then
                return
            end

            if
                input.UserInputType
                ~=
                Enum.UserInputType.Touch

                and

                input.UserInputType
                ~=
                Enum.UserInputType.MouseMovement
            then

                return

            end

            if
                not dragStart
                or
                not startPosition
            then

                return

            end

            local delta =
                input.Position
                -
                dragStart

            target.Position =
                UDim2.new(

                    startPosition.X.Scale,

                    startPosition.X.Offset
                    + delta.X,

                    startPosition.Y.Scale,

                    startPosition.Y.Offset
                    + delta.Y
                )
        end
    )

    UserInputService.InputEnded:Connect(
        function(input)

            if
                input.UserInputType
                ==
                Enum.UserInputType.Touch

                or

                input.UserInputType
                ==
                Enum.UserInputType.MouseButton1
            then

                dragging =
                    false

            end
        end
    )
end

makeDraggable(
    Main,
    Header
)

--==============================================================--
-- READY
--==============================================================--

State.Results.Metadata =
    buildMetadata()

State.Results.PatrolSystem = {

    found = false,

    groups = {

        Army = 0,

        Rebels = 0,

        Other = 0,
    },

    points = {},
}

State.Results.Summary = {

    totalCandidates = 0,

    activeBots = 0,

    botCandidates = 0,

    possibleDummies = 0,

    players = 0,

    army = 0,

    rebels = 0,

    unknownTeam = 0,
}

openArea(
    "Resumo"
)

setProgress(
    0
)

updateDetails()

setStatus(
    "Pronto para leitura de bots",
    COLORS.GREEN
)

print(
    "[CAFEINA BOT READER V1] carregado."
)
