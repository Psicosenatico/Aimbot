--========================================================
-- TEST CONTROL PANEL
-- ESP + AIMBOT
-- Para uso no seu próprio jogo no Roblox Studio
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

local ALLY_COLOR =
    Color3.fromRGB(0, 255, 90)

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

    if not name then
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

    if not player.Team then
        return nil
    end

    return NormalizeTeamName(
        player.Team.Name
    )
end


local function GetLocalTeam()

    return GetPlayerTeam(
        LocalPlayer
    )
end


--========================================================
-- PASTAS DOS TIMES
--========================================================

local function GetArmyFolder()

    return workspace:FindFirstChild(
        "Army"
    )
end


local function GetRebelsFolder()

    return workspace:FindFirstChild(
        "Rebels"
    )
end


--========================================================
-- ENCONTRAR MODELO DE PERSONAGEM
--========================================================

local function FindCharacterModel(object)

    if not object then
        return nil
    end


    local current = object


    while current
    and current ~= workspace do

        if current:IsA("Model") then

            local humanoid =
                current:FindFirstChildOfClass(
                    "Humanoid"
                )

            local root =
                current:FindFirstChild(
                    "HumanoidRootPart"
                )


            if humanoid
            and root then

                return current
            end
        end


        current =
            current.Parent
    end


    return nil
end


--========================================================
-- VERIFICAR SE É MANEQUIM ESTÁTICO
--========================================================

local function IsStaticDummy(character)

    if not character then
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

        return true
    end


    local hasUnanchoredPart = false


    for _, object in ipairs(
        character:GetDescendants()
    ) do

        if object:IsA("BasePart") then

            if not object.Anchored then

                hasUnanchoredPart = true

                break
            end
        end
    end


    if not hasUnanchoredPart then
        return true
    end


    return false
end


--========================================================
-- IDENTIFICAR BOT
--========================================================

local function GetBotTeam(character)

    if not character then
        return nil
    end


    local armyFolder =
        GetArmyFolder()


    if armyFolder
    and character:IsDescendantOf(
        armyFolder
    ) then

        return "Army"
    end


    local rebelsFolder =
        GetRebelsFolder()


    if rebelsFolder
    and character:IsDescendantOf(
        rebelsFolder
    ) then

        return "Rebels"
    end


    return nil
end


--========================================================
-- TIME DO PERSONAGEM
--========================================================

local function GetCharacterTeam(character)

    if not character then
        return nil
    end


    local player =
        Players:GetPlayerFromCharacter(
            character
        )


    --====================================================
    -- PLAYER
    --====================================================

    if player then

        return GetPlayerTeam(
            player
        )
    end


    --====================================================
    -- BOT
    --====================================================

    if IsStaticDummy(character) then
        return nil
    end


    return GetBotTeam(
        character
    )
end


--========================================================
-- É PERSONAGEM VÁLIDO?
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


    local player =
        Players:GetPlayerFromCharacter(
            character
        )


    if not player then

        if IsStaticDummy(
            character
        ) then

            return false
        end
    end


    return true
end


--========================================================
-- ALIADO
--========================================================

local function IsAllyCharacter(character)

    if not IsValidCharacter(
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

    if not IsValidCharacter(
        character
    ) then

        return false
    end


    if character ==
        LocalPlayer.Character then

        return false
    end


    local characterTeam =
        GetCharacterTeam(
            character
        )


    if not characterTeam then
        return false
    end


    if not TeamCheckEnabled then
        return true
    end


    local localTeam =
        GetLocalTeam()


    if not localTeam then
        return false
    end


    return characterTeam ~=
        localTeam
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

    if not IsValidCharacter(
        character
    ) then

        return
    end


    local highlight =
        ESPObjects[character]


    if not highlight then

        highlight =
            Instance.new("Highlight")


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
            character


        ESPObjects[character] =
            highlight
    end


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
-- OBTER TODOS OS PERSONAGENS
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

        if player.Character
        and not alreadyAdded[
            player.Character
        ] then

            local character =
                player.Character


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
    -- BOTS DO ARMY
    --====================================================

    local armyFolder =
        GetArmyFolder()


    if armyFolder then

        for _, object in ipairs(
            armyFolder:GetDescendants()
        ) do

            if object:IsA("Model") then

                local character =
                    FindCharacterModel(
                        object
                    )


                if character
                and character:IsDescendantOf(
                    armyFolder
                )
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
        end
    end


    --====================================================
    -- BOTS DOS REBELS
    --====================================================

    local rebelsFolder =
        GetRebelsFolder()


    if rebelsFolder then

        for _, object in ipairs(
            rebelsFolder:GetDescendants()
        ) do

            if object:IsA("Model") then

                local character =
                    FindCharacterModel(
                        object
                    )


                if character
                and character:IsDescendantOf(
                    rebelsFolder
                )
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
        end
    end


    return characters
end


--========================================================
-- ATUALIZAR ESP
--========================================================

local function UpdateESP()

    if not ESPEnabled then

        for character, highlight in pairs(
            ESPObjects
        ) do

            if highlight then
                highlight:Destroy()
            end

            ESPObjects[character] =
                nil
        end

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

                ApplyESP(
                    character,
                    true
                )


            elseif IsAllyCharacter(
                character
            ) then

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


    for character, highlight in pairs(
        ESPObjects
    ) do

        if not validCharacters[
            character
        ] then

            if highlight then
                highlight:Destroy()
            end

            ESPObjects[character] =
                nil
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
-- TARGET SELECTION
-- MAIS PRÓXIMO DENTRO DO FOV
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
-- MINIMIZAR
--========================================================

local function CreateMinimizedButton()

    MinimizedButton =
        Instance.new("TextButton")


    MinimizedButton.Name =
        "MinimizedButton"


    MinimizedButton.Size =
        UDim2.fromOffset(
            55,
            55
        )


    --====================================================
    -- CENTRALIZAÇÃO DO BOTÃO FLUTUANTE
    --====================================================

    MinimizedButton.AnchorPoint =
        Vector2.new(
            0.5,
            0.5
        )


    MinimizedButton.Position =
        UDim2.fromScale(
            0.5,
            0.5
        )


    --====================================================
    -- ESCUDO
    --====================================================

    MinimizedButton.Text =
        "🛡️"


    MinimizedButton.TextColor3 =
        WHITE


    MinimizedButton.TextSize =
        26


    MinimizedButton.TextXAlignment =
        Enum.TextXAlignment.Center


    MinimizedButton.TextYAlignment =
        Enum.TextYAlignment.Center


    MinimizedButton.TextWrapped =
        false


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
    -- RESTAURAR
    --====================================================

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
    -- ARRASTAR
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


    for character, highlight in pairs(
        ESPObjects
    ) do

        if highlight then
            highlight:Destroy()
        end

        ESPObjects[character] =
            nil
    end


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
    -- DISTÂNCIA LABEL
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
    -- INFO
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
        "Bots: Army / Rebels  |  Manequins estáticos: ignorados"


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
    -- OBJETOS NOVOS
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

                        local character =
                            FindCharacterModel(
                                object
                            )


                        if character then

                            task.wait(
                                0.05
                            )


                            UpdateESP()
                        end
                    end
                )
            end
        end
    )


    --====================================================
    -- MUDANÇA DE TIME
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
    -- MUDANÇA DE PASTAS / BOTS
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

CreateInterface()--========================================================
-- TEST CONTROL PANEL
-- ESP + AIMBOT
-- Para uso no seu próprio jogo no Roblox Studio
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

local ALLY_COLOR =
    Color3.fromRGB(0, 255, 90)

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

    if not name then
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

    if not player.Team then
        return nil
    end

    return NormalizeTeamName(
        player.Team.Name
    )
end


local function GetLocalTeam()

    return GetPlayerTeam(
        LocalPlayer
    )
end


--========================================================
-- PASTAS DOS TIMES
--========================================================

local function GetArmyFolder()

    return workspace:FindFirstChild(
        "Army"
    )
end


local function GetRebelsFolder()

    return workspace:FindFirstChild(
        "Rebels"
    )
end


--========================================================
-- ENCONTRAR MODELO DE PERSONAGEM
--========================================================

local function FindCharacterModel(object)

    if not object then
        return nil
    end


    local current = object


    while current
    and current ~= workspace do

        if current:IsA("Model") then

            local humanoid =
                current:FindFirstChildOfClass(
                    "Humanoid"
                )

            local root =
                current:FindFirstChild(
                    "HumanoidRootPart"
                )


            if humanoid
            and root then

                return current
            end
        end


        current =
            current.Parent
    end


    return nil
end


--========================================================
-- VERIFICAR SE É MANEQUIM ESTÁTICO
--========================================================

local function IsStaticDummy(character)

    if not character then
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

        return true
    end


    local hasUnanchoredPart = false


    for _, object in ipairs(
        character:GetDescendants()
    ) do

        if object:IsA("BasePart") then

            if not object.Anchored then

                hasUnanchoredPart = true

                break
            end
        end
    end


    if not hasUnanchoredPart then
        return true
    end


    return false
end


--========================================================
-- IDENTIFICAR BOT
--========================================================

local function GetBotTeam(character)

    if not character then
        return nil
    end


    local armyFolder =
        GetArmyFolder()


    if armyFolder
    and character:IsDescendantOf(
        armyFolder
    ) then

        return "Army"
    end


    local rebelsFolder =
        GetRebelsFolder()


    if rebelsFolder
    and character:IsDescendantOf(
        rebelsFolder
    ) then

        return "Rebels"
    end


    return nil
end


--========================================================
-- TIME DO PERSONAGEM
--========================================================

local function GetCharacterTeam(character)

    if not character then
        return nil
    end


    local player =
        Players:GetPlayerFromCharacter(
            character
        )


    --====================================================
    -- PLAYER
    --====================================================

    if player then

        return GetPlayerTeam(
            player
        )
    end


    --====================================================
    -- BOT
    --====================================================

    if IsStaticDummy(character) then
        return nil
    end


    return GetBotTeam(
        character
    )
end


--========================================================
-- É PERSONAGEM VÁLIDO?
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


    local player =
        Players:GetPlayerFromCharacter(
            character
        )


    if not player then

        if IsStaticDummy(
            character
        ) then

            return false
        end
    end


    return true
end


--========================================================
-- ALIADO
--========================================================

local function IsAllyCharacter(character)

    if not IsValidCharacter(
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

    if not IsValidCharacter(
        character
    ) then

        return false
    end


    if character ==
        LocalPlayer.Character then

        return false
    end


    local characterTeam =
        GetCharacterTeam(
            character
        )


    if not characterTeam then
        return false
    end


    if not TeamCheckEnabled then
        return true
    end


    local localTeam =
        GetLocalTeam()


    if not localTeam then
        return false
    end


    return characterTeam ~=
        localTeam
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

    if not IsValidCharacter(
        character
    ) then

        return
    end


    local highlight =
        ESPObjects[character]


    if not highlight then

        highlight =
            Instance.new("Highlight")


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
            character


        ESPObjects[character] =
            highlight
    end


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
-- OBTER TODOS OS PERSONAGENS
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

        if player.Character
        and not alreadyAdded[
            player.Character
        ] then

            local character =
                player.Character


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
    -- BOTS DO ARMY
    --====================================================

    local armyFolder =
        GetArmyFolder()


    if armyFolder then

        for _, object in ipairs(
            armyFolder:GetDescendants()
        ) do

            if object:IsA("Model") then

                local character =
                    FindCharacterModel(
                        object
                    )


                if character
                and character:IsDescendantOf(
                    armyFolder
                )
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
        end
    end


    --====================================================
    -- BOTS DOS REBELS
    --====================================================

    local rebelsFolder =
        GetRebelsFolder()


    if rebelsFolder then

        for _, object in ipairs(
            rebelsFolder:GetDescendants()
        ) do

            if object:IsA("Model") then

                local character =
                    FindCharacterModel(
                        object
                    )


                if character
                and character:IsDescendantOf(
                    rebelsFolder
                )
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
        end
    end


    return characters
end


--========================================================
-- ATUALIZAR ESP
--========================================================

local function UpdateESP()

    if not ESPEnabled then

        for character, highlight in pairs(
            ESPObjects
        ) do

            if highlight then
                highlight:Destroy()
            end

            ESPObjects[character] =
                nil
        end

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

                ApplyESP(
                    character,
                    true
                )


            elseif IsAllyCharacter(
                character
            ) then

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


    for character, highlight in pairs(
        ESPObjects
    ) do

        if not validCharacters[
            character
        ] then

            if highlight then
                highlight:Destroy()
            end

            ESPObjects[character] =
                nil
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
-- TARGET SELECTION
-- MAIS PRÓXIMO DENTRO DO FOV
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
-- MINIMIZAR
--========================================================

local function CreateMinimizedButton()

    MinimizedButton =
        Instance.new("TextButton")


    MinimizedButton.Name =
        "MinimizedButton"


    MinimizedButton.Size =
        UDim2.fromOffset(
            55,
            55
        )


    --====================================================
    -- CENTRALIZAÇÃO DO BOTÃO FLUTUANTE
    --====================================================

    MinimizedButton.AnchorPoint =
        Vector2.new(
            0.5,
            0.5
        )


    MinimizedButton.Position =
        UDim2.fromScale(
            0.5,
            0.5
        )


    --====================================================
    -- ESCUDO
    --====================================================

    MinimizedButton.Text =
        "🛡️"


    MinimizedButton.TextColor3 =
        WHITE


    MinimizedButton.TextSize =
        26


    MinimizedButton.TextXAlignment =
        Enum.TextXAlignment.Center


    MinimizedButton.TextYAlignment =
        Enum.TextYAlignment.Center


    MinimizedButton.TextWrapped =
        false


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
    -- RESTAURAR
    --====================================================

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
    -- ARRASTAR
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


    for character, highlight in pairs(
        ESPObjects
    ) do

        if highlight then
            highlight:Destroy()
        end

        ESPObjects[character] =
            nil
    end


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
    -- DISTÂNCIA LABEL
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
    -- INFO
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
        "Bots: Army / Rebels  |  Manequins estáticos: ignorados"


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
    -- OBJETOS NOVOS
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

                        local character =
                            FindCharacterModel(
                                object
                            )


                        if character then

                            task.wait(
                                0.05
                            )


                            UpdateESP()
                        end
                    end
                )
            end
        end
    )


    --====================================================
    -- MUDANÇA DE TIME
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
    -- MUDANÇA DE PASTAS / BOTS
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
