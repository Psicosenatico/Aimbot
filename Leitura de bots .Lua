-- ============================================================
-- CAFEÍNA • LEITURA DE BOTS V3
-- ============================================================
-- Pesquisa somente de bots / entidades Soldier.
--
-- V3:
-- • Mantém as funções principais da V2
-- • Identificador visual V3
-- • Análise de atribuição de Team
-- • Histórico de Team
-- • Verificação complementar de Highlight
-- • Eventos de criação/remoção
-- • Correlação temporal Players x Soldiers
-- • Spawn / estado inicial / remoção
-- • Exportação JSON
-- • Mensagem de sucesso na exportação
--
-- SOMENTE LEITURA.
-- ============================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- ============================================================
-- PARENT
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
    if v.Name == "CafeinaBotReader_V3" then
        pcall(function()
            v:Destroy()
        end)
    end
end

-- ============================================================
-- GUI
-- ============================================================

local Gui = Instance.new("ScreenGui")
Gui.Name = "CafeinaBotReader_V3"
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

-- ============================================================
-- HELPERS
-- ============================================================

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

local function safeFullName(x)
    local ok, v = pcall(function()
        return x:GetFullName()
    end)

    return ok and tostring(v) or tostring(x.Name)
end

local function getAttribute(x, key)
    local ok, v = pcall(function()
        return x:GetAttribute(key)
    end)

    return ok and v or nil
end

local function getRoot(model)
    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")
end

local function getHumanoid(model)
    return model:FindFirstChildOfClass("Humanoid")
end

local function isPlayerCharacter(model)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character == model then
            return true
        end
    end

    return false
end

-- ============================================================
-- ESTADO
-- ============================================================

local State = {
    Records = {},

    Army = {},
    Rebels = {},

    Mannequins = {},
    Playable = {},

    PatrolPoints = {},

    SoldierEvents = {},
    PlayerEvents = {},

    TeamChanges = {},

    ScanStartedUnix = nil,
    ScanFinishedUnix = nil,

    Scanned = false,
}

-- ============================================================
-- PLAYER SNAPSHOT
-- ============================================================

local function getPlayerTeam(player)
    local teamName = nil

    pcall(function()
        if player.Team then
            teamName = player.Team.Name
        end
    end)

    if not teamName then
        local attr = getAttribute(player, "Team")

        if attr ~= nil then
            teamName = tostring(attr)
        end
    end

    return teamName
end

local function getPlayerSnapshot()
    local result = {}

    for _, player in ipairs(Players:GetPlayers()) do
        result[#result + 1] = {
            name = player.Name,
            displayName = player.DisplayName,
            userId = player.UserId,
            team = getPlayerTeam(player),
            hasCharacter = player.Character ~= nil,
        }
    end

    return result
end

-- ============================================================
-- TEAM
-- ============================================================

local function readTeamSources(model)
    local sources = {}
    local values = {}

    -- Attribute Team
    local attrTeam = getAttribute(model, "Team")

    if attrTeam ~= nil then
        sources[#sources + 1] = "Attribute.Team"
        values["Attribute.Team"] = tostring(attrTeam)
    end

    -- Attribute TeamName
    local attrTeamName = getAttribute(model, "TeamName")

    if attrTeamName ~= nil then
        sources[#sources + 1] = "Attribute.TeamName"
        values["Attribute.TeamName"] = tostring(attrTeamName)
    end

    -- Attribute Faction
    local attrFaction = getAttribute(model, "Faction")

    if attrFaction ~= nil then
        sources[#sources + 1] = "Attribute.Faction"
        values["Attribute.Faction"] = tostring(attrFaction)
    end

    -- Child Team
    local teamObject = model:FindFirstChild("Team")

    if teamObject then
        if teamObject:IsA("StringValue") then
            sources[#sources + 1] = "StringValue.Team"
            values["StringValue.Team"] = tostring(teamObject.Value)

        elseif teamObject:IsA("ObjectValue") then
            sources[#sources + 1] = "ObjectValue.Team"

            pcall(function()
                values["ObjectValue.Team"] =
                    teamObject.Value and teamObject.Value.Name or "nil"
            end)

        elseif teamObject:IsA("IntValue")
            or teamObject:IsA("NumberValue") then

            sources[#sources + 1] = "Value.Team"
            values["Value.Team"] = tostring(teamObject.Value)
        end
    end

    -- Child TeamName
    local teamNameObject = model:FindFirstChild("TeamName")

    if teamNameObject and teamNameObject:IsA("StringValue") then
        sources[#sources + 1] = "StringValue.TeamName"
        values["StringValue.TeamName"] =
            tostring(teamNameObject.Value)
    end

    -- Child Faction
    local factionObject = model:FindFirstChild("Faction")

    if factionObject and factionObject:IsA("StringValue") then
        sources[#sources + 1] = "StringValue.Faction"
        values["StringValue.Faction"] =
            tostring(factionObject.Value)
    end

    -- Escolha da fonte principal.
    local primary = nil
    local primarySource = nil

    local priority = {
        "Attribute.Team",
        "StringValue.Team",
        "ObjectValue.Team",
        "Value.Team",
        "Attribute.TeamName",
        "StringValue.TeamName",
        "Attribute.Faction",
        "StringValue.Faction",
    }

    for _, source in ipairs(priority) do
        if values[source] ~= nil then
            primary = values[source]
            primarySource = source
            break
        end
    end

    return {
        team = primary,
        source = primarySource,
        sources = sources,
        values = values,
    }
end

-- ============================================================
-- HIGHLIGHT
-- ============================================================

local function inspectHighlight(model)
    local result = {
        exists = false,
        enabled = nil,
        depthMode = nil,
        fillColor = nil,
        outlineColor = nil,
        path = nil,
    }

    local highlight = model:FindFirstChildWhichIsA(
        "Highlight",
        true
    )

    if not highlight then
        return result
    end

    result.exists = true
    result.path = safeFullName(highlight)

    pcall(function()
        result.enabled = highlight.Enabled
    end)

    pcall(function()
        result.depthMode = tostring(highlight.DepthMode)
    end)

    pcall(function()
        result.fillColor = {
            r = highlight.FillColor.R,
            g = highlight.FillColor.G,
            b = highlight.FillColor.B,
        }
    end)

    pcall(function()
        result.outlineColor = {
            r = highlight.OutlineColor.R,
            g = highlight.OutlineColor.G,
            b = highlight.OutlineColor.B,
        }
    end)

    return result
end

-- ============================================================
-- MODELO
-- ============================================================

local function inspectModel(model)
    if not model:IsA("Model") then
        return nil
    end

    if isPlayerCharacter(model) then
        return nil
    end

    local humanoid = getHumanoid(model)

    if not humanoid then
        return nil
    end

    local root = getRoot(model)

    local teamInfo = readTeamSources(model)
    local highlightInfo = inspectHighlight(model)

    local signals = {}

    if root then
        signals[#signals + 1] = "RootPart"
    end

    signals[#signals + 1] = "Humanoid"

    if humanoid.Health > 0 then
        signals[#signals + 1] = "Health>0"
    end

    if humanoid.WalkSpeed > 0 then
        signals[#signals + 1] = "WalkSpeed"
    end

    if humanoid.MoveDirection.Magnitude > 0 then
        signals[#signals + 1] = "MoveDirection"
    end

    if model:FindFirstChildWhichIsA("Tool", true) then
        signals[#signals + 1] = "Tool"
    end

    if highlightInfo.exists then
        signals[#signals + 1] = "Highlight"
    end

    if teamInfo.team then
        signals[#signals + 1] = "Team"
    end

    local likelyMannequin =
        model.Name:lower():find("dummy", 1, true) ~= nil
        or model.Name:lower():find("mannequin", 1, true) ~= nil
        or model.Name:lower():find("manequim", 1, true) ~= nil

    local likelyPlayable =
        not likelyMannequin
        and root ~= nil

    local rec = {
        name = model.Name,
        path = safeFullName(model),
        className = model.ClassName,

        team = teamInfo.team,
        teamSource = teamInfo.source,
        teamSources = teamInfo.sources,
        teamValues = teamInfo.values,

        health = humanoid.Health,
        maxHealth = humanoid.MaxHealth,

        walkSpeed = humanoid.WalkSpeed,
        jumpPower = humanoid.JumpPower,

        rigType = tostring(humanoid.RigType),

        rootPart = root and root.Name or nil,

        position = root and {
            x = root.Position.X,
            y = root.Position.Y,
            z = root.Position.Z
        } or nil,

        moveDirection = {
            x = humanoid.MoveDirection.X,
            y = humanoid.MoveDirection.Y,
            z = humanoid.MoveDirection.Z
        },

        highlight = highlightInfo,

        attributes = {},
        signals = signals,

        likelyMannequin = likelyMannequin,
        likelyPlayable = likelyPlayable,

        firstSeenUnix = os.time(),
        lastSeenUnix = os.time(),

        teamHistory = {},
    }

    -- Attributes completos
    pcall(function()
        for k, v in pairs(model:GetAttributes()) do
            rec.attributes[tostring(k)] = tostring(v)
        end
    end)

    rec.teamHistory[#rec.teamHistory + 1] = {
        time = os.clock(),
        unix = os.time(),
        team = teamInfo.team,
        source = teamInfo.source,
    }

    return rec
end

-- ============================================================
-- PATROL POINTS
-- ============================================================

local function scanPatrolPoints()
    State.PatrolPoints = {}

    local folder = workspace:FindFirstChild("BotPatrolPoints")

    if not folder then
        return
    end

    for _, teamFolder in ipairs(folder:GetChildren()) do

        if teamFolder:IsA("Folder") then

            local list = {}

            for _, p in ipairs(teamFolder:GetDescendants()) do

                if p:IsA("BasePart") then

                    list[#list + 1] = {
                        name = p.Name,
                        path = safeFullName(p),

                        teamAttribute =
                            getAttribute(p, "Team"),

                        position = {
                            x = p.Position.X,
                            y = p.Position.Y,
                            z = p.Position.Z
                        },

                        anchored = p.Anchored,
                        transparency = p.Transparency,
                    }

                end
            end

            State.PatrolPoints[teamFolder.Name] = list
        end
    end
end

-- ============================================================
-- SOLDIER EVENTS
-- ============================================================

local function recordSoldierEvent(action, object)
    State.SoldierEvents[#State.SoldierEvents + 1] = {
        action = action,
        time = os.clock(),
        unix = os.time(),

        name = object.Name,
        className = object.ClassName,
        path = safeFullName(object),

        playerCount = #Players:GetPlayers(),
    }
end

local function recordPlayerEvent(action, player)
    State.PlayerEvents[#State.PlayerEvents + 1] = {
        action = action,
        time = os.clock(),
        unix = os.time(),

        name = player.Name,
        userId = player.UserId,

        team = getPlayerTeam(player),

        playerCount = #Players:GetPlayers(),
    }
end

-- ============================================================
-- SCAN
-- ============================================================

local function scanBots()

    State.Records = {}
    State.Army = {}
    State.Rebels = {}
    State.Mannequins = {}
    State.Playable = {}

    State.SoldierEvents = {}
    State.PlayerEvents = {}
    State.TeamChanges = {}

    State.ScanStartedUnix = os.time()

    scanPatrolPoints()

    -- Snapshot dos jogadores no início
    local initialPlayers = getPlayerSnapshot()

    -- Procura apenas modelos relevantes
    for _, inst in ipairs(workspace:GetDescendants()) do

        local rec = inspectModel(inst)

        if rec then

            State.Records[#State.Records + 1] = rec

            if rec.team == "Army" then
                State.Army[#State.Army + 1] = rec

            elseif rec.team == "Rebels" then
                State.Rebels[#State.Rebels + 1] = rec
            end

            if rec.likelyMannequin then
                State.Mannequins[#State.Mannequins + 1] = rec

            elseif rec.likelyPlayable then
                State.Playable[#State.Playable + 1] = rec
            end
        end
    end

    State.ScanFinishedUnix = os.time()
    State.Scanned = true

    return initialPlayers
end

-- ============================================================
-- EXPORTAÇÃO
-- ============================================================

local function buildExport()

    return {
        format = "Cafeina Bot Research",
        version = "V3",

        generatedAtUnix = os.time(),

        game = {
            placeId = game.PlaceId,
            gameId = game.GameId,
            jobId = game.JobId,
        },

        localPlayer = {
            name = LocalPlayer.Name,
            userId = LocalPlayer.UserId,
            team = getPlayerTeam(LocalPlayer),
        },

        scan = {
            startedUnix = State.ScanStartedUnix,
            finishedUnix = State.ScanFinishedUnix,

            duration =
                State.ScanFinishedUnix
                and State.ScanStartedUnix
                and (
                    State.ScanFinishedUnix
                    - State.ScanStartedUnix
                )
                or nil,

            note =
                "Dados observados pelo cliente. "
                .."Team e Highlight são registrados como "
                .."evidências independentes.",
        },

        detection = {

            bots = #State.Records,

            army = #State.Army,

            rebels = #State.Rebels,

            mannequins =
                #State.Mannequins,

            likelyPlayable =
                #State.Playable,

            soldierEvents =
                #State.SoldierEvents,

            playerEvents =
                #State.PlayerEvents,
        },

        players = getPlayerSnapshot(),

        bots = State.Records,

        teamAnalysis = {

            note =
                "Prioridade: Team observado diretamente. "
                .."Highlight funciona como confirmação complementar.",

            army = State.Army,

            rebels = State.Rebels,
        },

        events = {

            soldiers =
                State.SoldierEvents,

            players =
                State.PlayerEvents,

            teamChanges =
                State.TeamChanges,
        },

        patrolPoints =
            State.PatrolPoints,
    }
end

local function jsonExport()

    local ok, result = pcall(function()
        return HttpService:JSONEncode(
            buildExport()
        )
    end)

    if ok then
        return result
    end

    return nil
end

-- ============================================================
-- INTERFACE
-- ============================================================

local Main = new("Frame", {
    Parent = Gui,

    Size = UDim2.fromOffset(
        520,
        430
    ),

    Position =
        UDim2.new(
            .5,
            -260,
            .5,
            -215
        ),

    BackgroundColor3 =
        COLORS.bg,

    BorderSizePixel = 0
})

round(Main, 14)

-- ============================================================
-- HEADER
-- ============================================================

local Header = new("Frame", {
    Parent = Main,

    Size =
        UDim2.new(
            1,
            0,
            0,
            55
        ),

    BackgroundColor3 =
        COLORS.panel,

    BorderSizePixel = 0
})

round(Header, 14)

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
        "INTERFACE STANDALONE • SOMENTE LEITURA",
        UDim2.new(1,-95,0,16),
        UDim2.fromOffset(14,31),
        9
    )

sub.TextColor3 = COLORS.sub

-- ============================================================
-- V3
-- ============================================================

local Version = new("TextLabel", {
    Parent = Main,

    BackgroundTransparency = 1,

    Size =
        UDim2.fromOffset(
            30,
            18
        ),

    Position =
        UDim2.new(
            1,
            -40,
            1,
            -23
        ),

    Text = "V3",

    TextColor3 =
        COLORS.sub,

    Font =
        Enum.Font.GothamBold,

    TextSize = 10,

    TextXAlignment =
        Enum.TextXAlignment.Right,

    TextYAlignment =
        Enum.TextYAlignment.Center
})

-- ============================================================
-- BOTÕES HEADER
-- ============================================================

local Min = new("TextButton", {
    Parent = Header,

    Size =
        UDim2.fromOffset(
            30,
            30
        ),

    Position =
        UDim2.new(
            1,
            -76,
            0,
            11
        ),

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

round(Min, 8)

local Close = new("TextButton", {
    Parent = Header,

    Size =
        UDim2.fromOffset(
            30,
            30
        ),

    Position =
        UDim2.new(
            1,
            -40,
            0,
            11
        ),

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

round(Close, 8)

-- ============================================================
-- STATUS
-- ============================================================

local Status =
    label(
        Main,
        "Pronto para realizar a leitura.",
        UDim2.new(1,-28,0,28),
        UDim2.fromOffset(14,66),
        11
    )

Status.TextColor3 = COLORS.sub

-- ============================================================
-- SCAN
-- ============================================================

local Scan = new("TextButton", {
    Parent = Main,

    Size =
        UDim2.new(
            .5,
            -20,
            0,
            42
        ),

    Position =
        UDim2.fromOffset(
            14,
            98
        ),

    Text =
        "REALIZAR LEITURA DE BOTS",

    BackgroundColor3 =
        COLORS.blue2,

    TextColor3 =
        COLORS.text,

    Font =
        Enum.Font.GothamBold,

    TextSize = 10,

    BorderSizePixel = 0
})

round(Scan, 8)

-- ============================================================
-- EXPORT
-- ============================================================

local Export = new("TextButton", {
    Parent = Main,

    Size =
        UDim2.new(
            .5,
            -20,
            0,
            42
        ),

    Position =
        UDim2.new(
            .5,
            6,
            0,
            98
        ),

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

round(Export, 8)

-- ============================================================
-- SUMMARY
-- ============================================================

local Summary =
    label(
        Main,
        "Nenhuma leitura realizada.",
        UDim2.new(1,-28,0,52),
        UDim2.fromOffset(14,150),
        10
    )

Summary.TextWrapped = true
Summary.TextColor3 = COLORS.text

-- ============================================================
-- VIEWER
-- ============================================================

local Viewer = new("TextBox", {
    Parent = Main,

    Size =
        UDim2.new(
            1,
            -28,
            1,
            -222
        ),

    Position =
        UDim2.fromOffset(
            14,
            204
        ),

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

round(Viewer, 8)

-- ============================================================
-- BOTÃO FLUTUANTE
-- ============================================================

local Mini = new("TextButton", {
    Parent = Gui,

    Size =
        UDim2.fromOffset(
            54,
            54
        ),

    Position =
        UDim2.new(
            .5,
            -27,
            .5,
            -27
        ),

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

round(Mini, 99)

-- ============================================================
-- PREVIEW
-- ============================================================

local function preview()

    local lines = {

        "LEITURA DE BOTS • V3",
        "",

        "ENTIDADES",
        "Total: "..#State.Records,
        "Army: "..#State.Army,
        "Rebels: "..#State.Rebels,

        "Possíveis jogáveis: "
            ..#State.Playable,

        "Possíveis manequins: "
            ..#State.Mannequins,

        "",

        "EVENTOS",
        "Soldier events: "
            ..#State.SoldierEvents,

        "Player events: "
            ..#State.PlayerEvents,

        "",

        "TEAM ANALYSIS",
    }

    local teamSources = {}

    for _, r in ipairs(State.Records) do

        if r.team then

            local key =
                tostring(r.teamSource)
                .." = "
                ..tostring(r.team)

            teamSources[key] =
                (teamSources[key] or 0) + 1
        end
    end

    for source, amount in pairs(teamSources) do

        lines[#lines + 1] =
            "  "
            ..source
            .." : "
            ..amount
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "ENTIDADES:"

    for _, r in ipairs(State.Records) do

        local team =
            tostring(r.team or "?")

        local source =
            tostring(r.teamSource or "?")

        local highlight =
            r.highlight
            and r.highlight.exists
            and "HIGHLIGHT"
            or "SEM HIGHLIGHT"

        lines[#lines + 1] =
            "["
            ..team
            .."] "
            ..r.name
            .." | fonte="
            ..source
            .." | "
            ..highlight
    end

    Viewer.Text =
        table.concat(
            lines,
            "\n"
        )
end

-- ============================================================
-- SCAN EVENT
-- ============================================================

Scan.Activated:Connect(function()

    Scan.Text = "LENDO..."

    Status.Text =
        "Analisando Soldiers, Team, Highlight e eventos..."

    Status.TextColor3 =
        COLORS.sub

    task.spawn(function()

        local ok, result =
            pcall(scanBots)

        if ok then

            preview()

            Summary.Text =
                "Leitura concluída • "
                ..#State.Records
                .." entidades • "
                ..#State.Army
                .." Army • "
                ..#State.Rebels
                .." Rebels • "
                ..#State.SoldierEvents
                .." eventos Soldier"

            Status.Text =
                "Leitura concluída com sucesso."

            Status.TextColor3 =
                COLORS.green

        else

            Status.Text =
                "Erro durante a leitura: "
                ..tostring(result)

            Status.TextColor3 =
                COLORS.red
        end

        Scan.Text =
            "REALIZAR LEITURA DE BOTS"
    end)
end)

-- ============================================================
-- EXPORT EVENT
-- ============================================================

Export.Activated:Connect(function()

    if not State.Scanned then

        Status.Text =
            "Faça a leitura primeiro."

        Status.TextColor3 =
            COLORS.yellow

        return
    end

    Status.Text =
        "Gerando arquivo..."

    Status.TextColor3 =
        COLORS.sub

    local data =
        jsonExport()

    if not data then

        Status.Text =
            "Não foi possível gerar o JSON."

        Status.TextColor3 =
            COLORS.red

        return
    end

    local filename =
        "Cafeina_BotResearch_V3_"
        ..tostring(game.PlaceId)
        .."_"
        ..tostring(os.time())
        ..".json"

    local wrote = false

    -- ========================================================
    -- WRITEFILE
    -- ========================================================

    if typeof(writefile) == "function" then

        local ok =
            pcall(function()

                writefile(
                    filename,
                    data
                )

            end)

        wrote = ok
    end

    -- ========================================================
    -- FALLBACK CLIPBOARD
    -- ========================================================

    if wrote then

        Status.Text =
            "ARQUIVO EXPORTADO COM SUCESSO!"

        Status.TextColor3 =
            COLORS.green

        Summary.Text =
            "Arquivo salvo com sucesso:\n"
            ..filename

    elseif typeof(setclipboard) == "function" then

        local ok =
            pcall(function()
                setclipboard(data)
            end)

        if ok then

            Status.Text =
                "JSON COPIADO COM SUCESSO!"

            Status.TextColor3 =
                COLORS.green

            Summary.Text =
                "writefile indisponível.\n"
                .."O conteúdo completo foi copiado para a área de transferência."

        else

            Status.Text =
                "Falha ao salvar/copiar."

            Status.TextColor3 =
                COLORS.red
        end

    else

        Status.Text =
            "writefile/clipboard indisponíveis."

        Status.TextColor3 =
            COLORS.red
    end
end)

-- ============================================================
-- MINIMIZAR
-- ============================================================

Min.Activated:Connect(function()

    Main.Visible = false
    Mini.Visible = true

end)

-- ============================================================
-- BOTÃO FLUTUANTE
-- ============================================================

Mini.Activated:Connect(function()

    Main.Visible = true
    Mini.Visible = false

end)

-- ============================================================
-- FECHAR
-- ============================================================

Close.Activated:Connect(function()

    pcall(function()
        Gui:Destroy()
    end)

end)

-- ============================================================
-- ARRASTAR BOTÃO FLUTUANTE
-- ============================================================

do

    local dragging = false

    local dragStart
    local startPos

    Mini.InputBegan:Connect(function(input)

        if input.UserInputType ==
            Enum.UserInputType.MouseButton1
            or input.UserInputType ==
            Enum.UserInputType.Touch then

            dragging = true

            dragStart =
                input.Position

            startPos =
                Mini.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)

        if not dragging then
            return
        end

        if input.UserInputType ~=
            Enum.UserInputType.MouseMovement
            and input.UserInputType ~=
            Enum.UserInputType.Touch then

            return
        end

        local delta =
            input.Position
            - dragStart

        Mini.Position =
            UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,

                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
    end)

    UserInputService.InputEnded:Connect(function(input)

        if input.UserInputType ==
            Enum.UserInputType.MouseButton1
            or input.UserInputType ==
            Enum.UserInputType.Touch then

            dragging = false
        end
    end)

end

-- ============================================================
-- MONITORAMENTO DE PLAYERS
-- ============================================================

Players.PlayerAdded:Connect(function(player)

    recordPlayerEvent(
        "PLAYER_ADDED",
        player
    )

end)

Players.PlayerRemoving:Connect(function(player)

    recordPlayerEvent(
        "PLAYER_REMOVING",
        player
    )

end)

-- ============================================================
-- MONITORAMENTO DE SOLDIERS
-- ============================================================

local SoldiersFolder =
    workspace:FindFirstChild("Soldiers")

if SoldiersFolder then

    SoldiersFolder.ChildAdded:Connect(function(child)

        recordSoldierEvent(
            "CREATED",
            child
        )

    end)

    SoldiersFolder.ChildRemoved:Connect(function(child)

        recordSoldierEvent(
            "REMOVED",
            child
        )

    end)

else

    -- Caso Soldiers ainda não exista no momento da execução.
    workspace.ChildAdded:Connect(function(child)

        if child.Name == "Soldiers" then

            recordSoldierEvent(
                "SOLDIERS_FOLDER_CREATED",
                child
            )

            child.ChildAdded:Connect(function(bot)

                recordSoldierEvent(
                    "CREATED",
                    bot
                )

            end)

            child.ChildRemoved:Connect(function(bot)

                recordSoldierEvent(
                    "REMOVED",
                    bot
                )

            end)
        end
    end)
end

-- ============================================================
-- FIM
-- ============================================================

Status.Text =
    "V3 carregada. Pronto para realizar a leitura."

Status.TextColor3 =
    COLORS.sub
