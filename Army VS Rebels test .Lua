local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local GUI_NAME = "TestControlPanel"

local Connections = {}
local ESPObjects = {}
local NativeBotHighlightStates = setmetatable({}, {__mode = "k"})

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

local AutoBuyCore = nil
local AutoBuyLoadedByMenu = false
local AutoBuyEnabled = false
local AutoBuyToggleButton = nil


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

    for _, connection in ipairs(Connections) do

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
-- NORMALIZAÇÃO DO TIME
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
--
-- NÃO ALTERAR A LÓGICA DOS PLAYERS.
--========================================================

local function GetPlayerTeam(player)

    if not player then
        return nil
    end

    if player.Team then

        local team =
            NormalizeTeamName(
                player.Team.Name
            )

        if team then
            return team
        end
    end

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
-- DETECTAR BOT
--
-- FONTE VALIDADA PELO ESP RESEARCH V1.1:
--     Workspace.Soldiers
--     Model:GetAttribute("Team")
--
-- O HumanoidRootPart NÃO é obrigatório para reconhecer
-- o bot. Ele pode chegar alguns segundos depois.
--========================================================

local function IsBot(character)

    if not character
    or not character:IsA("Model") then
        return false
    end

    -- Nunca classificar Player como bot.
    if Players:GetPlayerFromCharacter(character) then
        return false
    end

    local soldiers =
        workspace:FindFirstChild("Soldiers")

    if not soldiers
    or character.Parent ~= soldiers then
        return false
    end

    local humanoid =
        character:FindFirstChildOfClass("Humanoid")

    if not humanoid
    or humanoid.Health <= 0 then
        return false
    end

    return true
end


--========================================================
-- LOCALIZAR TIME DO BOT
--
-- Fonte principal validada:
--     Attribute.Team
--
-- Fallbacks leves são mantidos apenas por compatibilidade.
--========================================================

local function GetBotTeam(character)

    if not IsBot(character) then
        return nil
    end

    local normalized =
        NormalizeTeamName(
            character:GetAttribute("Team")
        )

    if normalized then
        return normalized
    end

    local teamValue =
        character:FindFirstChild("Team")

    if teamValue then

        if teamValue:IsA("StringValue") then
            return NormalizeTeamName(teamValue.Value)
        end

        if teamValue:IsA("ObjectValue")
        and teamValue.Value then
            return NormalizeTeamName(teamValue.Value.Name)
        end
    end

    return nil
end


--========================================================
-- PERSONAGEM VÁLIDO
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
-- TIME DO PERSONAGEM
--
-- PLAYER:
--     Player.Team
--
-- BOT:
--     Model.Team
--     Patrol Point auxiliar
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

    if IsBot(character) then

        return GetBotTeam(
            character
        )
    end


    return nil
end


--========================================================
-- PERSONAGEM DE ESP
--
-- Players preservam a validação original.
-- Bots usam a detecção validada do V1.1 e não dependem
-- da chegada imediata do HumanoidRootPart.
--========================================================

local function IsESPCharacter(character)

    if not character
    or not character:IsA("Model") then
        return false
    end

    local player =
        Players:GetPlayerFromCharacter(character)

    if player then
        return IsValidCharacter(character)
    end

    return IsBot(character)
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


    return characterTeam ~=
        localTeam
end


--========================================================
-- HIGHLIGHT NATIVO DOS BOTS
--
-- O Highlight original do jogo serve apenas como sinal
-- auxiliar. Enquanto o nosso ESP estiver ativo, ele é
-- suprimido para não disputar cor com o PsicoESP.
-- Ao remover/desligar o ESP, o estado original é restaurado.
--========================================================

local function SuppressNativeBotHighlights(character)

    if not IsBot(character) then
        return
    end

    for _, object in ipairs(character:GetDescendants()) do

        if object:IsA("Highlight") then

            if NativeBotHighlightStates[object] == nil then
                NativeBotHighlightStates[object] = object.Enabled
            end

            object.Enabled = false
        end
    end
end


local function RestoreNativeBotHighlights(character)

    if not character then
        return
    end

    for highlight, originalEnabled in pairs(
        NativeBotHighlightStates
    ) do

        if highlight
        and highlight.Parent
        and highlight:IsDescendantOf(character) then

            highlight.Enabled = originalEnabled
            NativeBotHighlightStates[highlight] = nil
        end
    end
end


--========================================================
-- REMOVER ESP
--========================================================

local function RemoveESP(character)

    local highlight =
        ESPObjects[character]

    if highlight then
        highlight:Destroy()
        ESPObjects[character] = nil
    end

    if IsBot(character) then
        RestoreNativeBotHighlights(character)
    end
end


--========================================================
-- APLICAR ESP
--
-- PLAYERS:
--     Mantém o comportamento original.
--
-- BOTS:
--     ALLY  = PsicoESP_Ally  / verde
--     ENEMY = PsicoESP_Enemy / vermelho
--     Highlight nativo suprimido enquanto ativo.
--========================================================

local function ApplyESP(
    character,
    enemy
)

    if not IsESPCharacter(character) then
        return
    end

    local isBot =
        IsBot(character)

    if isBot then
        SuppressNativeBotHighlights(character)
    end

    local highlight =
        ESPObjects[character]

    if not highlight then

        highlight =
            Instance.new("Highlight")

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

    -- Players continuam com o nome original.
    -- Bots usam os nomes validados no ESP Research V1.1.
    if isBot then

        if enemy then
            highlight.Name = "PsicoESP_Enemy"
        else
            highlight.Name = "PsicoESP_Ally"
        end

    else
        highlight.Name = "TestESP"
    end

    -- Nossa cor é independente da cor nativa do jogo.
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
-- PEGAR TODOS OS BOTS
--
-- Fonte única validada:
--     filhos diretos de Workspace.Soldiers
--
-- Removidos:
--     varredura global do Workspace
--     BotPatrolPoints
--     GetDescendants() global
--========================================================

local function GetAllBots()

    local bots = {}

    local soldiers =
        workspace:FindFirstChild("Soldiers")

    if not soldiers then
        return bots
    end

    for _, object in ipairs(
        soldiers:GetChildren()
    ) do

        if IsBot(object) then
            table.insert(bots, object)
        end
    end

    return bots
end


--========================================================
-- TODOS OS PERSONAGENS
--========================================================

local function GetAllCharacters()

    local characters = {}
    local added = {}


    --====================================================
    -- PLAYERS
    --====================================================

    for _, player in ipairs(
        Players:GetPlayers()
    ) do

        local character =
            player.Character


        if character
        and not added[character]
        and IsValidCharacter(character) then

            added[character] =
                true

            table.insert(
                characters,
                character
            )
        end
    end


    --====================================================
    -- BOTS
    --====================================================

    for _, bot in ipairs(
        GetAllBots()
    ) do

        if not added[bot] then

            added[bot] =
                true

            table.insert(
                characters,
                bot
            )
        end
    end


    return characters
end


--========================================================
-- LIMPAR ESP
--========================================================

local function ClearAllESP()

    for character, highlight in pairs(
        ESPObjects
    ) do

        if highlight then
            highlight:Destroy()
        end

        ESPObjects[character] = nil

        if IsBot(character) then
            RestoreNativeBotHighlights(character)
        end
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

                -- INIMIGO

                ApplyESP(
                    character,
                    true
                )


            elseif IsAllyCharacter(
                character
            ) then

                -- ALIADO

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
    -- REMOVER ESP DE OBJETOS QUE SUMIRAM
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


    local bestTarget = nil
    local closestWorldDistance = math.huge


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
                            camera.CFrame.Position -
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

local JOKER_ICON_B64 = [[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]]

local function DecodeBase64(data)

    local alphabet =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

    data = string.gsub(
        data,
        "[^" .. alphabet .. "=]",
        ""
    )

    return (
        data:gsub(
            ".",
            function(character)

                if character == "=" then
                    return ""
                end

                local value =
                    string.find(
                        alphabet,
                        character,
                        1,
                        true
                    ) - 1

                local bits = ""

                for index = 6, 1, -1 do

                    bits =
                        bits ..
                        (
                            value % (2 ^ index) -
                            value % (2 ^ (index - 1)) > 0
                            and "1"
                            or "0"
                        )
                end

                return bits
            end
        ):gsub(
            "%d%d%d?%d?%d?%d?%d?%d?",
            function(bits)

                if #bits ~= 8 then
                    return ""
                end

                local value = 0

                for index = 1, 8 do

                    if string.sub(bits, index, index) == "1" then
                        value = value + 2 ^ (8 - index)
                    end
                end

                return string.char(value)
            end
        )
    )
end

local function GetJokerIconAsset()

    local assetFunction = nil

    if type(getcustomasset) == "function" then
        assetFunction = getcustomasset
    elseif type(getsynasset) == "function" then
        assetFunction = getsynasset
    end

    if not assetFunction
    or type(writefile) ~= "function" then
        return nil
    end

    local fileName =
        "Psicosenatico_Joker_Icon.png"

    local ok = pcall(
        function()

            local shouldWrite = true

            if type(isfile) == "function" then
                shouldWrite = not isfile(fileName)
            end

            if shouldWrite then
                writefile(
                    fileName,
                    DecodeBase64(JOKER_ICON_B64)
                )
            end
        end
    )

    if not ok then
        return nil
    end

    local assetOk, asset = pcall(
        function()
            return assetFunction(fileName)
        end
    )

    if assetOk then
        return asset
    end

    return nil
end

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


    MinimizedButton.AutoButtonColor =
        false


    MinimizedButton.BackgroundColor3 =
        BLACK


    MinimizedButton.BorderColor3 =
        BLACK


    MinimizedButton.BorderSizePixel =
        3


    MinimizedButton.ClipsDescendants =
        true


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


    local avatarHolder =
        Instance.new("Frame")


    avatarHolder.Name =
        "AvatarHolder"


    avatarHolder.Size =
        UDim2.new(
            1,
            -6,
            1,
            -6
        )


    avatarHolder.Position =
        UDim2.fromOffset(
            3,
            3
        )


    avatarHolder.BackgroundTransparency =
        1


    avatarHolder.BorderSizePixel =
        0


    avatarHolder.ClipsDescendants =
        true


    avatarHolder.Parent =
        MinimizedButton


    local avatarCorner =
        Instance.new("UICorner")


    avatarCorner.CornerRadius =
        UDim.new(
            1,
            0
        )


    avatarCorner.Parent =
        avatarHolder


    --====================================================
    -- ROSTO DO PALHAÇO / CORINGA
    --
    -- Preenche praticamente toda a área interna do botão
    -- flutuante para evitar a borda azul entre a imagem
    -- e a borda externa circular.
    --====================================================

    local jokerAsset =
        GetJokerIconAsset()


    if jokerAsset then

        local JokerImage =
            Instance.new("ImageLabel")


        JokerImage.Name =
            "JokerFace"


        JokerImage.Size =
            UDim2.new(
                1,
                0,
                1,
                0
            )


        JokerImage.AnchorPoint =
            Vector2.new(
                0,
                0
            )


        JokerImage.Position =
            UDim2.fromOffset(
                0,
                0
            )


        JokerImage.BackgroundTransparency =
            1


        JokerImage.BorderSizePixel =
            0


        JokerImage.Image =
            jokerAsset


        JokerImage.ScaleType =
            Enum.ScaleType.Fit


        JokerImage.ClipsDescendants =
            true


        JokerImage.Parent =
            avatarHolder


        local imageCorner =
            Instance.new("UICorner")


        imageCorner.CornerRadius =
            UDim.new(
                1,
                0
            )


        imageCorner.Parent =
            JokerImage

    else

        local JokerFallback =
            Instance.new("TextLabel")


        JokerFallback.Name =
            "JokerFaceFallback"


        JokerFallback.Size =
            UDim2.fromScale(
                0.88,
                0.88
            )


        JokerFallback.AnchorPoint =
            Vector2.new(
                0.5,
                0.5
            )


        JokerFallback.Position =
            UDim2.fromScale(
                0.5,
                0.5
            )


        JokerFallback.BackgroundTransparency =
            1


        JokerFallback.BorderSizePixel =
            0


        JokerFallback.Text =
            "🤡"


        JokerFallback.TextColor3 =
            WHITE


        JokerFallback.TextScaled =
            true


        JokerFallback.Font =
            Enum.Font.GothamBold


        JokerFallback.Parent =
            avatarHolder
    end


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

    local dragging = false
    local dragStart
    local startPosition


    Connect(
        MinimizedButton.InputBegan,
        function(input)

            if input.UserInputType ==
                Enum.UserInputType.MouseButton1
            or input.UserInputType ==
                Enum.UserInputType.Touch then

                dragging = true

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

                dragging = false
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


    local dragging = false


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

                dragging = true

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

                dragging = false
            end
        end
    )
end


--========================================================
-- AUTO BUY CORE INTEGRATION
--========================================================

local AUTO_BUY_CORE_SOURCE = [==[--[[
Psicosenatico Tycoon Auto Buy Core
Source logic: AUTO-TP-1.7.5.11
Purpose: standalone/importable Auto Buy engine without the original menu UI,
export system or AutoSave layer.

Integration:
    local AutoBuy = loadstring(game:HttpGet("RAW_URL"))()
    AutoBuy.Start()
    AutoBuy.Stop()
    AutoBuy.Toggle()

The same API is also exposed as:
    getgenv().PsicoTycoonAutoBuy
(or _G.PsicoTycoonAutoBuy when getgenv is unavailable)

Important:
- Automation starts OFF.
- Start() enables the same purchase/Collector/Bunker/Auto Rebirth flow
  validated in V1.7.5.11.
- Reloading this core shuts down an older loaded copy first, preventing
  duplicate automation loops and duplicated event connections.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VirtualInputManager = nil
pcall(function()
    VirtualInputManager = game:GetService("VirtualInputManager")
end)

local CORE_VERSION = "AUTO-BUY-CORE-1.7.5.11"
local SOURCE_VERSION = "AUTO-TP-1.7.5.11"
local MAX_AUX_EVENTS = 2000
local MONEY_INTERVAL = 0.25
local TYCOON_INTERVAL = 1.5
local CORRELATION_WINDOW = 4
local UNLOCK_WINDOW = 3.5

local ENV = _G
pcall(function()
    if type(getgenv) == "function" then
        ENV = getgenv()
    end
end)

if type(ENV.PsicoTycoonAutoBuy) == "table"
and type(ENV.PsicoTycoonAutoBuy.Shutdown) == "function" then
    pcall(function()
        ENV.PsicoTycoonAutoBuy.Shutdown("RELOAD")
    end)
end

local State = {
    Running = true,
    Reading = false,
    ReadingSessions = {},
    CurrentReadingSession = nil,
    StartedUnix = os.time(),
    StartedClock = os.clock(),
    Player = nil,
    Tycoon = nil,
    TycoonScore = 0,
    ButtonsFolder = nil,
    PurchasesFolder = nil,
    CurrentZone = "UNKNOWN",
    ZoneEvidence = "not evaluated",
    MainFloor = 1,
    ZoneTransitions = {},
    FloorTransitions = {},
    StageUnlocks = {},
    StageUnlockSeen = {},
    LastTransitionPrompt = nil,
    WatchedTransitionPrompts = setmetatable({}, {__mode = "k"}),
    MoneyObject = nil,
    MoneySourceKind = nil,
    MoneySourceEvidence = nil,
    MoneyCandidates = {},
    LastMoneyDiscoveryClock = 0,
    LastMoney = nil,
    RebirthObject = nil,
    LastRebirths = nil,
    InitialButtons = {},
    InitialPurchases = {},
    ButtonCache = {},
    Pending = {},
    Transactions = {},
    Events = {},
    CriticalEvents = {},
    Errors = {},
    ErrorRepeats = {},

    AutomationEnabled = false,
    AutomationState = "OFF",
    AutomationTarget = nil,
    AutomationTargetStarted = nil,
    AutomationAttempts = {},
    AutomationResets = {},
    AutomationCooldowns = {},
    AutomationBlockedFunds = {},
    AutomationServerSignal = nil,
    AutomationServerSignalSeq = 0,
    AutomationLastRebirth = nil,
    AutomationRunId = 0,
    AutomationSuccessful = 0,
    AutomationFailed = 0,

    TotemCollectAttempts = {},
    TotemCollectSuccessful = 0,
    TotemCollectFailed = 0,
    LastTotemCollectClock = 0,
    IdleCollectChecks = 0,
    IdleCollectTriggers = 0,

    BunkerTransitionLog = {},
    BunkerRescans = 0,
    BunkerSessionActive = false,
    BunkerSessionId = 0,
    BunkerSessionStartedUnix = nil,
    BunkerSessionStartedElapsed = nil,
    BunkerSessionReason = nil,
    BunkerEnterInProgress = false,
    BunkerEnterCooldownUntil = 0,
    BunkerExitInProgress = false,
    BunkerSuppressedMainDetections = 0,
    BunkerLastTransitionEvidence = nil,
    BunkerEnterPromptObservedClock = 0,
    BunkerExitPromptObservedClock = 0,
    BunkerManualEnterCount = 0,
    BunkerManualExitCount = 0,
    BunkerCollectorExitAttempts = 0,
    BunkerCollectorExitSuccessful = 0,
    BunkerCollectorExitFailed = 0,
    BunkerExitOnlyTeleportAttempts = 0,
    BunkerMainTeleportBlocks = 0,
    BunkerExitSettleUntil = 0,
    BunkerExitRetryUntil = 0,
    BunkerExitFailureCount = 0,
    BunkerPhysicalReconciliations = 0,
    BunkerLastRawPhysicalZone = "UNKNOWN",
    BunkerLastRawPhysicalEvidence = nil,
    BunkerLastCompletedSessionId = 0,
    BunkerTransitionFreezeActive = false,
    BunkerTransitionFreezeDirection = nil,
    BunkerTransitionFreezeStartedClock = 0,
    BunkerTransitionFreezeReason = nil,
    BunkerTransitionFreezeCount = 0,
    BunkerTransitionFreezeReleased = 0,
    BunkerTransitionOriginPosition = nil,
    BunkerTransitionSourcePart = nil,
    BunkerTransitionSourcePath = nil,
    BunkerTransitionLastDisplacement = 0,
    BunkerTransitionConfirmMode = nil,

    AutoRebirthServerReady = false,
    AutoRebirthServerSignalSeen = false,
    AutoRebirthButtonsLeft = nil,
    AutoRebirthLastSignalUnix = nil,
    AutoRebirthLastSignalElapsed = nil,
    AutoRebirthLastSignalValue = nil,
    AutoRebirthAttempts = {},
    AutoRebirthSuccessful = 0,
    AutoRebirthFailed = 0,
    AutoRebirthLastAttemptClock = 0,
    AutoRebirthLastMethod = nil,

    MovementSafeTeleportAttempts = 0,
    MovementSafeTeleportConfirmed = 0,
    MovementUnsafeDestinationRejected = 0,
    MovementRecoveryAttempts = 0,
    MovementRecoverySuccessful = 0,
    MovementCharacterLosses = 0,
    MovementLastSafeCFrame = nil,
    MovementLastSafeUnix = nil,
    MovementLastSafeReason = nil,
    MovementCharacter = nil,

    DataStats = {
        TotalEventsObserved = 0,
        AuxiliaryEventsStored = 0,
        AuxiliaryEventsDiscarded = 0,
        CriticalEventsStored = 0,
        TransactionsStored = 0,
        TransactionDataDiscarded = 0,
    },

    Connections = {},
    TycoonConnections = {},
    Health = {
        Bootstrap = "STARTING",
        Tycoon = "SEARCHING",
        Money = "SEARCHING",
        Rebirths = "SEARCHING",
        Engine = "STARTING",
        Reading = "PAUSED",
        Automation = "OFF",
        Zone = "UNKNOWN",
        Floor = "1",
    },
}


local function elapsed()
    return math.floor((os.clock() - State.StartedClock) * 1000) / 1000
end
local function clockText()
    return os.date("%H:%M:%S")
end
local function normalize(value)
    return string.lower(tostring(value or "")):gsub("[%s_%-%./]", "")
end
local function safeFullName(inst)
    if not inst then
        return "<nil>"
    end
    local ok, result = pcall(function()
        return inst:GetFullName()
    end)
    if ok then
        return result
    end
    return "<detached>"
end
local function getAttributes(inst)
    if not inst then
        return {}
    end
    local ok, attrs = pcall(function()
        return inst:GetAttributes()
    end)
    if not ok or type(attrs) ~= "table" then
        return {}
    end
    local result = {}
    for key, value in pairs(attrs) do
        result[tostring(key)] = tostring(value)
    end
    return result
end
local function attrCI(inst, wanted)
    local wantedNorm = normalize(wanted)
    local attrs = getAttributes(inst)
    for key, value in pairs(attrs) do
        if normalize(key) == wantedNorm then
            return value
        end
    end
    return nil
end
local function parseNumber(value)
    if value == nil then
        return nil
    end
    if type(value) == "number" then
        return value
    end
    local text = tostring(value)
    text = text:gsub(",", "")
    text = text:gsub("%s", "")
    text = text:gsub("R%$", "")
    text = text:gsub("%$", "")
    local suffix = string.upper(string.sub(text, -1))
    local multiplier = 1
    if suffix == "K" then
        multiplier = 1e3
        text = string.sub(text, 1, -2)
    elseif suffix == "M" then
        multiplier = 1e6
        text = string.sub(text, 1, -2)
    elseif suffix == "B" then
        multiplier = 1e9
        text = string.sub(text, 1, -2)
    elseif suffix == "T" then
        multiplier = 1e12
        text = string.sub(text, 1, -2)
    end
    local number = tonumber(text)
    if number == nil then
        return nil
    end
    return number * multiplier
end
local function containsAny(value, words)
    local text = normalize(value)
    for _, word in ipairs(words) do
        if string.find(text, normalize(word), 1, true) then
            return true
        end
    end
    return false
end
local CRITICAL_EVENT_KINDS = {
    TRANSACTION_FINALIZED = true,
    MONEY_SPEND = true,
    REBIRTH_CHANGE = true,
    BUTTON_REMOVED = true,
    PURCHASE_CREATED = true,
    BUTTONS_UNLOCKED = true,
    READING_STARTED = true,
    READING_STOPPED = true,
    ZONE_CHANGED = true,
    FLOOR_CHANGED = true,
    TRANSITION_PROMPT = true,
    ERROR = true,
}
local function pushEvent(kind, label, details)
    local item = {
        Time = clockText(),
        Unix = os.time(),
        Elapsed = elapsed(),
        Kind = kind,
        Label = label,
        Details = details or {},
    }
    State.DataStats.TotalEventsObserved = State.DataStats.TotalEventsObserved + 1
    if CRITICAL_EVENT_KINDS[kind] then
        table.insert(State.CriticalEvents, item)
        State.DataStats.CriticalEventsStored = #State.CriticalEvents
    end
    table.insert(State.Events, item)
    State.DataStats.AuxiliaryEventsStored = #State.Events
    while #State.Events > MAX_AUX_EVENTS do
        table.remove(State.Events, 1)
        State.DataStats.AuxiliaryEventsDiscarded =
            State.DataStats.AuxiliaryEventsDiscarded + 1
        State.DataStats.AuxiliaryEventsStored = #State.Events
    end
    return item
end
local function pushError(stage, err)
    local message = tostring(err)
    local key = tostring(stage) .. "|" .. message
    local nowClock = os.clock()
    local repeatInfo = State.ErrorRepeats[key]
    if repeatInfo and (nowClock - repeatInfo.LastClock) < 2 then
        repeatInfo.Count = repeatInfo.Count + 1
        repeatInfo.LastClock = nowClock
        return
    end
    State.ErrorRepeats[key] = {
        Count = repeatInfo and (repeatInfo.Count + 1) or 1,
        LastClock = nowClock,
    }
    local item = {
        Time = clockText(),
        Elapsed = elapsed(),
        Stage = stage,
        Error = message,
        RepeatCount = State.ErrorRepeats[key].Count,
    }
    table.insert(State.Errors, item)
    pushEvent("ERROR", stage, {
        Error = message,
        RepeatCount = item.RepeatCount,
    })
end
local function safeCall(stage, fn)
    local ok, result = pcall(fn)
    if not ok then
        pushError(stage, result)
        return false, result
    end
    return true, result
end
local function addConnection(signal, callback, bucket)
    local target = bucket or State.Connections
    local ok, connection = pcall(function()
        return signal:Connect(function(...)
            local args = {...}
            local callbackOk, callbackErr = pcall(function()
                callback(unpack(args))
            end)
            if not callbackOk then
                pushError("EVENT_CALLBACK", callbackErr)
            end
        end)
    end)
    if ok and connection then
        table.insert(target, connection)
        return connection
    end
    if not ok then
        pushError("CONNECT", connection)
    end
    return nil
end
local function disconnectAll(list)
    local old = list
    for i = #old, 1, -1 do
        local connection = old[i]
        old[i] = nil
        pcall(function()
            connection:Disconnect()
        end)
    end
end
local function waitForLocalPlayer(timeout)
    local startTime = os.clock()
    local player = Players.LocalPlayer
    while not player and os.clock() - startTime < timeout do
        task.wait(0.1)
        player = Players.LocalPlayer
    end
    return player
end


State.Player = waitForLocalPlayer(10)
if not State.Player then
    warn("[Psico Auto Buy Core 1.7.5.11] LocalPlayer indisponivel.")
    return nil
end


local function describeButton(button)
    local info = {
        Name = button.Name,
        Path = safeFullName(button),
        Price = attrCI(button, "Price"),
        Cost = attrCI(button, "Cost"),
        Owner = attrCI(button, "Owner"),
        Rebirths = attrCI(button, "Rebirths"),
        RequiredRebirths = attrCI(button, "RequiredRebirths"),
        LinkedPurchases = attrCI(button, "LinkedPurchases"),
        ProductId = attrCI(button, "ProductId"),
        DeveloperProductId = attrCI(button, "DeveloperProductId"),
        GamePassId = attrCI(button, "GamePassId"),
        Gamepass = attrCI(button, "Gamepass"),
        DevProduct = attrCI(button, "DevProduct"),
        NonPurchase = attrCI(button, "NonPurchase"),
        Dependency = attrCI(button, "Dependency"),
        Kills = attrCI(button, "Kills"),
        Robux = attrCI(button, "Robux"),
        Attributes = getAttributes(button),
        HasTouch = button:FindFirstChild("Touch", true) ~= nil,
        HasTouchInterest = button:FindFirstChildWhichIsA("TouchTransmitter", true) ~= nil,
        HasPrompt = button:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil,
    }
    local dependency = tostring(info.Dependency or "")
    local name = tostring(info.Name or "")
    if string.find(normalize(dependency), "bunker", 1, true)
    or string.find(normalize(name), "bunker", 1, true) then
        info.Zone = "BUNKER"
        info.MovementPolicy = "LOCAL_SAFE_TELEPORT_IN_BUNKER; CROSS_ZONE_VIA_GAME_PROMPTS"
    else
        info.Zone = "MAIN_TYCOON"
        info.MovementPolicy = "NORMAL_LOCAL_ACCESS"
    end
    return info
end
local function describePurchase(purchase)
    local prompt = purchase:FindFirstChildWhichIsA("ProximityPrompt", true)
    local info = {
        Name = purchase.Name,
        Path = safeFullName(purchase),
        Owner = attrCI(purchase, "Owner"),
        Rebirths = attrCI(purchase, "Rebirths"),
        LinkedPurchases = attrCI(purchase, "LinkedPurchases"),
        ProductId = attrCI(purchase, "ProductId"),
        DeveloperProductId = attrCI(purchase, "DeveloperProductId"),
        GamePassId = attrCI(purchase, "GamePassId"),
        Gamepass = attrCI(purchase, "Gamepass"),
        DevProduct = attrCI(purchase, "DevProduct"),
        NonPurchase = attrCI(purchase, "NonPurchase"),
        Dependency = attrCI(purchase, "Dependency"),
        Kills = attrCI(purchase, "Kills"),
        Attributes = getAttributes(purchase),
    }
    if prompt then
        info.ProximityPrompt = {
            Path = safeFullName(prompt),
            ActionText = prompt.ActionText,
            ObjectText = prompt.ObjectText,
            HoldDuration = prompt.HoldDuration,
            MaxActivationDistance = prompt.MaxActivationDistance,
            Enabled = prompt.Enabled,
        }
    end
    local dependency = tostring(info.Dependency or "")
    local name = tostring(info.Name or "")
    if string.find(normalize(dependency), "bunker", 1, true)
    or string.find(normalize(name), "bunker", 1, true) then
        info.Zone = "BUNKER"
        info.MovementPolicy = "LOCAL_SAFE_TELEPORT_IN_BUNKER; CROSS_ZONE_VIA_GAME_PROMPTS"
    else
        info.Zone = "MAIN_TYCOON"
        info.MovementPolicy = "NORMAL_LOCAL_ACCESS"
    end
    return info
end
local function textContains(value, needle)
    return string.find(normalize(value), normalize(needle), 1, true) ~= nil
end
local function inferLogicalZone(info)
    info = info or {}
    local name = tostring(info.Name or "")
    local dependency = tostring(info.Dependency or "")
    local path = tostring(info.Path or "")
    if textContains(name, "Bunker")
    or textContains(dependency, "Bunker")
    or textContains(path, ".Bunker") then
        return "BUNKER"
    end
    return "MAIN_TYCOON"
end
local function modelPosition(instance)
    if not instance or not instance.Parent then
        return nil
    end
    local ok, position = pcall(function()
        if instance:IsA("Model") then
            return instance:GetPivot().Position
        end
        if instance:IsA("BasePart") then
            return instance.Position
        end
        local part = instance:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end)
    if ok then
        return position
    end
    return nil
end
local function stageNumberFromDependency(dependency)
    local text = tostring(dependency or "")
    local direct = string.match(text, "[Ff]loor%s*(%d+)")
    if direct then
        return tonumber(direct)
    end
    return nil
end
local function recordStageUnlock(buttonInfo, reason)
    if not buttonInfo then
        return
    end
    local floor = stageNumberFromDependency(buttonInfo.Dependency)
        or tonumber(State.MainFloor)
        or 1
    local stageName = "Floor" .. tostring(floor)
    local name = tostring(buttonInfo.Name or "?")
    local seenKey = stageName .. "|" .. name
    if State.StageUnlockSeen[seenKey] then
        return
    end
    State.StageUnlockSeen[seenKey] = true
    local bucket = nil
    for _, item in ipairs(State.StageUnlocks) do
        if item.Stage == stageName then
            bucket = item
            break
        end
    end
    if not bucket then
        bucket = {
            Stage = stageName,
            Floor = floor,
            FirstObservedUnix = os.time(),
            FirstObservedElapsed = elapsed(),
            Buttons = {},
        }
        table.insert(State.StageUnlocks, bucket)
    end
    table.insert(bucket.Buttons, {
        Name = name,
        Path = buttonInfo.Path,
        Dependency = buttonInfo.Dependency,
        Zone = buttonInfo.Zone or inferLogicalZone(buttonInfo),
        Type = (buttonInfo.RequiredRebirths or buttonInfo.Rebirths)
            and "REBIRTH"
            or ((buttonInfo.Price or buttonInfo.Cost) and "TYCOON_MONEY" or "UNKNOWN"),
        Reason = reason or "BUTTON_AVAILABLE",
        ObservedUnix = os.time(),
        ObservedElapsed = elapsed(),
    })
end
local function detectMainFloor()
    if not State.PurchasesFolder then
        return State.MainFloor or 1, "Purchases folder unavailable"
    end
    if State.PurchasesFolder:FindFirstChild("Floor3") then
        return 3, "Floor3 exists in Purchases"
    end
    if State.PurchasesFolder:FindFirstChild("Floor2") then
        return 2, "Floor2 exists in Purchases"
    end
    return 1, "Floor2/Floor3 not yet purchased"
end
local function setMainFloor(newFloor, evidence)
    newFloor = tonumber(newFloor) or 1
    if State.MainFloor == newFloor then
        State.Health.Floor = tostring(newFloor)
        return
    end
    local previous = State.MainFloor
    State.MainFloor = newFloor
    State.Health.Floor = tostring(newFloor)
    local transition = {
        Time = clockText(),
        Unix = os.time(),
        Elapsed = elapsed(),
        From = previous,
        To = newFloor,
        Evidence = evidence,
    }
    table.insert(State.FloorTransitions, transition)
    if State.Reading then
        pushEvent("FLOOR_CHANGED", "Floor " .. tostring(newFloor), transition)
    end
end
local function setZone(newZone, evidence)
    newZone = tostring(newZone or "UNKNOWN")
    evidence = tostring(evidence or "no evidence")

    local exitPromptAuthorized =
        State.BunkerExitInProgress
        and (State.BunkerExitPromptObservedClock or 0) > 0
        and (os.clock() - (State.BunkerExitPromptObservedClock or 0)) <= 9

    if State.BunkerSessionActive
    and State.CurrentZone == "BUNKER"
    and newZone == "MAIN_TYCOON"
    and not exitPromptAuthorized then
        State.BunkerSuppressedMainDetections = State.BunkerSuppressedMainDetections + 1
        State.ZoneEvidence = "BUNKER_SESSION_LOCK_SUPPRESSED: " .. evidence
        State.Health.Zone = "BUNKER"
        if State.Reading then
            pushEvent("ZONE_CHANGE_SUPPRESSED", "BUNKER", {
                Time = clockText(),
                Unix = os.time(),
                Elapsed = elapsed(),
                From = "BUNKER",
                RequestedTo = "MAIN_TYCOON",
                Evidence = evidence,
                SessionId = State.BunkerSessionId,
                Reason = "BUNKER_SESSION_LOCK_REQUIRES_REAL_EXIT_PROMPT",
            })
        end
        return
    end

    if State.CurrentZone == newZone then
        State.ZoneEvidence = evidence or State.ZoneEvidence
        State.Health.Zone = newZone
        return
    end

    local previous = State.CurrentZone
    State.CurrentZone = newZone
    State.ZoneEvidence = evidence or "no evidence"
    State.Health.Zone = newZone
    local transition = {
        Time = clockText(),
        Unix = os.time(),
        Elapsed = elapsed(),
        From = previous,
        To = newZone,
        Evidence = State.ZoneEvidence,
    }
    table.insert(State.ZoneTransitions, transition)
    if State.Reading then
        pushEvent("ZONE_CHANGED", newZone, transition)
    end
end
local function detectZoneByPosition()
    local character = State.Player and State.Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        return "UNKNOWN", "HumanoidRootPart unavailable"
    end

    local exitPromptAuthorized =
        State.BunkerExitInProgress
        and (State.BunkerExitPromptObservedClock or 0) > 0
        and (os.clock() - (State.BunkerExitPromptObservedClock or 0)) <= 9

    if State.BunkerSessionActive
    and State.CurrentZone == "BUNKER"
    and not exitPromptAuthorized then
        return "BUNKER", "Bunker session lock active; Exit prompt not yet confirmed"
    end

    local bunkerTransitionArmed =
        State.BunkerEnterInProgress
        or State.BunkerSessionActive
        or State.CurrentZone == "BUNKER"

    local nearestBunker = math.huge
    local nearestMain = math.huge

    -- Zone detection intentionally uses BUTTONS ONLY.
    -- Purchased Bunker weapons often lose their original Dependency metadata
    -- and were historically misclassified as MAIN_TYCOON. They must never
    -- participate in physical zone confirmation.
    if State.ButtonsFolder then
        local count = 0
        for _, child in ipairs(State.ButtonsFolder:GetChildren()) do
            count = count + 1
            if count > 120 then
                break
            end
            if child:IsA("Model") or child:IsA("Folder") then
                local info = State.ButtonCache[child.Name] or describeButton(child)
                local position = modelPosition(child)
                if position then
                    local distance = (root.Position - position).Magnitude
                    local nameNorm = normalize(info and info.Name)
                    local dependencyNorm = normalize(info and info.Dependency)
                    local rootBunker = nameNorm == "bunker" and dependencyNorm == ""
                    local logicalZone = rootBunker and "MAIN_TYCOON" or inferLogicalZone(info)
                    if logicalZone == "BUNKER" then
                        nearestBunker = math.min(nearestBunker, distance)
                    else
                        nearestMain = math.min(nearestMain, distance)
                    end
                end
            end
        end
    end

    if bunkerTransitionArmed
    and nearestBunker <= 90
    and nearestBunker < nearestMain then
        return "BUNKER",
            "buttons-only armed Bunker proximity=" .. tostring(math.floor(nearestBunker)) .. " studs"
    end

    if nearestMain <= 180 then
        if not bunkerTransitionArmed and nearestBunker <= 90 then
            return "MAIN_TYCOON",
                "buttons-only Bunker proximity ignored until Enter transition; main=" ..
                tostring(math.floor(nearestMain)) .. " bunker=" ..
                tostring(math.floor(nearestBunker))
        end
        return "MAIN_TYCOON",
            "buttons-only nearest main=" .. tostring(math.floor(nearestMain)) .. " studs"
    end

    if bunkerTransitionArmed and nearestBunker <= 180 then
        return "BUNKER",
            "buttons-only armed near Bunker buttons=" .. tostring(math.floor(nearestBunker)) .. " studs"
    end

    if not bunkerTransitionArmed and nearestBunker < math.huge then
        return "MAIN_TYCOON",
            "buttons-only Bunker proximity ignored because no Enter transition/session is active"
    end

    return "OUTSIDE_TYCOON", "far from known Tycoon/Bunker buttons"
end

local function detectRawPhysicalZoneByPosition()
    local character = State.Player and State.Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        return "UNKNOWN", "HumanoidRootPart unavailable"
    end

    local nearestBunker = math.huge
    local nearestMain = math.huge

    -- RAW confirmation also uses BUTTONS ONLY. Do not inspect Purchases:
    -- an already-purchased Bunker gun can look like a MAIN purchase because
    -- its purchase model no longer carries Dependency="Bunker".
    if State.ButtonsFolder then
        local count = 0
        for _, child in ipairs(State.ButtonsFolder:GetChildren()) do
            count = count + 1
            if count > 120 then
                break
            end
            if child:IsA("Model") or child:IsA("Folder") then
                local info = State.ButtonCache[child.Name] or describeButton(child)
                local position = modelPosition(child)
                if position then
                    local distance = (root.Position - position).Magnitude
                    local nameNorm = normalize(info and info.Name)
                    local dependencyNorm = normalize(info and info.Dependency)
                    local rootBunker = nameNorm == "bunker" and dependencyNorm == ""
                    local logicalZone = rootBunker and "MAIN_TYCOON" or inferLogicalZone(info)
                    if logicalZone == "BUNKER" then
                        nearestBunker = math.min(nearestBunker, distance)
                    else
                        nearestMain = math.min(nearestMain, distance)
                    end
                end
            end
        end
    end

    if nearestMain < math.huge and nearestBunker < math.huge then
        -- Do not give MAIN priority merely because both zones have nearby
        -- objects. The old priority rule could return MAIN even when Bunker was closer, e.g. Bunker=10, Main=13.
        -- The physically nearest button set wins.
        if nearestBunker < nearestMain and nearestBunker <= 180 then
            return "BUNKER",
                "raw buttons-only nearest bunker=" .. tostring(math.floor(nearestBunker)) ..
                " main=" .. tostring(math.floor(nearestMain))
        end
        if nearestMain < nearestBunker and nearestMain <= 180 then
            return "MAIN_TYCOON",
                "raw buttons-only nearest main=" .. tostring(math.floor(nearestMain)) ..
                " bunker=" .. tostring(math.floor(nearestBunker))
        end
        if nearestMain == nearestBunker and nearestMain <= 70 then
            return "UNKNOWN",
                "raw buttons-only exact tie=" .. tostring(math.floor(nearestMain))
        end
    end

    if nearestBunker <= 70 then
        return "BUNKER",
            "raw buttons-only strong bunker=" .. tostring(math.floor(nearestBunker))
    end
    if nearestMain <= 70 then
        return "MAIN_TYCOON",
            "raw buttons-only strong main=" .. tostring(math.floor(nearestMain))
    end
    if nearestMain <= 180 and nearestBunker > 180 then
        return "MAIN_TYCOON",
            "raw buttons-only main-only=" .. tostring(math.floor(nearestMain))
    end
    if nearestBunker <= 180 and nearestMain > 180 then
        return "BUNKER",
            "raw buttons-only bunker-only=" .. tostring(math.floor(nearestBunker))
    end

    return "UNKNOWN",
        "raw buttons-only ambiguous main=" ..
        tostring(nearestMain < math.huge and math.floor(nearestMain) or "inf") ..
        " bunker=" ..
        tostring(nearestBunker < math.huge and math.floor(nearestBunker) or "inf")
end
local function classifyTransitionPrompt(prompt)
    local action = normalize(prompt and prompt.ActionText)
    local object = normalize(prompt and prompt.ObjectText)
    local path = normalize(prompt and safeFullName(prompt))
    local bunkerEvidence =
        string.find(object, "bunker", 1, true)
        or string.find(path, "bunker", 1, true)
    if bunkerEvidence and string.find(action, "enter", 1, true) then
        return "ENTER_BUNKER"
    end
    if bunkerEvidence
    and (string.find(action, "exit", 1, true)
        or string.find(action, "leave", 1, true)
        or string.find(action, "return", 1, true)) then
        return "EXIT_BUNKER"
    end
    return nil
end
local function transitionPromptPart(prompt)
    if not prompt then
        return nil
    end
    local current = prompt.Parent
    while current and current ~= workspace do
        if current:IsA("BasePart") then
            return current
        end
        current = current.Parent
    end
    return nil
end
local autoSetBunkerTransitionFreeze
local autoUpdateBunkerTransitionFreeze
local function watchTransitionPrompts(instance)
    if not instance then
        return
    end
    local prompts = {}
    if instance:IsA("ProximityPrompt") then
        table.insert(prompts, instance)
    end
    for _, descendant in ipairs(instance:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") then
            table.insert(prompts, descendant)
        end
    end
    for _, prompt in ipairs(prompts) do
        if not State.WatchedTransitionPrompts[prompt] then
            local direction = classifyTransitionPrompt(prompt)
            if direction then
                State.WatchedTransitionPrompts[prompt] = true
                addConnection(prompt.Triggered, function(player)
                    if player ~= State.Player then
                        return
                    end
                    local item = {
                        Direction = direction,
                        Clock = os.clock(),
                        Time = clockText(),
                        Unix = os.time(),
                        Path = safeFullName(prompt),
                        ActionText = prompt.ActionText,
                        ObjectText = prompt.ObjectText,
                    }
                    State.LastTransitionPrompt = item
                    if direction == "ENTER_BUNKER" then
                        State.BunkerEnterPromptObservedClock = item.Clock
                        State.BunkerExitSettleUntil = 0
                        State.BunkerExitRetryUntil = 0
                        if not State.BunkerEnterInProgress then
                            if not State.BunkerSessionActive then
                                State.BunkerSessionId = State.BunkerSessionId + 1
                            end
                            State.BunkerManualEnterCount = State.BunkerManualEnterCount + 1
                            State.BunkerSessionActive = true
                            State.BunkerEnterInProgress = true
                            State.BunkerExitInProgress = false
                            State.BunkerSessionStartedUnix = os.time()
                            State.BunkerSessionStartedElapsed = elapsed()
                            State.BunkerSessionReason = "MANUAL_ENTER_PROMPT_WAITING_PHYSICAL_CONFIRMATION"
                            local transitionCharacter = State.Player and State.Player.Character
                            local transitionRoot = transitionCharacter
                                and transitionCharacter:FindFirstChild("HumanoidRootPart")
                            State.BunkerTransitionOriginPosition = transitionRoot and transitionRoot.Position or nil
                            State.BunkerTransitionSourcePart = transitionPromptPart(prompt)
                            State.BunkerTransitionSourcePath = State.BunkerTransitionSourcePart
                                and safeFullName(State.BunkerTransitionSourcePart)
                                or nil
                            State.BunkerTransitionLastDisplacement = 0
                            autoSetBunkerTransitionFreeze(
                                true,
                                "ENTER_BUNKER",
                                "MANUAL_ENTER_PROMPT_TRIGGERED"
                            )
                            pushEvent("AUTOMATION", "BUNKER_MANUAL_SESSION_ADOPTED", {
                                SessionId = State.BunkerSessionId,
                                Prompt = item.Path,
                                Policy = "MANUAL_ENTER_FREEZES_TELEPORT_UNTIL_RAW_PHYSICAL_BUNKER_CONFIRMATION",
                            })
                        end
                    elseif direction == "EXIT_BUNKER" then
                        local wasAutoExit = State.BunkerExitInProgress
                        State.BunkerExitPromptObservedClock = item.Clock
                        State.BunkerExitRetryUntil = 0
                        if not wasAutoExit then
                            State.BunkerManualExitCount = State.BunkerManualExitCount + 1
                            State.BunkerExitInProgress = true
                            local transitionCharacter = State.Player and State.Player.Character
                            local transitionRoot = transitionCharacter
                                and transitionCharacter:FindFirstChild("HumanoidRootPart")
                            State.BunkerTransitionOriginPosition = transitionRoot and transitionRoot.Position or nil
                            State.BunkerTransitionSourcePart = transitionPromptPart(prompt)
                            State.BunkerTransitionSourcePath = State.BunkerTransitionSourcePart
                                and safeFullName(State.BunkerTransitionSourcePart)
                                or nil
                            State.BunkerTransitionLastDisplacement = 0
                            autoSetBunkerTransitionFreeze(
                                true,
                                "EXIT_BUNKER",
                                "MANUAL_EXIT_PROMPT_TRIGGERED"
                            )
                        end
                        State.BunkerSessionReason = wasAutoExit
                            and "AUTO_EXIT_PROMPT_WAITING_PHYSICAL_CONFIRMATION"
                            or "MANUAL_EXIT_PROMPT_WAITING_PHYSICAL_CONFIRMATION"
                        pushEvent("AUTOMATION", "BUNKER_EXIT_PROMPT_OBSERVED_WAITING_PHYSICAL_CONFIRMATION", {
                            SessionId = State.BunkerSessionId,
                            Prompt = item.Path,
                            WasAutoExit = wasAutoExit,
                            Policy = "PROMPT_EVENT_ALONE_NEVER_RELEASES_SESSION; RAW_PHYSICAL_MAIN_REQUIRED",
                        })
                    end
                    if State.Reading then
                        pushEvent("TRANSITION_PROMPT", direction, item)
                    end
                end, State.TycoonConnections)
            end
        end
    end
end
local function classify(buttonInfo, purchaseInfo)
    local button = buttonInfo or {}
    local purchase = purchaseInfo or {}
    local evidence = {}
    local price = parseNumber(button.Price or button.Cost)
    local requiredRebirths = parseNumber(button.RequiredRebirths or button.Rebirths)
    local killsRequired = parseNumber(button.Kills or purchase.Kills)
    local gamepass = button.Gamepass or purchase.Gamepass
    local devProduct = button.DevProduct or purchase.DevProduct
    local productId = button.ProductId or purchase.ProductId
    local developerProductId = button.DeveloperProductId or purchase.DeveloperProductId
    local gamePassId = button.GamePassId or purchase.GamePassId
    local robux = button.Robux
    local hasMarketplaceMarker =
        (gamepass ~= nil and tostring(gamepass) ~= "")
        or (devProduct ~= nil and tostring(devProduct) ~= "")
        or (productId ~= nil and tostring(productId) ~= "")
        or (developerProductId ~= nil and tostring(developerProductId) ~= "")
        or (gamePassId ~= nil and tostring(gamePassId) ~= "")
        or (robux ~= nil and tostring(robux) ~= "")
    if price ~= nil then
        table.insert(evidence, "Price/Cost=" .. tostring(price))
    end
    if requiredRebirths and requiredRebirths > 0 then
        table.insert(evidence, "Rebirth requirement=" .. tostring(requiredRebirths))
    end
    if killsRequired and killsRequired > 0 then
        table.insert(evidence, "Kills requirement=" .. tostring(killsRequired))
    end
    if gamepass ~= nil and tostring(gamepass) ~= "" then
        table.insert(evidence, "Gamepass=" .. tostring(gamepass))
    end
    if devProduct ~= nil and tostring(devProduct) ~= "" then
        table.insert(evidence, "DevProduct=" .. tostring(devProduct))
    end
    if productId ~= nil and tostring(productId) ~= "" then
        table.insert(evidence, "ProductId=" .. tostring(productId))
    end
    if developerProductId ~= nil and tostring(developerProductId) ~= "" then
        table.insert(evidence, "DeveloperProductId=" .. tostring(developerProductId))
    end
    if gamePassId ~= nil and tostring(gamePassId) ~= "" then
        table.insert(evidence, "GamePassId=" .. tostring(gamePassId))
    end
    if robux ~= nil and tostring(robux) ~= "" then
        table.insert(evidence, "Robux=" .. tostring(robux))
    end
    local classType = "UNKNOWN"
    local confidence = "unknown"
    local score = 0
    local eligible = false
    local eligibilityReason = "Insufficient evidence"
    if hasMarketplaceMarker and killsRequired and killsRequired > 0 then
        classType = "KILLS_OR_PREMIUM"
        confidence = "high"
        score = 14
        eligible = false
        eligibilityReason = "Ignored: item exposes Kills and Marketplace/premium evidence"
    elseif hasMarketplaceMarker then
        classType = "ROBUX_ONLY"
        confidence = "high"
        score = 12
        eligible = false
        eligibilityReason = "Ignored: Marketplace/premium purchase"
    elseif requiredRebirths and requiredRebirths > 0 then
        classType = "REBIRTH"
        confidence = "high"
        score = 10
        local currentRebirths = State.LastRebirths
        local satisfied = currentRebirths ~= nil and currentRebirths >= requiredRebirths
        eligible = satisfied
        eligibilityReason = satisfied
            and ("Eligible: rebirth requirement satisfied (" .. tostring(currentRebirths) .. "/" .. tostring(requiredRebirths) .. ")")
            or ("Blocked: requires " .. tostring(requiredRebirths) .. " rebirth(s), current=" .. tostring(currentRebirths ~= nil and currentRebirths or "unknown"))
    elseif price ~= nil and price >= 0 then
        classType = "TYCOON_MONEY"
        confidence = "high"
        score = price == 0 and 11 or 9
        eligible = true
        eligibilityReason = price == 0
            and "Eligible: free structural Tycoon purchase (Price=0)"
            or "Eligible: ordinary Tycoon-money purchase"
    elseif killsRequired and killsRequired > 0 then
        classType = "KILLS_OR_PREMIUM"
        confidence = "medium"
        score = 7
        eligible = false
        eligibilityReason = "Ignored: Kills-based requirement"
    end
    return {
        Type = classType,
        Confidence = confidence,
        Score = score,
        Evidence = evidence,
        AutomationEligible = eligible,
        AutomationReason = eligibilityReason,
        Requirements = {
            Price = price,
            Rebirths = requiredRebirths,
            Kills = killsRequired,
            HasMarketplaceMarker = hasMarketplaceMarker,
        },
    }
end
local function ownerMatches(owner)
    if owner == nil or not State.Player then
        return false
    end
    local text = tostring(owner)
    return text == State.Player.Name
        or text == tostring(State.Player.UserId)
        or normalize(text) == normalize(State.Player.Name)
end
local function scoreTycoon(tycoon)
    if not tycoon then
        return -1, {}
    end
    if not tycoon:IsA("Model") and not tycoon:IsA("Folder") then
        return -1, {}
    end
    local score = 0
    local evidence = {}
    local buttons = tycoon:FindFirstChild("Buttons")
    local purchases = tycoon:FindFirstChild("Purchases")
    if not buttons or not purchases then
        return 0, evidence
    end
    local owner = attrCI(tycoon, "Owner")
    if ownerMatches(owner) then
        score = score + 100
        table.insert(evidence, "Tycoon Owner matches LocalPlayer")
    end
    local folders = {buttons, purchases}
    for _, folder in ipairs(folders) do
        local count = 0
        for _, child in ipairs(folder:GetChildren()) do
            count = count + 1
            if ownerMatches(attrCI(child, "Owner")) then
                score = score + 40
                table.insert(evidence, child.Name .. " Owner matches LocalPlayer")
                break
            end
            if count >= 80 then
                break
            end
        end
    end
    return score, evidence
end
local function findPlayerTycoon()
    local tycoons = workspace:FindFirstChild("Tycoons")
    if not tycoons then
        return nil, 0, {}
    end
    local best = nil
    local bestScore = 0
    local bestEvidence = {}
    for _, tycoon in ipairs(tycoons:GetChildren()) do
        local score, evidence = scoreTycoon(tycoon)
        if score > bestScore then
            best = tycoon
            bestScore = score
            bestEvidence = evidence
        end
    end
    if best and bestScore >= 40 then
        return best, bestScore, bestEvidence
    end
    return nil, bestScore, bestEvidence
end
local function findStat(names)
    local leaderstats = State.Player and State.Player:FindFirstChild("leaderstats")
    if not leaderstats then
        return nil
    end
    for _, wanted in ipairs(names) do
        local direct = leaderstats:FindFirstChild(wanted)
        if direct and direct:IsA("ValueBase") then
            return direct
        end
    end
    for _, child in ipairs(leaderstats:GetChildren()) do
        if child:IsA("ValueBase") and containsAny(child.Name, names) then
            return child
        end
    end
    return nil
end
local MONEY_NAMES = {"Money", "Cash", "Coins", "Coin", "Currency", "Saldo"}
local function readValue(obj)
    if not obj or not obj.Parent then
        return nil
    end
    local ok, value = pcall(function()
        if obj:IsA("ValueBase") then
            return obj.Value
        end
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            return obj.Text
        end
        return nil
    end)
    if not ok then
        return nil
    end
    return parseNumber(value)
end
local function moneyCandidateScore(instance, rootKind)
    if not instance or not instance.Parent then
        return nil
    end
    local isValue = instance:IsA("ValueBase")
    local isText = instance:IsA("TextLabel")
        or instance:IsA("TextButton")
        or instance:IsA("TextBox")
    if not isValue and not isText then
        return nil
    end
    local nameNorm = normalize(instance.Name)
    local nameMatches = containsAny(instance.Name, MONEY_NAMES)
    local value = readValue(instance)
    if value == nil then
        return nil
    end
    local score = 0
    local evidence = {}
    if nameNorm == "money" then
        score = score + 60
        table.insert(evidence, "exact name=Money")
    elseif nameMatches then
        score = score + 35
        table.insert(evidence, "money-like name")
    elseif isText then
        local text = tostring(instance.Text or "")
        if string.find(text, "$", 1, true) then
            score = score + 8
            table.insert(evidence, "HUD text contains $")
        else
            return nil
        end
    else
        return nil
    end
    if rootKind == "LEADERSTATS" then
        score = score + 100
        table.insert(evidence, "leaderstats")
    elseif rootKind == "PLAYER" then
        score = score + 55
        table.insert(evidence, "Player descendant")
    elseif rootKind == "TYCOON" then
        score = score + 45
        table.insert(evidence, "local Tycoon descendant")
    elseif rootKind == "PLAYERGUI" then
        score = score + 20
        table.insert(evidence, "PlayerGui display fallback")
    end
    if isValue then
        score = score + 25
        table.insert(evidence, "ValueBase")
    else
        table.insert(evidence, "GUI text fallback")
    end
    local pathNorm = normalize(safeFullName(instance))
    if string.find(pathNorm, "price", 1, true)
    or string.find(pathNorm, "cost", 1, true)
    or string.find(pathNorm, "button", 1, true)
    or string.find(pathNorm, "shop", 1, true) then
        score = score - 45
        table.insert(evidence, "penalty: shop/price-like path")
    end
    return score, value, evidence
end
local function discoverMoneySource()
    local candidates = {}
    local seen = setmetatable({}, {__mode = "k"})
    local function consider(instance, rootKind)
        if not instance or seen[instance] then
            return
        end
        seen[instance] = true
        local score, value, evidence = moneyCandidateScore(instance, rootKind)
        if score then
            table.insert(candidates, {
                Instance = instance,
                Path = safeFullName(instance),
                ClassName = instance.ClassName,
                RootKind = rootKind,
                Score = score,
                Value = value,
                Evidence = evidence,
            })
        end
    end
    local function scanRoot(root, rootKind, limit)
        if not root then
            return
        end
        consider(root, rootKind)
        local count = 0
        for _, descendant in ipairs(root:GetDescendants()) do
            count = count + 1
            if count > limit then
                break
            end
            consider(descendant, rootKind)
        end
    end
    local leaderstats = State.Player and State.Player:FindFirstChild("leaderstats")
    scanRoot(leaderstats, "LEADERSTATS", 100)
    if State.Player then
        for _, child in ipairs(State.Player:GetChildren()) do
            if child ~= leaderstats and child.Name ~= "PlayerGui" then
                scanRoot(child, "PLAYER", 600)
            end
        end
    end
    scanRoot(State.Tycoon, "TYCOON", 1200)
    local playerGui = State.Player and State.Player:FindFirstChild("PlayerGui")
    scanRoot(playerGui, "PLAYERGUI", 1200)
    table.sort(candidates, function(a, b)
        if a.Score == b.Score then
            return tostring(a.Path) < tostring(b.Path)
        end
        return a.Score > b.Score
    end)
    local exportCandidates = {}
    for index, candidate in ipairs(candidates) do
        if index > 20 then
            break
        end
        table.insert(exportCandidates, {
            Path = candidate.Path,
            ClassName = candidate.ClassName,
            RootKind = candidate.RootKind,
            Score = candidate.Score,
            Value = candidate.Value,
            Evidence = candidate.Evidence,
        })
    end
    State.MoneyCandidates = exportCandidates
    State.LastMoneyDiscoveryClock = os.clock()
    local best = candidates[1]
    if best then
        State.MoneySourceKind = best.RootKind
        State.MoneySourceEvidence = best.Evidence
        return best.Instance
    end
    State.MoneySourceKind = nil
    State.MoneySourceEvidence = {"no numeric money candidate found"}
    return nil
end
local function refreshStatsObjects()
    if not State.MoneyObject or not State.MoneyObject.Parent then
        State.MoneyObject = discoverMoneySource()
    elseif os.clock() - (State.LastMoneyDiscoveryClock or 0) >= 4 then
        local current = State.MoneyObject
        local currentPath = safeFullName(current)
        local discovered = discoverMoneySource()
        if discovered then
            local currentEntry = nil
            local bestEntry = State.MoneyCandidates[1]
            for _, entry in ipairs(State.MoneyCandidates) do
                if entry.Path == currentPath then
                    currentEntry = entry
                    break
                end
            end
            if not currentEntry
            or (bestEntry and bestEntry.Score >= (currentEntry.Score or 0) + 20) then
                State.MoneyObject = discovered
            else
                State.MoneyObject = current
                State.MoneySourceKind = currentEntry.RootKind
                State.MoneySourceEvidence = currentEntry.Evidence
            end
        else
            State.MoneyObject = current
            State.MoneySourceKind = "PRESERVED"
            State.MoneySourceEvidence = {"previous valid source preserved; refresh found no stronger candidate"}
        end
    end
    if not State.RebirthObject or not State.RebirthObject.Parent then
        State.RebirthObject = findStat({"Rebirths", "Rebirth", "Renascimentos", "Renascimento"})
    end
end
local function buttonsSet()
    local result = {}
    if State.ButtonsFolder then
        for _, child in ipairs(State.ButtonsFolder:GetChildren()) do
            result[child.Name] = true
        end
    end
    return result
end
local function pendingFor(name)
    local item = State.Pending[name]
    if not item or item.Completed then
        item = {
            Name = name,
            Started = os.clock(),
            Button = nil,
            Purchase = nil,
            ButtonRemovedAt = nil,
            PurchaseCreatedAt = nil,
            MoneyBefore = State.LastMoney,
            MoneyAfter = nil,
            RebirthsBefore = State.LastRebirths,
            RebirthsAfter = nil,
            Unlocks = {},
            Completed = false,
        }
        State.Pending[name] = item
    end
    return item
end
local function finalize(name)
    local pending = State.Pending[name]
    if not pending or pending.Completed then
        return
    end
    local classification = classify(pending.Button, pending.Purchase)
    local transaction = {
        Id = #State.Transactions + 1,
        Name = name,
        Time = clockText(),
        Elapsed = elapsed(),
        Classification = classification,
        AutomationEligible = classification.AutomationEligible,
        AutomationReason = classification.AutomationReason,
        Zone = (pending.Button and pending.Button.Zone)
            or inferLogicalZone(pending.Button or pending.Purchase),
        MainFloorAtTransaction = State.MainFloor,
        MovementPolicy = (pending.Button and pending.Button.MovementPolicy)
            or (inferLogicalZone(pending.Button or pending.Purchase) == "BUNKER"
                and "USE_GAME_TRANSITION"
                or "NORMAL_LOCAL_ACCESS"),
        Button = pending.Button,
        Purchase = pending.Purchase,
        DeclaredPrice = pending.Button and (pending.Button.Price or pending.Button.Cost) or nil,
        RequiredRebirths = pending.Button and (pending.Button.RequiredRebirths or pending.Button.Rebirths) or nil,
        LinkedPurchases = (pending.Button and pending.Button.LinkedPurchases)
            or (pending.Purchase and pending.Purchase.LinkedPurchases) or nil,
        Dependency = (pending.Button and pending.Button.Dependency)
            or (pending.Purchase and pending.Purchase.Dependency) or nil,
        MoneyBefore = pending.MoneyBefore,
        MoneyAfter = pending.MoneyAfter,
        MoneyDelta = (
            pending.MoneyBefore ~= nil and pending.MoneyAfter ~= nil
        ) and (pending.MoneyAfter - pending.MoneyBefore) or nil,
        RebirthsBefore = pending.RebirthsBefore,
        RebirthsAfter = pending.RebirthsAfter,
        UnlockedButtons = pending.Unlocks,
        Timing = {
            ButtonRemovedAt = pending.ButtonRemovedAt,
            PurchaseCreatedAt = pending.PurchaseCreatedAt,
        },
    }
    local declaredPriceNumber = parseNumber(transaction.DeclaredPrice)
    local delta = transaction.MoneyDelta
    transaction.EconomyEvidence = {
        Direction = delta and (delta < 0 and "SPEND" or (delta > 0 and "INCOME" or "NO_CHANGE")) or "UNOBSERVED",
        ExactPriceMatch = (
            declaredPriceNumber ~= nil
            and delta ~= nil
            and delta < 0
            and math.abs(delta) == declaredPriceNumber
        ) or false,
        ObservedSpend = (delta ~= nil and delta < 0) and math.abs(delta) or nil,
        ObservedIncome = (delta ~= nil and delta > 0) and delta or nil,
    }
    if transaction.Classification.Type == "TYCOON_MONEY"
    and transaction.EconomyEvidence.ExactPriceMatch then
        transaction.Classification.Confidence = "confirmed"
        transaction.Classification.Score = math.max(transaction.Classification.Score or 0, 15)
        transaction.AutomationEligible = true
        transaction.AutomationReason = "Eligible: confirmed Tycoon-money purchase"
        transaction.Classification.AutomationEligible = true
        transaction.Classification.AutomationReason = "Eligible: confirmed Tycoon-money purchase"
        table.insert(transaction.Classification.Evidence, "Money deduction exactly matches declared Price")
    elseif transaction.Classification.Type == "TYCOON_MONEY"
    and delta ~= nil and delta > 0 then
        table.insert(transaction.Classification.Evidence, "Positive Money delta is income, not purchase cost")
    end
    table.insert(State.Transactions, transaction)
    State.DataStats.TransactionsStored = #State.Transactions
    pending.Completed = true
    pushEvent("TRANSACTION_FINALIZED", name, transaction)
end
local function watchUnlocks(name, baseline)
    task.spawn(function()
        local seen = {}
        local finishAt = os.clock() + UNLOCK_WINDOW
        while State.Running and os.clock() < finishAt do
            if State.ButtonsFolder then
                for _, child in ipairs(State.ButtonsFolder:GetChildren()) do
                    if not baseline[child.Name] then
                        seen[child.Name] = true
                    end
                end
            end
            task.wait(0.15)
        end
        local pending = State.Pending[name]
        if not pending then
            return
        end
        local list = {}
        for childName in pairs(seen) do
            table.insert(list, childName)
        end
        table.sort(list)
        pending.Unlocks = list
        if #list > 0 then
            pushEvent("BUTTONS_UNLOCKED", name, {
                UnlockedButtons = list,
            })
        end
        finalize(name)
    end)
end
local function watchButtonAttributes(button)
    local attrs = {
        "Price",
        "Cost",
        "Owner",
        "Rebirths",
        "RequiredRebirths",
        "LinkedPurchases",
        "ProductId",
        "DeveloperProductId",
        "GamePassId",
        "Gamepass",
        "DevProduct",
        "NonPurchase",
        "Dependency",
        "Kills",
        "Robux",
    }
    for _, attrName in ipairs(attrs) do
        addConnection(button:GetAttributeChangedSignal(attrName), function()
            local info = describeButton(button)
            State.ButtonCache[button.Name] = info
            if not State.Reading then
                return
            end
            pushEvent("BUTTON_ATTRIBUTE_CHANGED", button.Name, {
                Attribute = attrName,
                Button = info,
                Classification = classify(info, nil),
            })
        end, State.TycoonConnections)
    end
end
local function onButtonAdded(button)
    if not button:IsA("Model") and not button:IsA("Folder") then
        return
    end
    local info = describeButton(button)
    State.ButtonCache[button.Name] = info
    watchButtonAttributes(button)
    watchTransitionPrompts(button)
    if not State.Reading then
        return
    end
    recordStageUnlock(info, "BUTTON_AVAILABLE")
    pushEvent("BUTTON_AVAILABLE", button.Name, {
        Button = info,
        Classification = classify(info, nil),
    })
end
local function onButtonRemoved(button)
    local name = button.Name
    local info = State.ButtonCache[name] or describeButton(button)
    State.ButtonCache[name] = nil
    if not State.Reading then
        return
    end
    local pending = pendingFor(name)
    pending.Button = info
    pending.ButtonRemovedAt = os.clock()
    pending.MoneyBefore = State.LastMoney
    pending.RebirthsBefore = State.LastRebirths
    local baseline = buttonsSet()
    pushEvent("BUTTON_REMOVED", name, {
        Button = info,
        Classification = classify(info, nil),
        MoneyBefore = pending.MoneyBefore,
        RebirthsBefore = pending.RebirthsBefore,
    })
    watchUnlocks(name, baseline)
end
local function onPurchaseAdded(purchase)
    if not purchase:IsA("Model") and not purchase:IsA("Folder") then
        return
    end
    if not State.Reading then
        return
    end
    local name = purchase.Name
    local pending = pendingFor(name)
    local info = describePurchase(purchase)
    if pending.Button and pending.Button.Zone then
        info.Zone = pending.Button.Zone
        info.MovementPolicy = pending.Button.MovementPolicy
    end
    watchTransitionPrompts(purchase)
    pending.Purchase = info
    pending.PurchaseCreatedAt = os.clock()
    pushEvent("PURCHASE_CREATED", name, {
        Purchase = info,
        Classification = classify(pending.Button, info),
    })
end
local function scanInitial()
    State.ButtonCache = {}
    local buttonsSnapshot = {}
    local purchasesSnapshot = {}
    if State.ButtonsFolder then
        for _, button in ipairs(State.ButtonsFolder:GetChildren()) do
            if button:IsA("Model") or button:IsA("Folder") then
                local info = describeButton(button)
                table.insert(buttonsSnapshot, info)
                State.ButtonCache[button.Name] = info
                watchButtonAttributes(button)
                watchTransitionPrompts(button)
            end
        end
    end
    if State.PurchasesFolder then
        for _, purchase in ipairs(State.PurchasesFolder:GetChildren()) do
            if purchase:IsA("Model") or purchase:IsA("Folder") then
                table.insert(purchasesSnapshot, describePurchase(purchase))
                watchTransitionPrompts(purchase)
            end
        end
    end
    if State.Reading then
        State.InitialButtons = buttonsSnapshot
        State.InitialPurchases = purchasesSnapshot
        pushEvent("INITIAL_STATE", "Initial state", {
            Buttons = #State.InitialButtons,
            Purchases = #State.InitialPurchases,
        })
    end
end
local function bindTycoon(tycoon, score, evidence)
    if not tycoon or not tycoon.Parent then
        return false
    end
    local buttons = tycoon:FindFirstChild("Buttons")
    local purchases = tycoon:FindFirstChild("Purchases")
    if not buttons or not purchases then
        return false
    end
    if State.Tycoon == tycoon
    and State.ButtonsFolder == buttons
    and State.PurchasesFolder == purchases
    and State.ButtonsFolder.Parent == tycoon
    and State.PurchasesFolder.Parent == tycoon then
        State.TycoonScore = score
        State.Health.Tycoon = "CONFIRMED"
        return true
    end
    disconnectAll(State.TycoonConnections)
    State.Tycoon = tycoon
    State.TycoonScore = score or 0
    State.ButtonsFolder = buttons
    State.PurchasesFolder = purchases
    scanInitial()
    addConnection(buttons.ChildAdded, onButtonAdded, State.TycoonConnections)
    addConnection(buttons.ChildRemoved, onButtonRemoved, State.TycoonConnections)
    addConnection(purchases.ChildAdded, onPurchaseAdded, State.TycoonConnections)
    State.Health.Tycoon = "CONFIRMED"
    if State.Reading then
        pushEvent("TYCOON_BOUND", tycoon.Name, {
            Path = safeFullName(tycoon),
            Score = State.TycoonScore,
            Evidence = evidence,
        })
    end
    return true
end
local function reconsiderTycoon()
    local tycoon, score, evidence = findPlayerTycoon()
    if tycoon then
        bindTycoon(tycoon, score, evidence)
    else
        State.Health.Tycoon = "SEARCHING"
    end
end
local function correlateStatChanges(oldMoney, newMoney, oldRebirths, newRebirths)
    local now = os.clock()
    local best = nil
    local bestTime = -1
    for _, pending in pairs(State.Pending) do
        if not pending.Completed then
            local eventTime = pending.PurchaseCreatedAt or pending.ButtonRemovedAt
            if eventTime
            and now - eventTime <= CORRELATION_WINDOW
            and eventTime > bestTime then
                best = pending
                bestTime = eventTime
            end
        end
    end
    if not best then
        return
    end
    if oldMoney ~= nil and newMoney ~= nil and newMoney < oldMoney then
        best.MoneyBefore = best.MoneyBefore or oldMoney
        best.MoneyAfter = newMoney
    end
    if oldRebirths ~= nil
    and newRebirths ~= nil
    and oldRebirths ~= newRebirths then
        best.RebirthsBefore = best.RebirthsBefore or oldRebirths
        best.RebirthsAfter = newRebirths
    end
end
local buildAutomationCandidates

buildAutomationCandidates = function()
    local result = {Eligible = {}, Ignored = {}}
    if not State.ButtonsFolder then return result end
    for _, button in ipairs(State.ButtonsFolder:GetChildren()) do
        if button:IsA("Model") or button:IsA("Folder") then
            local info = State.ButtonCache[button.Name] or describeButton(button)
            local classification = classify(info, nil)
            local record = {
                Name = button.Name,
                Path = safeFullName(button),
                Type = classification.Type,
                AutomationEligible = classification.AutomationEligible,
                AutomationReason = classification.AutomationReason,
                Requirements = classification.Requirements,
                Dependency = info.Dependency,
                Zone = info.Zone or inferLogicalZone(info),
                MovementPolicy = info.MovementPolicy or
                    (inferLogicalZone(info) == "BUNKER"
                        and "LOCAL_SAFE_TELEPORT_IN_BUNKER; CROSS_ZONE_VIA_GAME_PROMPTS"
                        or "NORMAL_LOCAL_ACCESS"),
                Price = info.Price or info.Cost,
                Rebirths = info.RequiredRebirths or info.Rebirths,
                Kills = info.Kills,
                Gamepass = info.Gamepass,
                DevProduct = info.DevProduct,
            }
            if classification.AutomationEligible then
                table.insert(result.Eligible, record)
            else
                table.insert(result.Ignored, record)
            end
        end
    end
    table.sort(result.Eligible, function(a, b) return tostring(a.Name) < tostring(b.Name) end)
    table.sort(result.Ignored, function(a, b) return tostring(a.Name) < tostring(b.Name) end)
    return result
end
local function setReading(enabled)
    enabled = enabled and true or false
    if State.Reading == enabled then
        return
    end
    if enabled then
        State.Reading = true
        State.Health.Reading = "ACTIVE"
        State.Pending = {}
        refreshStatsObjects()
        State.LastMoney = readValue(State.MoneyObject)
        State.LastRebirths = readValue(State.RebirthObject)
        local session = {
            StartedUnix = os.time(),
            StartedElapsed = elapsed(),
            StartedMoney = State.LastMoney,
            StartedRebirths = State.LastRebirths,
            StartedZone = State.CurrentZone,
            StartedFloor = State.MainFloor,
            StartedEventCount = State.DataStats.TotalEventsObserved,
            StartedTransactionCount = #State.Transactions,
        }
        State.CurrentReadingSession = session
        table.insert(State.ReadingSessions, session)
        scanInitial()
        pushEvent("READING_STARTED", "READING_STARTED", {
            Money = State.LastMoney,
            Rebirths = State.LastRebirths,
            Buttons = #State.InitialButtons,
            Purchases = #State.InitialPurchases,
            TransactionsStored = #State.Transactions,
            EventsObserved = State.DataStats.TotalEventsObserved,
        })
    else
        pushEvent("READING_STOPPED", "READING_STOPPED", {
            Money = State.LastMoney,
            Rebirths = State.LastRebirths,
            TransactionsStored = #State.Transactions,
            EventsObserved = State.DataStats.TotalEventsObserved,
            AuxiliaryEventsDiscarded = State.DataStats.AuxiliaryEventsDiscarded,
        })
        if State.CurrentReadingSession then
            State.CurrentReadingSession.StoppedUnix = os.time()
            State.CurrentReadingSession.StoppedElapsed = elapsed()
            State.CurrentReadingSession.StoppedMoney = State.LastMoney
            State.CurrentReadingSession.StoppedRebirths = State.LastRebirths
            State.CurrentReadingSession.StoppedZone = State.CurrentZone
            State.CurrentReadingSession.StoppedFloor = State.MainFloor
            State.CurrentReadingSession.StoppedEventCount =
                State.DataStats.TotalEventsObserved
            State.CurrentReadingSession.StoppedTransactionCount =
                #State.Transactions
            State.CurrentReadingSession.EventsObserved =
                State.CurrentReadingSession.StoppedEventCount -
                (State.CurrentReadingSession.StartedEventCount or 0)
            State.CurrentReadingSession.TransactionsRecorded =
                State.CurrentReadingSession.StoppedTransactionCount -
                (State.CurrentReadingSession.StartedTransactionCount or 0)
        end
        State.CurrentReadingSession = nil
        State.Pending = {}
        State.Reading = false
        State.Health.Reading = "PAUSED"
    end
end
local AUTO_SERVER_WAIT = 1.35
local AUTO_RETRY_COOLDOWN = 2.5
local AUTO_IDLE_WAIT = 0.22
local AUTO_POST_RESULT_WAIT = 0.08
local AUTO_COLLECT_MIN = 1000
local AUTO_COLLECT_CONFIRM_TIMEOUT = 4
local AUTO_COLLECT_RECHECK_INTERVAL = 0.30
local AUTO_COLLECT_MIN_GAP = 0.75
local BUNKER_RESCAN_WAIT = 0.45
local BUNKER_REQUIRED_EMPTY_RESCANS = 2
local BUNKER_ENTRY_RETRY_COOLDOWN = 3
local BUNKER_PURCHASE_SETTLE = 0.30
local BUNKER_PENDING_RETRY_WAIT = 0.65
local BUNKER_EXIT_PROMPT_DISCOVERY_TIMEOUT = 2.5
local BUNKER_EXIT_FAILURE_COOLDOWN = 4.0
local BUNKER_TRANSITION_FREEZE_TIMEOUT = 10.0
local BUNKER_TRANSITION_MIN_DISPLACEMENT = 60
local AUTO_REBIRTH_CONFIRM_TIMEOUT = 5
local AUTO_REBIRTH_RETRY_COOLDOWN = 8
local AUTOSAVE_INTERVAL = 15
local autoRefreshFundsBlocks
local function autoRecord(kind, details)
    details = details or {}
    details.AutomationState = State.AutomationState
    details.Target = State.AutomationTarget
    pushEvent("AUTOMATION", kind, details)
end
local function autoGetCharacter()
    local character = State.Player and State.Player.Character
    if not character then return nil, nil, nil end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    return character, humanoid, root
end
local function autoCaptureCurrentSafePosition(reason)
    local character, humanoid, root = autoGetCharacter()
    if not character or not humanoid or not root or humanoid.Health <= 0 then
        return false
    end
    State.MovementCharacter = character
    State.MovementLastSafeCFrame = root.CFrame
    State.MovementLastSafeUnix = os.time()
    State.MovementLastSafeReason = tostring(reason or "CURRENT_POSITION_CONFIRMED_SAFE")
    autoRecord("SAFE_POSITION_CAPTURED", {
        Reason = State.MovementLastSafeReason,
        Zone = State.CurrentZone,
        X = root.Position.X,
        Y = root.Position.Y,
        Z = root.Position.Z,
    })
    return true
end
autoSetBunkerTransitionFreeze = function(active, direction, reason)
    active = active and true or false
    if active then
        State.BunkerTransitionFreezeActive = true
        State.BunkerTransitionFreezeDirection = direction
        State.BunkerTransitionFreezeStartedClock = os.clock()
        State.BunkerTransitionFreezeReason = tostring(reason or "BUNKER_TRANSITION_STARTED")
        State.BunkerTransitionFreezeCount =
            (State.BunkerTransitionFreezeCount or 0) + 1
        autoRecord("BUNKER_TRANSITION_TELEPORT_FREEZE_STARTED", {
            Direction = direction,
            Reason = State.BunkerTransitionFreezeReason,
            Policy = "AFTER_ENTER_OR_EXIT_ACTIVATION_NO_TELEPORT_UNTIL_PHYSICAL_ZONE_CONFIRMATION",
        })
    else
        local previousDirection = State.BunkerTransitionFreezeDirection
        local previousReason = State.BunkerTransitionFreezeReason
        local duration = os.clock() - (State.BunkerTransitionFreezeStartedClock or os.clock())
        State.BunkerTransitionFreezeActive = false
        State.BunkerTransitionFreezeDirection = nil
        State.BunkerTransitionFreezeStartedClock = 0
        State.BunkerTransitionFreezeReason = nil
        State.BunkerTransitionFreezeReleased =
            (State.BunkerTransitionFreezeReleased or 0) + 1
        autoRecord("BUNKER_TRANSITION_TELEPORT_FREEZE_RELEASED", {
            Direction = previousDirection,
            PreviousReason = previousReason,
            ReleaseReason = tostring(reason or "TRANSITION_RESOLVED"),
            Duration = duration,
            LastDisplacement = State.BunkerTransitionLastDisplacement,
            ConfirmMode = State.BunkerTransitionConfirmMode,
            SourcePart = State.BunkerTransitionSourcePath,
        })
        State.BunkerTransitionOriginPosition = nil
        State.BunkerTransitionSourcePart = nil
        State.BunkerTransitionSourcePath = nil
        State.BunkerTransitionLastDisplacement = 0
        State.BunkerTransitionConfirmMode = nil
    end
end

autoUpdateBunkerTransitionFreeze = function(source)
    if not State.BunkerTransitionFreezeActive then
        return false, nil, nil
    end

    local rawZone, rawEvidence = detectRawPhysicalZoneByPosition()
    State.BunkerLastRawPhysicalZone = rawZone
    State.BunkerLastRawPhysicalEvidence = rawEvidence

    local direction = State.BunkerTransitionFreezeDirection
    local age = os.clock() - (State.BunkerTransitionFreezeStartedClock or os.clock())

    local _, _, root = autoGetCharacter()
    local displacement = nil
    if root and State.BunkerTransitionOriginPosition then
        displacement = (root.Position - State.BunkerTransitionOriginPosition).Magnitude
        State.BunkerTransitionLastDisplacement = displacement
    end

    local sourceDistance = nil
    local sourcePart = State.BunkerTransitionSourcePart
    if root and sourcePart and sourcePart.Parent and sourcePart:IsDescendantOf(workspace) then
        sourceDistance = (root.Position - sourcePart.Position).Magnitude
    end

    -- During transition freeze there are no script teleports. Therefore a
    -- large displacement away from the source prompt is direct evidence that
    -- the game's Enter/Exit transition moved the character, even if a legacy
    -- object classifier still reports the wrong logical zone.
    local displacementConfirmed =
        displacement ~= nil
        and displacement >= BUNKER_TRANSITION_MIN_DISPLACEMENT
        and (sourceDistance == nil or sourceDistance >= BUNKER_TRANSITION_MIN_DISPLACEMENT)

    local rawTargetConfirmed = false
    if direction == "ENTER_BUNKER" then
        rawTargetConfirmed =
            rawZone == "BUNKER"
            and displacement ~= nil
            and displacement >= 20
            and (sourceDistance == nil or sourceDistance >= 20)
    elseif direction == "EXIT_BUNKER" then
        rawTargetConfirmed =
            rawZone == "MAIN_TYCOON"
            and displacement ~= nil
            and displacement >= 20
            and (sourceDistance == nil or sourceDistance >= 20)
    end

    if direction == "ENTER_BUNKER"
    and (displacementConfirmed or rawTargetConfirmed) then
        local confirmMode = displacementConfirmed
            and "GAME_TRANSITION_DISPLACEMENT"
            or "RAW_BUTTON_ZONE_PLUS_DISPLACEMENT"
        local confirmationEvidence =
            confirmMode ..
            "; displacement=" .. tostring(displacement and math.floor(displacement * 10) / 10 or "nil") ..
            "; sourceDistance=" .. tostring(sourceDistance and math.floor(sourceDistance * 10) / 10 or "nil") ..
            "; raw=" .. tostring(rawZone) ..
            "; rawEvidence=" .. tostring(rawEvidence)

        State.BunkerTransitionConfirmMode = confirmMode
        State.BunkerEnterInProgress = false
        State.BunkerEnterCooldownUntil = 0
        setZone("BUNKER", "BUNKER_ENTER_CONFIRMED: " .. confirmationEvidence)
        autoCaptureCurrentSafePosition("BUNKER_ENTER_CONFIRMED")
        autoSetBunkerTransitionFreeze(false, nil, "ENTER_PHYSICAL_BUNKER_CONFIRMED")
        autoRecord("BUNKER_ENTER_TRANSITION_CONFIRMED", {
            Source = tostring(source or "UNKNOWN"),
            ConfirmedZone = "BUNKER",
            RawZone = rawZone,
            Evidence = confirmationEvidence,
            Displacement = displacement,
            SourceDistance = sourceDistance,
            ConfirmMode = confirmMode,
            Age = age,
        })
        return true, "BUNKER", confirmationEvidence
    end

    if direction == "EXIT_BUNKER"
    and (displacementConfirmed or rawTargetConfirmed) then
        local confirmMode = displacementConfirmed
            and "GAME_TRANSITION_DISPLACEMENT"
            or "RAW_BUTTON_ZONE_PLUS_DISPLACEMENT"
        local confirmationEvidence =
            confirmMode ..
            "; displacement=" .. tostring(displacement and math.floor(displacement * 10) / 10 or "nil") ..
            "; sourceDistance=" .. tostring(sourceDistance and math.floor(sourceDistance * 10) / 10 or "nil") ..
            "; raw=" .. tostring(rawZone) ..
            "; rawEvidence=" .. tostring(rawEvidence)

        local completedSession = State.BunkerSessionId
        State.BunkerTransitionConfirmMode = confirmMode
        State.BunkerSessionActive = false
        State.BunkerExitInProgress = false
        State.BunkerEnterInProgress = false
        State.BunkerSessionReason = "EXIT_GAME_TRANSITION_CONFIRMED"
        State.BunkerLastCompletedSessionId = math.max(
            State.BunkerLastCompletedSessionId or 0,
            completedSession or 0
        )
        State.BunkerExitRetryUntil = 0
        State.BunkerExitSettleUntil = math.max(
            State.BunkerExitSettleUntil or 0,
            os.clock() + 0.35
        )
        setZone("MAIN_TYCOON", "BUNKER_EXIT_CONFIRMED: " .. confirmationEvidence)
        autoCaptureCurrentSafePosition("BUNKER_EXIT_CONFIRMED")
        autoSetBunkerTransitionFreeze(false, nil, "EXIT_PHYSICAL_MAIN_CONFIRMED")
        autoRecord("BUNKER_EXIT_TRANSITION_CONFIRMED", {
            Source = tostring(source or "UNKNOWN"),
            SessionId = completedSession,
            ConfirmedZone = "MAIN_TYCOON",
            RawZone = rawZone,
            Evidence = confirmationEvidence,
            Displacement = displacement,
            SourceDistance = sourceDistance,
            ConfirmMode = confirmMode,
            Age = age,
        })
        return true, "MAIN_TYCOON", confirmationEvidence
    end

    if age >= BUNKER_TRANSITION_FREEZE_TIMEOUT then
        if direction == "ENTER_BUNKER" and rawZone == "MAIN_TYCOON" then
            State.BunkerEnterInProgress = false
            State.BunkerEnterCooldownUntil =
                os.clock() + BUNKER_ENTRY_RETRY_COOLDOWN
            setZone("MAIN_TYCOON", "BUNKER_ENTER_CONFIRMED_NOT_TRANSITIONED")
            autoSetBunkerTransitionFreeze(false, nil, "ENTER_REMAINED_IN_MAIN")
            return false, rawZone, rawEvidence
        elseif direction == "EXIT_BUNKER" and rawZone == "BUNKER" then
            State.BunkerExitInProgress = false
            State.BunkerSessionActive = true
            State.BunkerSessionReason = "EXIT_CONFIRMED_NOT_TRANSITIONED"
            State.BunkerExitRetryUntil =
                os.clock() + BUNKER_EXIT_FAILURE_COOLDOWN
            setZone("BUNKER", "BUNKER_EXIT_CONFIRMED_NOT_TRANSITIONED")
            autoSetBunkerTransitionFreeze(false, nil, "EXIT_REMAINED_IN_BUNKER")
            return false, rawZone, rawEvidence
        end
    end

    return false, rawZone, rawEvidence
end

local function autoReconcileBunkerPhysicalState(source)
    local rawZone, rawEvidence = detectRawPhysicalZoneByPosition()
    State.BunkerLastRawPhysicalZone = rawZone
    State.BunkerLastRawPhysicalEvidence = rawEvidence

    if rawZone == "MAIN_TYCOON"
    and not State.BunkerEnterInProgress
    and (
        State.BunkerSessionActive
        or State.CurrentZone == "BUNKER"
        or State.BunkerExitInProgress
    ) then
        local previousSession = State.BunkerSessionId
        State.BunkerSessionActive = false
        State.BunkerExitInProgress = false
        State.BunkerEnterInProgress = false
        State.BunkerSessionReason = "PHYSICAL_MAIN_RECONCILED"
        State.BunkerExitRetryUntil = 0
        State.BunkerExitSettleUntil = math.max(
            State.BunkerExitSettleUntil or 0,
            os.clock() + 0.25
        )
        State.BunkerLastCompletedSessionId = math.max(
            State.BunkerLastCompletedSessionId or 0,
            previousSession or 0
        )
        State.BunkerPhysicalReconciliations =
            (State.BunkerPhysicalReconciliations or 0) + 1

        setZone("MAIN_TYCOON", "RAW_PHYSICAL_MAIN_RECONCILED: " .. tostring(rawEvidence))
        autoCaptureCurrentSafePosition("RAW_PHYSICAL_MAIN_RECONCILED")
        autoRecord("BUNKER_STALE_STATE_CLEARED_BY_PHYSICAL_MAIN", {
            Source = tostring(source or "UNKNOWN"),
            SessionId = previousSession,
            RawZone = rawZone,
            Evidence = rawEvidence,
            Policy = "PHYSICAL_MAIN_OVERRIDES_STALE_BUNKER_LOCK; NEVER_TELEPORT_BACK_TO_EXIT_FROM_MAIN",
        })
        return true, rawZone, rawEvidence
    end

    return false, rawZone, rawEvidence
end

local function autoTargetPart(container)
    if not container then return nil end
    local touch = container:FindFirstChild("Touch", true)
    if touch and touch:IsA("BasePart") then
        return touch
    end
    if container:IsA("Model") and container.PrimaryPart then
        return container.PrimaryPart
    end
    return container:FindFirstChildWhichIsA("BasePart", true)
end
local function autoBunkerTransitionContextActive()
    if State.BunkerTransitionFreezeActive
    or State.BunkerSessionActive
    or State.CurrentZone == "BUNKER"
    or State.BunkerEnterInProgress
    or State.BunkerExitInProgress then
        return true
    end
    if os.clock() < (State.BunkerExitSettleUntil or 0) then
        return true
    end
    return false
end

local function autoIsBunkerExitTargetPart(targetPart)
    if not targetPart then
        return false
    end
    local pathNorm = normalize(safeFullName(targetPart))
    return string.find(pathNorm, "purchasesbunkerexitprompt", 1, true) ~= nil
        or string.find(pathNorm, "bunkerexitprompt", 1, true) ~= nil
end

local function autoIsBunkerEnterTargetPart(targetPart)
    if not targetPart then
        return false
    end
    local pathNorm = normalize(safeFullName(targetPart))
    return string.find(pathNorm, "purchasesbunkerenterprompt", 1, true) ~= nil
        or string.find(pathNorm, "bunkerenterprompt", 1, true) ~= nil
end

local function autoTeleportToPart(targetPart, bunkerMode)
    local character, humanoid, root = autoGetCharacter()
    if not character or not humanoid or not root or humanoid.Health <= 0 then
        State.MovementCharacterLosses = State.MovementCharacterLosses + 1
        return false, "CHARACTER_UNAVAILABLE"
    end
    if not targetPart or not targetPart.Parent or not targetPart:IsA("BasePart") then
        return false, "TARGET_PART_UNAVAILABLE"
    end
    if not targetPart:IsDescendantOf(workspace) then
        State.MovementUnsafeDestinationRejected = State.MovementUnsafeDestinationRejected + 1
        return false, "TARGET_NOT_IN_WORKSPACE"
    end
    if State.Tycoon and State.Tycoon.Parent and not targetPart:IsDescendantOf(State.Tycoon) then
        State.MovementUnsafeDestinationRejected = State.MovementUnsafeDestinationRejected + 1
        autoRecord("SAFE_TELEPORT_REJECTED", {
            Reason = "TARGET_OUTSIDE_ACTIVE_TYCOON",
            TargetPart = safeFullName(targetPart),
        })
        return false, "TARGET_OUTSIDE_ACTIVE_TYCOON"
    end

    if State.BunkerTransitionFreezeActive then
        State.BunkerMainTeleportBlocks = State.BunkerMainTeleportBlocks + 1
        autoRecord("SAFE_TELEPORT_BLOCKED_BY_TRANSITION_FREEZE", {
            SessionId = State.BunkerSessionId,
            Zone = State.CurrentZone,
            Direction = State.BunkerTransitionFreezeDirection,
            TargetPart = safeFullName(targetPart),
            BunkerMode = bunkerMode,
            Policy = "NO_TELEPORT_AFTER_ENTER_OR_EXIT_ACTIVATION_UNTIL_RAW_PHYSICAL_ZONE_CONFIRMATION",
        })
        return false, "BUNKER_TRANSITION_FREEZE_ACTIVE"
    end

    if autoBunkerTransitionContextActive() then
        local allowed = false
        if bunkerMode == "ENTER_PROMPT"
        and State.BunkerEnterInProgress
        and autoIsBunkerEnterTargetPart(targetPart) then
            allowed = true
        elseif bunkerMode == "EXIT_PROMPT"
        and State.BunkerExitInProgress
        and autoIsBunkerExitTargetPart(targetPart) then
            allowed = true
        elseif bunkerMode == "BUNKER_PURCHASE"
        and State.BunkerSessionActive
        and State.CurrentZone == "BUNKER"
        and State.ButtonsFolder
        and targetPart:IsDescendantOf(State.ButtonsFolder) then
            allowed = true
        end

        if not allowed then
            State.BunkerMainTeleportBlocks = State.BunkerMainTeleportBlocks + 1
            autoRecord("SAFE_TELEPORT_BLOCKED_BY_BUNKER_BOUNDARY", {
                SessionId = State.BunkerSessionId,
                Zone = State.CurrentZone,
                TargetPart = safeFullName(targetPart),
                BunkerMode = bunkerMode,
                Policy = "BUNKER_CONTEXT_ALLOWS_ONLY_ENTER_PROMPT_BEFORE_ACTIVATION, ELIGIBLE_BUNKER_PURCHASES, OR_EXIT_PROMPT_BEFORE_ACTIVATION",
            })
            return false, "BUNKER_BOUNDARY_EXIT_REQUIRED"
        end
    end

    if State.MovementCharacter ~= character then
        State.MovementCharacter = character
        State.MovementLastSafeCFrame = root.CFrame
        State.MovementLastSafeUnix = os.time()
        State.MovementLastSafeReason = "CHARACTER_ACQUIRED"
    end

    State.MovementSafeTeleportAttempts = State.MovementSafeTeleportAttempts + 1

    local originCFrame = root.CFrame
    local destinationPosition = targetPart.Position + Vector3.new(0, 2.6, 0)

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {character}
    rayParams.IgnoreWater = false

    local groundResult = workspace:Raycast(
        destinationPosition + Vector3.new(0, 0.5, 0),
        Vector3.new(0, -14, 0),
        rayParams
    )

    if not groundResult then
        State.MovementUnsafeDestinationRejected = State.MovementUnsafeDestinationRejected + 1
        autoRecord("SAFE_TELEPORT_REJECTED", {
            Reason = "NO_SURFACE_BELOW_TARGET",
            TargetPart = safeFullName(targetPart),
            TargetX = targetPart.Position.X,
            TargetY = targetPart.Position.Y,
            TargetZ = targetPart.Position.Z,
        })
        return false, "UNSAFE_DESTINATION_NO_SURFACE"
    end

    local surfaceGap = destinationPosition.Y - groundResult.Position.Y
    if surfaceGap > 10.5 then
        State.MovementUnsafeDestinationRejected = State.MovementUnsafeDestinationRejected + 1
        autoRecord("SAFE_TELEPORT_REJECTED", {
            Reason = "SURFACE_TOO_FAR_BELOW",
            TargetPart = safeFullName(targetPart),
            SurfaceGap = surfaceGap,
            Surface = safeFullName(groundResult.Instance),
        })
        return false, "UNSAFE_DESTINATION_SURFACE_TOO_LOW"
    end

    local function recover(reason)
        State.MovementRecoveryAttempts = State.MovementRecoveryAttempts + 1

        local restoreCFrame = State.MovementLastSafeCFrame or originCFrame
        local restored = false

        if root.Parent and humanoid.Parent and humanoid.Health > 0 then
            restored = pcall(function()
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                root.CFrame = restoreCFrame
            end)
        end

        if restored then
            State.MovementRecoverySuccessful = State.MovementRecoverySuccessful + 1
        else
            State.MovementCharacterLosses = State.MovementCharacterLosses + 1
        end

        autoRecord("SAFE_TELEPORT_RECOVERY", {
            Reason = reason,
            Restored = restored,
            TargetPart = safeFullName(targetPart),
            Surface = safeFullName(groundResult.Instance),
        })

        return false, reason
    end

    local destination = CFrame.new(destinationPosition) * root.CFrame.Rotation
    local ok, err = pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        root.CFrame = destination
    end)

    if not ok then
        return recover("TELEPORT_FAILED:" .. tostring(err))
    end

    task.wait(0.12)

    if not root.Parent or not humanoid.Parent or humanoid.Health <= 0 then
        State.MovementCharacterLosses = State.MovementCharacterLosses + 1
        return false, "CHARACTER_LOST_AFTER_TELEPORT"
    end

    local firstDistance = (root.Position - targetPart.Position).Magnitude
    local firstDrop = destinationPosition.Y - root.Position.Y
    if firstDistance > 7 or firstDrop > 6 or root.AssemblyLinearVelocity.Y < -55 then
        return recover(
            firstDistance > 7 and "TELEPORT_NOT_CONFIRMED"
            or firstDrop > 6 and "POST_TELEPORT_DROP_DETECTED"
            or "POST_TELEPORT_FAST_FALL_DETECTED"
        )
    end

    task.wait(0.18)

    if not root.Parent or not humanoid.Parent or humanoid.Health <= 0 then
        State.MovementCharacterLosses = State.MovementCharacterLosses + 1
        return false, "CHARACTER_LOST_DURING_POSTCHECK"
    end

    local finalDistance = (root.Position - targetPart.Position).Magnitude
    local finalDrop = destinationPosition.Y - root.Position.Y
    if finalDistance > 8 or finalDrop > 6 or root.AssemblyLinearVelocity.Y < -55 then
        return recover(
            finalDistance > 8 and "POST_TELEPORT_POSITION_UNSTABLE"
            or finalDrop > 6 and "POST_TELEPORT_DROP_DETECTED"
            or "POST_TELEPORT_FAST_FALL_DETECTED"
        )
    end

    State.MovementLastSafeCFrame = root.CFrame
    State.MovementLastSafeUnix = os.time()
    State.MovementLastSafeReason = "SAFE_TELEPORT_CONFIRMED"
    State.MovementSafeTeleportConfirmed = State.MovementSafeTeleportConfirmed + 1

    return true, "TELEPORT_POSITION_CONFIRMED"
end

local function autoCollectorContainer()
    if not State.Tycoon then
        return nil
    end
    local direct = State.Tycoon:FindFirstChild("Collector", true)
    if direct then
        return direct
    end
    for _, descendant in ipairs(State.Tycoon:GetDescendants()) do
        if normalize(descendant.Name) == "collector" then
            return descendant
        end
    end
    return nil
end
local function autoCollectorAmount()
    local collector = autoCollectorContainer()
    if not collector then
        return nil, nil
    end
    for _, descendant in ipairs(collector:GetDescendants()) do
        if normalize(descendant.Name) == "money" then
            local value = readValue(descendant)
            if value ~= nil then
                return value, safeFullName(descendant)
            end
        end
    end
    return nil, nil
end
local function autoCollectorTouchPart()
    local collector = autoCollectorContainer()
    if not collector then
        return nil
    end
    for _, descendant in ipairs(collector:GetDescendants()) do
        if descendant:IsA("BasePart")
        and descendant:FindFirstChildWhichIsA("TouchTransmitter") then
            return descendant
        end
    end
    local preferred = {
        "touch", "collect", "collector", "totem", "pad", "button", "claim"
    }
    for _, wanted in ipairs(preferred) do
        for _, descendant in ipairs(collector:GetDescendants()) do
            if descendant:IsA("BasePart") then
                local n = normalize(descendant.Name)
                if string.find(n, wanted, 1, true) then
                    return descendant
                end
            end
        end
    end
    if collector:IsA("BasePart") then
        return collector
    end
    return collector:FindFirstChildWhichIsA("BasePart", true)
end
local function autoTeleportToCollectorAndConfirm()
    if State.BunkerSessionActive
    or State.CurrentZone == "BUNKER"
    or State.BunkerEnterInProgress
    or State.BunkerExitInProgress then
        autoRecord("TOTEM_COLLECT_BLOCKED_BY_BUNKER_STATE", {
            SessionId = State.BunkerSessionId,
            SessionActive = State.BunkerSessionActive,
            Zone = State.CurrentZone,
            EnterInProgress = State.BunkerEnterInProgress,
            ExitInProgress = State.BunkerExitInProgress,
            Policy = "COLLECTOR_TELEPORT_FORBIDDEN_UNTIL_EXIT_PROMPT_CONFIRMS_MAIN",
        })
        return false, "BUNKER_EXIT_REQUIRED_BEFORE_COLLECT"
    end

    local collectorBefore, collectorPath = autoCollectorAmount()
    local moneyObject = findStat(MONEY_NAMES) or State.MoneyObject
    if moneyObject and moneyObject.Parent then
        State.MoneyObject = moneyObject
        local liveMoney = readValue(moneyObject)
        if liveMoney ~= nil then
            State.LastMoney = liveMoney
        end
    end
    local moneyBefore = State.LastMoney
    if collectorBefore == nil then
        return false, "COLLECTOR_AMOUNT_UNAVAILABLE"
    end
    if collectorBefore < AUTO_COLLECT_MIN then
        return false, "COLLECTOR_BELOW_THRESHOLD"
    end
    if moneyBefore == nil then
        return false, "MONEY_UNAVAILABLE"
    end
    local targetPart = autoCollectorTouchPart()
    if not targetPart then
        return false, "COLLECTOR_TOUCH_PART_NOT_FOUND"
    end
    local character, humanoid, root = autoGetCharacter()
    if not character or not humanoid or not root or humanoid.Health <= 0 then
        return false, "CHARACTER_UNAVAILABLE"
    end
    local attempt = {
        Id = #State.TotemCollectAttempts + 1,
        StartedUnix = os.time(),
        StartedElapsed = elapsed(),
        CollectorBefore = collectorBefore,
        CollectorPath = collectorPath,
        MoneyBefore = moneyBefore,
        TargetPart = safeFullName(targetPart),
        Result = "STARTED",
    }
    table.insert(State.TotemCollectAttempts, attempt)
    State.AutomationState = "COLLECTING_TOTEM"
    State.Health.Automation = "COLLECTING_TOTEM"
    State.LastTotemCollectClock = os.clock()
    autoRecord("TOTEM_COLLECT_STARTED", {
        CollectAttemptId = attempt.Id,
        CollectorBefore = collectorBefore,
        MoneyBefore = moneyBefore,
        TargetPart = attempt.TargetPart,
        Movement = "SAFE_WORLD_Y_TELEPORT_WITH_SURFACE_CHECK_AND_RECOVERY",
    })
    local ok, teleportReason = autoTeleportToPart(targetPart)
    if not ok then
        attempt.Result = teleportReason or "TELEPORT_FAILED"
        attempt.FinishedUnix = os.time()
        attempt.FinishedElapsed = elapsed()
        State.TotemCollectFailed = State.TotemCollectFailed + 1
        autoRecord("TOTEM_COLLECT_FAILED", {
            CollectAttemptId = attempt.Id,
            Reason = attempt.Result,
        })
        return false, attempt.Result
    end
    local deadline = os.clock() + AUTO_COLLECT_CONFIRM_TIMEOUT
    local highestMoney = moneyBefore
    while State.Running and State.AutomationEnabled and os.clock() < deadline do
        local currentMoney = readValue(State.MoneyObject)
        if currentMoney ~= nil then
            State.LastMoney = currentMoney
            highestMoney = math.max(highestMoney, currentMoney)
            if currentMoney > moneyBefore then
                local collectorAfter = select(1, autoCollectorAmount())
                attempt.Result = "MONEY_INCREASE_CONFIRMED"
                attempt.MoneyAfter = currentMoney
                attempt.CollectorAfter = collectorAfter
                attempt.FinishedUnix = os.time()
                attempt.FinishedElapsed = elapsed()
                State.TotemCollectSuccessful = State.TotemCollectSuccessful + 1
                autoRefreshFundsBlocks()
                autoRecord("TOTEM_COLLECT_SUCCESS_CONFIRMED", {
                    CollectAttemptId = attempt.Id,
                    MoneyBefore = moneyBefore,
                    MoneyAfter = currentMoney,
                    MoneyDelta = currentMoney - moneyBefore,
                    CollectorBefore = collectorBefore,
                    CollectorAfter = collectorAfter,
                    Evidence = "REAL_WALLET_INCREASED",
                })
                return true, "MONEY_INCREASE_CONFIRMED"
            end
        end
        task.wait(0.03)
    end
    attempt.Result = "MONEY_DID_NOT_INCREASE"
    attempt.MoneyAfter = highestMoney
    attempt.CollectorAfter = select(1, autoCollectorAmount())
    attempt.FinishedUnix = os.time()
    attempt.FinishedElapsed = elapsed()
    State.TotemCollectFailed = State.TotemCollectFailed + 1
    autoRecord("TOTEM_COLLECT_FAILED", {
        CollectAttemptId = attempt.Id,
        Reason = "MONEY_DID_NOT_INCREASE",
        MoneyBefore = moneyBefore,
        MoneyAfter = highestMoney,
        CollectorBefore = collectorBefore,
        CollectorAfter = attempt.CollectorAfter,
    })
    return false, "MONEY_DID_NOT_INCREASE"
end
local function autoBindServerResponseSignals()
    local remotes = ReplicatedStorage:FindFirstChild("__remotes")
    local tycoonService = remotes and remotes:FindFirstChild("TycoonService")
    if not tycoonService then
        return
    end
    local purchased = tycoonService:FindFirstChild("ButtonPurchased")
    local rejected = tycoonService:FindFirstChild("ButtonCannotPurchase")
    local setCanRebirth = tycoonService:FindFirstChild("SetCanRebirth")
    local function bind(remote, status)
        if not remote or not remote:IsA("RemoteEvent") then
            return
        end
        addConnection(remote.OnClientEvent, function(...)
            if not State.AutomationEnabled or not State.AutomationTarget then
                return
            end
            State.AutomationServerSignalSeq = State.AutomationServerSignalSeq + 1
            State.AutomationServerSignal = {
                Seq = State.AutomationServerSignalSeq,
                Clock = os.clock(),
                Status = status,
                Remote = safeFullName(remote),
                Target = State.AutomationTarget,
                ArgsCount = select("#", ...),
            }
            autoRecord("SERVER_PURCHASE_RESPONSE_OBSERVED", {
                Status = status,
                Remote = safeFullName(remote),
                Target = State.AutomationTarget,
                SignalSeq = State.AutomationServerSignalSeq,
            })
        end)
    end
    bind(purchased, "ACCEPTED")
    bind(rejected, "REJECTED")
    if setCanRebirth and setCanRebirth:IsA("RemoteEvent") then
        addConnection(setCanRebirth.OnClientEvent, function(scopeName, value)
            if tostring(scopeName) ~= "Tycoon" then
                return
            end
            State.AutoRebirthServerSignalSeen = true
            State.AutoRebirthLastSignalUnix = os.time()
            State.AutoRebirthLastSignalElapsed = elapsed()
            State.AutoRebirthLastSignalValue = value
            if typeof(value) == "boolean" then
                State.AutoRebirthServerReady = value == true
                if value == true then
                    State.AutoRebirthButtonsLeft = 0
                end
            elseif typeof(value) == "number" then
                State.AutoRebirthButtonsLeft = value
                State.AutoRebirthServerReady = false
            else
                State.AutoRebirthServerReady = false
            end
            if State.Reading then
                pushEvent("AUTOMATION", "AUTO_REBIRTH_SERVER_STATE", {
                    Scope = tostring(scopeName),
                    ValueType = typeof(value),
                    Value = (typeof(value) == "number" or typeof(value) == "boolean" or typeof(value) == "string")
                        and value
                        or "<" .. tostring(typeof(value)) .. ">",
                    Ready = State.AutoRebirthServerReady,
                    ButtonsLeft = State.AutoRebirthButtonsLeft,
                    Rebirths = State.LastRebirths,
                })
            end
        end)
    end
end
local function autoWaitForAcceptance(buttonName, originalButton, timeout)
    timeout = timeout or AUTO_SERVER_WAIT
    local started = os.clock()
    local startSeq = State.AutomationServerSignalSeq
    while State.Running and State.AutomationEnabled and os.clock() - started <= timeout do
        local signal = State.AutomationServerSignal
        if signal
        and signal.Seq > startSeq
        and signal.Target == buttonName then
            if signal.Status == "ACCEPTED" then
                return true, "SERVER_BUTTON_PURCHASED"
            elseif signal.Status == "REJECTED" then
                return false, "SERVER_BUTTON_CANNOT_PURCHASE"
            end
        end
        local buttonGone = not originalButton or not originalButton.Parent
        local purchaseExists = State.PurchasesFolder
            and State.PurchasesFolder:FindFirstChild(buttonName) ~= nil
        if buttonGone or purchaseExists then
            return true, buttonGone and "BUTTON_REMOVED" or "PURCHASE_CREATED"
        end
        task.wait(0.03)
    end
    return false, "NO_ACCEPTANCE_OBSERVED"
end
local function autoFindBunkerPrompt(actionText)
    if not State.PurchasesFolder then
        return nil
    end
    local bunker = State.PurchasesFolder:FindFirstChild("Bunker")
    if not bunker then
        return nil
    end

    local wanted = normalize(actionText)
    local wantedDirection = nil
    if wanted == "enter" or wanted == "entrada" then
        wantedDirection = "ENTER_BUNKER"
    elseif wanted == "exit" or wanted == "leave" or wanted == "return"
    or wanted == "sair" or wanted == "saida" then
        wantedDirection = "EXIT_BUNKER"
    end

    for _, descendant in ipairs(bunker:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") then
            local direction = classifyTransitionPrompt(descendant)
            if wantedDirection then
                if direction == wantedDirection then
                    return descendant
                end
            elseif actionText and textContains(descendant.ActionText, actionText) then
                return descendant
            end
        end
    end

    -- IMPORTANT: when a direction was requested, never return the opposite
    -- prompt as a fallback. A missing ExitPrompt must stay missing until it
    -- actually exists.
    return nil
end
local function autoPromptPart(prompt)
    return transitionPromptPart(prompt)
end
local function autoTriggerBunkerPrompt(prompt, targetZone, labelPrefix)
    if not prompt then
        return false, "PROMPT_NOT_FOUND"
    end
    local part = autoPromptPart(prompt)
    if not part then
        return false, "PROMPT_PART_NOT_FOUND"
    end

    local direction = targetZone == "BUNKER" and "ENTER_BUNKER" or "EXIT_BUNKER"
    local mode = targetZone == "BUNKER" and "ENTER_PROMPT" or "EXIT_PROMPT"

    if targetZone == "BUNKER" then
        State.BunkerEnterInProgress = true
        State.BunkerEnterPromptObservedClock = 0
    else
        State.BunkerExitInProgress = true
        State.BunkerExitPromptObservedClock = 0
    end

    State.AutomationState = targetZone == "BUNKER"
        and "POSITIONING_BUNKER_ENTER"
        or "POSITIONING_BUNKER_EXIT"
    State.Health.Automation = State.AutomationState

    local positioned, positionReason = autoTeleportToPart(part, mode)
    if not positioned then
        if targetZone == "BUNKER" then
            State.BunkerEnterInProgress = false
        else
            State.BunkerExitInProgress = false
        end
        autoRecord(labelPrefix .. "_POSITION_FAILED", {
            Prompt = safeFullName(prompt),
            TargetPart = safeFullName(part),
            Reason = positionReason,
            Movement = "SAFE_TELEPORT_TO_TRANSITION_PROMPT_ONLY",
        })
        return false, positionReason
    end

    local _, _, originRoot = autoGetCharacter()
    if not originRoot then
        return false, "CHARACTER_UNAVAILABLE_BEFORE_PROMPT"
    end
    local transitionOrigin = originRoot.Position
    local transitionStartedClock = os.clock()
    State.BunkerTransitionOriginPosition = transitionOrigin
    State.BunkerTransitionSourcePart = part
    State.BunkerTransitionSourcePath = safeFullName(part)
    State.BunkerTransitionLastDisplacement = 0
    State.BunkerTransitionConfirmMode = nil

    local transition = {
        Id = #State.BunkerTransitionLog + 1,
        FromZone = State.CurrentZone,
        TargetZone = targetZone,
        Prompt = safeFullName(prompt),
        TargetPart = safeFullName(part),
        ActionText = prompt.ActionText,
        StartedUnix = os.time(),
        StartedElapsed = elapsed(),
        Result = "STARTED",
        Movement = "SAFE_TELEPORT_TO_PROMPT_THEN_TELEPORT_FREEZE",
    }
    table.insert(State.BunkerTransitionLog, transition)

    local activationMethod = nil
    local promptOk = false
    if type(fireproximityprompt) == "function" then
        promptOk = pcall(function()
            fireproximityprompt(prompt)
        end)
        if promptOk then
            activationMethod = "FIREPROXIMITYPROMPT"
        end
    else
        promptOk = pcall(function()
            prompt:InputHoldBegin()
            task.wait(math.max(0.10, tonumber(prompt.HoldDuration) or 0) + 0.12)
            prompt:InputHoldEnd()
        end)
        if promptOk then
            activationMethod = "INPUT_HOLD"
        end
    end

    autoRecord(labelPrefix .. "_PROMPT_STARTED", {
        TransitionId = transition.Id,
        Prompt = transition.Prompt,
        TargetPart = transition.TargetPart,
        ActionText = transition.ActionText,
        PositionReason = positionReason,
        ActivationMethod = activationMethod,
        Movement = transition.Movement,
    })

    if not promptOk then
        if targetZone == "BUNKER" then
            State.BunkerEnterInProgress = false
        else
            State.BunkerExitInProgress = false
        end
        transition.Result = "PROMPT_TRIGGER_FAILED"
        transition.FinishedUnix = os.time()
        transition.FinishedElapsed = elapsed()
        return false, "PROMPT_TRIGGER_FAILED"
    end

    autoSetBunkerTransitionFreeze(
        true,
        direction,
        labelPrefix .. "_PROMPT_ACTIVATED"
    )

    local deadline = os.clock() + BUNKER_TRANSITION_FREEZE_TIMEOUT
    while State.Running and State.AutomationEnabled and os.clock() < deadline do
        local resolved, rawZone, rawEvidence =
            autoUpdateBunkerTransitionFreeze(labelPrefix .. "_WAIT")
        if resolved and rawZone == targetZone then
            local _, _, currentRoot = autoGetCharacter()
            local displacement = currentRoot
                and (currentRoot.Position - transitionOrigin).Magnitude
                or nil
            transition.Result = "ZONE_CONFIRMED"
            transition.FinishedUnix = os.time()
            transition.FinishedElapsed = elapsed()
            transition.Displacement = displacement
            transition.PromptObserved =
                direction == "ENTER_BUNKER"
                    and (State.BunkerEnterPromptObservedClock or 0) >= transitionStartedClock - 0.10
                or direction == "EXIT_BUNKER"
                    and (State.BunkerExitPromptObservedClock or 0) >= transitionStartedClock - 0.10
            transition.PhysicalEvidence = rawEvidence
            transition.ActivationMethod = activationMethod
            State.BunkerLastTransitionEvidence = tostring(rawEvidence)
            autoRecord(labelPrefix .. "_ZONE_CONFIRMED", {
                TransitionId = transition.Id,
                FromZone = transition.FromZone,
                ToZone = targetZone,
                Displacement = displacement,
                PromptObserved = transition.PromptObserved,
                PhysicalEvidence = rawEvidence,
                ActivationMethod = activationMethod,
                Movement = transition.Movement,
                Policy = "RAW_PHYSICAL_ZONE_CONFIRMATION_RELEASES_TELEPORT_FREEZE",
            })
            return true, "ZONE_CONFIRMED_RAW_PHYSICAL"
        end
        task.wait(0.05)
    end

    local _, timeoutRawZone, timeoutEvidence =
        autoUpdateBunkerTransitionFreeze(labelPrefix .. "_TIMEOUT")
    if State.BunkerTransitionFreezeActive then
        if direction == "ENTER_BUNKER" and timeoutRawZone == "MAIN_TYCOON" then
            State.BunkerEnterInProgress = false
            State.BunkerEnterCooldownUntil =
                os.clock() + BUNKER_ENTRY_RETRY_COOLDOWN
            autoSetBunkerTransitionFreeze(false, nil, "ENTER_REMAINED_IN_MAIN_TIMEOUT")
        elseif direction == "EXIT_BUNKER" and timeoutRawZone == "BUNKER" then
            State.BunkerExitInProgress = false
            State.BunkerSessionActive = true
            State.BunkerExitRetryUntil =
                os.clock() + BUNKER_EXIT_FAILURE_COOLDOWN
            autoSetBunkerTransitionFreeze(false, nil, "EXIT_REMAINED_IN_BUNKER_TIMEOUT")
        end
    end

    transition.Result = "ZONE_NOT_CONFIRMED"
    transition.FinishedUnix = os.time()
    transition.FinishedElapsed = elapsed()
    transition.PhysicalEvidence = timeoutEvidence
    autoRecord(labelPrefix .. "_ZONE_TIMEOUT", {
        TransitionId = transition.Id,
        CurrentZone = State.CurrentZone,
        ExpectedZone = targetZone,
        RawPhysicalZone = timeoutRawZone,
        RawPhysicalEvidence = timeoutEvidence,
        TeleportFreezeActive = State.BunkerTransitionFreezeActive,
        Policy = "NO_CROSS_ZONE_TELEPORT_DURING_UNCONFIRMED_TRANSITION",
    })
    return false, "ZONE_NOT_CONFIRMED"
end
local function autoEnterBunker()
    if State.BunkerSessionActive and State.CurrentZone == "BUNKER" then
        return true, "ALREADY_IN_BUNKER_SESSION"
    end
    if os.clock() < (State.BunkerEnterCooldownUntil or 0) then
        return false, "BUNKER_ENTER_RETRY_COOLDOWN"
    end

    State.AutomationState = "ENTERING_BUNKER"
    State.Health.Automation = "ENTERING_BUNKER"
    local prompt = autoFindBunkerPrompt("enter")
    local entered, reason = autoTriggerBunkerPrompt(prompt, "BUNKER", "BUNKER_ENTER")
    if entered then
        if not State.BunkerSessionActive then
            State.BunkerSessionId = State.BunkerSessionId + 1
        end
        State.BunkerSessionActive = true
        State.BunkerSessionStartedUnix = State.BunkerSessionStartedUnix or os.time()
        State.BunkerSessionStartedElapsed = State.BunkerSessionStartedElapsed or elapsed()
        State.BunkerSessionReason = "ENTER_PROMPT_AND_PHYSICAL_CONFIRMED"
        State.BunkerExitInProgress = false
        autoRecord("BUNKER_SESSION_LOCKED", {
            SessionId = State.BunkerSessionId,
            Reason = reason,
            Zone = State.CurrentZone,
            Policy = "ENTER_ONLY_FOR_ELIGIBLE_BUNKER_TARGET; LOCK_UNTIL_QUEUE_EMPTY; EXIT_TELEPORT_TARGET_ONLY",
        })
    end
    return entered, reason
end

local function autoPresentEligibleBunkerButtons()
    local result = {
        Count = 0,
        Names = {},
    }
    if not State.ButtonsFolder or not State.ButtonsFolder.Parent then
        return result
    end

    local candidates = buildAutomationCandidates().Eligible
    for _, record in ipairs(candidates) do
        local isRootBunker =
            normalize(record.Name) == "bunker"
            and (record.Dependency == nil or tostring(record.Dependency) == "")
        if not isRootBunker and record.Zone == "BUNKER" then
            local button = State.ButtonsFolder:FindFirstChild(record.Name)
            if button and button.Parent then
                result.Count = result.Count + 1
                table.insert(result.Names, tostring(record.Name))
            end
        end
    end
    table.sort(result.Names)
    return result
end

local function autoExitBunker()
    local pendingBunker = autoPresentEligibleBunkerButtons()
    if pendingBunker.Count > 0 then
        autoRecord("BUNKER_EXIT_BLOCKED_ITEMS_REMAIN", {
            SessionId = State.BunkerSessionId,
            PendingCount = pendingBunker.Count,
            PendingNames = pendingBunker.Names,
            Policy = "EXIT_TELEPORT_IS_FORBIDDEN_UNTIL_ALL_ELIGIBLE_BUNKER_ITEMS_ARE_GONE",
        })
        return false, "BUNKER_ELIGIBLE_ITEMS_REMAIN"
    end

    local reconciled, rawZone, rawEvidence =
        autoReconcileBunkerPhysicalState("AUTO_EXIT_PRECHECK")
    if reconciled or rawZone == "MAIN_TYCOON" then
        return true, "ALREADY_PHYSICALLY_IN_MAIN"
    end

    if not State.BunkerSessionActive and State.CurrentZone == "MAIN_TYCOON" then
        if os.clock() < (State.BunkerExitSettleUntil or 0) then
            return false, "BUNKER_EXIT_SETTLE_ACTIVE"
        end
        return true, "ALREADY_IN_MAIN_TYCOON_WITHOUT_SESSION"
    end

    if os.clock() < (State.BunkerExitRetryUntil or 0) then
        return false, "BUNKER_EXIT_RETRY_COOLDOWN"
    end

    State.AutomationState = "EXITING_BUNKER"
    State.Health.Automation = "EXITING_BUNKER"
    State.BunkerExitInProgress = true
    State.BunkerExitPromptObservedClock = 0

    local prompt = nil
    local discoveryDeadline = os.clock() + BUNKER_EXIT_PROMPT_DISCOVERY_TIMEOUT
    repeat
        prompt = autoFindBunkerPrompt("exit")
        if prompt then
            break
        end

        local nowReconciled, nowRawZone =
            autoReconcileBunkerPhysicalState("EXIT_PROMPT_DISCOVERY")
        if nowReconciled or nowRawZone == "MAIN_TYCOON" then
            State.BunkerExitInProgress = false
            return true, "PHYSICAL_MAIN_DURING_EXIT_DISCOVERY"
        end
        task.wait(0.08)
    until os.clock() >= discoveryDeadline

    if not prompt then
        State.BunkerExitInProgress = false
        State.BunkerExitFailureCount = (State.BunkerExitFailureCount or 0) + 1
        State.BunkerExitRetryUntil = os.clock() + BUNKER_EXIT_FAILURE_COOLDOWN
        autoRecord("BUNKER_EXIT_PROMPT_NOT_READY", {
            SessionId = State.BunkerSessionId,
            RetryAfter = BUNKER_EXIT_FAILURE_COOLDOWN,
            Policy = "STRICT_EXIT_PROMPT_ONLY; NEVER_FALLBACK_TO_ENTER_PROMPT",
        })
        return false, "EXIT_PROMPT_NOT_FOUND"
    end

    if classifyTransitionPrompt(prompt) ~= "EXIT_BUNKER" then
        State.BunkerExitInProgress = false
        State.BunkerExitFailureCount = (State.BunkerExitFailureCount or 0) + 1
        State.BunkerExitRetryUntil = os.clock() + BUNKER_EXIT_FAILURE_COOLDOWN
        autoRecord("BUNKER_EXIT_WRONG_PROMPT_REJECTED", {
            SessionId = State.BunkerSessionId,
            Prompt = safeFullName(prompt),
            ActionText = prompt.ActionText,
            Policy = "NEVER_USE_ENTER_PROMPT_AS_EXIT",
        })
        return false, "EXIT_PROMPT_DIRECTION_MISMATCH"
    end

    local part = autoPromptPart(prompt)
    if not part then
        State.BunkerExitInProgress = false
        State.BunkerExitRetryUntil = os.clock() + BUNKER_EXIT_FAILURE_COOLDOWN
        return false, "EXIT_PROMPT_PART_NOT_FOUND"
    end

    -- Reconcile again immediately before the only allowed Bunker teleport.
    -- If the game has already returned the player to MAIN, never teleport
    -- them back into the Bunker just to reach Exit.
    local beforeTeleportReconciled, beforeTeleportRaw =
        autoReconcileBunkerPhysicalState("EXIT_BEFORE_TELEPORT")
    if beforeTeleportReconciled or beforeTeleportRaw == "MAIN_TYCOON" then
        State.BunkerExitInProgress = false
        return true, "PHYSICAL_MAIN_BEFORE_EXIT_TELEPORT"
    end

    State.BunkerExitOnlyTeleportAttempts = State.BunkerExitOnlyTeleportAttempts + 1
    autoRecord("BUNKER_EXIT_ONLY_TELEPORT_STARTED", {
        SessionId = State.BunkerSessionId,
        Prompt = safeFullName(prompt),
        TargetPart = safeFullName(part),
        RawPhysicalZone = beforeTeleportRaw,
        Policy = "EXIT_PROMPT_IS_THE_ONLY_TELEPORT_TARGET_ALLOWED_DURING_BUNKER_SESSION",
    })

    local positioned, positionReason = autoTeleportToPart(part, "EXIT_PROMPT")
    if not positioned then
        local afterFailReconciled, afterFailRaw =
            autoReconcileBunkerPhysicalState("EXIT_POSITION_FAILED")
        if afterFailReconciled or afterFailRaw == "MAIN_TYCOON" then
            State.BunkerExitInProgress = false
            return true, "PHYSICAL_MAIN_AFTER_EXIT_POSITION_FAILURE"
        end
        State.BunkerExitInProgress = false
        State.BunkerSessionReason = "EXIT_POSITION_FAILED_SESSION_RETAINED"
        State.BunkerExitFailureCount = (State.BunkerExitFailureCount or 0) + 1
        State.BunkerExitRetryUntil = os.clock() + BUNKER_EXIT_FAILURE_COOLDOWN
        autoRecord("BUNKER_EXIT_ONLY_TELEPORT_FAILED", {
            SessionId = State.BunkerSessionId,
            Reason = positionReason,
            TargetPart = safeFullName(part),
            RetryAfter = BUNKER_EXIT_FAILURE_COOLDOWN,
        })
        return false, positionReason
    end

    local _, _, originRoot = autoGetCharacter()
    if not originRoot then
        State.BunkerExitInProgress = false
        return false, "CHARACTER_UNAVAILABLE_BEFORE_EXIT_PROMPT"
    end
    local originPosition = originRoot.Position
    local transitionStartedClock = os.clock()
    State.BunkerTransitionOriginPosition = originPosition
    State.BunkerTransitionSourcePart = part
    State.BunkerTransitionSourcePath = safeFullName(part)
    State.BunkerTransitionLastDisplacement = 0
    State.BunkerTransitionConfirmMode = nil

    local transition = {
        Id = #State.BunkerTransitionLog + 1,
        FromZone = State.CurrentZone,
        TargetZone = "MAIN_TYCOON",
        Prompt = safeFullName(prompt),
        TargetPart = safeFullName(part),
        ActionText = prompt.ActionText,
        StartedUnix = os.time(),
        StartedElapsed = elapsed(),
        Result = "STARTED",
        Movement = "SAFE_TELEPORT_TO_EXIT_PROMPT_ONLY_THEN_REAL_EXIT_PROMPT",
    }
    table.insert(State.BunkerTransitionLog, transition)

    local activationMethod = nil
    local promptOk = false
    if type(fireproximityprompt) == "function" then
        promptOk = pcall(function()
            fireproximityprompt(prompt)
        end)
        if promptOk then
            activationMethod = "FIREPROXIMITYPROMPT"
        end
    else
        promptOk = pcall(function()
            prompt:InputHoldBegin()
            task.wait(math.max(0.10, tonumber(prompt.HoldDuration) or 0) + 0.12)
            prompt:InputHoldEnd()
        end)
        if promptOk then
            activationMethod = "INPUT_HOLD"
        end
    end

    autoRecord("BUNKER_EXIT_PROMPT_STARTED", {
        TransitionId = transition.Id,
        Prompt = transition.Prompt,
        TargetPart = transition.TargetPart,
        ActionText = transition.ActionText,
        PositionReason = positionReason,
        ActivationMethod = activationMethod,
        Movement = transition.Movement,
    })

    if not promptOk then
        State.BunkerExitInProgress = false
        State.BunkerSessionActive = true
        State.BunkerSessionReason = "EXIT_PROMPT_TRIGGER_FAILED_SESSION_RETAINED"
        State.BunkerExitFailureCount = (State.BunkerExitFailureCount or 0) + 1
        State.BunkerExitRetryUntil = os.clock() + BUNKER_EXIT_FAILURE_COOLDOWN
        return false, "EXIT_PROMPT_TRIGGER_FAILED"
    end

    autoSetBunkerTransitionFreeze(
        true,
        "EXIT_BUNKER",
        "BUNKER_EXIT_PROMPT_ACTIVATED"
    )

    local deadline = os.clock() + BUNKER_TRANSITION_FREEZE_TIMEOUT
    while State.Running and State.AutomationEnabled and os.clock() < deadline do
        local resolved, nowRawZone, nowRawEvidence =
            autoUpdateBunkerTransitionFreeze("AUTO_EXIT_WAIT")
        if resolved and nowRawZone == "MAIN_TYCOON" then
            local _, _, currentRoot = autoGetCharacter()
            local displacement = currentRoot
                and (currentRoot.Position - originPosition).Magnitude
                or nil
            local exitObserved =
                (State.BunkerExitPromptObservedClock or 0) > 0
                and (State.BunkerExitPromptObservedClock or 0) >= transitionStartedClock - 0.10

            transition.Result = "ZONE_CONFIRMED"
            transition.FinishedUnix = os.time()
            transition.FinishedElapsed = elapsed()
            transition.Displacement = displacement
            transition.PromptObserved = exitObserved
            transition.PhysicalEvidence = nowRawEvidence
            transition.ActivationMethod = activationMethod
            autoRecord("BUNKER_SESSION_RELEASED", {
                SessionId = State.BunkerSessionId,
                Reason = State.BunkerSessionReason,
                ExitPolicy = "TELEPORT_TO_EXIT_ONLY; ACTIVATE_REAL_EXIT; FREEZE_ALL_TELEPORTS_UNTIL_RAW_PHYSICAL_MAIN",
                Displacement = displacement,
                PromptObserved = exitObserved,
                RawPhysicalZone = nowRawZone,
                RawPhysicalEvidence = nowRawEvidence,
                ActivationMethod = activationMethod,
                TeleportFreezeReleased = not State.BunkerTransitionFreezeActive,
            })
            return true, "EXIT_PHYSICAL_MAIN_CONFIRMED"
        end
        task.wait(0.05)
    end

    local timeoutReconciled, timeoutRaw, timeoutEvidence =
        autoReconcileBunkerPhysicalState("EXIT_CONFIRM_TIMEOUT")
    if timeoutReconciled or timeoutRaw == "MAIN_TYCOON" then
        if State.BunkerTransitionFreezeActive then
            autoSetBunkerTransitionFreeze(false, nil, "EXIT_TIMEOUT_PHYSICAL_MAIN_CONFIRMED")
        end
        State.BunkerExitInProgress = false
        return true, "PHYSICAL_MAIN_RECONCILED_AFTER_EXIT_TIMEOUT"
    end

    if State.BunkerTransitionFreezeActive and timeoutRaw == "BUNKER" then
        autoSetBunkerTransitionFreeze(false, nil, "EXIT_TIMEOUT_CONFIRMED_STILL_IN_BUNKER")
    end
    State.BunkerExitInProgress = false
    State.BunkerSessionActive = true
    State.BunkerSessionReason = "EXIT_NOT_CONFIRMED_SESSION_RETAINED"
    State.BunkerExitFailureCount = (State.BunkerExitFailureCount or 0) + 1
    State.BunkerExitRetryUntil = os.clock() + BUNKER_EXIT_FAILURE_COOLDOWN
    setZone("BUNKER", "BUNKER_EXIT_NOT_CONFIRMED; SESSION_RETAINED")
    autoRecord("BUNKER_SESSION_EXIT_FAILED", {
        SessionId = State.BunkerSessionId,
        Reason = "EXIT_NOT_CONFIRMED",
        Zone = State.CurrentZone,
        RawPhysicalZone = timeoutRaw,
        RawPhysicalEvidence = timeoutEvidence,
        RetryAfter = BUNKER_EXIT_FAILURE_COOLDOWN,
        Policy = "NO_SPAM; RETRY_COOLDOWN; PHYSICAL_MAIN_RECONCILIATION_RUNS_EVERY_AUTOMATION_LOOP",
    })
    return false, "EXIT_NOT_CONFIRMED"
end

local function autoCollectWithBunkerExit()
    autoReconcileBunkerPhysicalState("COLLECTOR_PRECHECK")
    if os.clock() < (State.BunkerExitSettleUntil or 0) then
        return false, "BUNKER_EXIT_SETTLE_ACTIVE"
    end

    local bunkerContext =
        State.BunkerSessionActive
        or State.CurrentZone == "BUNKER"
        or State.BunkerEnterInProgress
        or State.BunkerExitInProgress

    if bunkerContext then
        State.BunkerCollectorExitAttempts = State.BunkerCollectorExitAttempts + 1
        autoRecord("TOTEM_COLLECT_REQUIRES_BUNKER_EXIT", {
            SessionId = State.BunkerSessionId,
            SessionActive = State.BunkerSessionActive,
            Zone = State.CurrentZone,
            EnterInProgress = State.BunkerEnterInProgress,
            ExitInProgress = State.BunkerExitInProgress,
            Policy = "EXIT_BUNKER_THROUGH_REAL_EXIT_PROMPT_BEFORE_ANY_COLLECTOR_TELEPORT",
        })

        local exited, exitReason = autoExitBunker()
        if not exited then
            State.BunkerCollectorExitFailed = State.BunkerCollectorExitFailed + 1
            autoRecord("TOTEM_COLLECT_BUNKER_EXIT_FAILED", {
                SessionId = State.BunkerSessionId,
                Reason = exitReason,
                Policy = "NO_COLLECTOR_TELEPORT_UNTIL_REAL_EXIT_PROMPT_IS_OBSERVED",
            })
            return false, "BUNKER_EXIT_FAILED_BEFORE_COLLECT:" .. tostring(exitReason)
        end

        State.BunkerCollectorExitSuccessful = State.BunkerCollectorExitSuccessful + 1
        autoRecord("TOTEM_COLLECT_BUNKER_EXIT_CONFIRMED", {
            SessionId = State.BunkerSessionId,
            Reason = exitReason,
            Zone = State.CurrentZone,
            NextAction = "WAIT_EXIT_SETTLE_THEN_COLLECT_FROM_MAIN",
        })
        local settleDeadline = os.clock() + 1.2
        while State.Running
        and State.AutomationEnabled
        and os.clock() < settleDeadline
        and os.clock() < (State.BunkerExitSettleUntil or 0) do
            task.wait(0.05)
        end
    end

    if autoBunkerTransitionContextActive() then
        return false, "BUNKER_BOUNDARY_STILL_ACTIVE_AFTER_EXIT"
    end
    return autoTeleportToCollectorAndConfirm()
end

local function autoEffectiveZone(record)
    if normalize(record.Name) == "bunker"
    and (record.Dependency == nil or tostring(record.Dependency) == "") then
        return "MAIN_TYCOON"
    end
    return record.Zone or "MAIN_TYCOON"
end
local function autoCandidateScore(record)
    local score = 100
    local effectiveZone = autoEffectiveZone(record)
    local price = parseNumber(record.Price)
    local required = parseNumber(record.Rebirths)
    if effectiveZone == State.CurrentZone then score = score - 35 end
    if effectiveZone == "MAIN_TYCOON" then score = score - 15 end
    if price ~= nil and price == 0 then score = score - 35 end
    if record.Type == "REBIRTH" then
        score = score - 40
    elseif record.Type == "TYCOON_MONEY" then
        if price ~= nil and State.LastMoney ~= nil and State.LastMoney >= price then
            score = score - 30
        else
            score = score - 5
        end
    end
    if required then score = score + required * 0.001 end
    if price then score = score + math.min(price, 9999999) * 0.0000001 end
    return score
end
autoRefreshFundsBlocks = function()
    local money = State.LastMoney
    for key, block in pairs(State.AutomationBlockedFunds) do
        if not block then
            State.AutomationBlockedFunds[key] = nil
        else
            local requiredPrice = tonumber(block.Price)
            if money ~= nil and requiredPrice ~= nil and money >= requiredPrice then
                State.AutomationBlockedFunds[key] = nil
                autoRecord("FUNDS_BLOCK_RELEASED", {
                    Key = key,
                    Name = block.Name,
                    Price = requiredPrice,
                    Money = money,
                    Reason = "BALANCE_NOW_SUFFICIENT",
                })
            end
        end
    end
end
local function autoBlockedFundsSummary()
    local count = 0
    local cheapestPrice = nil
    local cheapestName = nil
    for key, block in pairs(State.AutomationBlockedFunds) do
        if block then
            local price = tonumber(block.Price)
            count = count + 1
            if price ~= nil and (cheapestPrice == nil or price < cheapestPrice) then
                cheapestPrice = price
                cheapestName = block.Name
            end
        end
    end
    return count, cheapestPrice, cheapestName
end
local function autoShouldIdleCollect()
    autoRefreshFundsBlocks()
    local blockedCount, cheapestBlockedPrice, cheapestBlockedName = autoBlockedFundsSummary()
    if blockedCount <= 0 then
        return false, "NO_BLOCKED_FUNDS_PURCHASES"
    end
    local money = State.LastMoney
    if money == nil then
        return false, "MONEY_UNAVAILABLE"
    end
    if cheapestBlockedPrice ~= nil and money >= cheapestBlockedPrice then
        return false, "PURCHASE_NOW_AFFORDABLE"
    end
    local collectorAmount, collectorPath = autoCollectorAmount()
    State.IdleCollectChecks = State.IdleCollectChecks + 1
    if collectorAmount == nil then
        return false, "COLLECTOR_UNAVAILABLE", {
            BlockedCount = blockedCount,
            CheapestBlockedPrice = cheapestBlockedPrice,
            CheapestBlockedName = cheapestBlockedName,
            Money = money,
        }
    end
    if collectorAmount < AUTO_COLLECT_MIN then
        return false, "COLLECTOR_BELOW_THRESHOLD", {
            BlockedCount = blockedCount,
            CheapestBlockedPrice = cheapestBlockedPrice,
            CheapestBlockedName = cheapestBlockedName,
            Money = money,
            CollectorAmount = collectorAmount,
            CollectorPath = collectorPath,
        }
    end
    if os.clock() - (State.LastTotemCollectClock or 0) < AUTO_COLLECT_MIN_GAP then
        return false, "COLLECT_GAP_ACTIVE"
    end
    return true, "BLOCKED_PURCHASES_AND_COLLECTOR_READY", {
        BlockedCount = blockedCount,
        CheapestBlockedPrice = cheapestBlockedPrice,
        CheapestBlockedName = cheapestBlockedName,
        Money = money,
        CollectorAmount = collectorAmount,
        CollectorPath = collectorPath,
    }
end
local function autoTryContinuousIdleCollect()
    local shouldCollect, reason, details = autoShouldIdleCollect()
    if not shouldCollect then
        return false, reason
    end
    State.IdleCollectTriggers = State.IdleCollectTriggers + 1
    autoRecord("CONTINUOUS_COLLECT_TRIGGERED", {
        Reason = reason,
        BlockedCount = details and details.BlockedCount,
        CheapestBlockedPrice = details and details.CheapestBlockedPrice,
        CheapestBlockedName = details and details.CheapestBlockedName,
        Money = details and details.Money,
        CollectorAmount = details and details.CollectorAmount,
        CollectorPath = details and details.CollectorPath,
        Threshold = AUTO_COLLECT_MIN,
    })
    local collected, collectReason = autoCollectWithBunkerExit()
    if collected then
        autoRefreshFundsBlocks()
        local _, cheapestAfter, cheapestNameAfter = autoBlockedFundsSummary()
        autoRecord("CONTINUOUS_COLLECT_CYCLE_COMPLETE", {
            Result = collectReason,
            Money = State.LastMoney,
            CheapestBlockedPrice = cheapestAfter,
            CheapestBlockedName = cheapestNameAfter,
            NextAction = cheapestAfter and State.LastMoney and State.LastMoney >= cheapestAfter
                and "RESUME_PURCHASES"
                or "WAIT_FOR_COLLECTOR_1000",
        })
        return true, collectReason
    end
    autoRecord("CONTINUOUS_COLLECT_CYCLE_FAILED", {
        Reason = collectReason,
    })
    return false, collectReason
end
local function autoSelectCandidate()
    autoRefreshFundsBlocks()
    local candidates = buildAutomationCandidates().Eligible
    local now = os.clock()
    local filtered = {}
    for _, record in ipairs(candidates) do
        local key = record.Path or record.Name
        local cooldownUntil = State.AutomationCooldowns[key] or 0
        local fundsBlocked = State.AutomationBlockedFunds[key] ~= nil
        if now >= cooldownUntil and not fundsBlocked then
            table.insert(filtered, record)
        end
    end
    table.sort(filtered, function(a, b)
        local sa = autoCandidateScore(a)
        local sb = autoCandidateScore(b)
        if sa == sb then
            return tostring(a.Name) < tostring(b.Name)
        end
        return sa < sb
    end)
    return filtered[1]
end
local function autoSelectCandidateInZone(zoneName)
    autoRefreshFundsBlocks()
    local candidates = buildAutomationCandidates().Eligible
    local filtered = {}
    local now = os.clock()
    for _, record in ipairs(candidates) do
        local key = record.Path or record.Name
        local blocked = State.AutomationBlockedFunds[key] ~= nil
        local cooldownUntil = State.AutomationCooldowns[key]
        if autoEffectiveZone(record) == zoneName
        and not blocked
        and (not cooldownUntil or now >= cooldownUntil) then
            table.insert(filtered, record)
        end
    end
    table.sort(filtered, function(a, b)
        local scoreA = autoCandidateScore(a)
        local scoreB = autoCandidateScore(b)
        if scoreA == scoreB then
            return tostring(a.Name) < tostring(b.Name)
        end
        return scoreA < scoreB
    end)
    return filtered[1]
end
local function autoFindButton(record)
    if not State.ButtonsFolder or not record then return nil end
    local direct = State.ButtonsFolder:FindFirstChild(record.Name)
    if direct then return direct end
    for _, child in ipairs(State.ButtonsFolder:GetChildren()) do
        if safeFullName(child) == record.Path then
            return child
        end
    end
    return nil
end
local function autoPendingEligibleInZone(zoneName)
    local candidates = buildAutomationCandidates().Eligible
    local count = 0
    local names = {}
    local earliestCooldown = nil
    for _, record in ipairs(candidates) do
        if autoEffectiveZone(record) == zoneName then
            local button = autoFindButton(record)
            if button and button.Parent then
                count = count + 1
                table.insert(names, tostring(record.Name))
                local key = record.Path or record.Name
                local cooldownUntil = State.AutomationCooldowns[key]
                if cooldownUntil
                and cooldownUntil > os.clock()
                and (not earliestCooldown or cooldownUntil < earliestCooldown) then
                    earliestCooldown = cooldownUntil
                end
            end
        end
    end
    table.sort(names)
    return count, names, earliestCooldown
end

local function autoEnsureBunkerSessionPhysical()
    if not State.BunkerSessionActive then
        return true, "NO_ACTIVE_BUNKER_SESSION"
    end

    if State.LastTransitionPrompt
    and State.LastTransitionPrompt.Direction == "EXIT_BUNKER"
    and (State.BunkerExitPromptObservedClock or 0) >= (State.LastTransitionPrompt.Clock or 0) then
        State.BunkerSessionActive = false
        State.BunkerExitInProgress = false
        State.BunkerEnterInProgress = false
        State.BunkerSessionReason = "REAL_EXIT_PROMPT_ALREADY_OBSERVED"
        setZone("MAIN_TYCOON", "REAL_EXIT_PROMPT_ALREADY_OBSERVED")
        return false, "BUNKER_SESSION_ALREADY_EXITED"
    end

    return true, "BUNKER_SESSION_LOCK_ACTIVE_NO_AUTOMATIC_REENTRY"
end

local function autoAttemptPurchase(record)
    if not record then return false, "NO_TARGET" end
    local button = autoFindButton(record)
    if not button or not button.Parent then
        return false, "BUTTON_GONE_BEFORE_ATTEMPT"
    end
    local effectiveZone = autoEffectiveZone(record)

    if State.BunkerSessionActive and effectiveZone == "MAIN_TYCOON" then
        autoRecord("BUNKER_SESSION_BLOCKED_MAIN_TARGET", {
            SessionId = State.BunkerSessionId,
            Name = record.Name,
            Policy = "NO_MAIN_TARGET_UNTIL_BUNKER_QUEUE_IS_TRULY_EMPTY_AND_EXIT_PROMPT_CONFIRMS",
        })
        return false, "BUNKER_SESSION_LOCK_BLOCKED_MAIN_TARGET"
    end

    if effectiveZone == "BUNKER" then
        if not State.BunkerSessionActive then
            local entered, reason = autoEnterBunker()
            if not entered then
                return false, reason
            end
        else
            local physicalOk, physicalReason = autoEnsureBunkerSessionPhysical()
            if not physicalOk then
                return false, physicalReason
            end
        end
    elseif State.BunkerSessionActive
    or State.CurrentZone == "BUNKER"
    or State.BunkerEnterInProgress
    or State.BunkerExitInProgress then
        local exited, reason = autoExitBunker()
        if not exited then
            return false, reason
        end
        local settleDeadline = os.clock() + 1.2
        while State.Running
        and State.AutomationEnabled
        and os.clock() < settleDeadline
        and os.clock() < (State.BunkerExitSettleUntil or 0) do
            task.wait(0.05)
        end
        if autoBunkerTransitionContextActive() then
            return false, "MAIN_PURCHASE_WAITING_FOR_BUNKER_EXIT_SETTLE"
        end
    end
    button = autoFindButton(record)
    if not button or not button.Parent then
        return false, "BUTTON_GONE_AFTER_ZONE_TRANSITION"
    end
    local targetPart = autoTargetPart(button)
    if not targetPart then
        return false, "TOUCH_PART_NOT_FOUND"
    end
    State.AutomationState = effectiveZone == "BUNKER" and "TELEPORTING_BUNKER_PURCHASE" or "TELEPORTING"
    State.Health.Automation = State.AutomationState
    State.AutomationTarget = record.Name
    State.AutomationTargetStarted = os.clock()
    local attempt = {
        Id = #State.AutomationAttempts + 1,
        RunId = State.AutomationRunId,
        Name = record.Name,
        Path = record.Path,
        Type = record.Type,
        Zone = record.Zone,
        EffectiveZone = effectiveZone,
        StartedUnix = os.time(),
        StartedElapsed = elapsed(),
        MoneyBefore = State.LastMoney,
        RebirthsBefore = State.LastRebirths,
        FloorBefore = State.MainFloor,
        ZoneBefore = State.CurrentZone,
        Result = "STARTED",
    }
    table.insert(State.AutomationAttempts, attempt)
    autoRecord("PURCHASE_ATTEMPT_STARTED", {
        AttemptId = attempt.Id,
        Name = record.Name,
        Type = record.Type,
        Zone = effectiveZone,
        Price = record.Price,
        Rebirths = record.Rebirths,
    })
    local moved, movementReason
    if effectiveZone == "BUNKER" then
        moved, movementReason = autoTeleportToPart(
            targetPart,
            "BUNKER_PURCHASE"
        )
    else
        moved, movementReason = autoTeleportToPart(targetPart)
    end

    if not moved then
        local signal = State.AutomationServerSignal
        local buttonGone = not button.Parent
        local purchaseExists = State.PurchasesFolder
            and State.PurchasesFolder:FindFirstChild(record.Name) ~= nil
        local serverAccepted = signal
            and signal.Target == record.Name
            and signal.Status == "ACCEPTED"
        if buttonGone or purchaseExists or serverAccepted then
            attempt.Result = "ACCEPTED_OBSERVED_DURING_MOVEMENT_RECOVERY"
            attempt.Reason = movementReason
            attempt.MovementEvidence = movementReason
            attempt.AcceptanceEvidence = serverAccepted and "SERVER_BUTTON_PURCHASED"
                or buttonGone and "BUTTON_REMOVED"
                or "PURCHASE_CREATED"
            attempt.FinishedUnix = os.time()
            attempt.FinishedElapsed = elapsed()
            attempt.MoneyAfter = State.LastMoney
            attempt.RebirthsAfter = State.LastRebirths
            attempt.FloorAfter = State.MainFloor
            attempt.ZoneAfter = State.CurrentZone
            State.AutomationSuccessful = State.AutomationSuccessful + 1
            State.AutomationCooldowns[record.Path or record.Name] = nil
            autoRecord("PURCHASE_ACCEPTED_DURING_MOVEMENT_RECOVERY", {
                AttemptId = attempt.Id,
                Name = record.Name,
                MovementReason = movementReason,
                Evidence = attempt.AcceptanceEvidence,
                Zone = effectiveZone,
            })
            if effectiveZone == "BUNKER" then
                autoCaptureCurrentSafePosition("BUNKER_PURCHASE_ACCEPTED:" .. tostring(record.Name))
                task.wait(BUNKER_PURCHASE_SETTLE)
            else
                task.wait(AUTO_POST_RESULT_WAIT)
            end
            return true, attempt.AcceptanceEvidence
        end
        attempt.Result = effectiveZone == "BUNKER" and "BUNKER_TELEPORT_FAILED" or "TELEPORT_FAILED"
        attempt.Reason = movementReason
        attempt.FinishedUnix = os.time()
        attempt.FinishedElapsed = elapsed()
        State.AutomationFailed = State.AutomationFailed + 1
        State.AutomationCooldowns[record.Path or record.Name] = os.clock() + AUTO_RETRY_COOLDOWN
        autoRecord("PURCHASE_ATTEMPT_FAILED", {
            AttemptId = attempt.Id,
            Name = record.Name,
            Stage = effectiveZone == "BUNKER" and "BUNKER_TELEPORT" or "TELEPORT",
            Reason = movementReason,
            SessionRetained = State.BunkerSessionActive,
        })
        return false, movementReason
    end

    attempt.MovementEvidence = movementReason
    if effectiveZone == "BUNKER" then
        autoRecord("PURCHASE_TARGET_BUNKER_TELEPORTED", {
            AttemptId = attempt.Id,
            Name = record.Name,
            TargetPart = safeFullName(targetPart),
            Evidence = movementReason,
            SessionId = State.BunkerSessionId,
        })
    else
        attempt.TeleportEvidence = movementReason
        autoRecord("PURCHASE_TARGET_TELEPORTED", {
            AttemptId = attempt.Id,
            Name = record.Name,
            TargetPart = safeFullName(targetPart),
            Evidence = movementReason,
        })
    end
    State.AutomationState = "WAIT_SERVER"
    State.Health.Automation = "WAIT_SERVER"
    local accepted, acceptanceReason = autoWaitForAcceptance(record.Name, button, AUTO_SERVER_WAIT)
    attempt.FinishedUnix = os.time()
    attempt.FinishedElapsed = elapsed()
    attempt.MoneyAfter = State.LastMoney
    attempt.RebirthsAfter = State.LastRebirths
    attempt.FloorAfter = State.MainFloor
    attempt.ZoneAfter = State.CurrentZone
    attempt.AcceptanceEvidence = acceptanceReason
    if accepted then
        attempt.Result = "ACCEPTED_OBSERVED"
        State.AutomationSuccessful = State.AutomationSuccessful + 1
        State.AutomationCooldowns[record.Path or record.Name] = nil
        autoRecord("PURCHASE_ACCEPTED_OBSERVED", {
            AttemptId = attempt.Id,
            Name = record.Name,
            Evidence = acceptanceReason,
            MoneyBefore = attempt.MoneyBefore,
            MoneyAfter = attempt.MoneyAfter,
            RebirthsBefore = attempt.RebirthsBefore,
            RebirthsAfter = attempt.RebirthsAfter,
        })
        if effectiveZone == "BUNKER" then
            autoCaptureCurrentSafePosition("BUNKER_PURCHASE_CONFIRMED:" .. tostring(record.Name))
            task.wait(BUNKER_PURCHASE_SETTLE)
        else
            task.wait(AUTO_POST_RESULT_WAIT)
        end
        return true, acceptanceReason
    end
    attempt.Result = "NO_ACCEPTANCE_OBSERVED"
    State.AutomationFailed = State.AutomationFailed + 1
    State.AutomationCooldowns[record.Path or record.Name] = os.clock() + AUTO_RETRY_COOLDOWN
    local declaredPrice = parseNumber(record.Price)
    local insufficientBalanceInferred =
        record.Type == "TYCOON_MONEY"
        and declaredPrice ~= nil
        and State.LastMoney ~= nil
        and State.LastMoney < declaredPrice
    autoRecord("PURCHASE_NOT_ACCEPTED_OBSERVED", {
        AttemptId = attempt.Id,
        Name = record.Name,
        Reason = acceptanceReason,
        DeclaredPrice = declaredPrice,
        MoneyObserved = State.LastMoney,
        InsufficientBalanceInferred = insufficientBalanceInferred,
        Note = "No client-visible button removal/purchase creation was observed; exact server internal reason is unknown.",
    })
    if insufficientBalanceInferred then
        local blockKey = record.Path or record.Name
        State.AutomationBlockedFunds[blockKey] = {
            Name = record.Name,
            Path = record.Path,
            Price = declaredPrice,
            MoneyAtBlock = State.LastMoney,
            BlockedUnix = os.time(),
            BlockedElapsed = elapsed(),
            Reason = "PURCHASE_REJECTED_WHILE_MONEY_BELOW_PRICE",
        }
        autoRecord("FUNDS_BLOCK_SAVED", {
            Name = record.Name,
            Path = record.Path,
            Price = declaredPrice,
            Money = State.LastMoney,
            Reason = "DO_NOT_RETRY_UNTIL_BALANCE_SUFFICIENT_OR_COLLECTION_SUCCEEDS",
        })
        local collectorAmount, collectorPath = autoCollectorAmount()
        autoRecord("AUTO_COLLECT_CHECK", {
            AttemptId = attempt.Id,
            PurchaseTarget = record.Name,
            CollectorAmount = collectorAmount,
            CollectorPath = collectorPath,
            Threshold = AUTO_COLLECT_MIN,
            Trigger = "PURCHASE_REJECTED_AND_LOCAL_MONEY_BELOW_DECLARED_PRICE",
        })
        if collectorAmount ~= nil and collectorAmount >= AUTO_COLLECT_MIN then
            local collected, collectReason = autoCollectWithBunkerExit()
            if collected then
                autoRefreshFundsBlocks()
                task.wait(AUTO_POST_RESULT_WAIT)
                return false, "TOTEM_COLLECTED_AFTER_INSUFFICIENT_BALANCE"
            else
                return false, "AUTO_COLLECT_FAILED:" .. tostring(collectReason)
            end
        end
    end
    return false, acceptanceReason
end
local function autoFindRebirthButton()
    local playerGui = State.Player and State.Player:FindFirstChild("PlayerGui")
    if not playerGui then
        return nil
    end
    local rebirthGui = playerGui:FindFirstChild("RebirthGui")
    if not rebirthGui then
        return nil
    end
    local frame = rebirthGui:FindFirstChild("Frame")
    local buttons = frame and frame:FindFirstChild("Buttons")
    local direct = buttons and buttons:FindFirstChild("Rebirth")
    if direct and direct:IsA("GuiButton") then
        return direct
    end
    for _, obj in ipairs(rebirthGui:GetDescendants()) do
        if obj:IsA("GuiButton")
        and normalize(obj.Name) == "rebirth" then
            return obj
        end
    end
    return nil
end
local function autoRebirthButtonText(button)
    if not button then
        return ""
    end
    local best = ""
    local okText, directText = pcall(function()
        return button.Text
    end)
    if okText and type(directText) == "string" and #directText > #best then
        best = directText
    end
    for _, descendant in ipairs(button:GetDescendants()) do
        if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
            local ok, value = pcall(function()
                return descendant.Text
            end)
            if ok and type(value) == "string" and #value > #best then
                best = value
            end
        end
    end
    return best
end
local function autoGuiActuallyVisible(button)
    if not button or not button.Parent or not State.Player then
        return false
    end
    local playerGui = State.Player:FindFirstChild("PlayerGui")
    if not playerGui then
        return false
    end
    local current = button
    while current do
        if current:IsA("GuiObject") then
            local ok, visible = pcall(function()
                return current.Visible
            end)
            if ok and visible == false then
                return false
            end
        elseif current:IsA("ScreenGui") then
            local ok, enabled = pcall(function()
                return current.Enabled
            end)
            if ok and enabled == false then
                return false
            end
        end
        if current == playerGui then
            break
        end
        current = current.Parent
    end
    return true
end
local function autoGetRebirthReadiness()
    local button = autoFindRebirthButton()
    if not button then
        return false, "REBIRTH_BUTTON_NOT_FOUND", nil, nil
    end
    local interactable = false
    local active = false
    local okInteractable, interactableValue = pcall(function()
        return button.Interactable
    end)
    if okInteractable then
        interactable = interactableValue == true
    end
    local okActive, activeValue = pcall(function()
        return button.Active
    end)
    if okActive then
        active = activeValue == true
    end
    local textValue = autoRebirthButtonText(button)
    local textNorm = normalize(textValue)
    local saysButtonsLeft =
        string.find(textNorm, "buttonsleft", 1, true) ~= nil
        or string.find(textNorm, "buttonleft", 1, true) ~= nil
    local uiReady = interactable and active and not saysButtonsLeft
    if uiReady then
        return true,
            State.AutoRebirthServerReady and "SERVER_TRUE_AND_UI_INTERACTABLE" or "UI_INTERACTABLE_READY",
            button,
            textValue
    end
    return false, "UI_NOT_READY", button, textValue
end
local function autoActivateRebirthButton(button)
    if not button or not button.Parent then
        return false, "REBIRTH_BUTTON_UNAVAILABLE"
    end
    if VirtualInputManager and autoGuiActuallyVisible(button) then
        local ok, err = pcall(function()
            local pos = button.AbsolutePosition
            local size = button.AbsoluteSize
            local x = math.floor(pos.X + size.X * 0.5)
            local y = math.floor(pos.Y + size.Y * 0.5)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(0.06)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
        if ok then
            return true, "VIRTUAL_INPUT_GUI_CLICK"
        end
        autoRecord("AUTO_REBIRTH_INPUT_WARNING", {
            Method = "VIRTUAL_INPUT_GUI_CLICK",
            Error = tostring(err),
            FallbackAvailable = type(firesignal) == "function",
        })
    end
    if type(firesignal) == "function" then
        local ok, err = pcall(function()
            firesignal(button.Activated, nil, 1)
        end)
        if ok then
            return true, "GUI_ACTIVATED_SIGNAL_FALLBACK"
        end
        return false, "GUI_ACTIVATED_SIGNAL_FAILED:" .. tostring(err)
    end
    return false, "NO_SUPPORTED_GUI_INPUT_METHOD"
end
local function autoBlockedFundsCount()
    local count = 0
    for _ in pairs(State.AutomationBlockedFunds) do
        count += 1
    end
    return count
end
local function autoAttemptRebirth()
    local now = os.clock()
    if now - (State.AutoRebirthLastAttemptClock or 0) < AUTO_REBIRTH_RETRY_COOLDOWN then
        return false, "REBIRTH_RETRY_COOLDOWN"
    end
    autoRefreshFundsBlocks()
    local blockedFunds = autoBlockedFundsCount()
    if blockedFunds > 0 then
        return false, "FUNDS_BLOCKED_PURCHASES_REMAIN"
    end
    if State.BunkerSessionActive or State.CurrentZone == "BUNKER" then
        return false, "BUNKER_SESSION_NOT_FINISHED"
    end
    local ready, readinessReason, confirmButton, confirmText = autoGetRebirthReadiness()
    if not ready then
        return false, readinessReason
    end
    local before = State.LastRebirths
    if before == nil then
        return false, "REBIRTH_STAT_UNAVAILABLE"
    end
    local function panelIsOpen()
        local playerGui = State.Player and State.Player:FindFirstChild("PlayerGui")
        local rebirthGui = playerGui and playerGui:FindFirstChild("RebirthGui")
        local frame = rebirthGui and rebirthGui:FindFirstChild("Frame")
        if not rebirthGui or not frame or not frame:IsA("GuiObject") then
            return false, rebirthGui, frame
        end
        local enabled = true
        if rebirthGui:IsA("ScreenGui") then
            local okEnabled, enabledValue = pcall(function()
                return rebirthGui.Enabled
            end)
            if okEnabled then
                enabled = enabledValue == true
            end
        end
        local frameVisible = false
        local okVisible, visibleValue = pcall(function()
            return frame.Visible
        end)
        if okVisible then
            frameVisible = visibleValue == true
        end
        return enabled and frameVisible and autoGuiActuallyVisible(frame), rebirthGui, frame
    end
    local function shortRebirthLabel(value)
        local raw = tostring(value or "")
        if #raw > 64 then
            return false
        end
        local norm = normalize(raw)
        return norm == "rebirth"
            or norm == "rebirths"
            or norm == "renascimento"
            or norm == "renascimentos"
            or norm == "renascer"
            or norm == "prestige"
            or norm == "prestigio"
            or norm == "prestígio"
    end
    local function virtualClick(button)
        if not button or not button.Parent then
            return false, "BUTTON_UNAVAILABLE"
        end
        if not VirtualInputManager then
            return false, "VIRTUAL_INPUT_UNAVAILABLE"
        end
        if not autoGuiActuallyVisible(button) then
            return false, "BUTTON_NOT_EFFECTIVELY_VISIBLE"
        end
        local ok, err = pcall(function()
            local pos = button.AbsolutePosition
            local size = button.AbsoluteSize
            local x = math.floor(pos.X + size.X * 0.5)
            local y = math.floor(pos.Y + size.Y * 0.5)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(0.06)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
        if ok then
            return true, "VIRTUAL_INPUT_GUI_CLICK"
        end
        return false, "VIRTUAL_INPUT_FAILED:" .. tostring(err)
    end
    local function fireSignal(button, signalName)
        if not button or not button.Parent then
            return false, "BUTTON_UNAVAILABLE"
        end
        if type(firesignal) ~= "function" then
            return false, "FIRESIGNAL_UNAVAILABLE"
        end
        local signal = nil
        local okSignal = pcall(function()
            signal = button[signalName]
        end)
        if not okSignal or not signal then
            return false, "SIGNAL_NOT_AVAILABLE:" .. tostring(signalName)
        end
        local ok, err = pcall(function()
            if signalName == "Activated" then
                firesignal(signal, nil, 1)
            else
                firesignal(signal)
            end
        end)
        if ok then
            return true, "FIRESIGNAL_" .. string.upper(signalName)
        end
        return false, "FIRESIGNAL_FAILED_" .. tostring(signalName) .. ":" .. tostring(err)
    end
    local function tryButtonInput(button, stage, waitPredicate)
        local methods = {
            {Kind = "SIGNAL", Name = "MouseButton1Click"},
            {Kind = "VIRTUAL", Name = "VirtualInput"},
            {Kind = "SIGNAL", Name = "Activated"},
        }
        for index, method in ipairs(methods) do
            local sent, methodName
            if method.Kind == "VIRTUAL" then
                sent, methodName = virtualClick(button)
            else
                sent, methodName = fireSignal(button, method.Name)
            end
            autoRecord("AUTO_REBIRTH_UI_INPUT", {
                AttemptId = #State.AutoRebirthAttempts + 1,
                Stage = stage,
                MethodIndex = index,
                Method = methodName,
                InputSent = sent,
                Path = safeFullName(button),
            })
            if sent then
                local started = os.clock()
                while State.Running
                and State.AutomationEnabled
                and os.clock() - started <= 1.6 do
                    local okPredicate, result = pcall(waitPredicate)
                    if okPredicate and result then
                        return true, methodName
                    end
                    task.wait(0.05)
                end
            end
        end
        return false, "ALL_" .. tostring(stage) .. "_INPUT_METHODS_FAILED"
    end
    local function openerScore(button, rebirthGui)
        if not button or not button:IsA("GuiButton") then
            return -math.huge, nil
        end
        if rebirthGui and button:IsDescendantOf(rebirthGui) then
            return -math.huge, nil
        end
        if not autoGuiActuallyVisible(button) then
            return -math.huge, nil
        end
        local nameNorm = normalize(button.Name)
        if string.find(nameNorm, "instant", 1, true) then
            return -math.huge, nil
        end
        local score = 0
        local evidence = {}
        if nameNorm == "rebirth" or nameNorm == "rebirthbutton" or nameNorm == "rebirthmenu" then
            score = score + 160
            table.insert(evidence, "EXACT_REBIRTH_NAME")
        elseif string.find(nameNorm, "rebirth", 1, true) then
            score = score + 125
            table.insert(evidence, "NAME_CONTAINS_REBIRTH")
        elseif string.find(nameNorm, "renascimento", 1, true)
        or string.find(nameNorm, "renascer", 1, true) then
            score = score + 125
            table.insert(evidence, "NAME_CONTAINS_RENASCIMENTO")
        end
        local label = autoRebirthButtonText(button)
        if shortRebirthLabel(label) then
            score = score + 150
            table.insert(evidence, "BUTTON_LABEL=" .. tostring(label))
        end
        return score, evidence
    end
    local function findHudOpener()
        local playerGui = State.Player and State.Player:FindFirstChild("PlayerGui")
        if not playerGui then
            return nil, "PLAYER_GUI_NOT_FOUND"
        end
        local rebirthGui = playerGui:FindFirstChild("RebirthGui")
        local all = playerGui:GetDescendants()
        local maxScan = math.min(#all, 4000)
        local bestButton = nil
        local bestScore = -math.huge
        local bestEvidence = nil
        for index = 1, maxScan do
            local obj = all[index]
            if obj:IsA("GuiButton") then
                local score, evidence = openerScore(obj, rebirthGui)
                if score > bestScore then
                    bestScore = score
                    bestButton = obj
                    bestEvidence = evidence
                end
            end
        end
        if bestScore < 100 then
            for index = 1, maxScan do
                local label = all[index]
                if label:IsA("TextLabel") or label:IsA("TextButton") then
                    local okText, labelText = pcall(function()
                        return label.Text
                    end)
                    if okText and shortRebirthLabel(labelText) and autoGuiActuallyVisible(label) then
                        local okLabelGeometry, labelCenter = pcall(function()
                            return label.AbsolutePosition + label.AbsoluteSize * 0.5
                        end)
                        if okLabelGeometry then
                            for buttonIndex = 1, maxScan do
                                local candidate = all[buttonIndex]
                                if candidate:IsA("GuiButton")
                                and (not rebirthGui or not candidate:IsDescendantOf(rebirthGui))
                                and autoGuiActuallyVisible(candidate) then
                                    local okButtonGeometry, buttonCenter = pcall(function()
                                        return candidate.AbsolutePosition + candidate.AbsoluteSize * 0.5
                                    end)
                                    if okButtonGeometry then
                                        local distance = (buttonCenter - labelCenter).Magnitude
                                        if distance <= 170 then
                                            local score, evidence = openerScore(candidate, rebirthGui)
                                            score = score + math.max(0, 190 - distance)
                                            table.insert(evidence, "NEAR_LABEL=" .. tostring(math.floor(distance)))
                                            if score > bestScore then
                                                bestScore = score
                                                bestButton = candidate
                                                bestEvidence = evidence
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        if not bestButton or bestScore < 80 then
            return nil, "NO_CONFIDENT_HUD_REBIRTH_OPENER"
        end
        return bestButton,
            table.concat(bestEvidence or {}, ";") .. ";score=" .. tostring(math.floor(bestScore))
    end
    State.AutoRebirthLastAttemptClock = now
    State.AutomationState = "REBIRTHING"
    State.Health.Automation = "REBIRTHING"
    local attempt = {
        Id = #State.AutoRebirthAttempts + 1,
        StartedUnix = os.time(),
        StartedElapsed = elapsed(),
        RebirthsBefore = before,
        ConfirmButtonPath = confirmButton and safeFullName(confirmButton) or nil,
        ConfirmButtonText = confirmText,
        ReadinessReason = readinessReason,
        ServerReady = State.AutoRebirthServerReady,
        ServerSignalSeen = State.AutoRebirthServerSignalSeen,
        ServerSignalValue = State.AutoRebirthLastSignalValue,
        ServerSignalUnix = State.AutoRebirthLastSignalUnix,
        Flow = "TWO_STEP_HUD_OPEN_THEN_CONFIRM",
    }
    table.insert(State.AutoRebirthAttempts, attempt)
    autoRecord("AUTO_REBIRTH_ATTEMPT_STARTED", {
        AttemptId = attempt.Id,
        RebirthsBefore = before,
        ConfirmButtonPath = attempt.ConfirmButtonPath,
        ConfirmButtonText = confirmText,
        ReadinessReason = readinessReason,
        ServerReady = State.AutoRebirthServerReady,
        ServerSignalValue = State.AutoRebirthLastSignalValue,
        Flow = attempt.Flow,
        Policy = "NORMAL_TWO_STEP_REBIRTH_UI_ONLY_NO_DIRECT_REBIRTH_REMOTE",
    })
    local panelOpen = panelIsOpen()
    local openMethod = "PANEL_ALREADY_OPEN"
    if not panelOpen then
        local opener, openerEvidence = findHudOpener()
        attempt.OpenerPath = opener and safeFullName(opener) or nil
        attempt.OpenerEvidence = openerEvidence
        autoRecord("AUTO_REBIRTH_OPENER_SELECTED", {
            AttemptId = attempt.Id,
            Path = attempt.OpenerPath,
            Evidence = openerEvidence,
            Found = opener ~= nil,
        })
        if not opener then
            attempt.Result = "HUD_OPENER_NOT_FOUND"
            attempt.FinishedUnix = os.time()
            attempt.FinishedElapsed = elapsed()
            State.AutoRebirthFailed = State.AutoRebirthFailed + 1
            return false, "HUD_OPENER_NOT_FOUND"
        end
        local opened, usedMethod = tryButtonInput(opener, "OPEN_PANEL", function()
            return panelIsOpen()
        end)
        openMethod = usedMethod
        if not opened then
            attempt.Result = "PANEL_OPEN_NOT_CONFIRMED"
            attempt.OpenMethod = usedMethod
            attempt.FinishedUnix = os.time()
            attempt.FinishedElapsed = elapsed()
            State.AutoRebirthFailed = State.AutoRebirthFailed + 1
            autoRecord("AUTO_REBIRTH_PANEL_OPEN_FAILED", {
                AttemptId = attempt.Id,
                OpenerPath = attempt.OpenerPath,
                Method = usedMethod,
            })
            return false, "PANEL_OPEN_NOT_CONFIRMED"
        end
    end
    attempt.OpenMethod = openMethod
    confirmButton = autoFindRebirthButton()
    ready, readinessReason, confirmButton, confirmText = autoGetRebirthReadiness()
    if not ready or not confirmButton or not autoGuiActuallyVisible(confirmButton) then
        attempt.Result = "CONFIRM_NOT_READY_AFTER_PANEL_OPEN"
        attempt.ConfirmReadinessReason = readinessReason
        attempt.FinishedUnix = os.time()
        attempt.FinishedElapsed = elapsed()
        State.AutoRebirthFailed = State.AutoRebirthFailed + 1
        return false, "CONFIRM_NOT_READY_AFTER_PANEL_OPEN"
    end
    attempt.ConfirmButtonPath = safeFullName(confirmButton)
    attempt.ConfirmButtonText = confirmText
    local confirmed, confirmMethod = tryButtonInput(confirmButton, "CONFIRM_REBIRTH", function()
        local rebirthObject = State.RebirthObject
        if not rebirthObject or not rebirthObject.Parent then
            rebirthObject = findStat({"Rebirths", "Rebirth", "Renascimentos", "Renascimento"})
            State.RebirthObject = rebirthObject
        end
        local liveRebirths = readValue(rebirthObject)
        if liveRebirths ~= nil then
            State.LastRebirths = liveRebirths
        end
        return liveRebirths ~= nil and liveRebirths > before
    end)
    State.AutoRebirthLastMethod = tostring(openMethod) .. " -> " .. tostring(confirmMethod)
    attempt.ConfirmMethod = confirmMethod
    if confirmed then
        local after = State.LastRebirths
        attempt.Result = "REBIRTH_INCREMENT_CONFIRMED"
        attempt.RebirthsAfter = after
        attempt.FinishedUnix = os.time()
        attempt.FinishedElapsed = elapsed()
        State.AutoRebirthSuccessful = State.AutoRebirthSuccessful + 1
        autoRecord("AUTO_REBIRTH_CONFIRMED", {
            AttemptId = attempt.Id,
            OpenMethod = openMethod,
            ConfirmMethod = confirmMethod,
            RebirthsBefore = before,
            RebirthsAfter = after,
            Evidence = "OBSERVED_LEADERSTATS_REBIRTH_INCREMENT",
        })
        return true, "REBIRTH_INCREMENT_CONFIRMED"
    end
    attempt.Result = "REBIRTH_INCREMENT_NOT_OBSERVED"
    attempt.RebirthsAfter = State.LastRebirths
    attempt.FinishedUnix = os.time()
    attempt.FinishedElapsed = elapsed()
    State.AutoRebirthFailed = State.AutoRebirthFailed + 1
    autoRecord("AUTO_REBIRTH_NOT_CONFIRMED", {
        AttemptId = attempt.Id,
        OpenMethod = openMethod,
        ConfirmMethod = confirmMethod,
        RebirthsBefore = before,
        RebirthsObserved = State.LastRebirths,
        RetryCooldownSeconds = AUTO_REBIRTH_RETRY_COOLDOWN,
        Note = "Two-step GUI flow attempted; no local Rebirth mutation is performed.",
    })
    return false, "REBIRTH_INCREMENT_NOT_OBSERVED"
end
local function autoHandleRebirth(oldValue, newValue)
    State.AutomationState = "RESETTING"
    State.Health.Automation = "RESETTING"
    State.LastRebirths = newValue
    State.AutomationLastRebirth = newValue
    State.AutomationTarget = nil
    State.AutomationTargetStarted = nil
    State.AutomationCooldowns = {}
    State.AutomationBlockedFunds = {}
    State.AutomationServerSignal = nil
    State.Pending = {}
    State.ButtonCache = {}
    State.BunkerSessionActive = false
    State.BunkerEnterInProgress = false
    State.BunkerEnterCooldownUntil = 0
    State.BunkerExitInProgress = false
    State.BunkerExitRetryUntil = 0
    State.BunkerExitFailureCount = 0
    State.BunkerEnterPromptObservedClock = 0
    State.BunkerExitPromptObservedClock = 0
    State.BunkerExitSettleUntil = 0
    State.BunkerTransitionFreezeActive = false
    State.BunkerTransitionFreezeDirection = nil
    State.BunkerTransitionFreezeStartedClock = 0
    State.BunkerTransitionFreezeReason = nil
    State.BunkerTransitionOriginPosition = nil
    State.BunkerTransitionSourcePart = nil
    State.BunkerTransitionSourcePath = nil
    State.BunkerTransitionLastDisplacement = 0
    State.BunkerTransitionConfirmMode = nil
    State.BunkerSessionReason = "REBIRTH_RESET"
    State.BunkerSessionStartedUnix = nil
    State.BunkerSessionStartedElapsed = nil
    State.AutoRebirthServerReady = false
    State.AutoRebirthButtonsLeft = nil
    State.AutoRebirthLastSignalValue = nil
    local reset = {
        Id = #State.AutomationResets + 1,
        Unix = os.time(),
        Elapsed = elapsed(),
        OldRebirths = oldValue,
        NewRebirths = newValue,
        Money = State.LastMoney,
        FloorBeforeRefresh = State.MainFloor,
        ZoneBeforeRefresh = State.CurrentZone,
    }
    table.insert(State.AutomationResets, reset)
    autoRecord("REBIRTH_RESET_DETECTED", reset)
    task.wait(0.8)
    reconsiderTycoon()
    scanInitial()
    local floor, floorEvidence = detectMainFloor()
    setMainFloor(floor, "automation reset refresh: " .. tostring(floorEvidence))
    local zone, zoneEvidence = detectZoneByPosition()
    setZone(zone, "automation reset refresh: " .. tostring(zoneEvidence))
    reset.FloorAfterRefresh = State.MainFloor
    reset.ZoneAfterRefresh = State.CurrentZone
    reset.ButtonsAfterRefresh = State.ButtonsFolder and #State.ButtonsFolder:GetChildren() or 0
    reset.PurchasesAfterRefresh = State.PurchasesFolder and #State.PurchasesFolder:GetChildren() or 0
    autoRecord("REBIRTH_RESET_RESCANNED", reset)
end
local function autoSyncRuntimeState()
    local moneyObject = findStat(MONEY_NAMES)
    if moneyObject then
        State.MoneyObject = moneyObject
        local money = readValue(moneyObject)
        if money ~= nil then
            State.LastMoney = money
            State.Health.Money = "ACTIVE"
        end
    end
    local rebirthObject = findStat({"Rebirths", "Rebirth", "Renascimentos", "Renascimento"})
    if rebirthObject then
        State.RebirthObject = rebirthObject
        local rebirths = readValue(rebirthObject)
        if rebirths ~= nil then
            State.LastRebirths = rebirths
            State.Health.Rebirths = "ACTIVE"
        end
    end
    local refsValid = State.Tycoon
        and State.Tycoon.Parent
        and State.ButtonsFolder
        and State.PurchasesFolder
        and State.ButtonsFolder.Parent == State.Tycoon
        and State.PurchasesFolder.Parent == State.Tycoon
        and State.Tycoon:FindFirstChild("Buttons") == State.ButtonsFolder
        and State.Tycoon:FindFirstChild("Purchases") == State.PurchasesFolder
    if not refsValid then
        State.Tycoon = nil
        State.ButtonsFolder = nil
        State.PurchasesFolder = nil
        reconsiderTycoon()
    end
    local currentRebirth = State.LastRebirths
    if State.AutomationLastRebirth ~= nil
    and currentRebirth ~= nil
    and currentRebirth > State.AutomationLastRebirth then
        autoHandleRebirth(State.AutomationLastRebirth, currentRebirth)
    end
    if currentRebirth ~= nil then
        State.AutomationLastRebirth = currentRebirth
    end
    return currentRebirth
end
local function setAutomation(enabled)
    enabled = enabled and true or false
    if State.AutomationEnabled == enabled then return end
    if enabled then
        if not State.Reading then
            setReading(true)
        end
        safeCall("AUTOMATION_ENABLE_SYNC", function()
            autoSyncRuntimeState()
            reconsiderTycoon()
        end)
        State.AutomationEnabled = true
        State.AutomationRunId = State.AutomationRunId + 1
        State.AutomationState = "SCANNING"
        State.Health.Automation = "ACTIVE"
        State.AutomationTarget = nil
        State.AutomationCooldowns = {}
        State.BunkerEnterInProgress = false
        State.BunkerEnterCooldownUntil = 0
        State.BunkerEnterPromptObservedClock = 0
        State.BunkerExitPromptObservedClock = 0
        State.BunkerExitRetryUntil = 0
        State.BunkerExitInProgress = false
        State.BunkerTransitionFreezeActive = false
        State.BunkerTransitionFreezeDirection = nil
        State.BunkerTransitionFreezeStartedClock = 0
        State.BunkerTransitionFreezeReason = nil
        State.BunkerTransitionOriginPosition = nil
        State.BunkerTransitionSourcePart = nil
        State.BunkerTransitionSourcePath = nil
        State.BunkerTransitionLastDisplacement = 0
        State.BunkerTransitionConfirmMode = nil
        autoRefreshFundsBlocks()
        State.AutomationServerSignal = nil
        State.AutomationLastRebirth = State.LastRebirths
        autoRecord("AUTOMATION_STARTED", {
            RunId = State.AutomationRunId,
            Money = State.LastMoney,
            Rebirths = State.LastRebirths,
            Floor = State.MainFloor,
            Zone = State.CurrentZone,
            Policy = "Continuous cycle: purchases + Bunker session lock + collector recovery; when the eligible purchase queue is exhausted and Rebirth is ready, Auto Rebirth opens the HUD Rebirth panel first, confirms inside RebirthGui second, then waits for Rebirths to increase before reset/rescan.",
        })
    else
        autoRecord("AUTOMATION_STOPPED", {
            RunId = State.AutomationRunId,
            Successful = State.AutomationSuccessful,
            Failed = State.AutomationFailed,
            Target = State.AutomationTarget,
        })
        State.AutomationEnabled = false
        State.AutomationState = "OFF"
        State.Health.Automation = "OFF"
        State.AutomationTarget = nil
        State.AutomationTargetStarted = nil
    end
end
autoBindServerResponseSignals()
task.spawn(function()
    while State.Running do
        if State.AutomationEnabled then
            safeCall("AUTOMATION_LOOP", function()
                local currentRebirth = autoSyncRuntimeState()
                autoUpdateBunkerTransitionFreeze("AUTOMATION_LOOP")
                if State.BunkerTransitionFreezeActive then
                    State.AutomationState = "WAITING_BUNKER_TRANSITION"
                    State.Health.Automation = "WAITING_BUNKER_TRANSITION"
                    task.wait(0.05)
                    return
                end
                autoReconcileBunkerPhysicalState("AUTOMATION_LOOP")
                if not State.Tycoon
                or not State.Tycoon.Parent
                or not State.ButtonsFolder
                or not State.ButtonsFolder.Parent
                or not State.PurchasesFolder
                or not State.PurchasesFolder.Parent then
                    State.AutomationState = "WAIT_TYCOON"
                    State.Health.Automation = "WAIT_TYCOON"
                    reconsiderTycoon()
                    task.wait(AUTO_IDLE_WAIT)
                    return
                end
                State.AutomationState = "SCANNING"
                State.Health.Automation = "ACTIVE"
                local target = nil
                if State.CurrentZone == "BUNKER" or State.BunkerSessionActive then
                    target = autoSelectCandidateInZone("BUNKER")
                    if not target then
                        local pendingCount, pendingNames, earliestCooldown =
                            autoPendingEligibleInZone("BUNKER")
                        if pendingCount > 0 then
                            autoRecord("BUNKER_PENDING_ELIGIBLE_RETAIN_LOCK", {
                                SessionId = State.BunkerSessionId,
                                PendingCount = pendingCount,
                                PendingNames = pendingNames,
                                EarliestCooldownRemaining = earliestCooldown
                                    and math.max(0, earliestCooldown - os.clock())
                                    or 0,
                                Policy = "DO_NOT_EXIT_WHILE_ANY_ELIGIBLE_BUNKER_BUTTON_STILL_EXISTS",
                            })
                            task.wait(BUNKER_PENDING_RETRY_WAIT)
                            return
                        end

                        local queueStillEmpty = true
                        for emptyPass = 1, BUNKER_REQUIRED_EMPTY_RESCANS do
                            State.BunkerRescans = State.BunkerRescans + 1
                            autoRecord("BUNKER_PRE_EXIT_RESCAN", {
                                Rescan = State.BunkerRescans,
                                EmptyPass = emptyPass,
                                RequiredEmptyPasses = BUNKER_REQUIRED_EMPTY_RESCANS,
                                WaitSeconds = BUNKER_RESCAN_WAIT,
                                SessionId = State.BunkerSessionId,
                            })
                            task.wait(BUNKER_RESCAN_WAIT)

                            target = autoSelectCandidateInZone("BUNKER")
                            local rawPendingCount, rawPendingNames =
                                autoPendingEligibleInZone("BUNKER")
                            if target or rawPendingCount > 0 then
                                queueStillEmpty = false
                                autoRecord("BUNKER_RESCAN_FOUND_ELIGIBLE", {
                                    Rescan = State.BunkerRescans,
                                    EmptyPass = emptyPass,
                                    Name = target and target.Name or nil,
                                    PendingCount = rawPendingCount,
                                    PendingNames = rawPendingNames,
                                    SessionId = State.BunkerSessionId,
                                })
                                break
                            end
                        end

                        if not target and queueStillEmpty then
                            autoRecord("BUNKER_ELIGIBLE_QUEUE_EXHAUSTED", {
                                SessionId = State.BunkerSessionId,
                                Rebirths = State.LastRebirths,
                                EmptyRescans = BUNKER_REQUIRED_EMPTY_RESCANS,
                                NextAction = "TELEPORT_TO_EXIT_PROMPT_ONLY_THEN_TRIGGER_REAL_EXIT_ONCE",
                            })
                            local exited, exitReason = autoExitBunker()
                            if exited then
                                task.wait(AUTO_POST_RESULT_WAIT)
                            else
                                autoRecord("BUNKER_EXIT_RETRY_LATER", {
                                    SessionId = State.BunkerSessionId,
                                    Reason = exitReason,
                                    SessionRetained = State.BunkerSessionActive,
                                })
                                task.wait(BUNKER_PENDING_RETRY_WAIT)
                            end
                            return
                        elseif not target then
                            task.wait(BUNKER_PENDING_RETRY_WAIT)
                            return
                        end
                    end
                end
                if not target then
                    target = autoSelectCandidate()
                end
                if not target then
                    local rebirthed, rebirthReason = autoAttemptRebirth()
                    if rebirthed then
                        task.wait(AUTO_POST_RESULT_WAIT)
                        return
                    end
                    if rebirthReason ~= "UI_NOT_READY"
                    and rebirthReason ~= "REBIRTH_BUTTON_NOT_FOUND"
                    and rebirthReason ~= "REBIRTH_RETRY_COOLDOWN"
                    and rebirthReason ~= "FUNDS_BLOCKED_PURCHASES_REMAIN" then
                        autoRecord("AUTO_REBIRTH_DEFERRED", {
                            Reason = rebirthReason,
                            Rebirths = State.LastRebirths,
                            ServerReady = State.AutoRebirthServerReady,
                            ButtonsLeft = State.AutoRebirthButtonsLeft,
                        })
                    end
                    State.AutomationState = "WAITING_FOR_FUNDS"
                    State.Health.Automation = "WAITING_FOR_FUNDS"
                    local collected = autoTryContinuousIdleCollect()
                    if collected then
                        State.AutomationState = "SCANNING"
                        State.Health.Automation = "ACTIVE"
                        task.wait(AUTO_POST_RESULT_WAIT)
                    else
                        task.wait(AUTO_COLLECT_RECHECK_INTERVAL)
                    end
                    return
                end
                autoAttemptPurchase(target)
                State.AutomationTarget = nil
                State.AutomationTargetStarted = nil
            end)
        end
        task.wait(State.AutomationEnabled and 0.18 or 0.5)
    end
end)


-- Core bootstrap: no GUI, no export layer and no AutoSave layer.
safeCall("CORE_INITIAL_STATS", function()
    State.MoneyObject = findStat(MONEY_NAMES) or discoverMoneySource()
    State.RebirthObject =
        findStat({"Rebirths", "Rebirth", "Renascimentos", "Renascimento"})
    State.LastMoney = readValue(State.MoneyObject)
    State.LastRebirths = readValue(State.RebirthObject)
end)

safeCall("CORE_INITIAL_TYCOON", function()
    reconsiderTycoon()
    local floor, floorEvidence = detectMainFloor()
    setMainFloor(floor, floorEvidence)
    local zone, zoneEvidence = detectZoneByPosition()
    setZone(zone, zoneEvidence)
end)

State.Health.Bootstrap = "OK"
State.Health.Engine = "ACTIVE"

task.spawn(function()
    while State.Running do
        safeCall("CORE_STAT_LOOP", function()
            refreshStatsObjects()
            local money = readValue(State.MoneyObject)
            local rebirths = readValue(State.RebirthObject)

            State.Health.Money =
                (State.MoneyObject and money ~= nil) and "ACTIVE" or "SEARCHING"
            State.Health.Rebirths =
                (State.RebirthObject and rebirths ~= nil) and "ACTIVE" or "SEARCHING"

            if State.Reading
            and State.LastMoney ~= nil
            and money ~= nil
            and money ~= State.LastMoney then
                local delta = money - State.LastMoney
                pushEvent(
                    delta < 0 and "MONEY_SPEND" or "MONEY_INCOME",
                    "Money",
                    {
                        OldValue = State.LastMoney,
                        NewValue = money,
                        Delta = delta,
                        Direction = delta < 0 and "SPEND" or "INCOME",
                    }
                )
                correlateStatChanges(
                    State.LastMoney,
                    money,
                    State.LastRebirths,
                    rebirths
                )
            end

            if State.Reading
            and State.LastRebirths ~= nil
            and rebirths ~= nil
            and rebirths ~= State.LastRebirths then
                pushEvent("REBIRTH_CHANGE", "Rebirths", {
                    OldValue = State.LastRebirths,
                    NewValue = rebirths,
                    Delta = rebirths - State.LastRebirths,
                })
                correlateStatChanges(
                    State.LastMoney,
                    money,
                    State.LastRebirths,
                    rebirths
                )
            end

            if money ~= nil then
                State.LastMoney = money
            end
            if rebirths ~= nil then
                State.LastRebirths = rebirths
            end
        end)
        task.wait(MONEY_INTERVAL)
    end
end)

task.spawn(function()
    while State.Running do
        safeCall("CORE_TYCOON_LOOP", function()
            reconsiderTycoon()
            local floor, floorEvidence = detectMainFloor()
            setMainFloor(floor, floorEvidence)

            -- V1.7.5.11 authority rule:
            -- the normal Tycoon loop may not overwrite zone state during
            -- an Enter/Exit transition freeze.
            if not State.BunkerTransitionFreezeActive then
                local zone, zoneEvidence = detectZoneByPosition()
                setZone(zone, zoneEvidence)
            end
        end)
        task.wait(TYCOON_INTERVAL)
    end
end)

local API = {}

API.Version = CORE_VERSION
API.SourceVersion = SOURCE_VERSION

function API.Start()
    if not State.Running then
        return false, "CORE_SHUTDOWN"
    end
    setAutomation(true)
    return State.AutomationEnabled, State.AutomationState
end

function API.Stop()
    if not State.Running then
        return false, "CORE_SHUTDOWN"
    end
    setAutomation(false)
    return not State.AutomationEnabled, State.AutomationState
end

function API.Toggle()
    if not State.Running then
        return false, "CORE_SHUTDOWN"
    end
    setAutomation(not State.AutomationEnabled)
    return State.AutomationEnabled, State.AutomationState
end

function API.IsEnabled()
    return State.Running and State.AutomationEnabled or false
end

function API.GetState()
    return {
        Running = State.Running,
        Enabled = State.AutomationEnabled,
        AutomationState = State.AutomationState,
        Target = State.AutomationTarget,
        Money = State.LastMoney,
        Rebirths = State.LastRebirths,
        Zone = State.CurrentZone,
        Floor = State.MainFloor,
        BunkerSessionActive = State.BunkerSessionActive,
        BunkerSessionId = State.BunkerSessionId,
        BunkerTransitionFreezeActive = State.BunkerTransitionFreezeActive,
        Successful = State.AutomationSuccessful,
        Failed = State.AutomationFailed,
        TotemCollectSuccessful = State.TotemCollectSuccessful,
        TotemCollectFailed = State.TotemCollectFailed,
        AutoRebirthSuccessful = State.AutoRebirthSuccessful,
        AutoRebirthFailed = State.AutoRebirthFailed,
        SafeTeleportsConfirmed = State.MovementSafeTeleportConfirmed,
        SafeTeleportRecoveries = State.MovementRecoverySuccessful,
        CharacterLosses = State.MovementCharacterLosses,
        Errors = #State.Errors,
    }
end

function API.GetEvents()
    return State.Events
end

function API.GetErrors()
    return State.Errors
end

function API.Shutdown(reason)
    if not State.Running then
        return true
    end

    if State.AutomationEnabled then
        setAutomation(false)
    end

    State.Running = false
    State.Health.Engine = "OFF"
    State.Health.Automation = "OFF"
    disconnectAll(State.TycoonConnections)
    disconnectAll(State.Connections)

    pushEvent("SYSTEM", "CORE_SHUTDOWN", {
        Reason = tostring(reason or "MANUAL"),
        Version = CORE_VERSION,
    })

    if ENV.PsicoTycoonAutoBuy == API then
        ENV.PsicoTycoonAutoBuy = nil
    end
    return true
end

ENV.PsicoTycoonAutoBuy = API

pushEvent("SYSTEM", "AUTO_BUY_CORE_READY", {
    Version = CORE_VERSION,
    SourceVersion = SOURCE_VERSION,
    AutomationStarts = "OFF",
})

return API

]==]

local function GetExecutionEnvironment()

    local env = _G

    pcall(function()
        if type(getgenv) == "function" then
            env = getgenv()
        end
    end)

    return env
end


local function ResolveKnownAutoBuyCore()

    if type(AutoBuyCore) == "table" then
        return AutoBuyCore
    end


    local env =
        GetExecutionEnvironment()


    local existing =
        env and env.PsicoTycoonAutoBuy


    if type(existing) == "table"
    and type(existing.Start) == "function" then

        AutoBuyCore = existing

        return AutoBuyCore
    end


    return nil
end


local function UpdateAutoBuyButtonVisual()

    if not AutoBuyToggleButton then
        return
    end


    if AutoBuyEnabled then

        AutoBuyToggleButton.Text =
            "🛒  Auto-Colect & Purchase: ON"

        AutoBuyToggleButton.BackgroundColor3 =
            BUTTON_ACTIVE

    else

        AutoBuyToggleButton.Text =
            "🛒  Auto-Colect & Purchase: OFF"

        AutoBuyToggleButton.BackgroundColor3 =
            BUTTON_COLOR
    end
end


local function RefreshAutoBuyEnabledState()

    local api =
        ResolveKnownAutoBuyCore()


    if not api then

        AutoBuyEnabled = false
        UpdateAutoBuyButtonVisual()
        return false
    end


    local stateOk, enabled = pcall(function()

        if type(api.IsEnabled) == "function" then
            return api.IsEnabled()
        end


        if type(api.GetState) == "function" then

            local state = api.GetState()

            return state
            and state.Enabled
            or false
        end


        return false
    end)


    AutoBuyEnabled =
        stateOk and enabled == true or false


    UpdateAutoBuyButtonVisual()

    return AutoBuyEnabled
end


local function EnsureAutoBuyCore()

    local existing =
        ResolveKnownAutoBuyCore()


    if existing then
        return existing, true, "READY"
    end


    local compiler =
        loadstring or load


    if type(compiler) ~= "function" then
        return nil, false, "LOADSTRING_UNAVAILABLE"
    end


    local chunk, compileError =
        compiler(AUTO_BUY_CORE_SOURCE)


    if not chunk then
        return nil, false, tostring(compileError)
    end


    local ranOk, result = pcall(chunk)


    if not ranOk then
        return nil, false, tostring(result)
    end


    local api =
        type(result) == "table"
        and result
        or ResolveKnownAutoBuyCore()


    if type(api) ~= "table"
    or type(api.Start) ~= "function" then
        return nil, false, "AUTO_BUY_API_NOT_READY"
    end


    AutoBuyCore = api
    AutoBuyLoadedByMenu = true

    return api, true, "LOADED"
end


local function TeardownAutoBuyCore(reason)

    local api =
        ResolveKnownAutoBuyCore()


    if api then

        pcall(function()
            if type(api.Stop) == "function" then
                api.Stop()
            end
        end)


        if AutoBuyLoadedByMenu
        and type(api.Shutdown) == "function" then

            pcall(function()
                api.Shutdown(reason or "MENU_CLOSE")
            end)
        end
    end


    AutoBuyEnabled = false
    AutoBuyCore = nil
    AutoBuyLoadedByMenu = false

    UpdateAutoBuyButtonVisual()
end


local function SetAutoBuyEnabled(enabled)

    local api, ok, message =
        EnsureAutoBuyCore()


    if not ok or not api then

        warn("[PSICOSENATICO PANEL] Falha ao carregar Auto Buy Core:", message)

        AutoBuyEnabled = false
        UpdateAutoBuyButtonVisual()

        return false, message
    end


    local callOk = false
    local resultEnabled = false
    local resultState = nil


    if enabled then

        callOk, resultEnabled, resultState = pcall(function()
            return api.Start()
        end)

    else

        callOk, resultEnabled, resultState = pcall(function()
            return api.Stop()
        end)
    end


    if not callOk then

        warn("[PSICOSENATICO PANEL] Falha ao alternar Auto Buy:", resultEnabled)

        AutoBuyEnabled = false
        UpdateAutoBuyButtonVisual()

        return false, resultEnabled
    end


    RefreshAutoBuyEnabledState()


    if not AutoBuyEnabled
    and enabled
    and resultEnabled ~= true then

        warn("[PSICOSENATICO PANEL] Auto Buy não confirmou ativação:", resultState)
    end


    return AutoBuyEnabled, resultState
end


--========================================================
-- RESET
--========================================================

local function ResetScript()

    TeardownAutoBuyCore("MENU_RESET")

    AimbotEnabled = false
    ESPEnabled = false

    ClearAllESP()

    DisconnectAll()


    if Gui then

        Gui:Destroy()

        Gui = nil
    end


    FOVCircle = nil
    MinimizedButton = nil


    task.wait(0.15)


    CreateInterface()
end


--========================================================
-- FECHAR SCRIPT
--========================================================

local function CloseScript()

    TeardownAutoBuyCore("MENU_CLOSE")

    AimbotEnabled = false
    ESPEnabled = false

    ClearAllESP()

    DisconnectAll()


    if Gui then

        Gui:Destroy()

        Gui = nil
    end


    Main = nil
    FOVCircle = nil
    MinimizedButton = nil
    CreatingInterface = false
end


--========================================================
-- INTERFACE
--========================================================

function CreateInterface()

    if CreatingInterface then
        return
    end


    CreatingInterface = true


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


    Main.AnchorPoint =
        Vector2.new(
            0.5,
            0.5
        )


    Main.Position =
        UDim2.fromScale(
            0.5,
            0.5
        )


    local function ApplyResponsiveMenuSize()

        local camera =
            GetCamera()

        local viewport =
            camera
            and camera.ViewportSize
            or Vector2.new(800, 600)


        local width =
            math.clamp(
                math.floor(viewport.X * 0.42),
                280,
                360
            )


        local height =
            math.max(
                180,
                math.min(
                    370,
                    math.floor(viewport.Y * 0.70)
                )
            )


        Main.Size =
            UDim2.fromOffset(
                width,
                height
            )
    end


    ApplyResponsiveMenuSize()


    Main.BackgroundColor3 =
        MENU_COLOR


    Main.BorderColor3 =
        BLACK


    Main.BorderSizePixel =
        3


    Main.ClipsDescendants =
        true


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
            -2,
            0,
            41
        )


    TitleBar.Position =
        UDim2.fromOffset(
            1,
            1
        )


    TitleBar.BackgroundColor3 =
        Color3.fromRGB(
            12,
            23,
            42
        )


    TitleBar.BorderSizePixel =
        0


    TitleBar.ClipsDescendants =
        true


    TitleBar.Parent =
        Main


    local titleBarCorner =
        Instance.new("UICorner")


    titleBarCorner.CornerRadius =
        UDim.new(
            0,
            10
        )


    titleBarCorner.Parent =
        TitleBar


    local Title =
        Instance.new("TextLabel")


    Title.Size =
        UDim2.new(
            1,
            -125,
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
        "🎯 PSICOSENATICO PANEL"


    Title.TextColor3 =
        WHITE


    Title.TextSize =
        17


    Title.TextScaled =
        true


    Title.Font =
        Enum.Font.GothamBold


    local titleTextConstraint =
        Instance.new("UITextSizeConstraint")


    titleTextConstraint.MinTextSize =
        11


    titleTextConstraint.MaxTextSize =
        17


    titleTextConstraint.Parent =
        Title


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
            -82,
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
    -- FECHAR
    --====================================================

    local Close =
        Instance.new("TextButton")


    Close.Size =
        UDim2.fromOffset(
            35,
            30
        )


    Close.Position =
        UDim2.new(
            1,
            -42,
            0,
            6
        )


    Close.BackgroundColor3 =
        BUTTON_COLOR


    Close.BorderColor3 =
        BLACK


    Close.BorderSizePixel =
        2


    Close.Text =
        "×"


    Close.TextColor3 =
        WHITE


    Close.TextSize =
        22


    Close.Font =
        Enum.Font.GothamBold


    Close.Parent =
        TitleBar


    local closeCorner =
        Instance.new("UICorner")


    closeCorner.CornerRadius =
        UDim.new(
            0,
            5
        )


    closeCorner.Parent =
        Close


    Connect(
        Close.MouseButton1Click,
        function()

            CloseScript()
        end
    )


    --====================================================
    -- CONTEÚDO COM ROLAGEM
    --====================================================

    local ContentScroll =
        Instance.new("ScrollingFrame")


    ContentScroll.Name =
        "ContentScroll"


    ContentScroll.Size =
        UDim2.new(
            1,
            0,
            1,
            -42
        )


    ContentScroll.Position =
        UDim2.fromOffset(
            0,
            42
        )


    ContentScroll.BackgroundTransparency =
        1


    ContentScroll.BorderSizePixel =
        0


    ContentScroll.CanvasSize =
        UDim2.fromOffset(
            0,
            380
        )


    ContentScroll.ScrollBarThickness =
        5


    ContentScroll.ScrollBarImageColor3 =
        Color3.fromRGB(
            125,
            160,
            205
        )


    ContentScroll.ScrollBarImageTransparency =
        0.10


    ContentScroll.ScrollingDirection =
        Enum.ScrollingDirection.Y


    ContentScroll.ElasticBehavior =
        Enum.ElasticBehavior.WhenScrollable


    ContentScroll.Parent =
        Main


    local cameraForResize =
        GetCamera()


    if cameraForResize then

        Connect(
            cameraForResize:GetPropertyChangedSignal(
                "ViewportSize"
            ),
            function()

                ApplyResponsiveMenuSize()
            end
        )
    end


    --====================================================
    -- DRAG DO MENU
    --====================================================

    local dragging = false
    local dragStart
    local startPosition


    Connect(
        TitleBar.InputBegan,
        function(input)

            if input.UserInputType ==
                Enum.UserInputType.MouseButton1
            or input.UserInputType ==
                Enum.UserInputType.Touch then

                dragging = true

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

                dragging = false
            end
        end
    )


    --====================================================
    -- AIMBOT
    --====================================================

    local AimButton =
        CreateButton(
            ContentScroll,
            "🎯  Aimbot: OFF",
            UDim2.fromOffset(
                10,
                12
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
            ContentScroll,
            "👥  Team Check: ON",
            UDim2.fromOffset(
                10,
                57
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
            ContentScroll,
            "👁️  ESP: OFF",
            UDim2.fromOffset(
                10,
                102
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
    -- AUTO-COLECT & PURCHASE
    --
    -- Integra o Auto Buy Core enviado pelo usuário.
    -- Nesta versão o botão alterna Start/Stop do core.
    --====================================================

    local AutoCollectPurchaseButton =
        CreateButton(
            ContentScroll,
            "🛒  Auto-Colect & Purchase: OFF",
            UDim2.fromOffset(
                10,
                147
            )
        )


    AutoBuyToggleButton =
        AutoCollectPurchaseButton


    RefreshAutoBuyEnabledState()


    Connect(
        AutoCollectPurchaseButton.MouseButton1Click,
        function()

            SetAutoBuyEnabled(
                not AutoBuyEnabled
            )
        end
    )


    --====================================================
    -- FOV
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
            197
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
        ContentScroll


    CreateSlider(
        ContentScroll,
        227,
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
            257
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
        ContentScroll


    CreateSlider(
        ContentScroll,
        287,
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
            ContentScroll,
            "🔄  Reset Script",
            UDim2.fromOffset(
                10,
                327
            )
        )


    Connect(
        Reset.MouseButton1Click,
        function()

            ResetScript()

        end
    )


    --====================================================
    -- FLUTUANTE
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
    -- BOTS / WORKSPACE.SOLDIERS
    --
    -- Monitoramento específico, sem observar todo o
    -- Workspace a cada novo descendant.
    --====================================================

    local function ConnectSoldiersFolder(folder)

        if not folder then
            return
        end

        Connect(
            folder.ChildAdded,
            function(object)

                if not object:IsA("Model") then
                    return
                end

                task.defer(
                    function()

                        -- O Model/Humanoid pode terminar de
                        -- replicar depois do ChildAdded.
                        for _ = 1, 30 do

                            if not object.Parent then
                                return
                            end

                            if IsBot(object) then
                                break
                            end

                            task.wait(0.1)
                        end

                        if ESPEnabled then
                            UpdateESP()
                        end
                    end
                )
            end
        )

        Connect(
            folder.ChildRemoved,
            function(object)

                RemoveESP(object)
            end
        )
    end


    local soldiers =
        workspace:FindFirstChild("Soldiers")

    if soldiers then
        ConnectSoldiersFolder(soldiers)
    end


    Connect(
        workspace.ChildAdded,
        function(object)

            if object.Name == "Soldiers" then

                task.defer(
                    function()

                        ConnectSoldiersFolder(object)

                        if ESPEnabled then
                            UpdateESP()
                        end
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
    -- RESPAWN
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
