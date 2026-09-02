--========================================================
-- PSICOSENATICO PANEL
-- ESP + AIMBOT
--
-- PLAYERS:
--     Player.Team
--
-- BOTS:
--     Workspace.Soldiers
--     Model:GetAttribute("Team")
--
-- ESP:
--     MEU TIME = VERDE
--     INIMIGO  = VERMELHO
--
-- O Highlight original do jogo é apenas confirmação.
-- A cor do nosso ESP é independente do jogo.
--========================================================

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
        MENU_COLOR


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
        UDim2.fromScale(
            1,
            1
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
            UDim2.fromScale(
                1.04,
                1.04
            )


        JokerImage.AnchorPoint =
            Vector2.new(
                0.5,
                0.5
            )


        JokerImage.Position =
            UDim2.fromScale(
                0.5,
                0.5
            )


        JokerImage.BackgroundTransparency =
            1


        JokerImage.BorderSizePixel =
            0


        JokerImage.Image =
            jokerAsset


        JokerImage.ScaleType =
            Enum.ScaleType.Crop


        JokerImage.Parent =
            avatarHolder

    else

        local JokerFallback =
            Instance.new("TextLabel")


        JokerFallback.Name =
            "JokerFaceFallback"


        JokerFallback.Size =
            UDim2.fromScale(
                0.86,
                0.86
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
