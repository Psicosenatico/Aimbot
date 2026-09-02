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
            -4,
            1,
            -4
        )


    avatarHolder.Position =
        UDim2.fromOffset(
            2,
            2
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
                1,
                1
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
            Enum.ScaleType.Stretch


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
