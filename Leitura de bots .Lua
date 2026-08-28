--==============================================================--
-- CAFEÍNA • BOT READING SCANNER
-- STANDALONE V1
--
-- OBJETIVO:
-- • Identificar bots ativos
-- • Diferenciar bots jogáveis de manequins
-- • Detectar Team
-- • Ler atributos dos bots
-- • Ler Humanoid
-- • Ler movimento
-- • Ler pontos de patrulha
-- • Relacionar bots aos pontos mais próximos
-- • Observar novos spawns
-- • Observar remoções
-- • Exportar leitura para JSON
--
-- NÃO DEPENDE DO MENU ANTIGO
--==============================================================--

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

if not LocalPlayer then
    LocalPlayer = Players.PlayerAdded:Wait()
end

--==============================================================--
-- CONFIG
--==============================================================--

local CONFIG = {
    GUI_NAME = "CafeinaBotReadingStandalone",

    BOT_FOLDER_NAME = "Soldiers",

    PATROL_FOLDER_NAME = "BotPatrolPoints",

    SAMPLE_INTERVAL = 0.75,

    MAX_MOVEMENT_SAMPLES = 20,

    MAX_BOTS = 500,

    MAX_PATROL_POINTS = 1000,

    EXPORT_FOLDER = "Cafeina",

    VERSION = "BOT-READING-V1",
}

--==============================================================--
-- STATE
--==============================================================--

local State = {
    Scanning = false,

    Monitoring = false,

    Minimized = false,

    StartedAt = os.time(),

    ScanCount = 0,

    LastScanAt = 0,

    Bots = {},

    SpawnHistory = {},

    RemovalHistory = {},

    PatrolPoints = {},

    TeamSummary = {
        Army = 0,
        Rebels = 0,
        Unknown = 0,
    },

    ClassificationSummary = {
        PlayableBot = 0,
        Mannequin = 0,
        Unknown = 0,
    },
}

--==============================================================--
-- SERVICES / REFERENCES
--==============================================================--

local Workspace = game:GetService("Workspace")

local BotFolder =
    Workspace:FindFirstChild(
        CONFIG.BOT_FOLDER_NAME
    )

local PatrolFolder =
    Workspace:FindFirstChild(
        CONFIG.PATROL_FOLDER_NAME
    )

--==============================================================--
-- HELPERS
--==============================================================--

local function safeCall(fn, fallback)
    local ok, result =
        pcall(fn)

    if ok then
        return result
    end

    return fallback
end

local function getFullName(instance)
    return safeCall(
        function()
            return instance:GetFullName()
        end,
        tostring(instance.Name)
    )
end

local function getAttribute(instance, name)
    return safeCall(
        function()
            return instance:GetAttribute(name)
        end,
        nil
    )
end

local function getAttributes(instance)
    return safeCall(
        function()
            return instance:GetAttributes()
        end,
        {}
    )
end

local function vectorToTable(v)
    if typeof(v) ~= "Vector3" then
        return nil
    end

    return {
        x = v.X,
        y = v.Y,
        z = v.Z,
    }
end

local function roundNumber(number)
    if type(number) ~= "number" then
        return number
    end

    return math.floor(
        number * 1000 + 0.5
    ) / 1000
end

local function distance(a, b)
    if not a or not b then
        return math.huge
    end

    return (
        a - b
    ).Magnitude
end

local function getRoot(model)
    return safeCall(
        function()
            return model:FindFirstChild(
                "HumanoidRootPart"
            )
        end,
        nil
    )
end

local function getHumanoid(model)
    return safeCall(
        function()
            return model:FindFirstChildOfClass(
                "Humanoid"
            )
        end,
        nil
    )
end

--==============================================================--
-- CLASSIFICATION
--==============================================================--

local function classifyBot(model)
    if not model
        or not model:IsA("Model")
    then
        return "Unknown"
    end

    local humanoid =
        getHumanoid(model)

    local root =
        getRoot(model)

    local team =
        getAttribute(
            model,
            "Team"
        )

    local health =
        getAttribute(
            model,
            "Health"
        )

    local speedMult =
        getAttribute(
            model,
            "SpeedMult"
        )

    local gun =
        getAttribute(
            model,
            "Gun"
        )

    local hasMovementStructure =
        humanoid ~= nil
        and root ~= nil

    local hasBotAttributes =
        team ~= nil
        or health ~= nil
        or speedMult ~= nil
        or gun ~= nil

    if
        hasMovementStructure
        and hasBotAttributes
    then
        return "PlayableBot"
    end

    if humanoid == nil then
        return "Mannequin"
    end

    return "Unknown"
end

--==============================================================--
-- PATROL POINT READING
--==============================================================--

local function readPatrolPoints()

    State.PatrolPoints = {}

    if not PatrolFolder then
        return
    end

    local descendants =
        safeCall(
            function()
                return PatrolFolder:GetDescendants()
            end,
            {}
        )

    local total = 0

    for _, object in ipairs(descendants) do

        if total >= CONFIG.MAX_PATROL_POINTS then
            break
        end

        if object:IsA("BasePart") then

            local folderTeam = nil

            if object.Parent then
                folderTeam =
                    tostring(
                        object.Parent.Name
                    )
            end

            local attributeTeam =
                getAttribute(
                    object,
                    "Team"
                )

            local position =
                safeCall(
                    function()
                        return object.Position
                    end,
                    nil
                )

            local point = {
                name =
                    tostring(object.Name),

                path =
                    getFullName(object),

                className =
                    tostring(object.ClassName),

                parent =
                    object.Parent
                    and getFullName(
                        object.Parent
                    )
                    or nil,

                folderTeam =
                    folderTeam,

                attributeTeam =
                    attributeTeam,

                position =
                    vectorToTable(
                        position
                    ),

                anchored =
                    safeCall(
                        function()
                            return object.Anchored
                        end,
                        nil
                    ),

                transparency =
                    safeCall(
                        function()
                            return object.Transparency
                        end,
                        nil
                    ),
            }

            State.PatrolPoints[
                #State.PatrolPoints + 1
            ] = point

            total += 1
        end
    end
end

--==============================================================--
-- FIND NEAREST PATROL POINT
--==============================================================--

local function findNearestPatrolPoint(
    position
)

    if not position then
        return nil
    end

    local closest = nil
    local closestDistance =
        math.huge

    for _, point
        in ipairs(State.PatrolPoints)
    do

        if point.position then

            local pointPosition =
                Vector3.new(
                    point.position.x,
                    point.position.y,
                    point.position.z
                )

            local currentDistance =
                distance(
                    position,
                    pointPosition
                )

            if currentDistance
                < closestDistance
            then
                closestDistance =
                    currentDistance

                closest = {
                    path =
                        point.path,

                    folderTeam =
                        point.folderTeam,

                    attributeTeam =
                        point.attributeTeam,

                    distance =
                        roundNumber(
                            currentDistance
                        ),
                }
            end
        end
    end

    return closest
end

--==============================================================--
-- MOVEMENT SNAPSHOT
--==============================================================--

local function readMovement(model)
    local humanoid =
        getHumanoid(model)

    local root =
        getRoot(model)

    if not humanoid
        or not root
    then
        return {
            available = false,
        }
    end

    local moveDirection =
        safeCall(
            function()
                return humanoid.MoveDirection
            end,
            Vector3.zero
        )

    local velocity =
        safeCall(
            function()
                return root.AssemblyLinearVelocity
            end,
            Vector3.zero
        )

    local state =
        safeCall(
            function()
                return humanoid:GetState()
            end,
            nil
        )

    local moving =
        moveDirection.Magnitude > 0.05
        or velocity.Magnitude > 1

    return {
        available = true,

        moving = moving,

        moveDirection =
            vectorToTable(
                moveDirection
            ),

        velocity =
            vectorToTable(
                velocity
            ),

        velocityMagnitude =
            roundNumber(
                velocity.Magnitude
            ),

        humanoidState =
            state
            and tostring(state)
            or nil,

        walkSpeed =
            safeCall(
                function()
                    return humanoid.WalkSpeed
                end,
                nil
            ),
    }
end

--==============================================================--
-- BOT RECORD
--==============================================================--

local function buildBotRecord(model)

    local humanoid =
        getHumanoid(model)

    local root =
        getRoot(model)

    local classification =
        classifyBot(model)

    local attributes =
        getAttributes(model)

    local team =
        getAttribute(
            model,
            "Team"
        )

    local position = nil

    if root then
        position =
            safeCall(
                function()
                    return root.Position
                end,
                nil
            )
    end

    local patrol =
        findNearestPatrolPoint(
            position
        )

    local movement =
        readMovement(model)

    local record = {

        name =
            tostring(model.Name),

        path =
            getFullName(model),

        className =
            tostring(model.ClassName),

        classification =
            classification,

        parent =
            model.Parent
            and getFullName(
                model.Parent
            )
            or nil,

        team =
            team,

        attributes =
            attributes,

        humanoid = {
            exists =
                humanoid ~= nil,

            health =
                humanoid
                and safeCall(
                    function()
                        return humanoid.Health
                    end,
                    nil
                )
                or nil,

            maxHealth =
                humanoid
                and safeCall(
                    function()
                        return humanoid.MaxHealth
                    end,
                    nil
                )
                or nil,

            walkSpeed =
                humanoid
                and safeCall(
                    function()
                        return humanoid.WalkSpeed
                    end,
                    nil
                )
                or nil,

            jumpPower =
                humanoid
                and safeCall(
                    function()
                        return humanoid.JumpPower
                    end,
                    nil
                )
                or nil,

            rigType =
                humanoid
                and safeCall(
                    function()
                        return tostring(
                            humanoid.RigType
                        )
                    end,
                    nil
                )
                or nil,
        },

        root = {
            exists =
                root ~= nil,

            position =
                vectorToTable(
                    position
                ),
        },

        movement =
            movement,

        nearestPatrolPoint =
            patrol,

        observedAt =
            os.time(),
    }

    return record
end

--==============================================================--
-- REGISTER BOT
--==============================================================--

local function registerBot(model)

    if not model
        or not model:IsA("Model")
    then
        return
    end

    if #State.SpawnHistory
        > CONFIG.MAX_BOTS
    then
        return
    end

    local record =
        buildBotRecord(model)

    local path =
        record.path

    State.Bots[path] = {
        model = model,

        record = record,

        firstSeen =
            os.time(),

        lastSeen =
            os.time(),

        samples = {},

        movementHistory = {},
    }

    State.SpawnHistory[
        #State.SpawnHistory + 1
    ] = {
        name =
            record.name,

        path =
            record.path,

        classification =
            record.classification,

        team =
            record.team,

        observedAt =
            os.time(),
    }
end

--==============================================================--
-- UPDATE BOT
--==============================================================--

local function updateBot(path, data)

    if not data
        or not data.model
    then
        return
    end

    local model =
        data.model

    if not model.Parent then
        return
    end

    local record =
        buildBotRecord(model)

    data.record =
        record

    data.lastSeen =
        os.time()

    local movement =
        record.movement

    data.movementHistory[
        #data.movementHistory + 1
    ] = {
        timestamp =
            os.time(),

        position =
            record.root.position,

        moving =
            movement.moving,

        direction =
            movement.moveDirection,

        velocity =
            movement.velocity,

        patrol =
            record.nearestPatrolPoint,
    }

    if #data.movementHistory
        > CONFIG.MAX_MOVEMENT_SAMPLES
    then
        table.remove(
            data.movementHistory,
            1
        )
    end
end

--==============================================================--
-- SCAN EXISTING BOTS
--==============================================================--

local function scanBots()

    State.Scanning = true

    State.Bots = {}

    State.SpawnHistory = {}

    State.RemovalHistory = {}

    State.TeamSummary = {
        Army = 0,
        Rebels = 0,
        Unknown = 0,
    }

    State.ClassificationSummary = {
        PlayableBot = 0,
        Mannequin = 0,
        Unknown = 0,
    }

    readPatrolPoints()

    BotFolder =
        Workspace:FindFirstChild(
            CONFIG.BOT_FOLDER_NAME
        )

    if not BotFolder then
        State.Scanning = false
        return
    end

    local children =
        BotFolder:GetChildren()

    local total = 0

    for _, object
        in ipairs(children)
    do

        if total >= CONFIG.MAX_BOTS then
            break
        end

        if object:IsA("Model") then

            registerBot(object)

            total += 1
        end
    end

    for _, data
        in pairs(State.Bots)
    do

        local team =
            data.record.team

        if team == "Army" then
            State.TeamSummary.Army += 1

        elseif team == "Rebels" then
            State.TeamSummary.Rebels += 1

        else
            State.TeamSummary.Unknown += 1
        end

        local classification =
            data.record.classification

        if classification
            == "PlayableBot"
        then
            State.ClassificationSummary.PlayableBot += 1

        elseif classification
            == "Mannequin"
        then
            State.ClassificationSummary.Mannequin += 1

        else
            State.ClassificationSummary.Unknown += 1
        end
    end

    State.ScanCount += 1
    State.LastScanAt = os.time()

    State.Scanning = false
end

--==============================================================--
-- BOT FOLDER EVENTS
--==============================================================--

local Connections = {}

local function disconnectAll()

    for _, connection
        in ipairs(Connections)
    do

        pcall(function()
            connection:Disconnect()
        end)

    end

    Connections = {}
end

local function startMonitoring()

    disconnectAll()

    BotFolder =
        Workspace:FindFirstChild(
            CONFIG.BOT_FOLDER_NAME
        )

    if not BotFolder then
        return
    end

    State.Monitoring = true

    Connections[
        #Connections + 1
    ] =
        BotFolder.ChildAdded:Connect(
            function(child)

                if not child:IsA("Model") then
                    return
                end

                task.wait(0.1)

                registerBot(child)

            end
        )

    Connections[
        #Connections + 1
    ] =
        BotFolder.ChildRemoved:Connect(
            function(child)

                if not child:IsA("Model") then
                    return
                end

                local path =
                    getFullName(child)

                local oldData =
                    State.Bots[path]

                if oldData then

                    State.RemovalHistory[
                        #State.RemovalHistory + 1
                    ] = {

                        name =
                            tostring(child.Name),

                        path =
                            path,

                        team =
                            oldData.record.team,

                        classification =
                            oldData.record.classification,

                        removedAt =
                            os.time(),
                    }

                    State.Bots[path] = nil
                end
            end
        )

    Connections[
        #Connections + 1
    ] =
        RunService.Heartbeat:Connect(
            function()

                if not State.Monitoring then
                    return
                end

                for path, data
                    in pairs(State.Bots)
                do

                    if
                        data.model
                        and data.model.Parent
                    then

                        updateBot(
                            path,
                            data
                        )
                    end
                end
            end
        )
end

--==============================================================--
-- EXPORT DATA
--==============================================================--

local function buildExport()

    local bots = {}

    for path, data
        in pairs(State.Bots)
    do

        local copy = {
            record =
                data.record,

            firstSeen =
                data.firstSeen,

            lastSeen =
                data.lastSeen,

            movementHistory =
                data.movementHistory,
        }

        bots[path] = copy
    end

    return {

        scanner = {
            name =
                "CAFEINA BOT READING",

            version =
                CONFIG.VERSION,

            generatedAt =
                os.time(),

            generatedDate =
                os.date(
                    "!%Y-%m-%dT%H:%M:%SZ"
                ),
        },

        game = {
            placeId =
                game.PlaceId,

            gameId =
                game.GameId,

            jobId =
                game.JobId,

            placeVersion =
                game.PlaceVersion,
        },

        structure = {
            botFolder =
                BotFolder
                and getFullName(
                    BotFolder
                )
                or nil,

            patrolFolder =
                PatrolFolder
                and getFullName(
                    PatrolFolder
                )
                or nil,
        },

        summary = {
            scanCount =
                State.ScanCount,

            botCount =
                #State.SpawnHistory,

            activeBots =
                State.ClassificationSummary.PlayableBot,

            mannequins =
                State.ClassificationSummary.Mannequin,

            unknown =
                State.ClassificationSummary.Unknown,

            army =
                State.TeamSummary.Army,

            rebels =
                State.TeamSummary.Rebels,

            unknownTeam =
                State.TeamSummary.Unknown,
        },

        patrolPoints =
            State.PatrolPoints,

        spawnHistory =
            State.SpawnHistory,

        removalHistory =
            State.RemovalHistory,

        bots =
            bots,
    }
end

local function encodeExport()

    local data =
        buildExport()

    local ok, result =
        pcall(function()
            return HttpService:JSONEncode(
                data
            )
        end)

    if not ok then
        return nil,
            tostring(result)
    end

    return result
end

--==============================================================--
-- FILE EXPORT
--==============================================================--

local function exportFile()

    local json, errorMessage =
        encodeExport()

    if not json then
        return false,
            errorMessage
    end

    local timestamp =
        os.date(
            "%Y%m%d_%H%M%S"
        )

    local filename =
        "Cafeina_BotReading_"
        .. tostring(
            game.PlaceId
        )
        .. "_"
        .. timestamp
        .. ".json"

    local writeFile =
        typeof(writefile)
        == "function"
        and writefile
        or nil

    if writeFile then

        local ok, err =
            pcall(
                function()
                    writeFile(
                        filename,
                        json
                    )
                end
            )

        if ok then
            return true,
                filename
        end

        return false,
            tostring(err)
    end

    return false,
        "writefile indisponível"
end

--==============================================================--
-- CLIPBOARD FALLBACK
--==============================================================--

local function copyExport()

    local json, errorMessage =
        encodeExport()

    if not json then
        return false,
            errorMessage
    end

    local clipboard =
        typeof(setclipboard)
        == "function"
        and setclipboard
        or nil

    if not clipboard then
        clipboard =
            typeof(toclipboard)
            == "function"
            and toclipboard
            or nil
    end

    if not clipboard then
        return false,
            "Clipboard indisponível"
    end

    local ok, err =
        pcall(
            clipboard,
            json
        )

    if ok then
        return true
    end

    return false,
        tostring(err)
end

--==============================================================--
-- GUI
--==============================================================--

local oldGui =
    LocalPlayer
    :WaitForChild("PlayerGui")
    :FindFirstChild(
        CONFIG.GUI_NAME
    )

if oldGui then
    oldGui:Destroy()
end

local Gui =
    Instance.new("ScreenGui")

Gui.Name =
    CONFIG.GUI_NAME

Gui.ResetOnSpawn =
    false

Gui.IgnoreGuiInset =
    true

Gui.Parent =
    LocalPlayer:WaitForChild(
        "PlayerGui"
    )

--==============================================================--
-- COLORS
--==============================================================--

local COLORS = {

    Background =
        Color3.fromRGB(
            12,
            12,
            15
        ),

    Panel =
        Color3.fromRGB(
            20,
            20,
            24
        ),

    Panel2 =
        Color3.fromRGB(
            29,
            29,
            35
        ),

    Red =
        Color3.fromRGB(
            225,
            38,
            52
        ),

    RedDark =
        Color3.fromRGB(
            110,
            20,
            30
        ),

    Green =
        Color3.fromRGB(
            65,
            210,
            118
        ),

    Yellow =
        Color3.fromRGB(
            242,
            184,
            57
        ),

    Text =
        Color3.fromRGB(
            245,
            245,
            248
        ),

    Sub =
        Color3.fromRGB(
            160,
            160,
            172
        ),
}

--==============================================================--
-- MAIN FRAME
--==============================================================--

local Main =
    Instance.new("Frame")

Main.Size =
    UDim2.fromOffset(
        430,
        430
    )

Main.Position =
    UDim2.fromScale(
        0.5,
        0.5
    )

Main.AnchorPoint =
    Vector2.new(
        0.5,
        0.5
    )

Main.BackgroundColor3 =
    COLORS.Background

Main.BorderSizePixel =
    0

Main.Parent =
    Gui

local corner =
    Instance.new("UICorner")

corner.CornerRadius =
    UDim.new(
        0,
        14
    )

corner.Parent =
    Main

--==============================================================--
-- HEADER
--==============================================================--

local Header =
    Instance.new("Frame")

Header.Size =
    UDim2.new(
        1,
        0,
        0,
        55
    )

Header.BackgroundColor3 =
    COLORS.Panel

Header.BorderSizePixel =
    0

Header.Parent =
    Main

local HeaderCorner =
    Instance.new("UICorner")

HeaderCorner.CornerRadius =
    UDim.new(
        0,
        14
    )

HeaderCorner.Parent =
    Header

local Title =
    Instance.new("TextLabel")

Title.BackgroundTransparency =
    1

Title.Position =
    UDim2.fromOffset(
        14,
        7
    )

Title.Size =
    UDim2.new(
        1,
        -100,
        0,
        23
    )

Title.Text =
    "CAFEÍNA • LEITURA DE BOTS"

Title.TextColor3 =
    COLORS.Text

Title.Font =
    Enum.Font.GothamBold

Title.TextSize =
    15

Title.TextXAlignment =
    Enum.TextXAlignment.Left

Title.Parent =
    Header

local Subtitle =
    Instance.new("TextLabel")

Subtitle.BackgroundTransparency =
    1

Subtitle.Position =
    UDim2.fromOffset(
        14,
        30
    )

Subtitle.Size =
    UDim2.new(
        1,
        -100,
        0,
        16
    )

Subtitle.Text =
    "BOT READING • STANDALONE"

Subtitle.TextColor3 =
    COLORS.Sub

Subtitle.Font =
    Enum.Font.Gotham

Subtitle.TextSize =
    9

Subtitle.TextXAlignment =
    Enum.TextXAlignment.Left

Subtitle.Parent =
    Header

--==============================================================--
-- MINIMIZE
--==============================================================--

local Minimize =
    Instance.new("TextButton")

Minimize.Size =
    UDim2.fromOffset(
        30,
        30
    )

Minimize.Position =
    UDim2.new(
        1,
        -75,
        0,
        11
    )

Minimize.BackgroundColor3 =
    COLORS.Panel2

Minimize.BorderSizePixel =
    0

Minimize.Text =
    "—"

Minimize.TextColor3 =
    COLORS.Text

Minimize.Font =
    Enum.Font.GothamBold

Minimize.TextSize =
    17

Minimize.Parent =
    Header

local MinCorner =
    Instance.new("UICorner")

MinCorner.CornerRadius =
    UDim.new(
        0,
        8
    )

MinCorner.Parent =
    Minimize

--==============================================================--
-- CLOSE
--==============================================================--

local Close =
    Instance.new("TextButton")

Close.Size =
    UDim2.fromOffset(
        30,
        30
    )

Close.Position =
    UDim2.new(
        1,
        -40,
        0,
        11
    )

Close.BackgroundColor3 =
    COLORS.RedDark

Close.BorderSizePixel =
    0

Close.Text =
    "×"

Close.TextColor3 =
    COLORS.Text

Close.Font =
    Enum.Font.GothamBold

Close.TextSize =
    18

Close.Parent =
    Header

local CloseCorner =
    Instance.new("UICorner")

CloseCorner.CornerRadius =
    UDim.new(
        0,
        8
    )

CloseCorner.Parent =
    Close

--==============================================================--
-- STATUS
--==============================================================--

local Status =
    Instance.new("TextLabel")

Status.BackgroundColor3 =
    COLORS.Panel

Status.BorderSizePixel =
    0

Status.Position =
    UDim2.fromOffset(
        10,
        65
    )

Status.Size =
    UDim2.new(
        1,
        -20,
        0,
        45
    )

Status.Text =
    "Pronto para leitura"

Status.TextColor3 =
    COLORS.Green

Status.Font =
    Enum.Font.GothamBold

Status.TextSize =
    11

Status.Parent =
    Main

local StatusCorner =
    Instance.new("UICorner")

StatusCorner.CornerRadius =
    UDim.new(
        0,
        9
    )

StatusCorner.Parent =
    Status

--==============================================================--
-- SUMMARY
--==============================================================--

local Summary =
    Instance.new("TextLabel")

Summary.BackgroundColor3 =
    COLORS.Panel

Summary.BorderSizePixel =
    0

Summary.Position =
    UDim2.fromOffset(
        10,
        120
    )

Summary.Size =
    UDim2.new(
        1,
        -20,
        0,
        115
    )

Summary.Text =
    "Nenhuma leitura realizada."

Summary.TextColor3 =
    COLORS.Text

Summary.Font =
    Enum.Font.Code

Summary.TextSize =
    11

Summary.TextWrapped =
    true

Summary.TextXAlignment =
    Enum.TextXAlignment.Left

Summary.TextYAlignment =
    Enum.TextYAlignment.Top

Summary.Parent =
    Main

local SummaryCorner =
    Instance.new("UICorner")

SummaryCorner.CornerRadius =
    UDim.new(
        0,
        9
    )

SummaryCorner.Parent =
    Summary

--==============================================================--
-- BUTTON CREATOR
--==============================================================--

local function createButton(
    text,
    position,
    size,
    color
)

    local button =
        Instance.new("TextButton")

    button.Position =
        position

    button.Size =
        size

    button.BackgroundColor3 =
        color

    button.BorderSizePixel =
        0

    button.Text =
        text

    button.TextColor3 =
        COLORS.Text

    button.Font =
        Enum.Font.GothamBold

    button.TextSize =
        10

    button.Parent =
        Main

    local c =
        Instance.new("UICorner")

    c.CornerRadius =
        UDim.new(
            0,
            8
        )

    c.Parent =
        button

    return button
end

--==============================================================--
-- BUTTONS
--==============================================================--

local ScanButton =
    createButton(
        "LER BOTS",
        UDim2.fromOffset(
            10,
            245
        ),
        UDim2.new(
            0.48,
            -5,
            0,
            40
        ),
        COLORS.Red
    )

local MonitorButton =
    createButton(
        "MONITORAR SPAWN",
        UDim2.new(
            0.52,
            5,
            0,
            245
        ),
        UDim2.new(
            0.48,
            -15,
            0,
            40
        ),
        COLORS.Panel2
    )

local ExportButton =
    createButton(
        "BAIXAR ARQUIVO DE LEITURA",
        UDim2.fromOffset(
            10,
            295
        ),
        UDim2.new(
            1,
            -20,
            0,
            42
        ),
        COLORS.RedDark
    )

local CopyButton =
    createButton(
        "COPIAR JSON",
        UDim2.fromOffset(
            10,
            347
        ),
        UDim2.new(
            1,
            -20,
            0,
            35
        ),
        COLORS.Panel2
    )

--==============================================================--
-- MINI BUTTON
--==============================================================--

local Mini =
    Instance.new("TextButton")

Mini.Size =
    UDim2.fromOffset(
        55,
        55
    )

Mini.Position =
    UDim2.fromScale(
        0.5,
        0.5
    )

Mini.AnchorPoint =
    Vector2.new(
        0.5,
        0.5
    )

Mini.BackgroundColor3 =
    COLORS.Red

Mini.BorderSizePixel =
    0

Mini.Text =
    "C"

Mini.TextColor3 =
    COLORS.Text

Mini.Font =
    Enum.Font.GothamBlack

Mini.TextSize =
    20

Mini.Visible =
    false

Mini.Parent =
    Gui

local MiniCorner =
    Instance.new("UICorner")

MiniCorner.CornerRadius =
    UDim.new(
        1,
        0
    )

MiniCorner.Parent =
    Mini

--==============================================================--
-- UPDATE SUMMARY
--==============================================================--

local function updateSummary()

    local total =
        0

    for _ in pairs(State.Bots) do
        total += 1
    end

    local patrolCount =
        #State.PatrolPoints

    Summary.Text =
        "BOTS ATIVOS: "
        .. tostring(total)
        .. "\n\n"

        .. "ARMY: "
        .. tostring(
            State.TeamSummary.Army
        )
        .. "\n"

        .. "REBELS: "
        .. tostring(
            State.TeamSummary.Rebels
        )
        .. "\n"

        .. "TEAM INDEFINIDO: "
        .. tostring(
            State.TeamSummary.Unknown
        )
        .. "\n\n"

        .. "JOGÁVEIS: "
        .. tostring(
            State.ClassificationSummary.PlayableBot
        )
        .. "\n"

        .. "MANEQUINS: "
        .. tostring(
            State.ClassificationSummary.Mannequin
        )
        .. "\n"

        .. "PATROL POINTS: "
        .. tostring(patrolCount)
end

--==============================================================--
-- SCAN BUTTON
--==============================================================--

ScanButton.Activated:Connect(
    function()

        if State.Scanning then
            return
        end

        Status.Text =
            "Lendo estrutura dos bots..."

        Status.TextColor3 =
            COLORS.Yellow

        task.spawn(
            function()

                local ok, err =
                    pcall(
                        scanBots
                    )

                if not ok then

                    Status.Text =
                        "Erro: "
                        .. tostring(err)

                    Status.TextColor3 =
                        COLORS.Red

                    return
                end

                updateSummary()

                Status.Text =
                    "Leitura concluída"

                Status.TextColor3 =
                    COLORS.Green
            end
        )
    end
)

--==============================================================--
-- MONITOR BUTTON
--==============================================================--

MonitorButton.Activated:Connect(
    function()

        if State.Monitoring then

            State.Monitoring =
                false

            disconnectAll()

            MonitorButton.Text =
                "MONITORAR SPAWN"

            MonitorButton.BackgroundColor3 =
                COLORS.Panel2

            Status.Text =
                "Monitoramento parado"

            Status.TextColor3 =
                COLORS.Yellow

            return
        end

        if not BotFolder then
            BotFolder =
                Workspace:FindFirstChild(
                    CONFIG.BOT_FOLDER_NAME
                )
        end

        if not BotFolder then

            Status.Text =
                "Workspace.Soldiers não encontrado"

            Status.TextColor3 =
                COLORS.Red

            return
        end

        startMonitoring()

        MonitorButton.Text =
            "MONITORAMENTO ATIVO"

        MonitorButton.BackgroundColor3 =
            COLORS.RedDark

        Status.Text =
            "Observando novos bots..."

        Status.TextColor3 =
            COLORS.Green
    end
)

--==============================================================--
-- EXPORT BUTTON
--==============================================================--

ExportButton.Activated:Connect(
    function()

        Status.Text =
            "Gerando arquivo JSON..."

        Status.TextColor3 =
            COLORS.Yellow

        task.spawn(
            function()

                local ok, result =
                    exportFile()

                if ok then

                    Status.Text =
                        "Arquivo criado: "
                        .. tostring(result)

                    Status.TextColor3 =
                        COLORS.Green

                else

                    Status.Text =
                        "Arquivo não criado • "
                        .. tostring(result)

                    Status.TextColor3 =
                        COLORS.Yellow
                end
            end
        )
    end
)

--==============================================================--
-- COPY BUTTON
--==============================================================--

CopyButton.Activated:Connect(
    function()

        local ok, result =
            copyExport()

        if ok then

            Status.Text =
                "JSON copiado para o clipboard"

            Status.TextColor3 =
                COLORS.Green

        else

            Status.Text =
                tostring(result)

            Status.TextColor3 =
                COLORS.Yellow
        end
    end
)

--==============================================================--
-- MINIMIZE
--==============================================================--

Minimize.Activated:Connect(
    function()

        Main.Visible =
            false

        Mini.Visible =
            true

        State.Minimized =
            true
    end
)

Mini.Activated:Connect(
    function()

        Mini.Visible =
            false

        Main.Visible =
            true

        State.Minimized =
            false
    end
)

--==============================================================--
-- CLOSE
--==============================================================--

Close.Activated:Connect(
    function()

        State.Monitoring =
            false

        disconnectAll()

        Gui:Destroy()
    end
)

--==============================================================--
-- INITIALIZATION
--==============================================================--

readPatrolPoints()

updateSummary()

Status.Text =
    "Standalone carregado • pronto"

Status.TextColor3 =
    COLORS.Green

print(
    "[CAFEINA] Bot Reading Standalone carregado."
)
