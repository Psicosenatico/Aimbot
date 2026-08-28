--==============================================================--
-- CAFEÍNA • BOT RESEARCH SCANNER
--==============================================================--
-- INTERFACE INDEPENDENTE
--
-- OBJETIVO:
-- • Investigar entidades que podem ser bots
-- • Diferenciar Player / Bot / Manequim / Indeterminado
-- • Detectar Army / Rebels
-- • Analisar BotPatrolPoints
-- • Analisar Humanoid / Health / movimento
-- • Analisar atributos e estrutura
-- • Identificar possíveis relações com patrulha
-- • Exportar a leitura para arquivo quando o ambiente permitir
--
-- OBS:
-- Este scanner trabalha somente com objetos que o cliente
-- consegue enxergar.
--==============================================================--

local Players =
    game:GetService("Players")

local UserInputService =
    game:GetService("UserInputService")

local HttpService =
    game:GetService("HttpService")

local TweenService =
    game:GetService("TweenService")

local CoreGui =
    game:GetService("CoreGui")

local LocalPlayer =
    Players.LocalPlayer

if not LocalPlayer then
    LocalPlayer =
        Players.PlayerAdded:Wait()
end

--==============================================================--
-- CONFIGURAÇÃO
--==============================================================--

local CONFIG = {

    GUI_NAME =
        "CafeinaBotResearch_Independent",

    MAX_ENTITIES =
        5000,

    MAX_CHILDREN_PER_ENTITY =
        250,

    PATROL_FOLDER =
        "BotPatrolPoints",

    POSSIBLE_BOT_CONTAINERS = {
        "Soldiers",
        "Bots",
        "Bot",
        "NPCs",
        "Enemies",
        "AI",
        "Units",
        "Characters",
    },

    TEAM_NAMES = {
        Army = true,
        Rebels = true,
    },

    YIELD_EVERY =
        50,

    MOVEMENT_SAMPLE_TIME =
        0.35,

    MOVEMENT_THRESHOLD =
        0.35,

    EXPORT_FILE =
        "Cafeina_Bot_Readout.json",
}

--==============================================================--
-- COLORS
--==============================================================--

local COLORS = {

    Background =
        Color3.fromRGB(
            10,
            12,
            17
        ),

    Panel =
        Color3.fromRGB(
            18,
            21,
            29
        ),

    Panel2 =
        Color3.fromRGB(
            25,
            29,
            39
        ),

    Panel3 =
        Color3.fromRGB(
            31,
            36,
            48
        ),

    Text =
        Color3.fromRGB(
            240,
            243,
            248
        ),

    Sub =
        Color3.fromRGB(
            151,
            160,
            176
        ),

    Blue =
        Color3.fromRGB(
            35,
            91,
            150
        ),

    BlueDark =
        Color3.fromRGB(
            18,
            46,
            82
        ),

    BlueBright =
        Color3.fromRGB(
            45,
            120,
            205
        ),

    Green =
        Color3.fromRGB(
            65,
            205,
            120
        ),

    Red =
        Color3.fromRGB(
            225,
            60,
            70
        ),

    Yellow =
        Color3.fromRGB(
            235,
            185,
            65
        ),

    Orange =
        Color3.fromRGB(
            235,
            125,
            55
        ),

    Stroke =
        Color3.fromRGB(
            55,
            64,
            82
        ),
}

--==============================================================--
-- EXECUTOR HELPERS
--==============================================================--

local SetClipboard =
    (
        typeof(setclipboard) == "function"
        and setclipboard
    )
    or
    (
        typeof(toclipboard) == "function"
        and toclipboard
    )
    or nil

local WriteFile =
    (
        typeof(writefile) == "function"
        and writefile
    )
    or nil

--==============================================================--
-- SAFE FUNCTIONS
--==============================================================--

local function safeCall(callback, default)
    local ok, result =
        pcall(callback)

    if ok then
        return result
    end

    return default
end

local function safeName(object)
    return safeCall(
        function()
            return tostring(object.Name)
        end,
        "?"
    )
end

local function safeClass(object)
    return safeCall(
        function()
            return tostring(object.ClassName)
        end,
        "?"
    )
end

local function safePath(object)
    return safeCall(
        function()
            return object:GetFullName()
        end,
        safeName(object)
    )
end

local function safeChildren(object)
    return safeCall(
        function()
            return object:GetChildren()
        end,
        {}
    )
end

local function safeDescendants(object)
    return safeCall(
        function()
            return object:GetDescendants()
        end,
        {}
    )
end

local function safeAttribute(object, name)
    return safeCall(
        function()
            return object:GetAttribute(name)
        end,
        nil
    )
end

local function safeAttributes(object)
    return safeCall(
        function()
            return object:GetAttributes()
        end,
        {}
    )
end

local function safeProperty(object, property)
    return safeCall(
        function()
            return object[property]
        end,
        nil
    )
end

local function safeIsA(object, className)
    return safeCall(
        function()
            return object:IsA(className)
        end,
        false
    )
end

local function formatNumber(value)
    if type(value) ~= "number" then
        return tostring(value)
    end

    return string.format(
        "%.3f",
        value
    )
end

local function vectorToTable(value)

    if typeof(value) ~= "Vector3" then
        return nil
    end

    return {
        x = value.X,
        y = value.Y,
        z = value.Z,
    }
end

--==============================================================--
-- GUI FACTORY
--==============================================================--

local function newObject(className, properties)

    local object =
        Instance.new(className)

    for property, value
        in pairs(properties or {})
    do
        object[property] = value
    end

    return object
end

local function addCorner(parent, radius)

    return newObject(
        "UICorner",
        {
            CornerRadius =
                UDim.new(
                    0,
                    radius or 8
                ),

            Parent =
                parent,
        }
    )
end

local function addStroke(parent)

    return newObject(
        "UIStroke",
        {
            Color =
                COLORS.Stroke,

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

local GuiParent

if typeof(gethui) == "function" then

    local ok, result =
        pcall(gethui)

    if ok then
        GuiParent = result
    end
end

local PlayerGui =
    LocalPlayer:WaitForChild(
        "PlayerGui"
    )

local ScreenGui =
    newObject(
        "ScreenGui",
        {
            Name =
                CONFIG.GUI_NAME,

            ResetOnSpawn =
                false,

            IgnoreGuiInset =
                true,

            ZIndexBehavior =
                Enum.ZIndexBehavior.Sibling,
        }
    )

local attached = false

if GuiParent then

    attached =
        pcall(function()
            ScreenGui.Parent =
                GuiParent
        end)
end

if not attached then

    attached =
        pcall(function()
            ScreenGui.Parent =
                CoreGui
        end)
end

if not attached then
    ScreenGui.Parent =
        PlayerGui
end

--==============================================================--
-- REMOVE SOMENTE NOSSA GUI
--==============================================================--

for _, object
    in ipairs(ScreenGui.Parent:GetChildren())
do

    if
        object ~= ScreenGui
        and object.Name
        == CONFIG.GUI_NAME
    then
        object:Destroy()
    end
end

--==============================================================--
-- STATE
--==============================================================--

local State = {

    Scanning =
        false,

    Cancel =
        false,

    HasRead =
        false,

    Results =
        {},

    Entities =
        {},

    PatrolPoints =
        {},

    SelectedIndex =
        nil,

    GeneratedText =
        "",

    LastExport =
        nil,
}

--==============================================================--
-- FIND TEAM
--==============================================================--

local function detectTeam(object)

    local team =
        safeAttribute(
            object,
            "Team"
        )

    if team ~= nil then

        team =
            tostring(team)

        if CONFIG.TEAM_NAMES[team] then
            return team,
                "Attribute.Team"
        end
    end

    local teamObject =
        safeProperty(
            object,
            "Team"
        )

    if teamObject then

        local teamName =
            safeCall(
                function()
                    return tostring(
                        teamObject.Name
                    )
                end,
                nil
            )

        if teamName
            and CONFIG.TEAM_NAMES[teamName]
        then
            return teamName,
                "Object.Team"
        end
    end

    local ancestors = {}

    local current =
        safeProperty(
            object,
            "Parent"
        )

    local depth = 0

    while current and depth < 8 do

        table.insert(
            ancestors,
            current
        )

        current =
            safeProperty(
                current,
                "Parent"
            )

        depth += 1
    end

    for _, ancestor
        in ipairs(ancestors)
    do

        local ancestorName =
            safeName(ancestor)

        if
            ancestorName == "Army"
            or ancestorName == "Rebels"
        then

            return ancestorName,
                "Ancestor"
        end

        local attribute =
            safeAttribute(
                ancestor,
                "Team"
            )

        if attribute then

            attribute =
                tostring(attribute)

            if CONFIG.TEAM_NAMES[attribute] then
                return attribute,
                    "Ancestor.Attribute.Team"
            end
        end
    end

    return "Unknown",
        "Not detected"
end

--==============================================================--
-- PLAYER TEST
--==============================================================--

local function isPlayerCharacter(model)

    if not model then
        return false
    end

    local player =
        safeCall(
            function()
                return Players:GetPlayerFromCharacter(
                    model
                )
            end,
            nil
        )

    if player then
        return true,
            player
    end

    return false,
        nil
end

--==============================================================--
-- HUMANOID
--==============================================================--

local function findHumanoid(model)

    local humanoid =
        safeCall(
            function()
                return model:FindFirstChildOfClass(
                    "Humanoid"
                )
            end,
            nil
        )

    return humanoid
end

local function findRoot(model)

    local root =
        safeCall(
            function()
                return model:FindFirstChild(
                    "HumanoidRootPart"
                )
            end,
            nil
        )

    if root then
        return root
    end

    local primary =
        safeProperty(
            model,
            "PrimaryPart"
        )

    if primary then
        return primary
    end

    return nil
end

--==============================================================--
-- PATROL POINTS
--==============================================================--

local function collectPatrolPoints()

    local result = {}

    local workspaceObject =
        workspace

    local folder =
        safeCall(
            function()
                return workspaceObject:FindFirstChild(
                    CONFIG.PATROL_FOLDER,
                    true
                )
            end,
            nil
        )

    if not folder then
        return result
    end

    local descendants =
        safeDescendants(folder)

    for _, object
        in ipairs(descendants)
    do

        if
            safeIsA(
                object,
                "BasePart"
            )
        then

            local team =
                safeAttribute(
                    object,
                    "Team"
                )

            local position =
                safeProperty(
                    object,
                    "Position"
                )

            result[
                #result + 1
            ] = {

                name =
                    safeName(object),

                className =
                    safeClass(object),

                path =
                    safePath(object),

                parentPath =
                    safePath(
                        safeProperty(
                            object,
                            "Parent"
                        )
                    ),

                team =
                    team
                    and tostring(team)
                    or "Unknown",

                position =
                    vectorToTable(
                        position
                    ),

                attributes =
                    safeAttributes(object),
            }
        end
    end

    return result
end

--==============================================================--
-- FIND NEAREST PATROL POINT
--==============================================================--

local function findNearestPatrol(root, team)

    if not root then
        return nil
    end

    local rootPosition =
        safeProperty(
            root,
            "Position"
        )

    if typeof(rootPosition)
        ~= "Vector3"
    then
        return nil
    end

    local nearest =
        nil

    local nearestDistance =
        math.huge

    for _, point
        in ipairs(State.PatrolPoints)
    do

        if
            point.position
            and
            (
                point.team
                == team
                or
                point.team
                == "Unknown"
            )
        then

            local position =
                Vector3.new(
                    point.position.x,
                    point.position.y,
                    point.position.z
                )

            local distance =
                (
                    rootPosition
                    - position
                ).Magnitude

            if distance
                < nearestDistance
            then

                nearestDistance =
                    distance

                nearest =
                    {
                        path =
                            point.path,

                        name =
                            point.name,

                        team =
                            point.team,

                        distance =
                            distance,
                    }
            end
        end
    end

    return nearest
end

--==============================================================--
-- MOVEMENT TEST
--==============================================================--

local function checkMovement(root, humanoid)

    if not root then

        return {
            available =
                false,

            moved =
                false,

            reason =
                "No root part",
        }
    end

    local start =
        safeProperty(
            root,
            "Position"
        )

    if typeof(start)
        ~= "Vector3"
    then

        return {
            available =
                false,

            moved =
                false,

            reason =
                "Position unavailable",
        }
    end

    local startTime =
        os.clock()

    task.wait(
        CONFIG.MOVEMENT_SAMPLE_TIME
    )

    local finish =
        safeProperty(
            root,
            "Position"
        )

    if typeof(finish)
        ~= "Vector3"
    then

        return {
            available =
                false,

            moved =
                false,

            reason =
                "Position unavailable after sample",
        }
    end

    local distance =
        (
            finish
            - start
        ).Magnitude

    local velocity =
        safeProperty(
            root,
            "AssemblyLinearVelocity"
        )

    local humanoidState =
        humanoid
        and
        safeCall(
            function()
                return tostring(
                    humanoid:GetState()
                )
            end,
            "Unknown"
        )
        or "No Humanoid"

    return {

        available =
            true,

        moved =
            distance
            >=
            CONFIG.MOVEMENT_THRESHOLD,

        distance =
            distance,

        sampleTime =
            os.clock()
            - startTime,

        velocity =
            vectorToTable(
                velocity
            ),

        humanoidState =
            humanoidState,
    }
end

--==============================================================--
-- RELEVANT CHILDREN
--==============================================================--

local function collectRelevantChildren(model)

    local result = {}

    local descendants =
        safeDescendants(model)

    local count = 0

    for _, object
        in ipairs(descendants)
    do

        count += 1

        if count >
            CONFIG.MAX_CHILDREN_PER_ENTITY
        then
            break
        end

        local className =
            safeClass(object)

        local name =
            safeName(object)

        local relevant =
            (
                className == "Humanoid"
            )
            or
            (
                name == "HumanoidRootPart"
            )
            or
            (
                className == "Animator"
            )
            or
            (
                className == "AnimationController"
            )
            or
            (
                className == "ObjectValue"
            )
            or
            (
                className == "StringValue"
            )
            or
            (
                className == "BoolValue"
            )
            or
            (
                className == "NumberValue"
            )
            or
            (
                name:lower():find(
                    "patrol",
                    1,
                    true
                ) ~= nil
            )
            or
            (
                name:lower():find(
                    "spawn",
                    1,
                    true
                ) ~= nil
            )
            or
            (
                name:lower():find(
                    "target",
                    1,
                    true
                ) ~= nil
            )
            or
            (
                name:lower():find(
                    "ai",
                    1,
                    true
                ) ~= nil
            )
            or
            (
                name:lower():find(
                    "weapon",
                    1,
                    true
                ) ~= nil
            )
        if relevant then

            result[
                #result + 1
            ] = {

                name =
                    name,

                className =
                    className,

                path =
                    safePath(object),

                value =
                    safeProperty(
                        object,
                        "Value"
                    ),
            }
        end
    end

    return result
end

--==============================================================--
-- SCORE CLASSIFICATION
--==============================================================--

local function classifyEntity(model)

    local humanoid =
        findHumanoid(model)

    local root =
        findRoot(model)

    local isPlayer,
        player =
        isPlayerCharacter(model)

    local team,
        teamSource =
        detectTeam(model)

    local attributes =
        safeAttributes(model)

    local score =
        0

    local evidence = {}

    local negativeEvidence = {}

    --==========================================================--
    -- PLAYER
    --==========================================================--

    if isPlayer then

        return {

            classification =
                "PLAYER",

            confidence =
                1,

            score =
                -100,

            team =
                (
                    player
                    and
                    safeProperty(
                        player,
                        "Team"
                    )
                    and
                    tostring(
                        safeProperty(
                            player.Team,
                            "Name"
                        )
                    )
                )
                or team,

            teamSource =
                player
                and
                "Players:GetPlayerFromCharacter"
                or teamSource,

            playerName =
                player
                and
                safeName(player)
                or nil,

            playerUserId =
                player
                and
                safeProperty(
                    player,
                    "UserId"
                )
                or nil,

            humanoid =
                humanoid ~= nil,

            root =
                root ~= nil,

            attributes =
                attributes,

            evidence = {
                "Players:GetPlayerFromCharacter retornou um Player"
            },

            negativeEvidence = {},
        }
    end

    --==========================================================--
    -- HUMANOID
    --==========================================================--

    if humanoid then

        score += 2

        table.insert(
            evidence,
            "Possui Humanoid"
        )

        local health =
            safeProperty(
                humanoid,
                "Health"
            )

        local maxHealth =
            safeProperty(
                humanoid,
                "MaxHealth"
            )

        if type(health) == "number"
            and type(maxHealth) == "number"
        then

            if maxHealth > 0 then

                score += 2

                table.insert(
                    evidence,
                    "Possui Health/MaxHealth válidos"
                )
            end
        end

        local state =
            safeCall(
                function()
                    return humanoid:GetState()
                end,
                nil
            )

        if state then

            if state
                ~= Enum.HumanoidStateType.None
            then

                score += 1

                table.insert(
                    evidence,
                    "Humanoid possui estado de execução"
                )
            end
        end
    else

        table.insert(
            negativeEvidence,
            "Não possui Humanoid"
        )
    end

    --==========================================================--
    -- ROOT
    --==========================================================--

    if root then

        score += 2

        table.insert(
            evidence,
            "Possui HumanoidRootPart/PrimaryPart"
        )

    else

        table.insert(
            negativeEvidence,
            "Não possui HumanoidRootPart/PrimaryPart"
        )
    end

    --==========================================================--
    -- TEAM
    --==========================================================--

    if team ~= "Unknown" then

        score += 2

        table.insert(
            evidence,
            "Equipe detectada: "
            .. team
            .. " via "
            .. teamSource
        )
    else

        table.insert(
            negativeEvidence,
            "Equipe não identificada"
        )
    end

    --==========================================================--
    -- BOT ATTRIBUTES
    --==========================================================--

    local botAttributeNames = {

        "Health",
        "HealthMult",
        "DamageMult",
        "Damage",
        "DamagePerSecond",
        "FireRate",
        "Range",
        "SpeedMult",
        "ReloadTime",
        "MagSize",
        "Gun",
    }

    local foundBotAttributes = {}

    for _, attributeName
        in ipairs(botAttributeNames)
    do

        if attributes[attributeName]
            ~= nil
        then

            foundBotAttributes[
                #foundBotAttributes + 1
            ] =
                attributeName
        end
    end

    if #foundBotAttributes > 0 then

        score +=
            math.min(
                4,
                #foundBotAttributes
            )

        table.insert(
            evidence,
            "Atributos relacionados a unidade: "
            .. table.concat(
                foundBotAttributes,
                ", "
            )
        )
    end

    --==========================================================--
    -- CONTAINER
    --==========================================================--

    local parent =
        safeProperty(
            model,
            "Parent"
        )

    local parentName =
        parent
        and
        safeName(parent)
        or ""

    for _, containerName
        in ipairs(
            CONFIG.POSSIBLE_BOT_CONTAINERS
        )
    do

        if parentName
            == containerName
        then

            score += 2

            table.insert(
                evidence,
                "Está dentro de "
                .. containerName
            )
        end
    end

    --==========================================================--
    -- PATROL
    --==========================================================--

    local nearestPatrol =
        findNearestPatrol(
            root,
            team
        )

    if nearestPatrol then

        local distance =
            nearestPatrol.distance

        if distance <= 100 then

            score += 3

            table.insert(
                evidence,
                "Existe ponto de patrulha próximo"
            )

        elseif distance <= 300 then

            score += 1

            table.insert(
                evidence,
                "Existe ponto de patrulha na região"
            )
        end
    end

    --==========================================================--
    -- MODEL
    --==========================================================--

    if safeIsA(model, "Model") then

        score += 1

        table.insert(
            evidence,
            "Entidade é um Model"
        )
    end

    --==========================================================--
    -- CLASSIFICATION
    --==========================================================--

    local classification

    local confidence

    if score >= 8 then

        classification =
            "BOT JOGÁVEL"

        confidence =
            math.clamp(
                score / 13,
                0,
                1
            )

    elseif score >= 4 then

        classification =
            "PROVÁVEL BOT"

        confidence =
            math.clamp(
                score / 10,
                0,
                0.85
            )

    elseif
        humanoid
        and
        not root
    then

        classification =
            "POSSÍVEL MANEQUIM"

        confidence =
            0.45

    else

        classification =
            "INDETERMINADO"

        confidence =
            0.25
    end

    return {

        classification =
            classification,

        confidence =
            confidence,

        score =
            score,

        team =
            team,

        teamSource =
            teamSource,

        humanoid =
            humanoid ~= nil,

        root =
            root ~= nil,

        player =
            false,

        attributes =
            attributes,

        evidence =
            evidence,

        negativeEvidence =
            negativeEvidence,

        nearestPatrol =
            nearestPatrol,
    }
end

--==============================================================--
-- ENTITY RECORD
--==============================================================--

local function buildEntityRecord(model)

    local classification =
        classifyEntity(model)

    local humanoid =
        findHumanoid(model)

    local root =
        findRoot(model)

    local position =
        root
        and
        safeProperty(
            root,
            "Position"
        )
        or nil

    local health =
        humanoid
        and
        safeProperty(
            humanoid,
            "Health"
        )
        or nil

    local maxHealth =
        humanoid
        and
        safeProperty(
            humanoid,
            "MaxHealth"
        )
        or nil

    local walkSpeed =
        humanoid
        and
        safeProperty(
            humanoid,
            "WalkSpeed"
        )
        or nil

    local jumpPower =
        humanoid
        and
        safeProperty(
            humanoid,
            "JumpPower"
        )
        or nil

    local velocity =
        root
        and
        safeProperty(
            root,
            "AssemblyLinearVelocity"
        )
        or nil

    local movement =
        checkMovement(
            root,
            humanoid
        )

    local player,
        playerObject =
        isPlayerCharacter(model)

    return {

        name =
            safeName(model),

        className =
            safeClass(model),

        path =
            safePath(model),

        parentPath =
            safePath(
                safeProperty(
                    model,
                    "Parent"
                )
            ),

        classification =
            classification.classification,

        confidence =
            classification.confidence,

        score =
            classification.score,

        team =
            classification.team,

        teamSource =
            classification.teamSource,

        isPlayer =
            player,

        playerName =
            playerObject
            and
            safeName(playerObject)
            or nil,

        playerUserId =
            playerObject
            and
            safeProperty(
                playerObject,
                "UserId"
            )
            or nil,

        humanoid =
            {

                exists =
                    humanoid ~= nil,

                health =
                    health,

                maxHealth =
                    maxHealth,

                walkSpeed =
                    walkSpeed,

                jumpPower =
                    jumpPower,

                state =
                    humanoid
                    and
                    safeCall(
                        function()
                            return tostring(
                                humanoid:GetState()
                            )
                        end,
                        "Unknown"
                    )
                    or nil,
            },

        root =
            {

                exists =
                    root ~= nil,

                name =
                    root
                    and
                    safeName(root)
                    or nil,

                position =
                    vectorToTable(position),

                velocity =
                    vectorToTable(velocity),
            },

        movement =
            movement,

        nearestPatrol =
            classification.nearestPatrol,

        attributes =
            classification.attributes,

        evidence =
            classification.evidence,

        negativeEvidence =
            classification.negativeEvidence,

        relevantChildren =
            collectRelevantChildren(model),
    }
end

--==============================================================--
-- ENTITY DISCOVERY
--==============================================================--

local function shouldInspectModel(model)

    if not safeIsA(model, "Model") then
        return false
    end

    local humanoid =
        findHumanoid(model)

    local root =
        findRoot(model)

    local isPlayer =
        isPlayerCharacter(model)

    local team =
        detectTeam(model)

    local lowerName =
        safeName(model):lower()

    local interestingName =
        lowerName:find(
            "bot",
            1,
            true
        )
        or
        lowerName:find(
            "npc",
            1,
            true
        )
        or
        lowerName:find(
            "soldier",
            1,
            true
        )
        or
        lowerName:find(
            "dummy",
            1,
            true
        )
        or
        lowerName:find(
            "mannequin",
            1,
            true
        )
        or
        lowerName:find(
            "armour",
            1,
            true
        )
        or
        lowerName:find(
            "enemy",
            1,
            true
        )

    return
        humanoid ~= nil
        or
        root ~= nil
        or
        isPlayer
        or
        team ~= "Unknown"
        or
        interestingName ~= nil
end

--==============================================================--
-- SCAN
--==============================================================--

local function performScan()

    if State.Scanning then
        return
    end

    State.Scanning =
        true

    State.Cancel =
        false

    State.Results =
        {}

    State.Entities =
        {}

    State.HasRead =
        false

    StatusLabel.Text =
        "Procurando estruturas..."

    StatusLabel.TextColor3 =
        COLORS.Yellow

    ProgressFill.Size =
        UDim2.new(
            0,
            0,
            1,
            0
        )

    --==========================================================--
    -- PATROL
    --==========================================================--

    State.PatrolPoints =
        collectPatrolPoints()

    --==========================================================--
    -- DESCENDANTS
    --==========================================================--

    local descendants =
        safeDescendants(
            workspace
        )

    local candidates =
        {}

    for _, object
        in ipairs(descendants)
    do

        if State.Cancel then
            break
        end

        if shouldInspectModel(object) then

            candidates[
                #candidates + 1
            ] =
                object

            if
                #candidates
                >= CONFIG.MAX_ENTITIES
            then
                break
            end
        end
    end

    local total =
        #candidates

    --==========================================================--
    -- ANALYZE
    --==========================================================--

    for index, model
        in ipairs(candidates)
    do

        if State.Cancel then
            break
        end

        local ok, record =
            pcall(
                buildEntityRecord,
                model
            )

        if ok
            and type(record)
            == "table"
        then

            State.Entities[
                #State.Entities + 1
            ] =
                record
        end

        local progress =
            total > 0
            and index / total
            or 1

        ProgressFill.Size =
            UDim2.new(
                progress,
                0,
                1,
                0
            )

        StatusLabel.Text =
            "Analisando "
            .. tostring(index)
            .. " / "
            .. tostring(total)

        if
            index
            % CONFIG.YIELD_EVERY
            == 0
        then
            task.wait()
        end
    end

    --==========================================================--
    -- SUMMARY
    --==========================================================--

    local summary = {

        total =
            #State.Entities,

        botJogavel =
            0,

        provavelBot =
            0,

        manequim =
            0,

        indeterminado =
            0,

        players =
            0,

        army =
            0,

        rebels =
            0,

        patrolPoints =
            #State.PatrolPoints,
    }

    for _, entity
        in ipairs(State.Entities)
    do

        if entity.classification
            == "BOT JOGÁVEL"
        then
            summary.botJogavel += 1

        elseif entity.classification
            == "PROVÁVEL BOT"
        then
            summary.provavelBot += 1

        elseif entity.classification
            == "POSSÍVEL MANEQUIM"
        then
            summary.manequim += 1

        else
            summary.indeterminado += 1
        end

        if entity.isPlayer then
            summary.players += 1
        end

        if entity.team == "Army" then
            summary.army += 1

        elseif entity.team == "Rebels" then
            summary.rebels += 1
        end
    end

    State.Results =
        {

            generatedAt =
                os.time(),

            game = {

                placeId =
                    game.PlaceId,

                gameId =
                    game.GameId,

                jobId =
                    game.JobId,
            },

            summary =
                summary,

            patrolPoints =
                State.PatrolPoints,

            entities =
                State.Entities,
        }

    State.HasRead =
        true

    State.Scanning =
        false

    if State.Cancel then

        StatusLabel.Text =
            "Leitura cancelada"

        StatusLabel.TextColor3 =
            COLORS.Orange

    else

        StatusLabel.Text =
            "Leitura concluída • "
            .. tostring(
                #State.Entities
            )
            .. " entidades"

        StatusLabel.TextColor3 =
            COLORS.Green

        ProgressFill.Size =
            UDim2.new(
                1,
                0,
                1,
                0
            )
    end

    updateSummary()
    showSummary()
end

--==============================================================--
-- JSON
--==============================================================--

local function generateJSON()

    if not State.HasRead then
        return nil
    end

    local ok, encoded =
        pcall(function()

            return HttpService:JSONEncode(
                State.Results
            )

        end)

    if not ok then
        return nil
    end

    return encoded
end

--==============================================================--
-- TEXT REPORT
--==============================================================--

local function generateReadableReport()

    if not State.HasRead then
        return "Nenhuma leitura realizada."
    end

    local lines = {}

    local summary =
        State.Results.summary

    table.insert(
        lines,
        "================================================"
    )

    table.insert(
        lines,
        "CAFEÍNA • BOT RESEARCH REPORT"
    )

    table.insert(
        lines,
        "================================================"
    )

    table.insert(
        lines,
        ""
    )

    table.insert(
        lines,
        "PLACE ID: "
        .. tostring(
            State.Results.game.placeId
        )
    )

    table.insert(
        lines,
        "GAME ID: "
        .. tostring(
            State.Results.game.gameId
        )
    )

    table.insert(
        lines,
        ""
    )

    table.insert(
        lines,
        "RESUMO"
    )

    table.insert(
        lines,
        "Entidades: "
        .. tostring(summary.total)
    )

    table.insert(
        lines,
        "Bot jogável: "
        .. tostring(summary.botJogavel)
    )

    table.insert(
        lines,
        "Provável bot: "
        .. tostring(summary.provavelBot)
    )

    table.insert(
        lines,
        "Possível manequim: "
        .. tostring(summary.manequim)
    )

    table.insert(
        lines,
        "Indeterminado: "
        .. tostring(summary.indeterminado)
    )

    table.insert(
        lines,
        "Players: "
        .. tostring(summary.players)
    )

    table.insert(
        lines,
        "Army: "
        .. tostring(summary.army)
    )

    table.insert(
        lines,
        "Rebels: "
        .. tostring(summary.rebels)
    )

    table.insert(
        lines,
        "Patrol Points: "
        .. tostring(summary.patrolPoints)
    )

    table.insert(
        lines,
        ""
    )

    table.insert(
        lines,
        "================================================"
    )

    table.insert(
        lines,
        "ENTIDADES"
    )

    table.insert(
        lines,
        "================================================"
    )

    for index, entity
        in ipairs(State.Entities)
    do

        table.insert(
            lines,
            ""
        )

        table.insert(
            lines,
            "------------------------------------------------"
        )

        table.insert(
            lines,
            "#" .. tostring(index)
        )

        table.insert(
            lines,
            "Nome: "
            .. entity.name
        )

        table.insert(
            lines,
            "Classe: "
            .. entity.className
        )

        table.insert(
            lines,
            "Classificação: "
            .. entity.classification
        )

        table.insert(
            lines,
            "Score: "
            .. tostring(entity.score)
        )

        table.insert(
            lines,
            "Confiança: "
            .. string.format(
                "%.1f%%",
                entity.confidence * 100
            )
        )

        table.insert(
            lines,
            "Time: "
            .. tostring(entity.team)
        )

        table.insert(
            lines,
            "Fonte do time: "
            .. tostring(entity.teamSource)
        )

        table.insert(
            lines,
            "Player: "
            .. tostring(entity.isPlayer)
        )

        table.insert(
            lines,
            "Path: "
            .. entity.path
        )

        table.insert(
            lines,
            ""
        )

        table.insert(
            lines,
            "HUMANOID"
        )

        table.insert(
            lines,
            "Existe: "
            .. tostring(
                entity.humanoid.exists
            )
        )

        table.insert(
            lines,
            "Health: "
            .. tostring(
                entity.humanoid.health
            )
            .. " / "
            .. tostring(
                entity.humanoid.maxHealth
            )
        )

        table.insert(
            lines,
            "WalkSpeed: "
            .. tostring(
                entity.humanoid.walkSpeed
            )
        )

        table.insert(
            lines,
            "Estado: "
            .. tostring(
                entity.humanoid.state
            )
        )

        table.insert(
            lines,
            ""
        )

        table.insert(
            lines,
            "MOVIMENTO"
        )

        table.insert(
            lines,
            "Root: "
            .. tostring(
                entity.root.exists
            )
        )

        table.insert(
            lines,
            "Movimento detectado: "
            .. tostring(
                entity.movement.moved
            )
        )

        table.insert(
            lines,
            "Distância durante amostra: "
            .. formatNumber(
                entity.movement.distance
            )
        )

        if entity.nearestPatrol then

            table.insert(
                lines,
                ""
            )

            table.insert(
                lines,
                "PATRULHA"
            )

            table.insert(
                lines,
                "Ponto próximo: "
                .. tostring(
                    entity.nearestPatrol.name
                )
            )

            table.insert(
                lines,
                "Time do ponto: "
                .. tostring(
                    entity.nearestPatrol.team
                )
            )

            table.insert(
                lines,
                "Distância: "
                .. formatNumber(
                    entity.nearestPatrol.distance
                )
            )

            table.insert(
                lines,
                "Path: "
                .. tostring(
                    entity.nearestPatrol.path
                )
            )
        end

        table.insert(
            lines,
            ""
        )

        table.insert(
            lines,
            "EVIDÊNCIAS"
        )

        for _, evidence
            in ipairs(
                entity.evidence
            )
        do

            table.insert(
                lines,
                " + "
                .. tostring(evidence)
            )
        end

        if #entity.negativeEvidence
            > 0
        then

            table.insert(
                lines,
                ""
            )

            table.insert(
                lines,
                "AUSÊNCIAS / CONTRA-EVIDÊNCIAS"
            )

            for _, evidence
                in ipairs(
                    entity.negativeEvidence
                )
            do

                table.insert(
                    lines,
                    " - "
                    .. tostring(evidence)
                )
            end
        end

        table.insert(
            lines,
            ""
        )

        table.insert(
            lines,
            "ATRIBUTOS"
        )

        for key, value
            in pairs(
                entity.attributes
            )
        do

            table.insert(
                lines,
                " "
                .. tostring(key)
                .. " = "
                .. tostring(value)
            )
        end

        table.insert(
            lines,
            ""
        )

        table.insert(
            lines,
            "FILHOS RELEVANTES"
        )

        for _, child
            in ipairs(
                entity.relevantChildren
            )
        do

            table.insert(
                lines,
                " • "
                .. tostring(child.name)
                .. " ["
                .. tostring(child.className)
                .. "]"
            )
        end
    end

    return table.concat(
        lines,
        "\n"
    )
end

--==============================================================--
-- EXPORT
--==============================================================--

local function exportReport()

    if not State.HasRead then

        StatusLabel.Text =
            "Faça uma leitura primeiro"

        StatusLabel.TextColor3 =
            COLORS.Yellow

        return
    end

    local json =
        generateJSON()

    if not json then

        StatusLabel.Text =
            "Erro ao gerar JSON"

        StatusLabel.TextColor3 =
            COLORS.Red

        return
    end

    State.GeneratedText =
        generateReadableReport()

    --==========================================================--
    -- WRITEFILE
    --==========================================================--

    if WriteFile then

        local ok =
            pcall(
                WriteFile,
                CONFIG.EXPORT_FILE,
                json
            )

        if ok then

            State.LastExport =
                CONFIG.EXPORT_FILE

            StatusLabel.Text =
                "Arquivo gerado: "
                .. CONFIG.EXPORT_FILE

            StatusLabel.TextColor3 =
                COLORS.Green

            return
        end
    end

    --==========================================================--
    -- CLIPBOARD FALLBACK
    --==========================================================--

    if SetClipboard then

        local ok =
            pcall(
                SetClipboard,
                json
            )

        if ok then

            StatusLabel.Text =
                "JSON copiado para o clipboard"

            StatusLabel.TextColor3 =
                COLORS.Green

            return
        end
    end

    StatusLabel.Text =
        "Ambiente não permite arquivo/clipboard"

    StatusLabel.TextColor3 =
        COLORS.Yellow
end

--==============================================================--
-- SUMMARY UI
--==============================================================--

function updateSummary()

    if not State.HasRead then

        SummaryText.Text =
            "Nenhuma leitura realizada."

        return
    end

    local s =
        State.Results.summary

    SummaryText.Text =
        "ENTIDADES: "
        .. tostring(s.total)
        .. "\n\n"
        .. "BOT JOGÁVEL: "
        .. tostring(s.botJogavel)
        .. "\n"
        .. "PROVÁVEL BOT: "
        .. tostring(s.provavelBot)
        .. "\n"
        .. "POSSÍVEL MANEQUIM: "
        .. tostring(s.manequim)
        .. "\n"
        .. "INDETERMINADO: "
        .. tostring(s.indeterminado)
        .. "\n\n"
        .. "ARMY: "
        .. tostring(s.army)
        .. "\n"
        .. "REBELS: "
        .. tostring(s.rebels)
        .. "\n"
        .. "PLAYERS: "
        .. tostring(s.players)
        .. "\n\n"
        .. "PATROL POINTS: "
        .. tostring(s.patrolPoints)
end

--==============================================================--
-- RESULT VIEW
--==============================================================--

local function showSummary()

    if not State.HasRead then
        Viewer.Text =
            "Nenhuma leitura realizada."

        return
    end

    local report =
        generateReadableReport()

    Viewer.Text =
        report
end

--==============================================================--
-- RESULT SELECTION
--==============================================================--

local function showEntity(index)

    local entity =
        State.Entities[index]

    if not entity then
        return
    end

    State.SelectedIndex =
        index

    local lines = {}

    table.insert(
        lines,
        "BOT RESEARCH • ENTITY #"
        .. tostring(index)
    )

    table.insert(
        lines,
        ""
    )

    table.insert(
        lines,
        "Nome: "
        .. entity.name
    )

    table.insert(
        lines,
        "Classificação: "
        .. entity.classification
    )

    table.insert(
        lines,
        "Score: "
        .. tostring(entity.score)
    )

    table.insert(
        lines,
        "Confiança: "
        .. string.format(
            "%.1f%%",
            entity.confidence * 100
        )
    )

    table.insert(
        lines,
        "Time: "
        .. tostring(entity.team)
    )

    table.insert(
        lines,
        "Fonte: "
        .. tostring(entity.teamSource)
    )

    table.insert(
        lines,
        ""
    )

    table.insert(
        lines,
        "PATH"
    )

    table.insert(
        lines,
        entity.path
    )

    table.insert(
        lines,
        ""
    )

    table.insert(
        lines,
        "HEALTH"
    )

    table.insert(
        lines,
        tostring(
            entity.humanoid.health
        )
        .. " / "
        .. tostring(
            entity.humanoid.maxHealth
        )
    )

    table.insert(
        lines,
        "WalkSpeed: "
        .. tostring(
            entity.humanoid.walkSpeed
        )
    )

    table.insert(
        lines,
        "State: "
        .. tostring(
            entity.humanoid.state
        )
    )

    table.insert(
        lines,
        ""
    )

    table.insert(
        lines,
        "MOVIMENTO"
    )

    table.insert(
        lines,
        "Detectado: "
        .. tostring(
            entity.movement.moved
        )
    )

    table.insert(
        lines,
        "Distância: "
        .. formatNumber(
            entity.movement.distance
        )
    )

    table.insert(
        lines,
        ""
    )

    table.insert(
        lines,
        "EVIDÊNCIAS"
    )

    for _, evidence
        in ipairs(entity.evidence)
    do

        table.insert(
            lines,
            "+ "
            .. tostring(evidence)
        )
    end

    if entity.nearestPatrol then

        table.insert(
            lines,
            ""
        )

        table.insert(
            lines,
            "PATRULHA"
        )

        table.insert(
            lines,
            "Nome: "
            .. tostring(
                entity.nearestPatrol.name
            )
        )

        table.insert(
            lines,
            "Time: "
            .. tostring(
                entity.nearestPatrol.team
            )
        )

        table.insert(
            lines,
            "Distância: "
            .. formatNumber(
                entity.nearestPatrol.distance
            )
        )
    end

    Viewer.Text =
        table.concat(
            lines,
            "\n"
        )
end

--==============================================================--
-- MAIN WINDOW
--==============================================================--

local Main =
    newObject(
        "Frame",
        {
            Size =
                UDim2.fromScale(
                    0.86,
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
                COLORS.Background,

            BorderSizePixel =
                0,

            Parent =
                ScreenGui,
        }
    )

addCorner(Main, 14)
addStroke(Main)

--==============================================================--
-- HEADER
--==============================================================--

local Header =
    newObject(
        "Frame",
        {
            Size =
                UDim2.new(
                    1,
                    0,
                    0,
                    54
                ),

            BackgroundColor3 =
                COLORS.Panel,

            BorderSizePixel =
                0,

            Parent =
                Main,
        }
    )

addCorner(Header, 14)

newObject(
    "TextLabel",
    {
        Position =
            UDim2.fromOffset(
                15,
                8
            ),

        Size =
            UDim2.new(
                1,
                -120,
                0,
                22
            ),

        BackgroundTransparency =
            1,

        Text =
            "CAFEÍNA • BOT RESEARCH",

        TextColor3 =
            COLORS.Text,

        Font =
            Enum.Font.GothamBold,

        TextSize =
            15,

        TextXAlignment =
            Enum.TextXAlignment.Left,

        Parent =
            Header,
    }
)

newObject(
    "TextLabel",
    {
        Position =
            UDim2.fromOffset(
                15,
                30
            ),

        Size =
            UDim2.new(
                1,
                -120,
                0,
                15
            ),

        BackgroundTransparency =
            1,

        Text =
            "scanner independente • análise client-visible",

        TextColor3 =
            COLORS.Sub,

        Font =
            Enum.Font.Gotham,

        TextSize =
            9,

        TextXAlignment =
            Enum.TextXAlignment.Left,

        Parent =
            Header,
    }
)

local MinimizeButton =
    newObject(
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
                    28,
                    28
                ),

            BackgroundColor3 =
                COLORS.BlueDark,

            BorderSizePixel =
                0,

            Text =
                "—",

            TextColor3 =
                COLORS.Text,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                16,

            Parent =
                Header,
        }
    )

addCorner(MinimizeButton, 8)

local CloseButton =
    newObject(
        "TextButton",
        {
            Position =
                UDim2.new(
                    1,
                    -42,
                    0,
                    11
                ),

            Size =
                UDim2.fromOffset(
                    28,
                    28
                ),

            BackgroundColor3 =
                COLORS.Red,

            BorderSizePixel =
                0,

            Text =
                "×",

            TextColor3 =
                COLORS.Text,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                17,

            Parent =
                Header,
        }
    )

addCorner(CloseButton, 8)

--==============================================================--
-- STATUS
--==============================================================--

local StatusBar =
    newObject(
        "Frame",
        {
            Position =
                UDim2.new(
                    0,
                    9,
                    0,
                    63
                ),

            Size =
                UDim2.new(
                    1,
                    -18,
                    0,
                    43
                ),

            BackgroundColor3 =
                COLORS.Panel,

            BorderSizePixel =
                0,

            Parent =
                Main,
        }
    )

addCorner(StatusBar, 9)

local StatusLabel =
    newObject(
        "TextLabel",
        {
            Position =
                UDim2.fromOffset(
                    12,
                    7
                ),

            Size =
                UDim2.new(
                    1,
                    -24,
                    0,
                    20
                ),

            BackgroundTransparency =
                1,

            Text =
                "Pronto para leitura",

            TextColor3 =
                COLORS.Green,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                10,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            Parent =
                StatusBar,
        }
    )

local ProgressBG =
    newObject(
        "Frame",
        {
            Position =
                UDim2.new(
                    0,
                    12,
                    1,
                    -8
                ),

            Size =
                UDim2.new(
                    1,
                    -24,
                    0,
                    4
                ),

            BackgroundColor3 =
                COLORS.Panel3,

            BorderSizePixel =
                0,

            Parent =
                StatusBar,
        }
    )

addCorner(ProgressBG, 99)

local ProgressFill =
    newObject(
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
                COLORS.BlueBright,

            BorderSizePixel =
                0,

            Parent =
                ProgressBG,
        }
    )

addCorner(ProgressFill, 99)

--==============================================================--
-- BODY
--==============================================================--

local Left =
    newObject(
        "Frame",
        {
            Position =
                UDim2.new(
                    0,
                    9,
                    0,
                    113
                ),

            Size =
                UDim2.new(
                    0.28,
                    -5,
                    1,
                    -122
                ),

            BackgroundColor3 =
                COLORS.Panel,

            BorderSizePixel =
                0,

            Parent =
                Main,
        }
    )

addCorner(Left, 10)

local Right =
    newObject(
        "Frame",
        {
            Position =
                UDim2.new(
                    0.28,
                    5,
                    0,
                    113
                ),

            Size =
                UDim2.new(
                    0.72,
                    -14,
                    1,
                    -122
                ),

            BackgroundColor3 =
                COLORS.Panel,

            BorderSizePixel =
                0,

            Parent =
                Main,
        }
    )

addCorner(Right, 10)

--==============================================================--
-- LEFT BUTTONS
--==============================================================--

local ScanButton =
    newObject(
        "TextButton",
        {
            Position =
                UDim2.fromOffset(
                    8,
                    8
                ),

            Size =
                UDim2.new(
                    1,
                    -16,
                    0,
                    40
                ),

            BackgroundColor3 =
                COLORS.Blue,

            BorderSizePixel =
                0,

            Text =
                "INICIAR LEITURA",

            TextColor3 =
                COLORS.Text,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                10,

            Parent =
                Left,
        }
    )

addCorner(ScanButton, 8)

local CancelButton =
    newObject(
        "TextButton",
        {
            Position =
                UDim2.fromOffset(
                    8,
                    54
                ),

            Size =
                UDim2.new(
                    1,
                    -16,
                    0,
                    34
                ),

            BackgroundColor3 =
                COLORS.Panel3,

            BorderSizePixel =
                0,

            Text =
                "CANCELAR",

            TextColor3 =
                COLORS.Sub,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                9,

            Parent =
                Left,
        }
    )

addCorner(CancelButton, 8)

local SummaryTitle =
    newObject(
        "TextLabel",
        {
            Position =
                UDim2.fromOffset(
                    11,
                    100
                ),

            Size =
                UDim2.new(
                    1,
                    -22,
                    0,
                    20
                ),

            BackgroundTransparency =
                1,

            Text =
                "RESUMO DA LEITURA",

            TextColor3 =
                COLORS.Text,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                10,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            Parent =
                Left,
        }
    )

SummaryText =
    newObject(
        "TextLabel",
        {
            Position =
                UDim2.fromOffset(
                    11,
                    125
                ),

            Size =
                UDim2.new(
                    1,
                    -22,
                    1,
                    -255
                ),

            BackgroundTransparency =
                1,

            Text =
                "Nenhuma leitura realizada.",

            TextColor3 =
                COLORS.Sub,

            Font =
                Enum.Font.Code,

            TextSize =
                9,

            TextWrapped =
                true,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            TextYAlignment =
                Enum.TextYAlignment.Top,

            Parent =
                Left,
        }
    )

local ExportButton =
    newObject(
        "TextButton",
        {
            Position =
                UDim2.new(
                    0,
                    8,
                    1,
                    -88
                ),

            Size =
                UDim2.new(
                    1,
                    -16,
                    0,
                    36
                ),

            BackgroundColor3 =
                COLORS.BlueDark,

            BorderSizePixel =
                0,

            Text =
                "GERAR ARQUIVO",

            TextColor3 =
                COLORS.Text,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                9,

            Parent =
                Left,
        }
    )

addCorner(ExportButton, 8)

local CopyButton =
    newObject(
        "TextButton",
        {
            Position =
                UDim2.new(
                    0,
                    8,
                    1,
                    -46
                ),

            Size =
                UDim2.new(
                    1,
                    -16,
                    0,
                    34
                ),

            BackgroundColor3 =
                COLORS.Panel3,

            BorderSizePixel =
                0,

            Text =
                "COPIAR LEITURA",

            TextColor3 =
                COLORS.Text,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                9,

            Parent =
                Left,
        }
    )

addCorner(CopyButton, 8)

--==============================================================--
-- RIGHT VIEWER
--==============================================================--

local ViewerTitle =
    newObject(
        "TextLabel",
        {
            Position =
                UDim2.fromOffset(
                    11,
                    8
                ),

            Size =
                UDim2.new(
                    1,
                    -22,
                    0,
                    20
                ),

            BackgroundTransparency =
                1,

            Text =
                "RESULTADO",

            TextColor3 =
                COLORS.Text,

            Font =
                Enum.Font.GothamBold,

            TextSize =
                11,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            Parent =
                Right,
        }
    )

Viewer =
    newObject(
        "TextBox",
        {
            Position =
                UDim2.fromOffset(
                    8,
                    34
                ),

            Size =
                UDim2.new(
                    1,
                    -16,
                    1,
                    -42
                ),

            BackgroundColor3 =
                COLORS.Background,

            BorderSizePixel =
                0,

            Text =
                "Execute a leitura para visualizar os resultados.",

            TextColor3 =
                COLORS.Text,

            Font =
                Enum.Font.Code,

            TextSize =
                9,

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
                Right,
        }
    )

addCorner(Viewer, 8)

--==============================================================--
-- FLOATING MINIMIZED BUTTON
--==============================================================--

local FloatingButton =
    newObject(
        "TextButton",
        {
            Visible =
                false,

            Size =
                UDim2.fromOffset(
                    58,
                    58
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
                COLORS.BlueDark,

            BorderSizePixel =
                0,

            Text =
                "BOT",

            TextColor3 =
                COLORS.Text,

            Font =
                Enum.Font.GothamBlack,

            TextSize =
                12,

            AutoButtonColor =
                true,

            Parent =
                ScreenGui,
        }
    )

addCorner(
    FloatingButton,
    99
)

addStroke(
    FloatingButton
)

--==============================================================--
-- DRAGGING
--==============================================================--

local function makeFreeDraggable(object)

    local dragging =
        false

    local dragInput =
        nil

    local dragStart =
        nil

    local startPosition =
        nil

    object.InputBegan:Connect(
        function(input)

            if
                input.UserInputType
                == Enum.UserInputType.MouseButton1
                or
                input.UserInputType
                == Enum.UserInputType.Touch
            then

                dragging =
                    true

                dragStart =
                    input.Position

                startPosition =
                    object.Position

                dragInput =
                    input
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
                ~= Enum.UserInputType.MouseMovement
                and
                input.UserInputType
                ~= Enum.UserInputType.Touch
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
                - dragStart

            object.Position =
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
                == Enum.UserInputType.MouseButton1
                or
                input.UserInputType
                == Enum.UserInputType.Touch
            then

                dragging =
                    false

                dragInput =
                    nil
            end
        end
    )
end

makeFreeDraggable(
    FloatingButton
)

--==============================================================--
-- BUTTON EVENTS
--==============================================================--

ScanButton.Activated:Connect(
    function()

        if State.Scanning then

            State.Cancel =
                true

            return
        end

        task.spawn(
            performScan
        )
    end
)

CancelButton.Activated:Connect(
    function()

        if State.Scanning then

            State.Cancel =
                true

            StatusLabel.Text =
                "Cancelando..."

            StatusLabel.TextColor3 =
                COLORS.Yellow
        end
    end
)

ExportButton.Activated:Connect(
    function()

        exportReport()
    end
)

CopyButton.Activated:Connect(
    function()

        if not State.HasRead then

            StatusLabel.Text =
                "Nenhuma leitura disponível"

            StatusLabel.TextColor3 =
                COLORS.Yellow

            return
        end

        local report =
            generateReadableReport()

        if SetClipboard then

            local ok =
                pcall(
                    SetClipboard,
                    report
                )

            if ok then

                StatusLabel.Text =
                    "Leitura copiada"

                StatusLabel.TextColor3 =
                    COLORS.Green

                return
            end
        end

        StatusLabel.Text =
            "Clipboard indisponível"

        StatusLabel.TextColor3 =
            COLORS.Yellow
    end
)

--==============================================================--
-- MINIMIZE
--==============================================================--

MinimizeButton.Activated:Connect(
    function()

        Main.Visible =
            false

        FloatingButton.Visible =
            true
    end
)

FloatingButton.Activated:Connect(
    function()

        Main.Visible =
            true

        FloatingButton.Visible =
            false
    end
)

--==============================================================--
-- CLOSE
--==============================================================--

CloseButton.Activated:Connect(
    function()

        State.Cancel =
            true

        ScreenGui:Destroy()
    end
)

--==============================================================--
-- INITIALIZE
--==============================================================--

State.PatrolPoints =
    collectPatrolPoints()

SummaryText.Text =
    "Pronto.\n\n"
    .. "Patrol Points encontrados: "
    .. tostring(
        #State.PatrolPoints
    )
    .. "\n\n"
    .. "Pressione INICIAR LEITURA."

print(
    "[CAFEÍNA] Bot Research Scanner independente carregado."
)
