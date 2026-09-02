--========================================================
-- TEST CONTROL PANEL
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

local JOKER_ICON_B64 = [[iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAYAAADimHc4AABLa0lEQVR42q29eZTc13Xf+Xm/vaq6lu7qDd0NNNBAgyCIjSS4i6sWarEsS7JlOY5lx45zMo6STMbOGSXjJIxzRnEyk/gojhXHSxwrsmPHGslaTFkSV3EVCZIAAYJNLA00ekF3V1d17fXb3/zxqn7dRYCUMmd+5/Sp7upa773ve+/93vvuE5+5fUwCCCF4p0tKCYAfQRwHdHz12I4XArDZ9gGodvzu/THEEj9WzzeA8G23dH9/t6sTqvfxJERSgqb1/f96n7n3WYUEKdQtgIb6xe4+JWXI676ngXqbOL7m7a69NAGx/KGPqbnQigEkhRvvJz9SJO7UWZlfSGSBlPIdlSCESL4YQMqSiRJ+lCvcdmts+3v77z1h9wQeI5ACZCxBCIQmup8Teh8zjmL1PxkjRFda3f9JoR4rUY8PpUAIaHeV4wXXV0YI0DOc7u12RcTb7/sRhK8ec62sGs0gkcE1FnQ9RQghsHSJj0kcB+/6vk4scJHvqoze751QJBYuhYamCYRhIuIQGceABCmR219OaGiGBWb62s8J4NWJohhknCht+61mGMRS0uoK0Ot+HVtsKWO7cRBvCapvVWhvk1NPIb37Y3ntY96+4twgwDHNvuX7TpdSjOT/j6sn+BiB0DWE7Ao6ioijCADdMCBVwBooYmaHyA9m0VI5ALKFQfVC6YHrv0G7qSytukncqbOxPI/eqtHptIh8d5suNaKuhbbZWhlvh6hk1W6Hph9BwD/sMnrYbunvjKtvx9d3ugopi2rHx9W6y+5tS3Q7pscIhGkhIBGIpuuk80UKO6bQR/eSLQxiD04jDAPXDyEog1l899VndW01MwbA0KT6DGNHHkKGId7mArWrC4lCmrUKINGEhtA1tTKiiLYP6a5w38lfXCP87Zb/P6OAHwWC/qevbR8igZnu62q6pgQfuOimQ2pihuHJGfI7pnFG9pK21HPb2/1MUFZWnb7+29n29RXTew0Zhngx2IPTjA5OM3rwPjyvTGNlkY0rC7ilS0StTUAiNA1N02hFMULGeIFIVkW4DZK07WhwPdj5ERSRKGD7Kvj/Yv3X+ICuk6oGYgvfuwqIwhA9M0Rh12Gmjh5jaHB0+zv1CV6GIZ5Xpl5bRG7UEcMKgvSJC1RPWeoxmRVEayJ5zoAoJI/L5Xdi20WEYWCHCki8riPFLDK8p0h2Yie0jyUro3P1MlEYouk6UmqEsVRRWCiS1RBuh6PtK+GdhC8EXEeGhvLsAZpm8m6rQQiBF767EnphqEgJ/FZMNRCEiMTi4yhCtxwK+9/D1PH3MjSgX9di3dYamyzRvrCAv34VaVeVkQiX7FAWK+3QXGwirRh8oAWBLGMKHZERNB0ziWQamyBdtWxEa4LsyC5y5iCkB7ZWjVmEfJHRwWnye2+isbLI+oWTdFYuKXjS1edsxbLPR4SA9W7Od7sSpPzRIOjdrN/S1UrpXbppEgX9EVHHi1XcK0HTNLSe4A2DzO5b2XPkGM7I3q6wSeCmsrlOvbZIo3SFwlGf6oWLeHUXHLBytnK8xa7wKw0lUFMgffX8oV2D6GklAN9XhhC5Mb4XgF1HNmMCWaZx8TU2pINsjWHnd5LbXSQ3fAzHMpBhiG0XcWbHGN5zjI1LJ7uKmEd0fVQYQxgrWCqYKtdJIqTtkPQj+gHjh0U9/zPQ0/Fi1jsQShXBxHGMjGNSEzOMHD3GyOgxhGH0wUulpJziauslzHRI4YY8ngsykAzsGEM4bfVYN42VjmlWGliOWq1ew8cuWqSGU/i+j78RvfN3MQWWaSCFDi4I1mhsLtG4IikNnGZ4l7J+p+u8vRhGZo8zvOcY62e/z8rZV4lalW2wFFPuOuqUITHeniNcNw8QP1wB2x3w24Xfy4Svd12tuqy0QWgCTRMJzk8cvIX8gfsQloXn+zg9XN9cQF9/nSV7mSBdw5SSwg15AGpLdeyije546KGy+IGhGD/0sHIW+BKv4ZMdy6GnBZ26C77ESjvK8o2AyI3VfcLAlwr7ZSAJZAQ2mBjYeQNvw8MvXWbplYusnDtLdmKWqdl92IPTieMePXgf+R3TVM+dYOX8GWQcoxsGURTTiuM+32C8szUnecmPHAX9sBVgaZIOsLDRYcNXS5RYEseRgps739MXNjqWQen8CertK1g7l/BHPGzDJqiAlSkAktpSnYGhbAInnXpn6+961xDcoE/4lmGj5wRRWyrh17srwVKvYfkGvh0iABNd+Q0gkBFa0YC0DRUXWVmjcbHC3PolBkb3JIoAFT2N3TGNtmcvy8+/SFRbUUoIZdc3bEVKSQbNtohIXj8j1m/akXpECVtH1/pXwduFH0mQMu7jgl5YalPzlEXEUYRm2Uzd8gDjtz4MejoRfNha5dyTj7Jx5knyd8ToaYEWKefmd3zSQxaNNYXtqaKz5ZQrHQqTO4nCNqZtEHohETGpgo3v+zhpG81UnyeUXeFbAiLUj65+14VGpEvFDQXK9HShESPBjLBsk8i1IIjBb+E3N9m4WqJV3SCT1jFSBbwYJgpDZKb30WqGeJVlNKGBJoglhFIipEDXVAwgpEIEL4SgK0pnZBonk8Zrd/BbDaUATTOvCUF7SvAjJfgoSedjTB2ubHQ4udiiE0o0yyYKfAbyRWbf9ymcqaNb8bkG62ee4tJz38GvLGAMF8geMInaXYKv7ZLKZRTu1j2yIzk0U2A7I/j1FlbKxkxliELlC9r1Dqm8ja7r6LqO7Ywk//NbAegCv+4ThTED4wOYtoGGASmJhkZEjNCUEgIZYQodXWhggJGGMPShreJ/ZEjgtdlYWccwQnJD4/ixjmGkmT54E7HQqC3PQzfSkxKCrhJMDbSuzXuRuEYBlhbS2Kxdmwf0YOd60NMLVzdqLnOrLp6ElK3Tdl1SEzPsvu+jCeQ4loHbWuPNZ5/GW58DM41eyGCN+URtGz/0SOUcdENHtxR8CFOQHtrKCfzQozC6UynSGVFwYrtYlpX83ftfo76slFj2EAMa+ZHs1jJPC3QsfHwsTBAS3w4xmxB4SgnqQ0ucMQfP84gaPiL00QBrwGZ5bo7NlWV2Hb+TocFR2r5gz/EH0VI5Fp75S+IoRjd0oiim3fUL2W0ZtNCEIhavB0FSxn0Q9HbYebvwX5iv40mwbQPPCxnYdwd77vsUIlWAKFLCL11k7pm/JnSXEWkbbSJCZAXpKYNIRFiGgg69G2NrpsA0LMxUhp3j9+H6aYL2EmYq0/d56pUy+eIUO8fvIz8wTb25gOeW8FsBzZU2hckChfGpZFX0fZcoQjMEmq2hoRHrEl3XlJnqCrICPcIasIjdGOlGxGEH6bcRziCB51NevEIceYzs2EHbF4zs2IEcztO8coko8LsrQRJKcHSFgF4kCLrRUG8FyNDbWgHXg6DrRT2b7YgXltq0YknGMcEPGb/hCIP3fHxL05ZF6fxLlObnIeMjyCFSDTIjAwTUsNJp/NBDT4s+K25X1hPHq2L5NwHYOX5fct/i6vfJj2T77uvF/V7ZY+TAUN9r+r6vcoG6v42zEFi2+UNDajEu0TCI6iGR76JX5xGFGQCW3jhN3KkzduQh2r5gdOI4uQ8O8ubjXyNqq1A1jiLKPhStXn5/fSIzWQExeoL1vZ9e8cXUoeMLnp6v03ID5f2DiJEbjjB2xyeJNKU9K/TZvPgK9fYVjAENv9NEpBoM3ZDGLoKTU1Zv2gr5DCOD55YwjAytRgUt0jFTGerNBRWldFp0og3qzQXyA9MsrzxPOjNOfmA6UYjnlmhcaVLYk0+E77klOhsd3BWPzkob3dGxB20GRjLki1M4mTxOJo9hhzg5G6lD1IkIwgjZCImiLvcpdDQhkD4QBQgiMNJolk19Y4NWZZ3BHbshjskXiwzs2kf50nlir93NF6AT9Ryw6PqA3ckKaNbbW1GQlPE1P71oJ4wEr1yqUOmojDYOQ+yJGQ4/9JMEmk2EwCbm4ovfo3z5LCKo095YZ2CfwdjRCcxUBsNQjrTnNKO2JBZtZaUtl3apjdAkwvITxXg1FyencoN6c4FOrYaTyVNvLiRKqlxdw85aDOR3JMKvlRqEKxFe1cMetLFHbVI5J1F6EoN3P5NpG0gdpK+iOV2ahJ0QAg2pxWjoIASx1+5TglffpFXdYGhyhlDq5AYyDAyPU770JjIMUN5e9iVhfQqoNa6fN7y92nV2pcpKWybCz+SLHHrgw7RI4/ohtgbnnvsrWldOgZnGjQNyt+sUpoYToQBEbYlHiagt8dsuhL1YvwG+iu9TpJLH+27Q93zf6/8bQDZjCjt3bll+3UWuSLymi+guf7/u43sBljDoWIvojoZlWYkD771eQm04EhsHLwgQbQG6hDTonoF0a4hoAIwCdipDs1zi4kuPs/f299LGYGhyhhs/+LO8+dd/Qhz6ILQ+5xsHbj8EzRTTj5j6tcLveCFS01mrtjlb8tF0HS2OEZkhZj/ycwTpSUJfCeTS839F89IJhK0ij+zNGQZ37+izNMPIEIt2En5GIlLhohchA6lidgHO4FYO4NU9jHSU4HnoRRj2Vk2tU3eJdUkmP6gcse/jVTy8kttDECIvIlyTBMs+fjnCr7t47ZCg7OO5PkG7qbA+jlReoMUEfkTU8bFNm0iT4EtEJCCrgSmh7oKVJxYCyzDoNBu0NtcY2rmPIBLkBgeR9gDVy2e74fyWQdtDU6SyuWQFaD2h934A/FjdbtRanFwPkEJL8oLJ+x5AZHYgu4TX0onHaZUWEQNjELRxiikG9w33ablnYbYzgp4Wyvp9iQwk3lUXfBAZAT6JgrY70r5icfc+3/fx6z6WbSaWH7kxfjNEWCBbIFcFcllDliJEW4NGjGzpyMYWNeG7AY21Ol7Zw2v4yJbEFDpWzsYXLnbaVIIHpB/hFBwYipGtVeWn4hg7naJZLlE6f0Kxpu2IkdnjFG68HxnHvFt55ZrA049FwnCeayjuvsft7Dj+XvITtyN9H2FZNBZO0iyX0DLDaJlhrOEJBm6N+iCiJ5xGfXnrfkvQ3OhAXWBJB+9qiEkekekqp0d1OKYSajeaeTvTKQOJZdh06i6+F+DXfUyhI1s6VCBuxkTtgDiIQJekpUkmyCLrOt7VEH/DQ7YkdtbCzlpbtR+pVp1lOXiBi8hESLtXP3bRhhywAmKv0yUVIyzLYnlujtL5E0kFb+/t7yU1MdPljhTMBI1KPxfUs/Y+XDJNztag0ah1+Y6Q1MSMqiJ1hS9L51m5cAFhKBpX6D6a6akEC6dPCT0H6Ps+lmVhGTam5+NtdEPchsQv18jOZmms1bHSzlZI6ktwFP7LQCaKwJfKb4ReEmbKVnf1NOIuLaIzNTzMyIBNdnQMM7fFS1UunOVUvYS36sOYgBGlCN8NMFu6ypIxsAcc5U8yalUlUDIc462Ukfo4QZfhFYbB8txcXyl17/EHefOvV4hDBeP+5iJxZxotlUNGC+j7RtKPbBd+KbJpS4MLlbLiTLo8+P77fwIjVVCJmbvOpVdeUp0HgBAu0veJh+pYAwINI+FnorbEq7m0Kx2CaoB7xcevKIGNuQPEkUUgBOFqB2M4i5GJ6TQ6mIZFJCK8dR8tpTJMmhLD1iHqOugAYhkrwQeK0GtfrUFHMFUc4tihGxidnmFqepaB3BA7RkaZGBpkYscUO3dOk0kXKK1v0l5rErYiRKxhD5nEWqyqdwIIBYZlEPlh4tSFaaGbUmXv6Ahjy2/JwKOxsUFucpQQByc3jCYiassXFVkpNHyZJuXoKhFzi7v6s8VQ53z5LERCffFWQOHG+7EHp/E8VRRfOnUSr93BsiyCOEZGFuhdZylDUj0mc6OD7wbIMuCBW/WYKB7iw/ceJ2VopEcV7VBeWeUHp1/n/MpZrIk8ltPug6IkkXKFErwtkC2JX/ewsMEV4Ej8lRoT/iA3vOdmbprejZHa6phoNOrd+nRMqtPESA1w9MAhitkCjz76LVo1HxcX33exhm0VESFVGOmKRPiWdCBQlDZpD1ltgj6QIIFmp/A6LZZOnWTf3Q8jw5DRg/clpU49a+J3KtQ2bYRuou/eteMRgGqo42iSt8yrtBZrCEdDGjF6psDMXQ8TaWnQ0zQWTlJevJKEcbGUqhKRaWPl2xR25RLLj4KQcC3uCt/l8N5beOR//8fs3jPDPe+5hwfue4h9s7NM7NrJjVNTmL7NxeYi/lqbKIgw0jpRJ4KGAFPiNzx0TVdZYksQdkKidkTkhxiByW1jN/DgfQ+xe/9+xnbsYGp0hF379pNPWXiaoNNQrSphLNHjgDj0KQwNI6MWCwuraCMCe8wm8CIiP0Y3NEVRCBVNqegtRMfAj12EJaERIHR7i9mPYzTLxm81KQxlMLPDCE0jNzFJ+dI50GOESBEEHWQEuvb+kUdqwzHeaERtOKZ+/iphK0Sk1bKeuvGD5IZniPwyxB2WT50kiiJiIdCFIJaqiwCjQ3qvTLJczRS0FtsQCrxqwKRR4F/8839FoVhg7769HD50BE2AY6UZyg/ipB3GJqaYHpgkvrrJSrlMp9pGlya+76KHJrpuQEtAJPA2A6QrEU1BRha48/Dt3HL0dg4euIHJnXvYuXuabLGI7rfIZFLYQr9GCaYm0EyLbG6I84sLhBkXY9RCT+voukbQidBjFaf0FACg24ZK1CK1sgkEWsoC2WUEDINYCNxWh8EduxGahmENoMUujdV1rEyaqOOB/7ZErF1ZTxwOQO7gGMO7j6kuArNIbe77eJ0Wmp1KQjBT0xCGjrlLJs7WdkbYvLABNYFftZA1lw/9/McoFAsU0mlu2DeL5/nbWkocJianyRQG2b1zgjtuupEfvPEmL7/8EnPz61TkhcRhy27TlvAEA06BPQdneODmYxw6dJiRkSHMQpFCOk21rcg4s6Acb48h8hvta+Aom82RNwSdrEEqb9OpeUnZU7YUBFmWg7+9ocuCeBOwJaLWRvoDoFtJyTWVTuE3amxcOsn0TbcqzujgfawuXcZvtSF0IWj3K6CxWEe2SBSQ2XEXvmGB70NtgasLKwjdVFFP940Mx6YdLYFdB7LYzgjVpSv4LR8QSK/B5PAgtx1TNYK9+w/2CV8zdOIwwrYdRm2HOJ9jYnKaiZkDvOee93D29OusLq9yau4MpYrqjhgZKlDMFpg5sJ+Z0TEmZmcZGRrBcix8V7124e0dG0A60hl3O4QXmnTC/vKgzE0Cc0p4eZvIjbEw8QnwZUhc3nLCeAqWhKVDVSb1baFv96UhhmNTK5VptSOEYZBJ60zMHmHpxUchVpyT0Wf9S1tZZnZ6jEHzKNL3VVHl6gIyChC6ufWGvfAr1dj6oktXlFUXLTw3QNqSG47dzMjIECNDIzi2RRRsKcDUIOgqQTN0bCtDCkhlMowUh5mcmKRV3eTelVtpRVvfsFAsJEJP61uhdDqjOijaXWUEroodC+l093uWWE0NQHcVXBOCh6aqPRt2YvGmreMRIls6IhPhtQMwATNSfPO2MnkPEZKcotPsWwXZ6WNw6kXi2oqCpsT6zzegHYOt4t3MjrsQloUV+nhemdXl9S1riYIk7g3aJeKOC1MWnY1OEsNHbYnnKEHPTO5S0NAVztsvU+OarjBTAzObwd62KgJXKdp0FOVhGhBs6/Y1u98mCCEP1LpF5J4SANJDI1jra4kCOmFMFigWLCqhroo3voZfdxMuCl9BjiRSUVAavHa35EkMZvpt3R5RogTdMPpWgWMZZCdmqdZW0IRQmXC7so675ibYqg2MM2gexQp9hGHQWFkk9joKfqL+rgi/5UKkSDEskSRQXkUDV+AUHGYP7GeALasP4q1bz4+Sv3XT6nvt3v2a7mDbDgP5EQbyI9i2kwj77beavvW/fCZHIWOT6TXyAhk9YiiXe0dqIMm6LZGEu4mvMrfifTttbvkjZwDTsDFFzzD1BIa2r4JeD9TU7D50yyGOpVKAV9GQ5S6WuZIdwzcmTa4yDKmVygn09ANn15m0+/G0x+dYRUUlT0zsoql6yBL48bodXoNDefK5gUT4vdsghjh85z4fTXeSH3ObJ4sjZUipTIbnX3yBrz/6KG+cfgPTySQwVHBSpIxry38iI5Lwuo97qntIX9EQvlA/2F1fqad+pJ6p3iqQYYg9OI0zcRPIuNsdvVJDxjHSFQhTI79jOsF4t3SRVm1zG+WwtQqk74NXTxpme1GQYv1iRStMFCgUlUtsR5JR06JT3ySVyqCbFl/92l+yEtT5xQ9/At1U/kE3LYJtjnq7wzY1pZzebRxGBOHWCmg3G+SK4/y3//Zf+PxTv4nvBZhejuOZm3j40z/J3TMHKJUqKklr1BNFFIxrld3rI5I+EOhgqt+FBb7vdmHpbUo0+qE0dD0AmuUS3uZC0uYyvGua9pXX0NqVdbw1T5XRgginOAr5aby4a/1XF7AsE8syE/wXeojQQ6TbREYxRAJhCnzfp1N3FeMZete1hCjwSXXrvP/m3/9bPvunv8IjX/5VPv/5z6vCS6PF+soVFRlZOrald52zEn7iM7q3mqFj2w7tZoNTb6oy5uOPP5YIf3TnDA+P3wPAFz7/RZ7/wYtMzM729zdl05i5YhJ69moPgRclzOk7XmlvW/ddBrlt1cowQgYtZNACOiydv5B03WUndqKlChheRSNqhOimA1GENbpDkW2+cr61zUZCyG2rbkO3mI7WLVh0Gcrtq0AMaCpk2/55BwZYvbrGL/+9X+bpte+Tnxkgn8vyu2d+n/GvH+Czn/oMr55Y4PziEoV0mkxhkOF8DrO7YrZfrufTabUolTcoVUoJxPzG9/8S3wu49bZf4P/++C9gORat6ibP/+BFvvwXX+HD9ToH9u7h5ZOnrh8JORrUu5DcW4hmlMT/1y7NBsIc6hP8FrMaIls1tQqiS1urwC6S2TGL0So1uz1cAZqlMzlxNOH667VFojDETA0QhU0FQ1GAxEYQguEg9DbSVkzl9kJJKudgtW28bQpI6wLP8/nc5/4xAP/11/4rK0GdLz79O0CDLz79O/zcBz/BLcdvZ7NSY2lliVZ1k1Z1k0xhkHwm1xfpBG6Daku9wezOKUYndvHUd75JdfVpRnfO8K8/9FOcP3+elaDO3TMHuPuOOyk4Kf78r74Jt91ONpuj0aiTBorZAnI1DUg6NQ8ZyK26Qasb82+DoARqB038NZBBC2FmrrPkI7AC8E2k26RR3UxgaNfBQxhRqZUwl6nxcchPb7WAXC5f66h6eUCkMhJnvIirrW6VDOvKF9jOCNWNK/jlgGq5SqFYwHSy/P4f/C5Tk1N84XNfxLEtXM/n/bfcxcd/629SXbrC448/xt133kXgNti/DSqiwE+wHyAF6EODjHb/Vy6tcnlxgUe/9yReRePXPv73mJic5p/8ybO0fcH7bxmkVd3k4NGj/DTw8slTZLO5JDseHyrAqjIeUP1CW86Zvlhf+qiWRlQmbOHjX/WwU7l+CApayDBUVZegDWaazZVlhvccS7ZXadRAOALhiAR+ejtSWrVNVQd+Wx0zScBsu/ucLpbaJpahYv1GfRmv4YMHK0GdQjrNY49+g0q9zmf//j8k9FqcO3+eT/2L38N3fb78t34bK+3w6ssvAfDyyTM89Z1vcu78eTYrm6qgbVvoppVAUbO+yeXFBV589QTnF5dYXlmmVq/zf/z4P+Rjt91NqbyhoMoPeeP0G+zdfxDTyXDw6FFuO3aUsNPlhTpN0qOjTHuTeJd8ZCVGNsIt59t1wD0I0ooGpq1j2qrPVBTBGioTd+p9Tth3Wwir019vb5UVq9zd1WMIp1frjEjvm056e2obKvYnneprJ0+Er5vY6Vwf3vtekCigs65KjV47oHLxCtVxRXv/nV/45eQ558+fZ+GNV3j67DCf/dRn+MUjv8T83DkA7r7zLlaWFyhVSgm+jxSHSA9kCUKoteoJ7TAyNMJIcZhaq87PfPJj7D54hHYkKVVKbPo6wtL5zccWuOnwVSbGhllZUwlZLxLqhDFp4MD0bs6/ehZvI1Q+Luo2bG0TvsgafS3v0pe4Cy72gIPIreBVPEzDJgi9LeH7rnohwyH2BbSbiMwYGdoY0pZomQhhZBhkakvYG3UEXuJ8vXZHRUCGgalpBIaBNSwoHPVpnuySWOsuvu3hl7o+wRVIP6K8skq1XOXg0aPdzLQBTpb//P15stPHqFxU9MWPvf8D/Ie5c6wsL3DT4WMMDg1i2xae5+N6fh/85LJbTrnnjH3XxywUWV5ZZnJikmq52md9/+B3vsmf/bNfwnIsMnrE+OQ4jbk6tXqdbDbH+FCBIX0fV9tvKBnYqllAmP3CtwaMJEzFUgmau+YqP+GsEvgZZBwmu3RUBmgiTBsij0Z1E2cEmqGFrk9pjwBYQxrOkUOY7QJW6LNy7gyB2yQmJIp1iJWvMHUbw7HRhKB4V8DmhQ3sYYFmCIJqQBzGqsWvozoLpAuF7BA3H70ZTB3Lscnncjz7/At8740NhGVxrm5z3w1FLCeFm7WImorDKa2vEnodhGaRSjmk0ilMyyKW4IcRlfVlllfXuXDpAqXKBpaA4sgoO8en2DE+ztNnX+HUwhZ8upGGFi9wy76bqLRbBPU6mxslmh0XISCVyRJFLS5fWlC4bXSdry4ROghbU7ATg9AFQhfgAg4YwiRsBYg2SMMDLQAtQJixekCcVeihaUhpsXPnhGr0BaVZyyyQ3tiNTYwbQ6fd2QY9jb7Qs9MqM/XhdF/Nt1cs95vhloX4INoaM5MKfqrlKrM7p9io1fnNxxa2/A2wvLLMQ/c9wOjQKM1aiWrLU0ooVyiVK5hOJiHe2pGkVd1Mnjs5MUk+kyOVySQJmnudRA7gS09vAt/h/oO3ssL5btWsmvgCgLRm0HJ9VfUyo8THyUaI3whVsd53sSwHEKqKhoMz5lwTdnuNIPGXMjLQLEnQadIMrf4NGvZQ3LclVHE/ugpJtQZoIJ00Ph2Kt0VAmvULF8lP5ZIcIPmQyevooMdJtKEcf5avP/mdd85rMikGh/axExLaut3q4HluAl/5TI60LjCdbCL0Hn2xPUv+5gsbXRDvv/7jH3wHPlbl4OEjVN0OS8tLCTFXzBYoZDM0mh3VEbc9YbMcPnrTh5k5sJ/5uXN8+8knaGkN0HVcv9eLpG+9ZQR4NsIcToQvIwvfD/C8MrZd3GpLMex7+naZi22qlG2BVfARqQbZ/S0iI2D9wkUGhrJbrSLdLgVLOph1A9MzkH5EWpqMT47TrqguiZW1ja5g+q+zq1f6LWebBaczKWqtOqXyBsWR8e7vqr0jDqOE0OspQjctOq1WP63g+yw+/23mH/8LSvPzfO7zf8CX/vC/UHBSjA8VqNWVLyg3qt3agCImt4eeH73pwxy//Th+o83U5BS3H78FWYmgESM8oR7fjrssqRK+lRrpei36ghnaKq/Selbb1wIebKpkq5ftGg5+1SJut2guxnTWXVKjW60jkRvjlX28pRBvzcOtuslSlFq6j8P/8z/9E15/6rvXKKCnFNu2rqEuVCDhc+oHz6vGp+ompZVFbNtJOKJryK9WnU1fTwT/5jd+lwFZ5a6DQ9x9ZIRDswW+8tfP8S9/+w9ZrfQ7673DOlqvXTDQiTfh0PgtHL/9OCdeOsHvf/lL/I8/+2/Kt9oWcXMLPaQtsbMmws9AnMVvuZhiq44iDAMilZC9454ysd14dB26kZA94GDv0dEdE8uyFHVbj/CWA7wrPr/00z/P7IH9/Id/93+xslJDoKFltnj4r//FV/jDP/4TUqkMb/5ldx/W8fciLItNX+f0mTc4fOgmPM9Pop/tSuixqNV2Oyk1Xn/XvMX3Xn2Bxee/TWN9Bdwyhw7v5cD0bvJdKnpmchcHpnfz3KlzfOOZV7jn2F6KWUUajk/uJWO/SZsAIrXx+313v4fV5VWef+ZJ9szMULlyiVKlikilkY1O0uMmunUN6aews6P4fg3fbWE5GcKe9QNxp359BXjbm+VEGmj0FRu8sgc+tF3VwiGMDPGSR8bJ87Gf+kkOzt4IwOf+yb+AOISMon+ffuIx/uAP/oiHPvRejh44xNLyEnMLlzn72JeYmD1CdvoYv/aH3+E7v3VTn/ATd+K2qLpbvqBaruJ5bpeacNAMnSCGfG6AV0+8xH/47b+gceU0mYxgz+G9jAwVKDf6LT2fy3HP0f3MLVymmC2Qz+UoN6rkczkK2QztjgftDnsOzmBl0zz/+LeZmdnF+ORunr9ySb2GIaiLLet30mbidIM4RhhZhSTdRWKKgAA1rmYM0KS/jXDqcepd7chtBJz0U4h6Af/qIN5FHW9ZQxgZTC0ibsbkDcHK+fN87nP/mNXlVR58371EYUjeEMyvr/FnX/9LfupTn+Th975PFSUmp7jj8BHuv3kP62+d5soLf8XCG6/wH//Hl66x6HJplWq7zeryalIVa1dKlMobLCws4HkuodfC1OD0mTf4G//0C6ycehanmGLPjNpUMTe/TqlSpdzY+qnV1fe84/ARZg7shy4nlM3mGNq1p5tAqQStvb6erA6AkQH7uhQ2NvhhIYFvGYZdQwYj3ppb0WMXDFw9qexcd5d8ZKie+N7rRyr0TVZE0+3O9YHHvv8Mf/GVr3L4tlt44OZjPNH9EEO5HJ/+2E9QnBhndXk16Uqo1esUswXuuXU3z528yMr5Ml/4/EUAfubBh2k3GyoMXVmkVKqwtLyUON/59TUmKiXOnn6dgnOK2+5/gDeefYF/+4V/z+LLr5KaHGffxATlqo+oL7Np2Gy24cLKCoPpYYoFq0/g21eFlU1zYHo3Z06fJOPkyedynDz9Sp9csqNjW2SoqSNtmTQzAJj6QHcFbKFHqMm+or0MQwzaMSLS0GsSui+gpXJodgpT0/A6Aeg6AvADRVMTZ0FrIMOWCjWJqYWS1eWL3HvXUcYnd7NaqTI5NphUxApOirmLl7acZL3O3MJlylW1/Iq5LJvtDVZLPo/8+m9w/uGXuO3YUapuh4KT4uWTpyg3qpRWFjELRcorqzz73LMAfOfxx3j55CkefeYEV9fmSU2Oo7suZ96aYyKlqJHju8Z4+N4HAXji1Ouq3SWS3J3dalfJZpXweys0k1HtKrV6nVdOL9BuVjm2d43Zm+/e1md65fpbnAwd/Bgj6hDqKdAjZLCpZLe9OVe6knhbZdvelj8LQ1c9QLK9xf93lYHW7z5kp50s0anJqSS27tVhV9wOVjaN32gzv3yFufn1JOIwc0WCepkTVxS37q52+L0/+CMeveEw9xzdTz6X49FnTnBgZpRSqQKlCtlsjke/813uOHyEUqXKk489QyqVYSJjU3NdPrx/hLHD9/LM449y/mqFh+99kM/8yt/nxAvP8sSp1ynXGygRDjI+Od73XSr1OlY2nThbABG3EULw6rllsqMXGZ/cq2AslJDvOd8IHAlrbWKtjpXK4fsKcjTHQ3ZChNFAGFl0w0AYRtcJy7dFPteoM73NH3SUMqTKoGVLoukarbZPNdS5IZdjfHKcU3NnqIWSPTMzqiOipKDjxNy5RPi/8vH3cc+DasPd1Ree5Gf/7e9w6PAx7jh8hLfefI1nXzvNV+bfIlPIkDcExex+5tfXGOrCxB2Hj/DoMyeoLSsCT7NhpVbj6OQo/8s//zdsVhtUr7yZwMWXvvjb/PmT3+dKKBmenEkgp1cnTg+N0K6UqHR9w8hQgcoV9RiRSpOmjUjlqYY649e0dnQzZlcgRiKC0gbCkxixINQlXqet4GggDS0drVvgN3rw3nO8P3T3oH6tzxBC7R+oXLlE9u73JE6vV2sdGRohGCkzAqwur1JcuJxAwcjUNPtnp3FuPM57bj7M+OTupE6byeSolzZpVUL2zYyRz+X4sfd/gJHiEOcXl3j2uWepV5Zoe5JMIYPstMlkcqxrw/zz3/iXXZhIMT65gydOvc7i9BDjNz1M3kpx+fIrDG4uJg1jE7OzTE5M8sbpN2B9LQlVS5Uq2WwuWQ0zM7tgm09saQ2Es72roktRFCL8almVEWKwCj5+1UJ4ReS2yXnvOFtChiFY5tsccoCMRF8HmPQjZKz6QyuVGo1GnQPOHu45up9vP7mEmSsyMTYMHKCQsdl98AiPPf8s0egRmgMpvvCdUwRnnsNcHmDZ1TjxwvO41TWieohuOezcMcRmS1Jqetz/0Pu45fjtAIxO7OLs6de5eb+i0Bvra5QMoSChC4VX941x6btzUNpkz/EHGQMq6MjNq1w9dYGf/eWPMjIyRKlUYeX8eYJqmUKxmPiElKExMtTfY9eLggCCelntqs+pSHJ7wR4BVkFFRb1uOmEUSaVTdNodsgMmaUtua8xqBn3tfD3vbWqaakH3ujG0kYEoQjotRHfvkzBUN0WrFSSh3fvuu5fzrz1PMVtA0x32z86yvnKFVnWTDz/8Ab786A8YOv4gQ/ku7qbX8TckbrkDVgpjxOCmvfuUJRoRZq7I7LYKmW1bTEzs4tjhW+mEMW/xGrM3K1x+4cxZnp8fYVLfilQqTWW1jYVXWLlwgfuPjfHxj34cy7HY3c20A7dFaWWRoVyOpfX1pH1xaXmJMyde49DxmxP/ls/leO5UdG2v6LbijYcLbR3hZzDNQSw7j2Y6WFaYDB80tu/es0IfDCOZSOh3N+FtzwcIW8jQRRtzAE/xH92SJgJWly8C95IeGiEamiCfy2FbOlHgYzpZMgXJ3/mFX+ZPn3yThTdeITuxk2Imm0w5zGQErZbL+NhBCkbEDTfeTHFCIa5aSfRRG+nRUdLAMeNWjNQA79t7Lw+/932ceOkE337pZdqbV0EfYHX5K+r184NM7NvH53/jn3L40E193NP6yhUuL64kxFzPmFaXL+IYggPTu1laXkoSus3LZ7sjs7ZKl7IVsa0HDRHaYBYQWk5NgeyFsV0ZG1ocEwNBu6SG2oXhNaMgha4UI8NQNWJlm1gjJn6zW7RAqo46U2d+/gpVt0O668RShpb0+4zvGIOriqf57N9+mP/zX/8ptVKZuXIJoiamYeO2JIcOH+PA9G6O336cg4ePsHL+vKK9U9cWvXtdbkO5HMHGOumhEd5351387M/8PL+6ssTXvvk1vvlWE5HZ2rX5mfsHrxG+6/lUW16fE+4J+tjhW5OV9oPTr3PH4SP84PTrtP1Ibcj2pSrYWN0V0La3UERTmfDb+4V6Mt4a1lGrqsmE26YPbll+1OsygmwT5wYTbEF8QW51CyARaZ2VuM7q8ioFJ5XsUuk1W3meUsI4Y9ywT8HJH39vrQsNJ6mVyvzcj9/H/Q+9j907JxgpDtGOZF9Ly1Ye0Uyil6QxeHg0yZCnJqbYPzvLP/8nv857vv8Un/vzrRaU999y1zWKDL0WpUqJqtvBb7QT6y9mC0zt20fBSVFaWmD3g/dxav4Kp199FS2lI4MYWludEnbaxPd7mzWyW+H7dnrNMLDtIm1fdGdFCE11uHW1ZlPE1DR8OkkmLONN7IkYsUe9k19W8KTlHUh5xIRoaYeo1GJpeYmirfHM44/y4I99SvV4blNC7/q5D36Cb77we2z6OrnZ2/ns3x7kZx58OPn/Rq2e1HwDt8VL3/8uV194sv/bDM8k4WNPGaVKiZHiMJ7nYtsOD933AJ8rV/nXj55HWBbjozuu6S/aqNWplqt91t/jh3qvOzI1TdXt8Pwf/3E/QniqNmybijXuUTcQdqNGS3VLdCEoP5glk9Zp+90VIHQNEUU0VhZxZse63WJ5/PVKd7KRDmFWvdGlqgqnRjTsdIQfthAY3U6BEBnC3MJlfvwnPsHxjSpLy0uKm89krimNOLbFR+8a5ktPbzJoRfzkvQ/39fwknQSVZa6+8CTpP/oz/AMqCinMKcrCP7AX/a7bYHhmayWUq6ykF5iYVBHSZqXGJz7+E6wEX+KPv7eG06W8e9BTL6+yvLKc1Cx6SWT+Ok285+fOsRxsIiZArmyjoVvg4iJCLSk/SrcJhoGwfHrOIug00Ua2Wn/0lCYeMaTEEGA7FgO7DkEcE/t16levIHpVDuEQBTFRJw3SBt0k0hVGWjkTI6Uj0hq6oVPZ2OD4Dcf46Ec+wtzcHMXxUcaHxwiCkEhKDEM5ZRlH5Mw0X39+jk/dP8rRvftoNxs0PY9WxycKIxbPvcH6F79A9rFnaP+tT/PB3/wi+z/xad4KNjFPnsHZULdhZYV0Mc1ypU5tbYWVzU0wdHRDx9DUIJLDu/ejiSVu3LkXTdNotzq4nQ5Nz+PZb3yNS1cWGTJ1zl5ZoJgt4Ng2tXqdmWklsKrb4ctf+w6NzjpOxiEk7IaXQtWPPYGwUghjAFO3iI02MtBBy6DretJHOja9h1RuEFN/Wx4g6ssJ7mcLg91OOKOvNrCViG1tZgYJtlCdEXi4Kx1OvHSCg4ePkDI0Vs6f5+DsjQRug4H8CO2w09fJPDSgc//BWxPyrbe96NSTj3Hov/9JEh7vuOvBxKG//SrMXaQKHJq7yOl6k/N3HCLYWKd65Di7d04knXUfu+1ullaWsBwrKfQEbouDN9/MW//u1+CWjyY17F4E9PLJHLV6nedOnWOlfAaRUTNMRQZkbQuG0FPK+u0sQdhIZCl0nyA2MEO1o4j0AG1fkLYk+khKPFIPwBDgScnAzEFMJ0do5qgvXSYOm2iWjtBBhrpKxLQYka9iGTqBHaIbGnbWUsOQ0GBTMD+3yMHZfaTikEtXFtm1e5p2p0Or46LFHtV2i2qtQeC2OL5vmEwqQ6NRJ2xXWS83eOsHz3Lov/9Jn5DXzr/JpeVzzL/8DP4LL+NsbPZDWvfvMdvCm19CHD9ObW2FMwsLiFjQ6DSJw5C1K/Msr25QWi9RqVRYuTyPfuUNFstNWvUKN952N5WNMilD4/kXf8Arb85x4fIlyu0raINAS0fYEjvlELUiiISqx8gQYQKhREYVhGEg9BCTDLGmZqzaA3lGpm+COCYIJEbK1qATg2XQabqJH3Asg+KOYa7OV5CRpXbCW1I1FnWpiCDWMT3Vnud7ASnHTiaaNKtVvvD7f8onH7yd1UqVs6dOkd2YVxHP8Exfh3IhnVYFl3abarnNmbkz3Pjai9ffQPHCy30+4HQ3GgI4nNuKkuY7Ph+9+WZ2HzzCy08/xZm5M2R9F3N4lIKToup2CDYUXbJWrdO5fBqvchn7yEeuec+WW4OshjC7tRMnUuMQLDXYSS5vqx17DdDDa2hoU9OQIiA/shVlepsLGIWUxULVxQ3VTKdo/SLMHldOaMc0K/MLaIaBDLv5AEBOKSCuuQR5B7PLbURuDJ5U8xUcwcr8Gb5aX2ZmZhdnzhRo/tc/ZiZlMfqvPt+/ga4LOSvnzzO/vsaPvf8DnB0dg7nPXwMz26/twt/+93zHp3XrDBMzB9i9c5rRj3+KpZUlnn76cZYuXOBEtzAzKTp4tQ02yxtEQcDw+A6Gs7kfiRPDjPCakRplUAhUZ4vl9Am+f6+BYjuzEzu3QumrCxiDaYuC2aESxDgCqleXKLTWEJkdiJFZMoNnaNd7ZUkDzQYraiMLIRQM/I0WgWdgDWhqLk+zmztEakTX4soGlUqNh+99kPLOPPOLNUa7kcr2a2XlCgUnxd/69KfZuWcf09PTPPHNP2fxpVPXWPf1hD/fnVt9JWsw8dDtvPfDn2KkOJz0lU5NTPGTn/hpHnv0G3S+9adUXnmdZ7qNuHtzDtONkNY4fdR0J1R1DiLV4Sfevkko0PE2AzXMAx0iD4kHno3TVaTXaWOImEA6DBRHsO2i2vYblNlYnsdI2Qb5jE55MwIhkI0KjZVFRrrh6ODEJJ32BVLpVLeKE+EHKeT5NmIkwrIEASGyGeNveH29kwAZx6TlBpS9mIOf/AxP/uF/wvvCvyK9dy+eZuAO7GB8qMDt9z3E3XfexeDQILV6k+LIGA/9/p9w8c1TfPVr3+Lr3dVzODfQZ+m960rWQCum2fOejzF7YH8CcalMhjiMWK+s8/LTT2F/88+Jnn6VizKkHsfcXEjzQKix8MAtyNzOBJ6ue23jeRT1ECn+xyTZwyzCNE42hx8WsSwTO7VK3EWP3O4t+KnXFvHWFjA6XkghZaFX3d6WqD4Yyk4fw7qy0L9BQ6QRZhq5VsXXGoCFD4gRA9lQS02mY6htTes6NXeGz/7Cz3P51iO0L17k0iuvs6sRUskaiP272P2zf1NRFV2izfN8BnKD3H7fBzh6xwN8sZDjyT/8T8yvVfB25rEXa4ngK4ZkYOZAwhtNTOxicmKSwG1w5fwpzp1fwP7mn7P+0imeMmKe9wJaMcw4GrsaITvvv4313QeT7p1eMpYUmnRFtUiipE80YT8zXcV0qXqBQRzaicHGod01hCIjo8eS0fnlNxfUUPOZIeeRlKlTbbq04+7BCl6Ngd0HMKwBDF2DqE2rXMGwLOIw2hpRoMcQGirWjUzwIrUCRKA+VEcSRSDjmILwuP+h97NU7ZCeOcBAWiAvX+Vm3aB1ZYMXn/oGsr5O28lhmQZWdzd+q91ByIg77n+IyTvu5vT6PG9UGqzpHqspjXZuiKGDtzI7c4BavY4dR+zy1tl48zUW/uD3OPOFL9J68nFOXljkq4HHqXqAh2DcknxAM5lJWYz85Ec5X/XIj48xmBlgs9VidXkFz/M49dZZMFMgw26vaF85oLsyNLU1VdMQ0kLqI5imiaZpxEGbIJSM7tlPZmQKXcZE1QVWX3scGcdbeUA+o1OtxtgCOk2X2sU3GDquBpQO7znG5soyURgiDL1vE0L/pkmBpUUERgbZLd3HcYzQNN66sk6pVOHQocOcOXOa237sb/B4o8r8K/PMpCzmF2t87ze/yMf+6M8oA9VuxmvddRv+Cy9j3XUbAB+6/Th2HLJw2VOOMxtil0/TvnCSIxudPl9xcRtUPSlD1nxJJAQZJB/RVR6w/tM/w+jwDLWzzzDb7YzwG+2EjpBuTEYLaW8bq5T0irb0LejRdfBs0LLJfjrNdAilhmUNbG3KAKrnTqhRmElJEnX+y2pNwZAtYPPca4wevC/ZYj84McnKhQtYlkkQx6pOfL3LA9OO8NoxMpRqWpTl0HJdXj55ip/9qR+ntKQmHn76H/w6X/n1fwQbCnOflCGsVZhJWdB1vtfcAtNA1MP/ZfXc/Snrmkgo8Q27c9ykSerny7R9yd2jaWZCjTeHU9x56DClpQXGhwoJ/ve6Nubm17cmCEf9cz/VKMutKiGeDXEWKzP0tiJWxMjsTML9eF6Zq/NvdXcvxf0jy/Ld0pqr6bQam2xcOql6cLqrwLLMpEaASKs+F13fCr2sAK8RJJNMevhPrPzHiaf/GoCDN9+smMWDR7j/H/4zVXRJWezNOfxV5POUEXNudoD5jv+OP9udb0/gTxkxTxkxbw6nuP/+29AfuIU9tx5hevc+lgOHsg97HI0HQo35js/BT36G9NAIlzeqyeyiyrYe0c3LZ9FS1z/XRbZU7yeejYgyqs8zM3zNmALLyrN79mCS+dYuvkHku2rCjIyVDwBwg4isY1BthYRCI44jWs0WY/uOITSNjCMI/Da1q8sIwwTZJhZ0T0uTCKMFcYwUPlSksn4ZqxPtAD1tsLpWZ3xmhpuP3UK744Jlcsed7+GMiOCVV9gdC86EIZteyC/eeIT9P/MTnKtfZNEAc2eWs2GAb+p4UxnKYcyljKCjwfD+QTYyBvs/9NP8+EN3sdRuc+//9jlGCLm0tES9UeWJ04uMGjEf0EwGTZ36e45y9AOfYGXlCpfmL7F3Zg9uGLJ0aQHP8zj50gtsbDYZcGzacYgMYoQQiLyCHuF1aQdTeVXTHCSWIXp3epamaXiux/jeveR37CKIBI36Opee+w4y6KjXEqJfAYqJDGl0x9FHrU0MS2dgbA++F5EeHKdRWiL0txXwk/O/2hB11HjHsLeJT60CPatj77DxKz4N1+UjH/gAZpdpHCmOsOvAjTx29gcUltcphJIf+BE1o83Nh44wO3sIb2w/n/nsr7Jx6Tyf/MTH+JV/90ecL1dpr17kV//NF7n7w59E2oMcKRjsuOtBGq5k155pmkuXOfXmGZ6b3yBotPiEaTGTsnhzOMXdn/ksZirD+bm3SJsauyYmubywRGmjxPnXnuety2tqiCsSyzAwpCTUUbMwGzGEadAMhEiBtNWpfoBhppJtvc5AngPHjtPylAGf/8FzdFbmVBEnjtFNe0sBKVNPVkGtFREgEAia1U0G9+zFMNRAikzGpHy1pLYNijSmFhDLmrJ+K0gUoOkWmm4gdIkzqawiNgVr8yuMTuzgyIEDNEqr6E6ayYkpUoNFSt/6FoOmTjRg8NxiHRlUObB3HzsHLPbf/V4KE9OMzN7A7MGj5NI6mjPIhz7xUwyNjBOEAeHGCtmdezBX53n9wiKvnXgBz3e5fGmRWwspbtYN5js+N/zi32H33hlq5TKXrlwhPz7GZqvFwqVLzC1c5vQbF7oFFUmEwDR1hK6pAdwu6pxEbKUA00R2GhD6WOkURnd2qoxjpo/fjrQGEZpGY3We5Ze/DV1U0CwbUkPos2PZR3qthT0lGHpMpaPCqthr02qGDO8+gBfGOLlhdFwalTUM4XUjHRfMDqLXsxiCMLOgm4iUjpHubuT2Y0QomF/c5IHjhxQvtLlBcWQHe/bfyMnATaDoZOhzeqGMDKqslDYoTChK2HV99t1wkDiWuG+9wvDsTZiWzanXTmK3N2kuXeaJF1+kurpIavdhlt58lZGIBPf1B27h7g99jFak89bCJTqNJlOTE5QXF7lw4Q3Onj7LyFCORqNDLGM0TUNHInQNU2gEvoBYU9/NchT82im0VAbDLmDYaULfpXjjNDt2zOJ7So5vff+r+NUSmqYhNA1raJooDNTUxJ4CelDkmDr1QOAHEZrQCOqrmLkC+VG1iS+dH2Vz6TJ+u0mMgNhEKKSHMELEBthZ5XzTHSI/JvJjFa45Gs3KOtlUnoO3HmdtcRmXmPHhMYZ3TvPXL36FYsVnJIJXwpgdGfjEBz/Md7/1VXY6GueW1tC1kMUrV/jut76KUytx5bUXee6Jb7NqDLJzwOLS0hIP3Xkn58+8Svbk5cTyvZ157v7MZ8lkUgRSY+nSZbLDg3Q8j8XFZZ555SSFlMXIgM16paFOwRCCSBiYhuhOZREEyZ4HJUxhmiDS6LpOHPoMjQwytu8egkiQcQQrc6+wceb5ZKq6lh3HzA4Tuk30g2OpR6SmJw22PV9gENLwJLJ7tmtYXWdgei+RlcPQBNmxIuXlVUwtQOoGhIZKxmJdCb/XvhhHYEdJ7iBMDWzBubOXODi7j6HRCeYvnmOoOMzUxBSePUTryce5r5hn3YopBz73HD/Onqkpdtz1IObqPM2ly4zM3sBIlwR0bjxOgMmRgoFz43HGXnuF755+BvGDeT42NsS657MZRhQ+8WmO3fMeYrdDrVxmY7OKbpuUV1Z54qXTuJVVbhm1yGgR85u+OrlVqjCzpwAAQ7ew6BC4HTB9ZNsHvUbYcolkwNSt92JYA6QtSWVznfmnvoGIfYQQaIaFMzrTLbE30W8YTT+iCwijLRhKmb0EI6Tux2i6jtdp0ax6jO/ej68ZDA2kyWTTrF1axBSCWChrEYalrKJ3KK/wVdte11rQVOG6E3RYXalw8/59rFQqGJpBJpdhdu8enmq1ab36Kh8dyFLbaPP9pbfI77uZXXumye7cQ3bnHvbeeJTASSXKWLy8wKAhCTdW+Pb3n+LAUpv7inlO15sJO3rne38MRyeBn8gPiPyAuUvnuXjmNWZ3DJHRlKGs1D2CSKrRZNqWAqSWRsRtpJYmDAO1GU131ZDudpWJG26hsPOwisqjDmce/3/wKytopo0IA6zhPVi5InHoE4WuUoAfi8Qzb4eirGMoKArV6F2/uoJh6ThjM7iRxtBgAUlEdW1RHZ7VS1p0XWGjaUKoYAk7UkGRBlEQYw+YXL28RMvzOXzjjSwsL7JnchJhO8xMjfKdp77NhZUqHxsbIlVp89U3XqIlHd6cO8ebc+cYH85z9YUneeLFFxkh5LUTLzD3+rNoj77IQ4bDmG0lSdmgqSMe+gi7DxwikBrtSom11a3679PPP08hZZGxDKYGIGVqnCt1CGOJ1o3Xzd6WJWEiZADCxNJDgiAEaRB3XNJTNzN928PQzf7fePpRWgtnVEErlggp0TNDGKksghjfDZQCIikSz51sPe2uhAFDUmqGxN3YtnH1Mk4mS664g2akM75jnM1SBa+6riwckNJSoxvpxs56iIgsMINte79ihBjg0oVzuNUSaSdLoThCIV8gMzhMNYRTb7zKaqXFfcU8D+gOrVdfJfPGGdZOvMorZx/nrZdOob1+GV45RWF5nQdCi7Fuwf3raxU2w4j7inmezurc/uM/hZnKsLJyhcsLS8m21O9+99u4rTY7i1lGdI9UroiNx6Wrddxo6yDp7Qro8dId1wcZqxE8O/Ywc8/7ibQ0pmmw9voTlM48o6blStDimEgIzMJOdNtBxiGB2/nhRxkOpi2mCz4XNyNVmJGSpRcfVTXjkVnavuDIAx/g5PdcWlfPI5wBeifKmsIAw1Bz3bQGws8g9Vayg1AS4kTw9LOvMj9/hWw2x+6d6lDO+z/y41w++RzRU6/y9S490eN5DueANZTTHxu6pk7wlBGzC/jY2BCn603SdxxKWld6G0Sy2RxPvXaSSqXGDbtUFmx1N1B4ZoGOVgYt7mvD7204FHG7b6NFamKGvd0DjGwNSudPsHjiicQgtbh/olh2wKQ7vhR9z3DmkeQN4vgdleC6PnVP+YMo8CkvLTC8Z4bIyiEjGJraR2OzjF9dRbf6z5zVNYM40pGdQHETfqBgyZUEfojQNWr1Fl55kYO33EWxWEQ3LMZ3z7Bjc4VjrsuL1SZvtTq81eoQxBHrns+65yf3f08LeCnwuKxJHgg17uuOS1v3fPb/3f8VM5WhtFlmbm6OwUyK0xfPcebECfZ3D5kY0T1yQ93pop1NzpU6ak620HC0CKFrCn66+I8w8dpN0lPH2HvvB7DtIpGEzdJJlp/+BlJKtO5RhoLuEe0yxsyNk86m8f1YnSO2fXj3OylAeX5BPRB4fqgyPa9FeXGR4eldSWQ0NLWPVrOF29jAsPMI3ULoFsQBcRypsM2MleW6Ehn43eNS1OkcK6Ua9U6d++66izgMGN25m83GOubJMxwYSHFgIMVbrQ6nUoLHmx1eCwLOxiHLQrLphRzz4TODhQSGAM78xCc5ds97cDsu5+feot6o0+y4PPnk8wwOKNwHmBpA0c7ARrnK0kaHUCj8t2wTqaWRXp22F2JaKrF0dh7mhvs/hmEog4uqC8w/9ddEfqd7em1M2jYwDA2/2+i7XQGB6/aTcbppvisUHRgyyGiCKFQ9kVFthbnvfQ3Zuprsrtx398NM3nS8224it42UtFWbi58iFXe7x2Sc8IuOIcg4Jk985wm+9b3vJi0jt3zqlxJqmi6s7Nq2rzmT0REpwd6co1jU7bXmA3v5wMc/kfzdaCiS7flnnmQwIxgZUMWSSdOF1GBi/ZfKCh/Etn0QIm7jxuoUkU6nxeD+m9l110fwYtVN6G0uqFOUWhVl+UDGNhlPxe8K8df1Adc7pjZRwjicuuoSRoovCstXmPve1zjw/o/jd0/WGJk9TrYwSPXciaQY/fbL0SJ6SKoJjbwW0tAdNM/ly7//nzl04BA3HVYNtHf+1u/y4j/6u0lR/v77b2PvzXde0+GwVq1TvXRWRTc338nRB9/XV3Ou1eu8dfK1ZJdjD3oyg1tHX222IzpeTN6BNV9Hdv1CHITEfoCWGWLq1gfUANZAjRtwSxd58/GvEXeq6JaDjALSlv424W8Zo5bKQbN8fQX0VsG7KeHojp4SwkQJl7/9ZXZ/6G/iZMbU+e/5aQrHBhAX32Dz3GtoNph6wkzjxjqyO4YqZeuKvwBSAw5Xr5b5xl9+NVFArjjOnb/1u5w9fYqJmQPcMjaMpjv9W2sjlyCEUnmDwG1xpDCI7/qq4bZcZXV5lbmFy31Od9J0+4Sv+lFb3c+k4cSCTqz20HW8iNTUMWZuuVVNFeueb79x6SRLLz6qjmdPm+CFpEztOpb/DueIvf0Ah/7ZnPp1/ULK1Mk7glIzIuoe7ep1WpTPncJIZ8iPThHpBo6VYWxsDN/M0Fl8k7jTQdMiOq5P7LvJMU+WoTPoQCtWoZ5pGZRWl5ndNc3uPXswrRSF4jA33HSYsdFRgghkLPE8lyhSM5jjWA0Bz2VzDA4OI/02bhDR7rSZv3iOqysrPPviCwxmHHanIjJaRG5oBDuoEnWV2dossbjZSpKuyA9p+ZLYLrDzzg8yfuxBcApK+MDSay+w9up3EXGEMDWkH19X+M1QEHR9gDU0STpfUId5dtrvHoZamgT7+g9Jde+fW3VphWolyMBn4ZmvJqfMAbRIM33TreyYmmDp1WdYnjul8jFdR8bK+ea1ENAYNXzWu2NcKpUaj33/GQ4ePYrpZElnUnien7QlxpHbN8Bve6tj7+/AbSUdz2+9+Rqy02ZkxxDgMVgcJpctAAW87j6A5aB/VeUzOs7MIQrHugcXta4mZ2Ve/P431UnbmkYsQYSStKUn3+VH2m9nGIoLiqTA0iS9hMzSJPq7nPyTsiRhJBjNGwxnLOpNj1YQoxk6QkKjdBnRLGEUR8gNZGj7AiczwOCemyBdQHbWcZstQH3ozOAgkZlCD10yWkQr1snh47er7N69j507J8hk891ILSKWEHeHx26fHR3H6qc3TbFSrzF/8RzlxUWef/EHOLbF7lTEYFonN7Rj23YnNf+nsraKG0YUUhb24AjarT9Jft9d6vCKKFLH89YWuPzY/6C9oYZvK75IRTtK+PTxRm9fAanhXaSyObx2h8Bzt7ig3mE+libfVfC2aSKEjmVoCKHjWJLxQpoo9Cm3I9AEaUPHb21SX3oTT1pkihMEkaAZ6eSKOxjaeztWfhA/8NDDNrm4hR66+CmlCLPTQC8UafsRARo79+5leHAY0zLxw4g4jBCawfLqKqdeP4WTSpFJb+UeTc/DbdZ59dVXWF1e5fTFc5RXVxkZsMlokcp27X5rr6wtctG1yO89SDD7Pgo33kvHLCaHmRKUqZ0/waXn/gqv3VDCj2OEJkgLyHcrYyn7WutvtqPkONveOWJ9CgA1hf3drD7jGIju9khLB12je3CxUsaOvKm2+bgQxBLLMsh6DWprlymtnCGbK+JkBvHQiDQduzjJ4MQEhakbcFIazbaL1dlED11MQxCZKUYGbN66cIEoiMmPDJFND2BaFjKWrFfWmXtzjoXXT9BoNHDSDm4QUtsssTJ/nlNn32R1eZWl5SVOvvQCIwM2I7p3jfUDeJpBJb+LcOoOrKnbMVIFGuFWbbexcJL5Z79Ldf4UAqngM4owhGDIlGQM6B0W9nbrVwYhEwWkxvYlBzoHnov46E1F+W5Cv8Yv6Ft7g1UsL5NTVzXN5PzVOnOVkJYXkbF1NFM1/UZCMLn/MIX9xxEjs8lw2N6UxkxniZXNFeJLFxH1ZazOJvvGBylFNqWmx933Psjx248nu1Xm19dor68ns37Gh9SGPb/RJuyoAxrml6/w1snX+kLO8ZyBPbQ76cpb0McIUxPJpJjeeQlerAS/fuEknauXETJOqBhiSUpIUobE2ibw61k/wGpHo+WGCCT5G+8nP1Ik7tRZXV5/ZwVcT/jblSC2HQ/nhf0vsdmOuLC6yUI1Jta05JDoOFKHge7YdxOF/cf7hsQKy2LQ6p7EVLvKQPWtZC/u/PwVqo0WszuG+oZkvNNVDXUqVy5RCyV5Yyvhyo6OMT65lwV9DDtVoEW6bzyPTYwMQzYuKcG7q5eRcdxlM4Wak20Khoh+JMEnCqjFtGKVCxS6CqiVyjTLJf5fHyTtiulK1EoAAAAASUVORK5CYII=]]

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
    -- ROSTO DO PALHAÇO / CORINGA
    --
    -- Tenta usar a imagem aprovada embutida no próprio
    -- arquivo. Se o executor não oferecer custom assets,
    -- usa o emoji de rosto como fallback visual.
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
                0.92,
                0.92
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
            Enum.ScaleType.Fit


        JokerImage.Parent =
            MinimizedButton


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
                0.78,
                0.78
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
            MinimizedButton
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
-- RESET
--========================================================

local function ResetScript()

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
    -- Botão visual nesta versão de teste.
    -- A função será integrada posteriormente.
    --====================================================

    local AutoCollectPurchaseButton =
        CreateButton(
            ContentScroll,
            "🛒  Auto-Colect & Purchase",
            UDim2.fromOffset(
                10,
                147
            )
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
