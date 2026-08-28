-- CAFEÍNA • LEITURA DE BOTS
-- Interface independente da interface antiga.
-- Mantém apenas leitura de bots + exportação local/cópia.
-- Botão flutuante azul-escuro pode ser arrastado livremente.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

local function getParent()
    if typeof(gethui) == "function" then
        local ok, p = pcall(gethui)
        if ok and p then return p end
    end
    return CoreGui
end

local Parent = getParent()

-- Remove SOMENTE instâncias desta nova interface.
-- Não procura nem altera a interface antiga.
for _, v in ipairs(Parent:GetChildren()) do
    if v.Name == "CafeinaBotReader_Standalone" then
        pcall(function() v:Destroy() end)
    end
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "CafeinaBotReader_Standalone"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = true
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = Parent

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
    for k,v in pairs(props or {}) do x[k] = v end
    return x
end

local function round(x, r)
    new("UICorner", {CornerRadius=UDim.new(0,r or 8), Parent=x})
end

local function label(parent, text, size, pos, textSize)
    return new("TextLabel", {
        Parent=parent, BackgroundTransparency=1, Text=text,
        Size=size, Position=pos, TextColor3=COLORS.text,
        Font=Enum.Font.Gotham, TextSize=textSize or 10,
        TextXAlignment=Enum.TextXAlignment.Left
    })
end

-- ============================================================
-- Estado
-- ============================================================

local State = {
    Records = {},
    Army = {},
    Rebels = {},
    Mannequins = {},
    Playable = {},
    PatrolPoints = {},
    Scanned = false,
}

local function safeFullName(x)
    local ok, v = pcall(function() return x:GetFullName() end)
    return ok and tostring(v) or tostring(x.Name)
end

local function attr(x, key)
    local ok, v = pcall(function() return x:GetAttribute(key) end)
    return ok and v or nil
end

local function hasClass(x, class)
    local ok, v = pcall(function() return x:IsA(class) end)
    return ok and v
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
        if p.Character == model then return true end
    end
    return false
end

-- Heurística deliberadamente conservadora:
-- 1) exclui personagens de Players;
-- 2) exige Model + Humanoid;
-- 3) procura sinais de entidade jogável;
-- 4) registra os sinais encontrados, sem afirmar que são definitivos.
local function inspectModel(model)
    if not hasClass(model, "Model") or isPlayerCharacter(model) then
        return nil
    end

    local hum = getHumanoid(model)
    if not hum then return nil end

    local root = getRoot(model)
    local teamValue = attr(model, "Team")
    local teamName = teamValue and tostring(teamValue) or nil

    if not teamName then
        local teamObj = model:FindFirstChild("Team")
        if teamObj and teamObj:IsA("StringValue") then
            teamName = teamObj.Value
        end
    end

    local signals = {}
    if root then table.insert(signals, "RootPart") end
    table.insert(signals, "Humanoid")
    if hum.Health > 0 then table.insert(signals, "Health>0") end
    if hum.WalkSpeed > 0 then table.insert(signals, "WalkSpeed") end
    if hum.MoveDirection.Magnitude > 0 then table.insert(signals, "MoveDirection") end
    if model:FindFirstChildWhichIsA("Tool", true) then table.insert(signals, "Tool") end

    local patrolFolder = workspace:FindFirstChild("BotPatrolPoints")
    local hasPatrol = patrolFolder ~= nil
    if hasPatrol then table.insert(signals, "BotPatrolPoints presente") end

    local likelyMannequin =
        model.Name:lower():find("dummy",1,true) ~= nil
        or model.Name:lower():find("mannequin",1,true) ~= nil
        or model.Name:lower():find("manequim",1,true) ~= nil

    local likelyPlayable = not likelyMannequin and root ~= nil

    local rec = {
        name = model.Name,
        path = safeFullName(model),
        className = model.ClassName,
        team = teamName,
        health = hum.Health,
        maxHealth = hum.MaxHealth,
        walkSpeed = hum.WalkSpeed,
        jumpPower = hum.JumpPower,
        rigType = tostring(hum.RigType),
        rootPart = root and root.Name or nil,
        position = root and {x=root.Position.X,y=root.Position.Y,z=root.Position.Z} or nil,
        moveDirection = {x=hum.MoveDirection.X,y=hum.MoveDirection.Y,z=hum.MoveDirection.Z},
        attributes = {},
        signals = signals,
        likelyMannequin = likelyMannequin,
        likelyPlayable = likelyPlayable,
    }

    pcall(function()
        for k,v in pairs(model:GetAttributes()) do
            rec.attributes[tostring(k)] = tostring(v)
        end
    end)

    return rec
end

local function scanPatrolPoints()
    State.PatrolPoints = {}
    local folder = workspace:FindFirstChild("BotPatrolPoints")
    if not folder then return end

    for _, teamFolder in ipairs(folder:GetChildren()) do
        if teamFolder:IsA("Folder") then
            local list = {}
            for _, p in ipairs(teamFolder:GetDescendants()) do
                if p:IsA("BasePart") then
                    list[#list+1] = {
                        name=p.Name,
                        path=safeFullName(p),
                        teamAttribute=attr(p,"Team"),
                        position={x=p.Position.X,y=p.Position.Y,z=p.Position.Z},
                        anchored=p.Anchored,
                        transparency=p.Transparency,
                    }
                end
            end
            State.PatrolPoints[teamFolder.Name] = list
        end
    end
end

local function scanBots()
    State.Records, State.Army, State.Rebels, State.Mannequins, State.Playable = {}, {}, {}, {}, {}
    scanPatrolPoints()

    for _, inst in ipairs(workspace:GetDescendants()) do
        local rec = inspectModel(inst)
        if rec then
            State.Records[#State.Records+1] = rec

            if rec.team == "Army" then
                State.Army[#State.Army+1] = rec
            elseif rec.team == "Rebels" then
                State.Rebels[#State.Rebels+1] = rec
            end

            if rec.likelyMannequin then
                State.Mannequins[#State.Mannequins+1] = rec
            elseif rec.likelyPlayable then
                State.Playable[#State.Playable+1] = rec
            end
        end
    end

    State.Scanned = true
end

local function buildExport()
    return {
        format = "Cafeina Bot Reader",
        version = "Standalone-1",
        generatedAtUnix = os.time(),
        game = {
            placeId = game.PlaceId,
            gameId = game.GameId,
            jobId = game.JobId,
        },
        detection = {
            note = "Heurísticas baseadas apenas no que está visível ao cliente.",
            bots = #State.Records,
            army = #State.Army,
            rebels = #State.Rebels,
            mannequins = #State.Mannequins,
            likelyPlayable = #State.Playable,
        },
        bots = State.Records,
        patrolPoints = State.PatrolPoints,
    }
end

local function jsonExport()
    local ok, result = pcall(function()
        return HttpService:JSONEncode(buildExport())
    end)
    return ok and result or nil
end

-- ============================================================
-- Interface NOVA
-- ============================================================

local Main = new("Frame", {
    Parent=Gui, Size=UDim2.fromOffset(520,430),
    Position=UDim2.new(.5,-260,.5,-215),
    BackgroundColor3=COLORS.bg, BorderSizePixel=0
})
round(Main,14)

local Header = new("Frame", {
    Parent=Main, Size=UDim2.new(1,0,0,55),
    BackgroundColor3=COLORS.panel, BorderSizePixel=0
})
round(Header,14)

label(Header,"CAFEÍNA • LEITURA DE BOTS",UDim2.new(1,-95,0,24),UDim2.fromOffset(14,7),15)
local sub=label(Header,"INTERFACE STANDALONE • SOMENTE LEITURA",UDim2.new(1,-95,0,16),UDim2.fromOffset(14,31),9)
sub.TextColor3=COLORS.sub

local Min = new("TextButton", {
    Parent=Header, Size=UDim2.fromOffset(30,30),
    Position=UDim2.new(1,-76,0,11), Text="—",
    BackgroundColor3=COLORS.panel2, TextColor3=COLORS.text,
    Font=Enum.Font.GothamBold, TextSize=17, BorderSizePixel=0
})
round(Min,8)

local Close = new("TextButton", {
    Parent=Header, Size=UDim2.fromOffset(30,30),
    Position=UDim2.new(1,-40,0,11), Text="×",
    BackgroundColor3=COLORS.red, TextColor3=COLORS.text,
    Font=Enum.Font.GothamBold, TextSize=18, BorderSizePixel=0
})
round(Close,8)

local Status = label(Main,"Pronto para realizar a leitura.",UDim2.new(1,-28,0,28),UDim2.fromOffset(14,66),11)
Status.TextColor3=COLORS.sub

local Scan = new("TextButton", {
    Parent=Main, Size=UDim2.new(.5,-20,0,42),
    Position=UDim2.fromOffset(14,98), Text="REALIZAR LEITURA DE BOTS",
    BackgroundColor3=COLORS.blue2, TextColor3=COLORS.text,
    Font=Enum.Font.GothamBold, TextSize=10, BorderSizePixel=0
})
round(Scan,8)

local Export = new("TextButton", {
    Parent=Main, Size=UDim2.new(.5,-20,0,42),
    Position=UDim2.new(.5,6,0,98), Text="BAIXAR ARQUIVO DE LEITURA",
    BackgroundColor3=COLORS.blue, TextColor3=COLORS.text,
    Font=Enum.Font.GothamBold, TextSize=10, BorderSizePixel=0
})
round(Export,8)

local Summary = label(Main,"Nenhuma leitura realizada.",UDim2.new(1,-28,0,52),UDim2.fromOffset(14,150),10)
Summary.TextWrapped=true
Summary.TextColor3=COLORS.text

local Viewer = new("TextBox", {
    Parent=Main, Size=UDim2.new(1,-28,1,-222),
    Position=UDim2.fromOffset(14,204),
    BackgroundColor3=COLORS.panel, BorderSizePixel=0,
    Text="", TextColor3=COLORS.text, Font=Enum.Font.Code,
    TextSize=9, MultiLine=true, ClearTextOnFocus=false,
    TextEditable=false, TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top
})
round(Viewer,8)

local Mini = new("TextButton", {
    Parent=Gui, Size=UDim2.fromOffset(54,54),
    Position=UDim2.new(.5,-27,.5,-27),
    BackgroundColor3=COLORS.blue, Text="C",
    TextColor3=COLORS.text, Font=Enum.Font.GothamBlack,
    TextSize=19, BorderSizePixel=0, Visible=false
})
round(Mini,99)

-- ============================================================
-- Preview
-- ============================================================

local function preview()
    local lines = {
        "LEITURA DE BOTS",
        "",
        "Bots/Modelos detectados: "..#State.Records,
        "Army: "..#State.Army,
        "Rebels: "..#State.Rebels,
        "Possíveis jogáveis: "..#State.Playable,
        "Possíveis manequins: "..#State.Mannequins,
        "",
        "BOTPATROLPOINTS:"
    }

    local totalPoints=0
    for team, list in pairs(State.PatrolPoints) do
        lines[#lines+1] = "  "..team..": "..#list.." pontos"
        totalPoints += #list
    end
    lines[#lines+1] = "Total de patrol points: "..totalPoints
    lines[#lines+1] = ""
    lines[#lines+1] = "ENTIDADES:"

    for _, r in ipairs(State.Records) do
        lines[#lines+1] =
            "["..tostring(r.team or "?").."] "
            ..r.name
            .." | HP "..string.format("%.1f",r.health)
            .."/"..string.format("%.1f",r.maxHealth)
            .." | "..(r.likelyMannequin and "MANEQUIM" or "POSSÍVEL BOT")
    end

    Viewer.Text=table.concat(lines,"\n")
end

Scan.Activated:Connect(function()
    Scan.Text="LENDO..."
    Status.Text="Inspecionando modelos, Humanoids, atributos, times e BotPatrolPoints..."
    task.spawn(function()
        local ok, err=pcall(scanBots)
        if ok then
            preview()
            Summary.Text="Leitura concluída • "..#State.Records.." entidades • "..#State.Army.." Army • "..#State.Rebels.." Rebels • "..#State.Mannequins.." possíveis manequins"
            Status.Text="Leitura concluída."
            Status.TextColor3=COLORS.green
        else
            Status.Text="Erro: "..tostring(err)
            Status.TextColor3=COLORS.red
        end
        Scan.Text="REALIZAR LEITURA DE BOTS"
    end)
end)

Export.Activated:Connect(function()
    if not State.Scanned then
        Status.Text="Faça a leitura primeiro."
        return
    end

    local data=jsonExport()
    if not data then
        Status.Text="Não foi possível gerar JSON."
        return
    end

    -- Nem todo ambiente/executor possui API de arquivo.
    local filename="Cafeina_BotReader_"..tostring(game.PlaceId)..".json"
    local wrote=false

    if typeof(writefile)=="function" then
        local ok=pcall(function() writefile(filename,data) end)
        wrote=ok
    end

    if not wrote and typeof(setclipboard)=="function" then
        pcall(setclipboard,data)
        Status.Text="JSON copiado para a área de transferência (writefile indisponível)."
    elseif wrote then
        Status.Text="Arquivo salvo: "..filename
    else
        Status.Text="Ambiente sem writefile/clipboard."
    end
end)

-- ============================================================
-- Minimizar / fechar
-- ============================================================

Min.Activated:Connect(function()
    Main.Visible=false
    Mini.Visible=true
end)

Close.Activated:Connect(function()
    pcall(function() Gui:Destroy() end)
end)

-- ============================================================
-- Arrastar livremente o botão flutuante
-- ============================================================

do
    local dragging=false
    local dragStart
    local startPos

    Mini.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1
        or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true
            dragStart=input.Position
            startPos=Mini.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType~=Enum.UserInputType.MouseMovement
        and input.UserInputType~=Enum.UserInputType.Touch then return end

        local delta=input.Position-dragStart
        Mini.Position=UDim2.new(
            startPos.X.Scale,startPos.X.Offset+delta.X,
            startPos.Y.Scale,startPos.Y.Offset+delta.Y
        )
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1
        or input.UserInputType==Enum.UserInputType.Touch then
            dragging=false
        end
    end)
end
