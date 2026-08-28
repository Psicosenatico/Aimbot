--========================================================
-- TEST CONTROL PANEL
-- ESP + AIMBOT
-- TEAM CHECK POR PLAYER.TEAM / BOT ATTRIBUTE "Team"
--========================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local GUI_NAME = "TestControlPanel"

local Connections = {}
local ESPObjects = {}

local Gui
local Main
local FOVCircle
local MinimizedButton

local AimbotEnabled = false
local TeamCheckEnabled = true
local ESPEnabled = false

local FOVRadius = 150
local AimDistance = 500

local CreatingInterface = false
local LastESPUpdate = 0

local ESP_UPDATE_INTERVAL = 0.20


--========================================================
-- CORES
--========================================================

local MENU_COLOR =
    Color3.fromRGB(18, 31, 55)

local BUTTON_COLOR =
    Color3.fromRGB(28, 48, 82)

local BUTTON_ACTIVE =
    Color3.fromRGB(35, 65, 105)

local BLACK =
    Color3.fromRGB(0, 0, 0)

local WHITE =
    Color3.fromRGB(255, 255, 255)

local FOV_COLOR =
    Color3.fromRGB(80, 170, 255)

-- ALIADOS SEMPRE VERDE
local ALLY_COLOR =
    Color3.fromRGB(0, 255, 90)

-- INIMIGOS SEMPRE VERMELHO
local ENEMY_COLOR =
    Color3.fromRGB(255, 60, 60)


--========================================================
-- CONNECTION MANAGER
--========================================================

local function Connect(signal, callback)

    local connection =
        signal:Connect(callback)

    table.insert(
        Connections,
        connection
    )

    return connection
end


local function DisconnectAll()

    for _, connection in ipairs(
        Connections
    ) do

        if connection
        and connection.Connected then

            connection:Disconnect()

        end
    end

    table.clear(Connections)
end


--========================================================
-- CAMERA
--========================================================

local function GetCamera()

    return workspace.CurrentCamera
end


--========================================================
-- NORMALIZAR TIME
--========================================================

local function NormalizeTeamName(name)

    if name == nil then
        return nil
    end

    local text =
        string.lower(
            tostring(name)
        )

    text =
        string.gsub(
            text,
            "%s+",
            ""
        )

    if text == "army"
    or text == "exercito"
    or text == "exército"
    or text == "green"
    or text == "verde" then

        return "Army"
    end

    if text == "rebels"
    or text == "rebel"
    or text == "rebeldes"
    or text == "red"
    or text == "vermelho" then

        return "Rebels"
    end

    return nil
end


--========================================================
-- TIME DO PLAYER
--========================================================

local function GetPlayerTeam(player)

    if not player then
        return nil
    end

    local team =
        player.Team

    if team then

        local normalized =
            NormalizeTeamName(
                team.Name
            )

        if normalized then
            return normalized
        end
    end

    -- Fallback para jogos que armazenam
    -- o time como atributo no Player.

    local attributeTeam =
        player:GetAttribute("Team")

    return NormalizeTeamName(
        attributeTeam
    )
end


local function GetLocalTeam()

    return GetPlayerTeam(
        LocalPlayer
    )
end


--========================================================
-- TIME DE UM BOT
--
-- IMPORTANTE:
-- Não procuramos mais Army/Rebels pelo caminho.
-- O próprio Model precisa possuir:
--
-- Model
-- ├─ Humanoid
-- ├─ HumanoidRootPart
-- └─ Attribute Team = Army/Rebels
--========================================================

local function GetBotTeam(character)

    if not character then
        return nil
    end

    if not character:IsA("Model") then
        return nil
    end

    local humanoid =
        character:FindFirstChildOfClass(
            "Humanoid"
        )

    local root =
        character:FindFirstChild(
            "HumanoidRootPart"
        )

    if not humanoid
    or not root then

        return nil
    end

    local team =
        character:GetAttribute(
            "Team"
        )

    return NormalizeTeamName(
        team
    )
end


--========================================================
-- TIME DO PERSONAGEM
--========================================================

local function GetCharacterTeam(character)

    if not character then
        return nil
    end

    if not character:IsA("Model") then
        return nil
    end


    --====================================================
    -- PLAYER
    --====================================================

    local player =
        Players:GetPlayerFromCharacter(
            character
        )

    if player then

        return GetPlayerTeam(
            player
        )
    end


    --====================================================
    -- BOT / NPC
    --====================================================

    return GetBotTeam(
        character
    )
end


--========================================================
-- VERIFICAR PERSONAGEM
--========================================================

local function IsValidCharacter(character)

    if not character then
        return false
    end

    if not character:IsA("Model") then
        return false
    end


    local humanoid =
        character:FindFirstChildOfClass(
            "Humanoid"
        )

    local root =
        character:FindFirstChild(
            "HumanoidRootPart"
        )


    if not humanoid
    or not root then

        return false
    end


    if humanoid.Health <= 0 then
        return false
    end


    return true
end


--========================================================
-- VERIFICAR SE É BOT VÁLIDO
--========================================================

local function IsValidBot(character)

    if not IsValidCharacter(
        character
    ) then

        return false
    end


    -- Se é Player, não é bot.
    if Players:GetPlayerFromCharacter(
        character
    ) then

        return false
    end


    -- O bot precisa possuir Team válido.
    local botTeam =
        GetBotTeam(
            character
        )

    if not botTeam then
        return false
    end


    return true
end


--========================================================
-- PERSONAGEM VÁLIDO PARA ESP
--========================================================

local function IsESPCharacter(character)

    if not IsValidCharacter(
        character
    ) then

        return false
    end


    local player =
        Players:GetPlayerFromCharacter(
            character
        )


    --====================================================
    -- PLAYER
    --====================================================

    if player then
        return true
    end


    --====================================================
    -- BOT
    --====================================================

    return IsValidBot(
        character
    )
end


--========================================================
-- ALIADO
--========================================================

local function IsAllyCharacter(character)

    if not IsESPCharacter(
        character
    ) then

        return false
    end


    if character ==
        LocalPlayer.Character then

        return true
    end


    local localTeam =
        GetLocalTeam()


    if not localTeam then
        return false
    end


    local characterTeam =
        GetCharacterTeam(
            character
        )


    if not characterTeam then
        return false
    end


    return characterTeam ==
        localTeam
end


--========================================================
-- INIMIGO
--========================================================

local function IsEnemyCharacter(character)

    if not IsESPCharacter(
        character
    ) then

        return false
    end


    if character ==
        LocalPlayer.Character then

        return false
    end


    local localTeam =
        GetLocalTeam()


    if not localTeam then
        return false
    end


    local characterTeam =
        GetCharacterTeam(
            character
        )


    if not characterTeam then
        return false
    end


    -- Team Check ON:
    -- somente o time diferente do nosso
    -- é inimigo.

    if TeamCheckEnabled then

        return characterTeam ~=
            localTeam
    end


    -- Quando Team Check está OFF,
    -- personagens válidos dos dois times
    -- continuam podendo receber ESP.
    return true
end


--========================================================
-- REMOVER ESP
--========================================================

local function RemoveESP(character)

    local highlight =
        ESPObjects[character]


    if highlight then

        highlight:Destroy()

        ESPObjects[character] =
            nil
    end
end


--========================================================
-- CRIAR / ATUALIZAR ESP
--========================================================

local function ApplyESP(
    character,
    enemy
)

    if not IsESPCharacter(
        character
    ) then

        return
    end


    local highlight =
        ESPObjects[character]


    if not highlight then

        highlight =
            Instance.new(
                "Highlight"
            )


        highlight.Name =
            "TestESP"


        highlight.Adornee =
            character


        highlight.DepthMode =
            Enum.HighlightDepthMode.AlwaysOnTop


        highlight.FillTransparency =
            0.75


        highlight.OutlineTransparency =
            0


        highlight.Parent =
            Gui


        ESPObjects[character] =
            highlight
    end


    --====================================================
    -- IMPORTANTE:
    --
    -- Não usamos a cor do Highlight original.
    -- Não usamos aura.
    -- Não usamos cor do nome.
    --
    -- Nosso Highlight é independente.
    --====================================================

    if enemy then

        highlight.FillColor =
            ENEMY_COLOR

        highlight.OutlineColor =
            ENEMY_COLOR

    else

        highlight.FillColor =
            ALLY_COLOR

        highlight.OutlineColor =
            ALLY_COLOR
    end
end


--========================================================
-- ENCONTRAR TODOS OS MODELS DE PERSONAGEM
--
-- Não procuramos mais somente em:
-- Workspace.Army
-- Workspace.Rebels
--
-- Procuramos Models no Workspace inteiro.
--
-- Isso permite encontrar:
-- Workspace.Soldiers.Goober9000
-- Workspace.Soldiers.ChunkyOtter8
-- etc.
--
-- Parts de BotPatrolPoints são ignoradas porque
-- não possuem Humanoid + HumanoidRootPart.
--========================================================

local function GetAllCharacters()

    local characters = {}
    local alreadyAdded = {}


    --====================================================
    -- PLAYERS
    --====================================================

    for _, player in ipairs(
        Players:GetPlayers()
    ) do

        local character =
            player.Character


        if character
        and not alreadyAdded[
            character
        ] then

            if IsValidCharacter(
                character
            ) then

                alreadyAdded[
                    character
                ] = true

                table.insert(
                    characters,
                    character
                )
            end
        end
    end


    --====================================================
    -- BOTS / NPCS
    --====================================================

    for _, object in ipairs(
        workspace:GetDescendants()
    ) do

        if object:IsA("Model") then

            if not alreadyAdded[
                object
            ] then

                -- Não adicionar Players aqui.
                local player =
                    Players:GetPlayerFromCharacter(
                        object
                    )


                if not player then

                    -- O modelo precisa possuir
                    -- Humanoid + RootPart + Team.

                    if IsValidBot(
                        object
                    ) then

                        alreadyAdded[
                            object
                        ] = true


                        table.insert(
                            characters,
                            object
                        )
                    end
                end
            end
        end
    end


    return characters
end


--========================================================
-- LIMPAR TODOS OS ESP
--========================================================

local function ClearAllESP()

    for character, highlight in pairs(
        ESPObjects
    ) do

        if highlight then
            highlight:Destroy()
        end

        ESPObjects[
            character
        ] = nil
    end
end


--========================================================
-- ATUALIZAR ESP
--========================================================

local function UpdateESP()

    if not ESPEnabled then

        ClearAllESP()

        return
    end


    local validCharacters = {}


    for _, character in ipairs(
        GetAllCharacters()
    ) do

        validCharacters[
            character
        ] = true


        if character ~=
            LocalPlayer.Character then


            if IsEnemyCharacter(
                character
            ) then

                -- INIMIGO = VERMELHO

                ApplyESP(
                    character,
                    true
                )


            elseif IsAllyCharacter(
                character
            ) then

                -- ALIADO = VERDE

                ApplyESP(
                    character,
                    false
                )


            else

                RemoveESP(
                    character
                )
            end
        end
    end


    --====================================================
    -- LIMPAR PERSONAGENS QUE SUMIRAM
    --====================================================

    for character, highlight in pairs(
        ESPObjects
    ) do

        if not validCharacters[
            character
        ] then

            if highlight then
                highlight:Destroy()
            end

            ESPObjects[
                character
            ] = nil
        end
    end
end


--========================================================
-- CENTRO DA TELA
--========================================================

local function GetScreenCenter()

    local camera =
        GetCamera()


    if not camera then

        return Vector2.new(
            0,
            0
        )
    end


    local viewport =
        camera.ViewportSize


    return Vector2.new(
        viewport.X / 2,
        viewport.Y / 2
    )
end


--========================================================
-- TARGET
--========================================================

local function GetTarget()

    local camera =
        GetCamera()


    if not camera then
        return nil
    end


    local center =
        GetScreenCenter()


    local bestTarget =
        nil


    local closestWorldDistance =
        math.huge


    for _, character in ipairs(
        GetAllCharacters()
    ) do

        if character ~=
            LocalPlayer.Character then


            if IsEnemyCharacter(
                character
            ) then


                local humanoid =
                    character:FindFirstChildOfClass(
                        "Humanoid"
                    )


                local root =
                    character:FindFirstChild(
                        "HumanoidRootPart"
                    )


                if humanoid
                and root
                and humanoid.Health > 0 then


                    local worldDistance =
                        (
                            camera.CFrame.Position
                            -
                            root.Position
                        ).Magnitude


                    if worldDistance <=
                        AimDistance then


                        local screenPosition,
                            visible =
                            camera:WorldToViewportPoint(
                                root.Position
                            )


                        if visible
                        and screenPosition.Z > 0 then


                            local screenPoint =
                                Vector2.new(
                                    screenPosition.X,
                                    screenPosition.Y
                                )


                            local screenDistance =
                                (
                                    screenPoint -
                                    center
                                ).Magnitude


                            if screenDistance <=
                                FOVRadius then


                                if worldDistance <
                                    closestWorldDistance then

                                    closestWorldDistance =
                                        worldDistance

                                    bestTarget =
                                        character
                                end
                            end
                        end
                    end
                end
            end
        end
    end


    return bestTarget
end


--========================================================
-- AIM
--========================================================

local function AimAtTarget(character)

    if not character then
        return
    end


    local camera =
        GetCamera()


    if not camera then
        return
    end


    local root =
        character:FindFirstChild(
            "HumanoidRootPart"
        )


    if not root then
        return
    end


    camera.CFrame =
        CFrame.lookAt(
            camera.CFrame.Position,
            root.Position
        )
end


--========================================================
-- FOV
--========================================================

local function UpdateFOV()

    if not FOVCircle then
        return
    end


    local camera =
        GetCamera()


    if not camera then
        return
    end


    local viewport =
        camera.ViewportSize


    FOVCircle.Size =
        UDim2.fromOffset(
            FOVRadius * 2,
            FOVRadius * 2
        )


    FOVCircle.Position =
        UDim2.fromOffset(
            viewport.X / 2,
            viewport.Y / 2
        )


    FOVCircle.Visible =
        AimbotEnabled
end


local function CreateFOVCircle()

    if FOVCircle then
        FOVCircle:Destroy()
    end


    FOVCircle =
        Instance.new("Frame")


    FOVCircle.Name =
        "FOV"


    FOVCircle.AnchorPoint =
        Vector2.new(
            0.5,
            0.5
        )


    FOVCircle.BackgroundTransparency =
        1


    FOVCircle.BorderSizePixel =
        0


    FOVCircle.Parent =
        Gui


    local corner =
        Instance.new("UICorner")


    corner.CornerRadius =
        UDim.new(
            1,
            0
        )


    corner.Parent =
        FOVCircle


    local stroke =
        Instance.new("UIStroke")


    stroke.Color =
        FOV_COLOR


    stroke.Thickness =
        2


    stroke.Transparency =
        0.1


    stroke.Parent =
        FOVCircle


    UpdateFOV()
end


--========================================================
-- BOTÃO FLUTUANTE
--========================================================

local function CreateMinimizedButton()

    MinimizedButton =
        Instance.new("TextButton")


    MinimizedButton.Name =
        "MinimizedButton"


    MinimizedButton.Size =
        UDim2.fromOffset(
            58,
            58
        )


    MinimizedButton.Position =
        UDim2.new(
            0.5,
            -29,
            0.5,
            -29
        )


    MinimizedButton.Text =
        ""


    MinimizedButton.BackgroundColor3 =
        MENU_COLOR


    MinimizedButton.BorderColor3 =
        BLACK


    MinimizedButton.BorderSizePixel =
        3


    MinimizedButton.Visible =
        false


    MinimizedButton.Parent =
        Gui


    local corner =
        Instance.new("UICorner")


    corner.CornerRadius =
        UDim.new(
            1,
            0
        )


    corner.Parent =
        MinimizedButton


    --====================================================
    -- ESCUDO
    --
    -- Usamos TextLabel separado e centralizado.
    --====================================================

    local Shield =
        Instance.new("TextLabel")


    Shield.Name =
        "Shield"


    Shield.Size =
        UDim2.fromScale(
            0.70,
            0.70
        )


    Shield.AnchorPoint =
        Vector2.new(
            0.5,
            0.5
        )


    Shield.Position =
        UDim2.fromScale(
            0.5,
            0.5
        )


    Shield.BackgroundTransparency =
        1


    Shield.Text =
        "🛡️"


    Shield.TextColor3 =
        WHITE


    Shield.TextScaled =
        true


    Shield.Font =
        Enum.Font.GothamBold


    Shield.TextXAlignment =
        Enum.TextXAlignment.Center


    Shield.TextYAlignment =
        Enum.TextYAlignment.Center


    Shield.Parent =
        MinimizedButton


    Connect(
        MinimizedButton.MouseButton1Click,
        function()

            Main.Visible =
                true

            MinimizedButton.Visible =
                false
        end
    )


    --====================================================
    -- DRAG
    --====================================================

    local dragging =
        false

    local dragStart
    local startPosition


    Connect(
        MinimizedButton.InputBegan,
        function(input)

            if input.UserInputType ==
                Enum.UserInputType.MouseButton1
            or input.UserInputType ==
                Enum.UserInputType.Touch then

                dragging =
                    true

                dragStart =
                    input.Position

                startPosition =
                    MinimizedButton.Position
            end
        end
    )


    Connect(
        UserInputService.InputChanged,
        function(input)

            if not dragging then
                return
            end


            if input.UserInputType ==
                Enum.UserInputType.MouseMovement
            or input.UserInputType ==
                Enum.UserInputType.Touch then

                local delta =
                    input.Position -
                    dragStart


                MinimizedButton.Position =
                    UDim2.new(

                        startPosition.X.Scale,

                        startPosition.X.Offset +
                        delta.X,

                        startPosition.Y.Scale,

                        startPosition.Y.Offset +
                        delta.Y
                    )
            end
        end
    )


    Connect(
        UserInputService.InputEnded,
        function(input)

            if input.UserInputType ==
                Enum.UserInputType.MouseButton1
            or input.UserInputType ==
                Enum.UserInputType.Touch then

                dragging =
                    false
            end
        end
    )
end


--========================================================
-- BOTÃO
--========================================================

local function CreateButton(
    parent,
    text,
    position
)

    local button =
        Instance.new("TextButton")


    button.Size =
        UDim2.new(
            1,
            -20,
            0,
            38
        )


    button.Position =
        position


    button.BackgroundColor3 =
        BUTTON_COLOR


    button.BorderColor3 =
        BLACK


    button.BorderSizePixel =
        2


    button.TextColor3 =
        WHITE


    button.Text =
        text


    button.TextSize =
        15


    button.Font =
        Enum.Font.GothamMedium


    button.Parent =
        parent


    local corner =
        Instance.new("UICorner")


    corner.CornerRadius =
        UDim.new(
            0,
            6
        )


    corner.Parent =
        button


    return button
end


--========================================================
-- SLIDER
--========================================================

local function CreateSlider(
    parent,
    y,
    minimum,
    maximum,
    currentValue,
    callback
)

    local slider =
        Instance.new("TextButton")


    slider.Size =
        UDim2.new(
            1,
            -20,
            0,
            24
        )


    slider.Position =
        UDim2.fromOffset(
            10,
            y
        )


    slider.BackgroundColor3 =
        Color3.fromRGB(
            8,
            15,
            28
        )


    slider.BorderColor3 =
        BLACK


    slider.BorderSizePixel =
        2


    slider.Text =
        ""


    slider.AutoButtonColor =
        false


    slider.Parent =
        parent


    local corner =
        Instance.new("UICorner")


    corner.CornerRadius =
        UDim.new(
            0,
            8
        )


    corner.Parent =
        slider


    local percentage =
        (
            currentValue -
            minimum
        )
        /
        (
            maximum -
            minimum
        )


    local knob =
        Instance.new("Frame")


    knob.Size =
        UDim2.fromOffset(
            14,
            24
        )


    knob.AnchorPoint =
        Vector2.new(
            0.5,
            0
        )


    knob.BackgroundColor3 =
        WHITE


    knob.BorderColor3 =
        BLACK


    knob.BorderSizePixel =
        2


    knob.Position =
        UDim2.new(
            percentage,
            0,
            0,
            0
        )


    knob.Parent =
        slider


    local dragging =
        false


    local function SetValue(x)

        local width =
            slider.AbsoluteSize.X


        if width <= 0 then
            return
        end


        local relative =
            math.clamp(

                x -
                slider.AbsolutePosition.X,

                0,

                width
            )


        local percent =
            relative / width


        local value =
            math.floor(

                minimum +
                percent *
                (
                    maximum -
                    minimum
                )
            )


        knob.Position =
            UDim2.new(
                percent,
                0,
                0,
                0
            )


        callback(value)
    end


    Connect(
        slider.InputBegan,
        function(input)

            if input.UserInputType ==
                Enum.UserInputType.MouseButton1
            or input.UserInputType ==
                Enum.UserInputType.Touch then

                dragging =
                    true

                SetValue(
                    input.Position.X
                )
            end
        end
    )


    Connect(
        UserInputService.InputChanged,
        function(input)

            if not dragging then
                return
            end


            if input.UserInputType ==
                Enum.UserInputType.MouseMovement
            or input.UserInputType ==
                Enum.UserInputType.Touch then

                SetValue(
                    input.Position.X
                )
            end
        end
    )


    Connect(
        UserInputService.InputEnded,
        function(input)

            if input.UserInputType ==
                Enum.UserInputType.MouseButton1
            or input.UserInputType ==
                Enum.UserInputType.Touch then

                dragging =
                    false
            end
        end
    )
end


--========================================================
-- RESET
--========================================================

local function ResetScript()

    AimbotEnabled =
        false

    ESPEnabled =
        false


    ClearAllESP()


    DisconnectAll()


    if Gui then

        Gui:Destroy()

        Gui =
            nil
    end


    FOVCircle =
        nil

    MinimizedButton =
        nil


    task.wait(0.15)


    CreateInterface()
end


--========================================================
-- INTERFACE
--========================================================

function CreateInterface()

    if CreatingInterface then
        return
    end


    CreatingInterface =
        true


    --====================================================
    -- GUI
    --====================================================

    Gui =
        Instance.new("ScreenGui")


    Gui.Name =
        GUI_NAME


    Gui.ResetOnSpawn =
        false


    Gui.IgnoreGuiInset =
        true


    Gui.Parent =
        PlayerGui


    --====================================================
    -- MAIN
    --====================================================

    Main =
        Instance.new("Frame")


    Main.Name =
        "Main"


    Main.Size =
        UDim2.fromOffset(
            330,
            430
        )


    Main.Position =
        UDim2.new(
            0.5,
            -165,
            0.5,
            -215
        )


    Main.BackgroundColor3 =
        MENU_COLOR


    Main.BorderColor3 =
        BLACK


    Main.BorderSizePixel =
        3


    Main.Parent =
        Gui


    local mainCorner =
        Instance.new("UICorner")


    mainCorner.CornerRadius =
        UDim.new(
            0,
            10
        )


    mainCorner.Parent =
        Main


    --====================================================
    -- TITLE
    --====================================================

    local TitleBar =
        Instance.new("Frame")


    TitleBar.Size =
        UDim2.new(
            1,
            0,
            0,
            42
        )


    TitleBar.BackgroundColor3 =
        Color3.fromRGB(
            12,
            23,
            42
        )


    TitleBar.BorderColor3 =
        BLACK


    TitleBar.BorderSizePixel =
        2


    TitleBar.Parent =
        Main


    local Title =
        Instance.new("TextLabel")


    Title.Size =
        UDim2.new(
            1,
            -90,
            1,
            0
        )


    Title.Position =
        UDim2.fromOffset(
            10,
            0
        )


    Title.BackgroundTransparency =
        1


    Title.Text =
        "🎯 Test Control Panel"


    Title.TextColor3 =
        WHITE


    Title.TextSize =
        17


    Title.Font =
        Enum.Font.GothamBold


    Title.TextXAlignment =
        Enum.TextXAlignment.Left


    Title.Parent =
        TitleBar


    --====================================================
    -- MINIMIZAR
    --====================================================

    local Minimize =
        Instance.new("TextButton")


    Minimize.Size =
        UDim2.fromOffset(
            35,
            30
        )


    Minimize.Position =
        UDim2.new(
            1,
            -42,
            0,
            6
        )


    Minimize.BackgroundColor3 =
        BUTTON_COLOR


    Minimize.BorderColor3 =
        BLACK


    Minimize.BorderSizePixel =
        2


    Minimize.Text =
        "—"


    Minimize.TextColor3 =
        WHITE


    Minimize.TextSize =
        20


    Minimize.Parent =
        TitleBar


    Connect(
        Minimize.MouseButton1Click,
        function()

            Main.Visible =
                false

            MinimizedButton.Visible =
                true
        end
    )


    --====================================================
    -- DRAG
    --====================================================

    local dragging =
        false

    local dragStart
    local startPosition


    Connect(
        TitleBar.InputBegan,
        function(input)

            if input.UserInputType ==
                Enum.UserInputType.MouseButton1
            or input.UserInputType ==
                Enum.UserInputType.Touch then

                dragging =
                    true

                dragStart =
                    input.Position

                startPosition =
                    Main.Position
            end
        end
    )


    Connect(
        UserInputService.InputChanged,
        function(input)

            if not dragging then
                return
            end


            if input.UserInputType ==
                Enum.UserInputType.MouseMovement
            or input.UserInputType ==
                Enum.UserInputType.Touch then

                local delta =
                    input.Position -
                    dragStart


                Main.Position =
                    UDim2.new(

                        startPosition.X.Scale,

                        startPosition.X.Offset +
                        delta.X,

                        startPosition.Y.Scale,

                        startPosition.Y.Offset +
                        delta.Y
                    )
            end
        end
    )


    Connect(
        UserInputService.InputEnded,
        function(input)

            if input.UserInputType ==
                Enum.UserInputType.MouseButton1
            or input.UserInputType ==
                Enum.UserInputType.Touch then

                dragging =
                    false
            end
        end
    )


    --====================================================
    -- AIMBOT
    --====================================================

    local AimButton =
        CreateButton(
            Main,
            "🎯  Aimbot: OFF",
            UDim2.fromOffset(
                10,
                55
            )
        )


    Connect(
        AimButton.MouseButton1Click,
        function()

            AimbotEnabled =
                not AimbotEnabled


            if AimbotEnabled then

                AimButton.Text =
                    "🎯  Aimbot: ON"

                AimButton.BackgroundColor3 =
                    BUTTON_ACTIVE

            else

                AimButton.Text =
                    "🎯  Aimbot: OFF"

                AimButton.BackgroundColor3 =
                    BUTTON_COLOR
            end


            UpdateFOV()
        end
    )


    --====================================================
    -- TEAM CHECK
    --====================================================

    local TeamButton =
        CreateButton(
            Main,
            "👥  Team Check: ON",
            UDim2.fromOffset(
                10,
                100
            )
        )


    Connect(
        TeamButton.MouseButton1Click,
        function()

            TeamCheckEnabled =
                not TeamCheckEnabled


            if TeamCheckEnabled then

                TeamButton.Text =
                    "👥  Team Check: ON"

                TeamButton.BackgroundColor3 =
                    BUTTON_ACTIVE

            else

                TeamButton.Text =
                    "👥  Team Check: OFF"

                TeamButton.BackgroundColor3 =
                    BUTTON_COLOR
            end


            UpdateESP()
        end
    )


    --====================================================
    -- ESP
    --====================================================

    local ESPButton =
        CreateButton(
            Main,
            "👁️  ESP: OFF",
            UDim2.fromOffset(
                10,
                145
            )
        )


    Connect(
        ESPButton.MouseButton1Click,
        function()

            ESPEnabled =
                not ESPEnabled


            if ESPEnabled then

                ESPButton.Text =
                    "👁️  ESP: ON"

                ESPButton.BackgroundColor3 =
                    BUTTON_ACTIVE

            else

                ESPButton.Text =
                    "👁️  ESP: OFF"

                ESPButton.BackgroundColor3 =
                    BUTTON_COLOR
            end


            UpdateESP()
        end
    )


    --====================================================
    -- FOV LABEL
    --====================================================

    local FOVLabel =
        Instance.new("TextLabel")


    FOVLabel.Size =
        UDim2.new(
            1,
            -20,
            0,
            25
        )


    FOVLabel.Position =
        UDim2.fromOffset(
            10,
            195
        )


    FOVLabel.BackgroundTransparency =
        1


    FOVLabel.Text =
        "FOV: " ..
        tostring(FOVRadius)


    FOVLabel.TextColor3 =
        WHITE


    FOVLabel.TextSize =
        14


    FOVLabel.Font =
        Enum.Font.GothamMedium


    FOVLabel.TextXAlignment =
        Enum.TextXAlignment.Left


    FOVLabel.Parent =
        Main


    --====================================================
    -- FOV SLIDER
    --====================================================

    CreateSlider(
        Main,
        225,
        50,
        500,
        FOVRadius,

        function(value)

            FOVRadius =
                value


            FOVLabel.Text =
                "FOV: " ..
                tostring(value)


            UpdateFOV()
        end
    )


    --====================================================
    -- DISTÂNCIA
    --====================================================

    local DistanceLabel =
        Instance.new("TextLabel")


    DistanceLabel.Size =
        UDim2.new(
            1,
            -20,
            0,
            25
        )


    DistanceLabel.Position =
        UDim2.fromOffset(
            10,
            255
        )


    DistanceLabel.BackgroundTransparency =
        1


    DistanceLabel.Text =
        "Distância do Aimbot: " ..
        tostring(AimDistance) ..
        " studs"


    DistanceLabel.TextColor3 =
        WHITE


    DistanceLabel.TextSize =
        14


    DistanceLabel.Font =
        Enum.Font.GothamMedium


    DistanceLabel.TextXAlignment =
        Enum.TextXAlignment.Left


    DistanceLabel.Parent =
        Main


    --====================================================
    -- DISTÂNCIA SLIDER
    --====================================================

    CreateSlider(
        Main,
        285,
        50,
        2000,
        AimDistance,

        function(value)

            AimDistance =
                value


            DistanceLabel.Text =
                "Distância do Aimbot: " ..
                tostring(value) ..
                " studs"
        end
    )


    --====================================================
    -- RESET
    --====================================================

    local Reset =
        CreateButton(
            Main,
            "🔄  Reset Script",
            UDim2.fromOffset(
                10,
                325
            )
        )


    Connect(
        Reset.MouseButton1Click,
        function()

            ResetScript()

        end
    )


    --====================================================
    -- INFORMAÇÃO
    --====================================================

    local Info =
        Instance.new("TextLabel")


    Info.Size =
        UDim2.new(
            1,
            -20,
            0,
            45
        )


    Info.Position =
        UDim2.fromOffset(
            10,
            375
        )


    Info.BackgroundTransparency =
        1


    Info.Text =
        "Aliados: VERDE  |  Inimigos: VERMELHO\n" ..
        "Players: Player.Team  |  Bots: Model.Team"


    Info.TextColor3 =
        WHITE


    Info.TextSize =
        10


    Info.Font =
        Enum.Font.Gotham


    Info.TextXAlignment =
        Enum.TextXAlignment.Left


    Info.Parent =
        Main


    --====================================================
    -- MINIMIZADO
    --====================================================

    CreateMinimizedButton()


    --====================================================
    -- FOV
    --====================================================

    CreateFOVCircle()


    --====================================================
    -- RENDER
    --====================================================

    Connect(
        RunService.RenderStepped,
        function()

            UpdateFOV()


            if AimbotEnabled then

                local target =
                    GetTarget()


                if target then

                    AimAtTarget(
                        target
                    )
                end
            end


            local now =
                os.clock()


            if ESPEnabled
            and now - LastESPUpdate >=
                ESP_UPDATE_INTERVAL then

                LastESPUpdate =
                    now

                UpdateESP()
            end
        end
    )


    --====================================================
    -- PLAYER ADDED
    --====================================================

    Connect(
        Players.PlayerAdded,
        function(player)

            Connect(
                player.CharacterAdded,
                function()

                    task.wait(0.15)


                    if ESPEnabled then
                        UpdateESP()
                    end
                end
            )
        end
    )


    --====================================================
    -- PLAYER REMOVING
    --====================================================

    Connect(
        Players.PlayerRemoving,
        function(player)

            if player.Character then

                RemoveESP(
                    player.Character
                )
            end
        end
    )


    --====================================================
    -- NOVOS OBJETOS
    --
    -- Não tentamos classificar imediatamente qualquer
    -- Model. O UpdateESP fará a validação completa:
    --
    -- Model
    -- + Humanoid
    -- + HumanoidRootPart
    -- + Team válido
    --====================================================

    Connect(
        workspace.DescendantAdded,
        function(object)

            if not ESPEnabled then
                return
            end


            if object:IsA("Model") then

                task.defer(
                    function()

                        task.wait(
                            0.05
                        )


                        UpdateESP()
                    end
                )
            end
        end
    )


    --====================================================
    -- MUDANÇA DE TIME DO PLAYER
    --====================================================

    Connect(
        LocalPlayer:GetPropertyChangedSignal(
            "Team"
        ),
        function()

            task.wait(0.1)


            if ESPEnabled then
                UpdateESP()
            end
        end
    )


    --====================================================
    -- MUDANÇA DO ATRIBUTO TEAM DO PLAYER
    --====================================================

    Connect(
        LocalPlayer:GetAttributeChangedSignal(
            "Team"
        ),
        function()

            task.wait(0.1)


            if ESPEnabled then
                UpdateESP()
            end
        end
    )


    --====================================================
    -- RESPAWN LOCAL
    --====================================================

    Connect(
        LocalPlayer.CharacterAdded,
        function()

            task.wait(0.2)


            if ESPEnabled then
                UpdateESP()
            end
        end
    )


    --====================================================
    -- MONITORAMENTO AUTOMÁTICO
    --====================================================

    task.spawn(
        function()

            while Gui
            and Gui.Parent do

                if ESPEnabled then

                    UpdateESP()

                end

                task.wait(
                    ESP_UPDATE_INTERVAL
                )
            end
        end
    )


    CreatingInterface =
        false
end


--========================================================
-- START
--========================================================

CreateInterface()
