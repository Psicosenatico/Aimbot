-- ============================================================
-- PSICOSENATICO • ESP RESEARCH V1.1
-- ESP EXPERIMENTAL + DIAGNÓSTICO COMPACTO
-- REVISÃO VISUAL: ALIADO VERDE / INIMIGO VERMELHO
--
-- Objetivo:
-- • Testar classificação Army/Rebels em Workspace.Soldiers
-- • Aplicar Highlight próprio: aliado sempre verde / inimigo sempre vermelho
-- • Neutralizar visualmente Highlights nativos enquanto o ESP estiver ativo
--   e restaurá-los ao desligar/fechar, evitando conflito de cores
-- • Registrar decisões/erros do ESP por evento (sem snapshots pesados)
-- • Exportar JSON compacto para análise posterior
-- • Enviar diagnóstico remoto em lotes para Psicov1.lua via endpoint
-- • Interface responsiva baseada no BOT RESEARCH V4
-- ============================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()


-- ============================================================
-- DIAGNOSTIC REPORTER REMOTO
-- Destino lógico do backend: Psicov1.lua
-- Envio em lotes para não sobrecarregar o ESP/diagnóstico local.
-- Falhas de rede nunca interrompem o script principal.
-- ============================================================

local RemoteDiagnostic = {}

RemoteDiagnostic.SCRIPT_NAME = "Psicov1.lua"
RemoteDiagnostic.VERSION = "1.1"
RemoteDiagnostic.ENDPOINT = "https://cafe-na-ia.onrender.com/api/runtime-diagnostics"
RemoteDiagnostic.FLUSH_INTERVAL = 5
RemoteDiagnostic.HEARTBEAT_INTERVAL = 20
RemoteDiagnostic.MAX_PENDING = 25

RemoteDiagnostic.RUN_ID = nil
RemoteDiagnostic.Pending = 0
RemoteDiagnostic.Sending = false
RemoteDiagnostic.HeartbeatRunning = false
RemoteDiagnostic.LastHTTPStatus = nil
RemoteDiagnostic.LastSendOK = nil
RemoteDiagnostic.SendCount = 0
RemoteDiagnostic.FailureCount = 0

local function getRequestFunction()
    if typeof(request) == "function" then
        return request
    end

    if typeof(http_request) == "function" then
        return http_request
    end

    if syn and typeof(syn.request) == "function" then
        return syn.request
    end

    if http and typeof(http.request) == "function" then
        return http.request
    end

    return nil
end

local RemoteRequest = getRequestFunction()

local function remoteNow()
    return os.time()
end

local function remoteCopyTable(original)
    local copy = {}

    for key, value in pairs(original or {}) do
        if type(value) == "table" then
            copy[key] = remoteCopyTable(value)
        else
            copy[key] = value
        end
    end

    return copy
end

local function remoteGenerateRunId()
    local ok, result = pcall(function()
        return HttpService:GenerateGUID(false)
    end)

    if ok and result then
        return result
    end

    return "run_"
        .. tostring(remoteNow())
        .. "_"
        .. tostring(math.random(100000, 999999))
end

local function remoteGetExecutorName()
    local env = _G

    if typeof(getgenv) == "function" then
        local ok, result = pcall(getgenv)
        if ok and type(result) == "table" then
            env = result
        end
    end

    for _, functionName in ipairs({ "identifyexecutor", "getexecutorname" }) do
        local fn = env and env[functionName]

        if typeof(fn) == "function" then
            local ok, result = pcall(fn)
            if ok and result then
                return tostring(result)
            end
        end
    end

    return "unknown"
end

local function newRemoteReport()
    return {
        script = RemoteDiagnostic.SCRIPT_NAME,
        version = RemoteDiagnostic.VERSION,
        runId = nil,
        status = "idle",
        phase = "idle",
        startedAt = nil,
        finishedAt = nil,
        message = "",
        steps = {},
        errors = {},
        counters = {},
        environment = {}
    }
end

RemoteDiagnostic.Report = newRemoteReport()

local function remoteResponseStatus(response)
    if type(response) ~= "table" then
        return nil
    end

    return tonumber(
        response.StatusCode
        or response.Status
        or response.status_code
        or response.status
    )
end

function RemoteDiagnostic.send(force)
    if not RemoteRequest or not RemoteDiagnostic.RUN_ID then
        return false
    end

    if RemoteDiagnostic.Sending then
        return false
    end

    if not force and RemoteDiagnostic.Pending <= 0 then
        return true
    end

    RemoteDiagnostic.Sending = true

    local pendingAtSend = RemoteDiagnostic.Pending
    local payload = {
        script = RemoteDiagnostic.SCRIPT_NAME,
        runId = RemoteDiagnostic.RUN_ID,
        report = remoteCopyTable(RemoteDiagnostic.Report)
    }

    task.spawn(function()
        local ok, response = pcall(function()
            local body = HttpService:JSONEncode(payload)

            return RemoteRequest({
                Url = RemoteDiagnostic.ENDPOINT,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = body
            })
        end)

        local statusCode = ok and remoteResponseStatus(response) or nil
        local accepted = ok and (statusCode == nil or (statusCode >= 200 and statusCode < 300))

        RemoteDiagnostic.LastHTTPStatus = statusCode
        RemoteDiagnostic.LastSendOK = accepted
        RemoteDiagnostic.SendCount = RemoteDiagnostic.SendCount + 1

        if accepted then
            RemoteDiagnostic.Pending = math.max(0, RemoteDiagnostic.Pending - pendingAtSend)
        else
            RemoteDiagnostic.FailureCount = RemoteDiagnostic.FailureCount + 1
        end

        RemoteDiagnostic.Sending = false

        -- Se chegaram novos eventos durante o POST, agenda novo envio sem bloquear.
        if RemoteDiagnostic.Pending > 0
        and RemoteDiagnostic.Report.status ~= "running" then
            task.defer(function()
                RemoteDiagnostic.send(true)
            end)
        end
    end)

    return true
end

local function remoteMarkDirty()
    RemoteDiagnostic.Pending = RemoteDiagnostic.Pending + 1

    if RemoteDiagnostic.Pending >= RemoteDiagnostic.MAX_PENDING then
        RemoteDiagnostic.send(false)
    end
end

function RemoteDiagnostic.start(message)
    RemoteDiagnostic.RUN_ID = remoteGenerateRunId()
    RemoteDiagnostic.Pending = 0
    RemoteDiagnostic.LastHTTPStatus = nil
    RemoteDiagnostic.LastSendOK = nil
    RemoteDiagnostic.SendCount = 0
    RemoteDiagnostic.FailureCount = 0
    RemoteDiagnostic.Report = newRemoteReport()

    local report = RemoteDiagnostic.Report
    report.runId = RemoteDiagnostic.RUN_ID
    report.status = "running"
    report.phase = "startup"
    report.startedAt = remoteNow()
    report.message = message or "Diagnóstico iniciado"
    report.environment = {
        placeId = game.PlaceId,
        gameId = game.GameId,
        jobId = game.JobId,
        executor = remoteGetExecutorName()
    }

    RemoteDiagnostic.Pending = 1
    RemoteDiagnostic.send(true)

    if not RemoteDiagnostic.HeartbeatRunning then
        RemoteDiagnostic.HeartbeatRunning = true

        task.spawn(function()
            while RemoteDiagnostic.HeartbeatRunning do
                task.wait(RemoteDiagnostic.FLUSH_INTERVAL)

                if RemoteDiagnostic.Report.status == "running" then
                    RemoteDiagnostic.send(false)
                end
            end
        end)

        task.spawn(function()
            while RemoteDiagnostic.HeartbeatRunning do
                task.wait(RemoteDiagnostic.HEARTBEAT_INTERVAL)

                if RemoteDiagnostic.Report.status ~= "running" then
                    break
                end

                RemoteDiagnostic.Report.phase = "heartbeat"
                RemoteDiagnostic.Report.message = "Diagnóstico ativo"
                remoteMarkDirty()
                RemoteDiagnostic.send(true)
            end
        end)
    end

    return RemoteDiagnostic.RUN_ID
end

function RemoteDiagnostic.event(name, message, extra)
    if not RemoteDiagnostic.RUN_ID
    or RemoteDiagnostic.Report.status ~= "running" then
        return
    end

    local step = {
        name = tostring(name or "unknown"),
        message = tostring(message or ""),
        time = remoteNow()
    }

    if type(extra) == "table" then
        for key, value in pairs(extra) do
            step[key] = value
        end
    end

    RemoteDiagnostic.Report.phase = step.name
    RemoteDiagnostic.Report.message = step.message
    RemoteDiagnostic.Report.steps[#RemoteDiagnostic.Report.steps + 1] = step

    if step.name == "ERROR" then
        RemoteDiagnostic.Report.errors[#RemoteDiagnostic.Report.errors + 1] = remoteCopyTable(step)
    end

    remoteMarkDirty()
end

function RemoteDiagnostic.counter(name, value)
    if not RemoteDiagnostic.RUN_ID
    or RemoteDiagnostic.Report.status ~= "running" then
        return
    end

    RemoteDiagnostic.Report.counters[tostring(name)] = value
    remoteMarkDirty()
end

function RemoteDiagnostic.finish(status, message)
    if not RemoteDiagnostic.RUN_ID then
        return
    end

    RemoteDiagnostic.Report.status = status or "success"
    RemoteDiagnostic.Report.phase = status == "interrupted" and "interrupted" or "finished"
    RemoteDiagnostic.Report.message = message or "Diagnóstico finalizado"
    RemoteDiagnostic.Report.finishedAt = remoteNow()
    RemoteDiagnostic.Pending = RemoteDiagnostic.Pending + 1
    RemoteDiagnostic.HeartbeatRunning = false
    RemoteDiagnostic.send(true)
end

function RemoteDiagnostic.forceFlush()
    return RemoteDiagnostic.send(true)
end

function RemoteDiagnostic.getStatus()
    return {
        script = RemoteDiagnostic.SCRIPT_NAME,
        version = RemoteDiagnostic.VERSION,
        endpoint = RemoteDiagnostic.ENDPOINT,
        runId = RemoteDiagnostic.RUN_ID,
        requestAvailable = RemoteRequest ~= nil,
        pending = RemoteDiagnostic.Pending,
        sends = RemoteDiagnostic.SendCount,
        failures = RemoteDiagnostic.FailureCount,
        lastHTTPStatus = RemoteDiagnostic.LastHTTPStatus,
        lastSendOK = RemoteDiagnostic.LastSendOK
    }
end

-- ============================================================
-- CONFIGURAÇÃO
-- ============================================================

local GUI_NAME = "PsicosenaticoESPResearch_V1"
local ESP_ALLY_HIGHLIGHT_NAME = "PsicoESP_Ally"
local ESP_ENEMY_HIGHLIGHT_NAME = "PsicoESP_Enemy"
local ESP_UNKNOWN_HIGHLIGHT_NAME = "PsicoESP_Unknown"
local ROOT_WAIT_TIMEOUT = 3

-- Cores do ESP (verde = aliado / vermelho = inimigo)
local ESP_ALLY_COLOR = Color3.fromRGB(65, 210, 118)
local ESP_ENEMY_COLOR = Color3.fromRGB(235, 38, 52)
local ESP_UNKNOWN_COLOR = Color3.fromRGB(242, 184, 57)

-- ============================================================
-- PARENT
-- ============================================================

local function getParent()
    if typeof(gethui) == "function" then
        local ok, p = pcall(gethui)
        if ok and p then return p end
    end
    return CoreGui
end

local Parent = getParent()

for _, v in ipairs(Parent:GetChildren()) do
    if v.Name == GUI_NAME then
        pcall(function() v:Destroy() end)
    end
end

local Gui = Instance.new("ScreenGui")
Gui.Name = GUI_NAME
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = true
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = Parent

-- ============================================================
-- CORES DA INTERFACE
-- ============================================================

local COLORS = {
    bg = Color3.fromRGB(10, 10, 13),
    panel = Color3.fromRGB(19, 19, 24),
    panel2 = Color3.fromRGB(28, 28, 35),
    text = Color3.fromRGB(245, 245, 248),
    sub = Color3.fromRGB(158, 158, 172),
    blue = Color3.fromRGB(22, 55, 105),
    blue2 = Color3.fromRGB(32, 82, 145),
    green = Color3.fromRGB(65, 210, 118),
    red = Color3.fromRGB(235, 38, 52),
    yellow = Color3.fromRGB(242, 184, 57),
    scroll = Color3.fromRGB(65, 65, 75)
}

-- ============================================================
-- HELPERS DE UI
-- ============================================================

local function new(class, props)
    local obj = Instance.new(class)
    for k, v in pairs(props or {}) do
        obj[k] = v
    end
    return obj
end

local function round(obj, radius)
    new("UICorner", {
        CornerRadius = UDim.new(0, radius or 8),
        Parent = obj
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
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center
    })
end

-- ============================================================
-- ESTADO
-- ============================================================

local State = {
    ESPEnabled = false,
    DiagnosticEnabled = false,
    DiagnosticEverStarted = false,

    RuntimeCounter = 0,
    Observed = {},       -- [Model] = record
    Records = {},        -- runtime records atuais/históricos
    ActiveESP = {},      -- [Model] = Highlight próprio ativo
    NativeHighlightStates = {}, -- [Highlight nativo] = estado Enabled original

    DiagnosticRecords = {}, -- [runtimeId] = resumo compacto
    Events = {},
    LiveLogs = {},

    DiagnosticStartUnix = nil,
    DiagnosticEndUnix = nil,
    DiagnosticStartClock = nil,

    EstimatedBytes = 0,
    ErrorCount = 0,

    Connections = {},
    ModelConnections = {} -- [Model] = {connections...}
}

-- ============================================================
-- UTILITÁRIOS
-- ============================================================

local function unix()
    return os.time()
end

local function clock()
    return os.clock()
end

local function safeFullName(instance)
    local ok, result = pcall(function()
        return instance:GetFullName()
    end)
    if ok then return tostring(result) end
    return tostring(instance and instance.Name or "UNKNOWN")
end

local function safeAttr(instance, key)
    local ok, result = pcall(function()
        return instance:GetAttribute(key)
    end)
    if ok then return result end
    return nil
end

local function getHumanoid(model)
    if not model then return nil end
    return model:FindFirstChildOfClass("Humanoid")
end

local function getRoot(model)
    if not model then return nil end
    return model:FindFirstChild("HumanoidRootPart")
end

local function getLocalTeam()
    local ok, team = pcall(function()
        return LocalPlayer.Team
    end)
    if ok and team then
        return tostring(team.Name), "Player.Team"
    end

    local attrTeam = safeAttr(LocalPlayer, "Team")
    if attrTeam ~= nil then
        return tostring(attrTeam), "Player.Attribute.Team"
    end

    return nil, nil
end

local function readBotTeam(model)
    local team = safeAttr(model, "Team")
    if team ~= nil then
        return tostring(team), "Attribute.Team"
    end

    local teamValue = model:FindFirstChild("Team")
    if teamValue and teamValue:IsA("StringValue") then
        return tostring(teamValue.Value), "StringValue.Team"
    end

    if teamValue and teamValue:IsA("ObjectValue") and teamValue.Value then
        return tostring(teamValue.Value.Name), "ObjectValue.Team"
    end

    return nil, nil
end

local function isValidTeam(team)
    return team == "Army" or team == "Rebels"
end

local function classifyTeams(botTeam, playerTeam)
    if not isValidTeam(botTeam) then
        return "UNKNOWN", "BOT_TEAM_INVALID_OR_MISSING"
    end

    if not isValidTeam(playerTeam) then
        return "UNKNOWN", "PLAYER_TEAM_INVALID_OR_MISSING"
    end

    if botTeam == playerTeam then
        return "ALLY", "BOT_TEAM_EQUALS_PLAYER_TEAM"
    end

    return "ENEMY", "BOT_TEAM_DIFFERS_FROM_PLAYER_TEAM"
end

local function isPsicoESPHighlight(obj)
    if not obj or not obj:IsA("Highlight") then
        return false
    end

    return obj.Name == ESP_ALLY_HIGHLIGHT_NAME
        or obj.Name == ESP_ENEMY_HIGHLIGHT_NAME
        or obj.Name == ESP_UNKNOWN_HIGHLIGHT_NAME
end

local function espNameForClassification(classification)
    if classification == "ALLY" then
        return ESP_ALLY_HIGHLIGHT_NAME
    elseif classification == "ENEMY" then
        return ESP_ENEMY_HIGHLIGHT_NAME
    end
    return ESP_UNKNOWN_HIGHLIGHT_NAME
end

local function suppressNativeHighlight(obj)
    if not obj or not obj:IsA("Highlight") or isPsicoESPHighlight(obj) then
        return
    end

    if State.NativeHighlightStates[obj] == nil then
        State.NativeHighlightStates[obj] = obj.Enabled
    end

    pcall(function()
        obj.Enabled = false
    end)
end

local function suppressNativeHighlights(model)
    if not State.ESPEnabled or not model then
        return
    end

    for _, obj in ipairs(model:GetDescendants()) do
        if obj:IsA("Highlight") and not isPsicoESPHighlight(obj) then
            suppressNativeHighlight(obj)
        end
    end
end

local function restoreNativeHighlights(model)
    local pending = {}

    for obj, originalEnabled in pairs(State.NativeHighlightStates) do
        local belongs = false

        if not model then
            belongs = true
        elseif obj and obj.Parent then
            local ok, result = pcall(function()
                return obj:IsDescendantOf(model)
            end)
            belongs = ok and result
        end

        if belongs then
            pending[#pending + 1] = { obj = obj, enabled = originalEnabled }
        end
    end

    for _, item in ipairs(pending) do
        local obj = item.obj
        if obj and obj.Parent then
            pcall(function()
                obj.Enabled = item.enabled
            end)
        end
        State.NativeHighlightStates[obj] = nil
    end
end

local function compactNativeHighlight(model)
    local result = {
        exists = false,
        count = 0,
        details = {}
    }

    if not model then return result end

    for _, obj in ipairs(model:GetDescendants()) do
        if obj:IsA("Highlight") and not isPsicoESPHighlight(obj) then
            result.exists = true
            result.count = result.count + 1

            result.details[#result.details + 1] = {
                name = obj.Name,
                enabled = obj.Enabled,
                depthMode = tostring(obj.DepthMode),
                fillTransparency = obj.FillTransparency,
                outlineTransparency = obj.OutlineTransparency,
                fillColor = {
                    r = obj.FillColor.R,
                    g = obj.FillColor.G,
                    b = obj.FillColor.B
                },
                outlineColor = {
                    r = obj.OutlineColor.R,
                    g = obj.OutlineColor.G,
                    b = obj.OutlineColor.B
                }
            }
        end
    end

    return result
end

local function safeJsonLength(value)
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(value)
    end)

    if ok and encoded then
        return #encoded
    end

    return 0
end

local function formatMB(bytes)
    return string.format("%.2f MB", (bytes or 0) / (1024 * 1024))
end

-- ============================================================
-- LIVE LOG + DIAGNÓSTICO
-- ============================================================

local function appendLiveLog(eventType, message)
    State.LiveLogs[#State.LiveLogs + 1] = {
        time = clock(),
        type = eventType,
        message = tostring(message or "")
    }

    while #State.LiveLogs > 180 do
        table.remove(State.LiveLogs, 1)
    end
end

local function ensureDiagnosticRecord(record)
    if not State.DiagnosticEnabled or not record then
        return nil
    end

    local existing = State.DiagnosticRecords[record.id]
    if existing then
        return existing
    end

    local playerTeam, playerTeamSource = getLocalTeam()
    local botTeam, botTeamSource = readBotTeam(record.model)
    local classification, classificationReason = classifyTeams(botTeam, playerTeam)
    local humanoid = getHumanoid(record.model)
    local root = getRoot(record.model)

    local diag = {
        id = record.id,
        name = record.name,
        initialPath = record.path,
        detectedAtUnix = record.detectedAtUnix,
        detectedAtClock = record.detectedAtClock,

        currentPath = record.model and safeFullName(record.model) or record.path,
        removed = record.removed or false,

        botTeam = botTeam,
        botTeamSource = botTeamSource,
        playerTeam = playerTeam,
        playerTeamSource = playerTeamSource,

        classification = classification,
        classificationReason = classificationReason,

        humanoidFound = humanoid ~= nil,
        rootFound = root ~= nil,
        rootWaitSeconds = record.rootWaitSeconds,

        health = humanoid and humanoid.Health or nil,
        maxHealth = humanoid and humanoid.MaxHealth or nil,

        espCreated = State.ActiveESP[record.model] ~= nil,
        nativeHighlight = compactNativeHighlight(record.model)
    }

    State.DiagnosticRecords[record.id] = diag
    State.EstimatedBytes = State.EstimatedBytes + safeJsonLength(diag)

    return diag
end

local function updateDiagnosticRecord(record)
    if not State.DiagnosticEnabled or not record then return end

    local diag = ensureDiagnosticRecord(record)
    if not diag then return end

    local playerTeam, playerTeamSource = getLocalTeam()
    local botTeam, botTeamSource = readBotTeam(record.model)
    local classification, classificationReason = classifyTeams(botTeam, playerTeam)
    local humanoid = getHumanoid(record.model)
    local root = getRoot(record.model)

    diag.currentPath = record.model and safeFullName(record.model) or diag.currentPath
    diag.removed = record.removed or false

    diag.botTeam = botTeam
    diag.botTeamSource = botTeamSource
    diag.playerTeam = playerTeam
    diag.playerTeamSource = playerTeamSource

    diag.classification = classification
    diag.classificationReason = classificationReason

    diag.humanoidFound = humanoid ~= nil
    diag.rootFound = root ~= nil
    diag.rootWaitSeconds = record.rootWaitSeconds

    diag.health = humanoid and humanoid.Health or diag.health
    diag.maxHealth = humanoid and humanoid.MaxHealth or diag.maxHealth

    diag.espCreated = record.model and State.ActiveESP[record.model] ~= nil or false
    diag.nativeHighlight = record.model and compactNativeHighlight(record.model) or diag.nativeHighlight

    if record.removed then
        diag.removedAtUnix = record.removedAtUnix
        diag.removedAtClock = record.removedAtClock
    end
end

local function addDiagnosticEvent(eventType, record, data, message)
    appendLiveLog(eventType, message)

    if eventType == "ERROR" then
        State.ErrorCount = State.ErrorCount + 1
    end

    if not State.DiagnosticEnabled then
        return
    end

    local event = {
        unix = unix(),
        time = clock(),
        type = eventType,
        botId = record and record.id or nil,
        data = data or {}
    }

    State.Events[#State.Events + 1] = event
    State.EstimatedBytes = State.EstimatedBytes + safeJsonLength(event) + 2

    -- Espelha o evento para o endpoint em lote. O diagnóstico local continua
    -- sendo a fonte principal e não depende da disponibilidade da rede.
    RemoteDiagnostic.event(
        eventType,
        message,
        {
            botId = record and record.id or nil,
            data = data or {}
        }
    )

    if record then
        ensureDiagnosticRecord(record)
        updateDiagnosticRecord(record)
    end
end

-- ============================================================
-- ESP
-- ============================================================

local function colorForClassification(classification)
    if classification == "ALLY" then
        return ESP_ALLY_COLOR
    elseif classification == "ENEMY" then
        return ESP_ENEMY_COLOR
    end
    return ESP_UNKNOWN_COLOR
end

local function destroyESP(model, record, reason)
    local esp = State.ActiveESP[model]

    if esp then
        State.ActiveESP[model] = nil
        pcall(function()
            esp:Destroy()
        end)

        if record then
            addDiagnosticEvent(
                "ESP_REMOVED",
                record,
                { reason = reason or "UNKNOWN" },
                string.format("ESP removido de %s", record.name)
            )
        end
    end

    -- Ao remover o ESP próprio, restaura o Highlight nativo desse modelo.
    restoreNativeHighlights(model)

    if record then
        updateDiagnosticRecord(record)
    end
end

local function applyOrUpdateESP(record, reason)
    if not record or not record.model or not record.model.Parent then
        return
    end

    local model = record.model
    local botTeam, botTeamSource = readBotTeam(model)
    local playerTeam, playerTeamSource = getLocalTeam()
    local classification, classificationReason = classifyTeams(botTeam, playerTeam)

    record.botTeam = botTeam
    record.botTeamSource = botTeamSource
    record.playerTeam = playerTeam
    record.playerTeamSource = playerTeamSource
    record.classification = classification
    record.classificationReason = classificationReason

    addDiagnosticEvent(
        "TEAM_READ",
        record,
        {
            botTeam = botTeam,
            botTeamSource = botTeamSource,
            playerTeam = playerTeam,
            playerTeamSource = playerTeamSource
        },
        string.format(
            "%s • Bot=%s | Jogador=%s",
            record.name,
            tostring(botTeam),
            tostring(playerTeam)
        )
    )

    addDiagnosticEvent(
        "CLASSIFIED_" .. classification,
        record,
        {
            classification = classification,
            reason = classificationReason,
            trigger = reason
        },
        string.format(
            "%s classificado como %s (%s vs %s)",
            record.name,
            classification,
            tostring(botTeam),
            tostring(playerTeam)
        )
    )

    if not State.ESPEnabled then
        destroyESP(model, record, "ESP_DISABLED")
        return
    end

    local color = colorForClassification(classification)
    local desiredName = espNameForClassification(classification)
    local esp = State.ActiveESP[model]

    -- Evita conflito visual com o Highlight nativo do jogo.
    -- O estado original é salvo e restaurado quando o ESP é desligado/removido.
    suppressNativeHighlights(model)

    -- Se a relação mudou (ALLY <-> ENEMY), recria com o nome correto.
    if esp and esp.Parent and esp.Name ~= desiredName then
        pcall(function()
            esp:Destroy()
        end)
        State.ActiveESP[model] = nil
        esp = nil
    end

    if not esp or not esp.Parent then
        local ok, created = pcall(function()
            local h = Instance.new("Highlight")
            h.Name = desiredName
            h.Adornee = model
            h.Enabled = true
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

            -- Mais opaco que o Highlight nativo para garantir leitura visual clara.
            h.FillTransparency = 0.42
            h.OutlineTransparency = 0
            h.FillColor = color
            h.OutlineColor = color
            h.Parent = model
            return h
        end)

        if ok and created then
            State.ActiveESP[model] = created

            addDiagnosticEvent(
                "ESP_CREATED",
                record,
                {
                    classification = classification,
                    highlightName = desiredName,
                    visualColor = classification == "ALLY" and "GREEN"
                        or classification == "ENEMY" and "RED"
                        or "YELLOW",
                    nativeHighlightSuppressed = true,
                    trigger = reason
                },
                string.format(
                    "ESP %s criado para %s",
                    classification,
                    record.name
                )
            )
        else
            addDiagnosticEvent(
                "ERROR",
                record,
                {
                    stage = "ESP_CREATE",
                    error = tostring(created)
                },
                string.format("Erro ao criar ESP para %s: %s", record.name, tostring(created))
            )
        end
    else
        pcall(function()
            esp.Name = desiredName
            esp.FillColor = color
            esp.OutlineColor = color
            esp.Adornee = model
            esp.Enabled = true
        end)

        addDiagnosticEvent(
            "ESP_UPDATED",
            record,
            {
                classification = classification,
                highlightName = desiredName,
                visualColor = classification == "ALLY" and "GREEN"
                    or classification == "ENEMY" and "RED"
                    or "YELLOW",
                nativeHighlightSuppressed = true,
                trigger = reason
            },
            string.format("ESP atualizado para %s", record.name)
        )
    end

    updateDiagnosticRecord(record)
end

-- ============================================================
-- ROOT / HUMANOID / HIGHLIGHT NATIVO
-- ============================================================

local function monitorRoot(record)
    task.spawn(function()
        if not record or not record.model then return end

        local model = record.model
        local startClock = clock()
        local root = getRoot(model)

        if root then
            record.rootWaitSeconds = 0

            addDiagnosticEvent(
                "ROOT_FOUND",
                record,
                { waitSeconds = 0 },
                string.format("%s • HumanoidRootPart já disponível", record.name)
            )

            updateDiagnosticRecord(record)
            return
        end

        addDiagnosticEvent(
            "ROOT_WAIT_STARTED",
            record,
            { timeoutSeconds = ROOT_WAIT_TIMEOUT },
            string.format("%s aguardando HumanoidRootPart...", record.name)
        )

        local ok, found = pcall(function()
            return model:WaitForChild("HumanoidRootPart", ROOT_WAIT_TIMEOUT)
        end)

        local elapsed = clock() - startClock
        record.rootWaitSeconds = elapsed

        if ok and found then
            addDiagnosticEvent(
                "ROOT_FOUND",
                record,
                { waitSeconds = elapsed },
                string.format(
                    "%s • HumanoidRootPart encontrado (%.2fs)",
                    record.name,
                    elapsed
                )
            )
        else
            addDiagnosticEvent(
                "ROOT_TIMEOUT",
                record,
                {
                    waitSeconds = elapsed,
                    timeoutSeconds = ROOT_WAIT_TIMEOUT
                },
                string.format(
                    "%s • HumanoidRootPart não apareceu em %.2fs",
                    record.name,
                    elapsed
                )
            )
        end

        updateDiagnosticRecord(record)
    end)
end

local function onNativeHighlightChanged(record, reason)
    if not record or not record.model or not record.model.Parent then return end

    local native = compactNativeHighlight(record.model)

    addDiagnosticEvent(
        "NATIVE_HIGHLIGHT_CHANGED",
        record,
        {
            reason = reason,
            nativeHighlight = native
        },
        string.format(
            "%s • Highlight nativo: %s",
            record.name,
            native.exists and "SIM" or "NÃO"
        )
    )
end

-- ============================================================
-- CONEXÕES POR BOT
-- ============================================================

local function disconnectModelConnections(model)
    local list = State.ModelConnections[model]
    if not list then return end

    for _, connection in ipairs(list) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    State.ModelConnections[model] = nil
end

local function addModelConnection(model, connection)
    State.ModelConnections[model] = State.ModelConnections[model] or {}
    table.insert(State.ModelConnections[model], connection)
end

local function connectRecord(record)
    local model = record.model
    if not model then return end

    disconnectModelConnections(model)

    local teamChanged = model:GetAttributeChangedSignal("Team"):Connect(function()
        local oldTeam = record.botTeam
        local newTeam, source = readBotTeam(model)

        addDiagnosticEvent(
            "TEAM_CHANGED",
            record,
            {
                oldTeam = oldTeam,
                newTeam = newTeam,
                source = source
            },
            string.format(
                "%s • Team: %s -> %s",
                record.name,
                tostring(oldTeam),
                tostring(newTeam)
            )
        )

        applyOrUpdateESP(record, "BOT_TEAM_CHANGED")
    end)
    addModelConnection(model, teamChanged)

    local descendantAdded = model.DescendantAdded:Connect(function(obj)
        if obj:IsA("Highlight") and not isPsicoESPHighlight(obj) then
            if State.ESPEnabled then
                suppressNativeHighlight(obj)
            end
            task.defer(function()
                onNativeHighlightChanged(record, "DESCENDANT_ADDED")
            end)
        elseif obj.Name == "HumanoidRootPart" and obj:IsA("BasePart") then
            addDiagnosticEvent(
                "ROOT_ADDED",
                record,
                {},
                string.format("%s • HumanoidRootPart adicionado", record.name)
            )
        end
    end)
    addModelConnection(model, descendantAdded)

    local descendantRemoving = model.DescendantRemoving:Connect(function(obj)
        if obj:IsA("Highlight") and not isPsicoESPHighlight(obj) then
            task.defer(function()
                onNativeHighlightChanged(record, "DESCENDANT_REMOVING")
            end)
        elseif obj.Name == "HumanoidRootPart" then
            addDiagnosticEvent(
                "ROOT_REMOVED",
                record,
                {},
                string.format("%s • HumanoidRootPart removido", record.name)
            )
        end
    end)
    addModelConnection(model, descendantRemoving)

    local humanoid = getHumanoid(model)
    if humanoid then
        local died = humanoid.Died:Connect(function()
            addDiagnosticEvent(
                "HUMANOID_DIED",
                record,
                {},
                string.format("%s • Humanoid morreu", record.name)
            )
        end)
        addModelConnection(model, died)
    end
end

-- ============================================================
-- REGISTRO DE SOLDIERS
-- ============================================================

local function registerSoldier(model, reason)
    if not model or not model:IsA("Model") then
        return nil
    end

    if State.Observed[model] then
        return State.Observed[model]
    end

    local soldiers = workspace:FindFirstChild("Soldiers")
    if not soldiers or not model:IsDescendantOf(soldiers) then
        return nil
    end

    local humanoid = getHumanoid(model)
    if not humanoid then
        -- Alguns Models podem chegar antes do Humanoid; aguarda brevemente.
        local ok, found = pcall(function()
            return model:WaitForChild("Humanoid", 2)
        end)
        if ok and found and found:IsA("Humanoid") then
            humanoid = found
        end
    end

    if not humanoid then
        appendLiveLog(
            "IGNORED",
            string.format("%s ignorado: sem Humanoid", model.Name)
        )
        return nil
    end

    State.RuntimeCounter = State.RuntimeCounter + 1

    local record = {
        id = State.RuntimeCounter,
        model = model,
        name = model.Name,
        path = safeFullName(model),
        detectedAtUnix = unix(),
        detectedAtClock = clock(),
        removed = false
    }

    State.Observed[model] = record
    State.Records[#State.Records + 1] = record

    local team, teamSource = readBotTeam(model)
    record.botTeam = team
    record.botTeamSource = teamSource

    addDiagnosticEvent(
        "BOT_FOUND",
        record,
        {
            path = record.path,
            reason = reason,
            team = team,
            teamSource = teamSource
        },
        string.format("%s encontrado em %s", record.name, record.path)
    )

    connectRecord(record)
    monitorRoot(record)

    if State.DiagnosticEnabled then
        ensureDiagnosticRecord(record)
    end

    applyOrUpdateESP(record, reason or "REGISTERED")

    return record
end

local function removeSoldier(model, reason)
    local record = State.Observed[model]
    if not record then return end

    record.removed = true
    record.removedAtUnix = unix()
    record.removedAtClock = clock()

    addDiagnosticEvent(
        "BOT_REMOVED",
        record,
        {
            path = record.path,
            reason = reason
        },
        string.format("%s removido de Workspace.Soldiers", record.name)
    )

    destroyESP(model, record, "BOT_REMOVED")
    updateDiagnosticRecord(record)

    disconnectModelConnections(model)
    State.Observed[model] = nil
end

local function scanExisting(reason)
    local soldiers = workspace:FindFirstChild("Soldiers")
    if not soldiers then
        appendLiveLog("ERROR", "Workspace.Soldiers não encontrado.")
        if State.DiagnosticEnabled then
            addDiagnosticEvent(
                "ERROR",
                nil,
                {
                    stage = "SCAN_EXISTING",
                    error = "Workspace.Soldiers not found"
                },
                "Workspace.Soldiers não encontrado."
            )
        end
        return
    end

    for _, child in ipairs(soldiers:GetChildren()) do
        if child:IsA("Model") then
            registerSoldier(child, reason or "EXISTING_SCAN")
        end
    end
end

-- ============================================================
-- MONITOR GLOBAL DE SOLDIERS
-- ============================================================

local SoldiersConnections = {}

local function disconnectSoldiersMonitoring()
    for _, connection in ipairs(SoldiersConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    SoldiersConnections = {}
end

local function connectSoldiersMonitoring()
    disconnectSoldiersMonitoring()

    local soldiers = workspace:FindFirstChild("Soldiers")
    if not soldiers then
        local ok, found = pcall(function()
            return workspace:WaitForChild("Soldiers", 5)
        end)
        if ok then soldiers = found end
    end

    if not soldiers then
        addDiagnosticEvent(
            "ERROR",
            nil,
            {
                stage = "CONNECT_MONITORING",
                error = "Workspace.Soldiers not found"
            },
            "Não foi possível iniciar monitoramento: Workspace.Soldiers ausente."
        )
        return
    end

    SoldiersConnections[#SoldiersConnections + 1] =
        soldiers.ChildAdded:Connect(function(child)
            if child:IsA("Model") then
                task.defer(function()
                    registerSoldier(child, "CHILD_ADDED")
                end)
            end
        end)

    SoldiersConnections[#SoldiersConnections + 1] =
        soldiers.ChildRemoved:Connect(function(child)
            if child:IsA("Model") then
                removeSoldier(child, "CHILD_REMOVED")
            end
        end)
end

local function ensureMonitoring()
    if #SoldiersConnections == 0 then
        connectSoldiersMonitoring()
    end
    scanExisting("MONITOR_START")
end

-- ============================================================
-- RECLASSIFICAÇÃO GERAL
-- ============================================================

local function reclassifyAll(reason)
    for _, record in ipairs(State.Records) do
        if record.model and record.model.Parent and not record.removed then
            applyOrUpdateESP(record, reason or "RECLASSIFY_ALL")
        end
    end
end

local function removeAllESP(reason)
    local models = {}
    for model in pairs(State.ActiveESP) do
        models[#models + 1] = model
    end

    for _, model in ipairs(models) do
        local record = State.Observed[model]
        destroyESP(model, record, reason or "ESP_DISABLED")
    end
end

-- ============================================================
-- DIAGNÓSTICO
-- ============================================================

local function resetDiagnosticData()
    State.DiagnosticRecords = {}
    State.Events = {}
    State.EstimatedBytes = 0
    State.ErrorCount = 0
end

local function startDiagnostic()
    if State.DiagnosticEnabled then return end

    resetDiagnosticData()

    State.DiagnosticEnabled = true
    State.DiagnosticEverStarted = true
    State.DiagnosticStartUnix = unix()
    State.DiagnosticEndUnix = nil
    State.DiagnosticStartClock = clock()

    appendLiveLog("DIAGNOSTIC_STARTED", "Diagnóstico V1.1 iniciado.")

    -- Inicia uma nova execução remota identificada como Psicov1.lua.
    -- Se o executor não oferecer request/http_request, o diagnóstico local
    -- continua normalmente e o estado remoto ficará como indisponível.
    RemoteDiagnostic.start("PSICOSENATICO ESP Research V1.1 iniciado")

    ensureMonitoring()

    -- Registra o estado atual de tudo que já existe.
    for _, record in ipairs(State.Records) do
        if record.model and record.model.Parent and not record.removed then
            ensureDiagnosticRecord(record)

            addDiagnosticEvent(
                "DIAGNOSTIC_BASELINE",
                record,
                {
                    path = safeFullName(record.model),
                    nativeHighlight = compactNativeHighlight(record.model),
                    espActive = State.ActiveESP[record.model] ~= nil
                },
                string.format("Baseline registrado para %s", record.name)
            )
        end
    end

    reclassifyAll("DIAGNOSTIC_START")
end

local function stopDiagnostic()
    if not State.DiagnosticEnabled then return end

    addDiagnosticEvent(
        "DIAGNOSTIC_STOPPED",
        nil,
        {},
        "Diagnóstico V1.1 parado."
    )

    State.DiagnosticEnabled = false
    State.DiagnosticEndUnix = unix()

    RemoteDiagnostic.counter("events", #State.Events)
    RemoteDiagnostic.counter("errors", State.ErrorCount)
    RemoteDiagnostic.counter("observedNow", (function()
        local n = 0
        for _ in pairs(State.Observed) do n = n + 1 end
        return n
    end)())
    RemoteDiagnostic.finish("success", "Diagnóstico V1.1 finalizado")
end

-- ============================================================
-- SERIALIZAÇÃO COMPACTA
-- ============================================================

local function serializeDiagnosticRecords()
    local list = {}

    for _, diag in pairs(State.DiagnosticRecords) do
        list[#list + 1] = diag
    end

    table.sort(list, function(a, b)
        return (a.id or 0) < (b.id or 0)
    end)

    return list
end

local function countClassifications()
    local ally, enemy, unknown = 0, 0, 0

    for _, record in pairs(State.Observed) do
        if record.classification == "ALLY" then
            ally = ally + 1
        elseif record.classification == "ENEMY" then
            enemy = enemy + 1
        else
            unknown = unknown + 1
        end
    end

    return ally, enemy, unknown
end

local function activeESPCount()
    local n = 0
    for model, esp in pairs(State.ActiveESP) do
        if model and model.Parent and esp and esp.Parent then
            n = n + 1
        end
    end
    return n
end

local function buildExport()
    -- Atualiza o resumo final dos registros sem duplicar eventos.
    for _, record in ipairs(State.Records) do
        if State.DiagnosticRecords[record.id] then
            updateDiagnosticRecord(record)
        end
    end

    local ally, enemy, unknown = countClassifications()

    return {
        format = "Psicosenatico ESP Research",
        version = "V1.1",
        collectionMode = "EVENT_DRIVEN_COMPACT",
        generatedAtUnix = unix(),

        description =
            "Diagnóstico do ESP experimental. Registra detecção, equipe, classificação, root, Highlight nativo, criação/remoção do ESP e erros sem snapshots periódicos pesados.",

        game = {
            placeId = game.PlaceId,
            gameId = game.GameId,
            jobId = game.JobId
        },

        diagnostic = {
            startUnix = State.DiagnosticStartUnix,
            endUnix = State.DiagnosticEndUnix,
            status = State.DiagnosticEnabled and "RECORDING" or "STOPPED"
        },

        remoteDelivery = RemoteDiagnostic.getStatus(),

        localPlayer = {
            name = LocalPlayer.Name,
            userId = LocalPlayer.UserId,
            team = select(1, getLocalTeam())
        },

        summary = {
            observedNow = (function()
                local n = 0
                for _ in pairs(State.Observed) do n = n + 1 end
                return n
            end)(),

            diagnosticBots = (function()
                local n = 0
                for _ in pairs(State.DiagnosticRecords) do n = n + 1 end
                return n
            end)(),

            ally = ally,
            enemy = enemy,
            unknown = unknown,
            activeESP = activeESPCount(),
            events = #State.Events,
            errors = State.ErrorCount
        },

        bots = serializeDiagnosticRecords(),
        events = State.Events
    }
end

local function jsonExport()
    local ok, result = pcall(function()
        return HttpService:JSONEncode(buildExport())
    end)

    if ok then return result end
    return nil, result
end

-- ============================================================
-- INTERFACE
-- ============================================================

local Main = new("Frame", {
    Parent = Gui,
    BackgroundColor3 = COLORS.bg,
    BorderSizePixel = 0,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5)
})
round(Main, 16)

local function updateMainSize()
    local camera = workspace.CurrentCamera
    if not camera then return end

    local viewport = camera.ViewportSize

    local maxHeight = math.floor(viewport.Y * 0.70)
    local maxWidth = math.floor(viewport.X * 0.92)

    local desiredHeight = math.floor(viewport.Y * 0.68)
    local desiredWidth = math.floor(viewport.X * 0.88)

    local height = math.min(desiredHeight, maxHeight)
    local width = math.min(desiredWidth, maxWidth)

    height = math.max(height, 300)
    width = math.max(width, 420)

    height = math.min(height, viewport.Y - 20)
    width = math.min(width, viewport.X - 20)

    Main.Size = UDim2.fromOffset(width, height)
end

updateMainSize()

if workspace.CurrentCamera then
    State.Connections[#State.Connections + 1] =
        workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateMainSize)
end

-- HEADER

local Header = new("Frame", {
    Parent = Main,
    Size = UDim2.new(1, 0, 0, 61),
    BackgroundColor3 = COLORS.panel,
    BorderSizePixel = 0
})
round(Header, 16)

local Title = label(
    Header,
    "PSICOSENATICO • ESP RESEARCH",
    UDim2.new(1, -150, 0, 25),
    UDim2.fromOffset(18, 7),
    17
)

local Version = label(
    Header,
    "V1.1",
    UDim2.fromOffset(42, 17),
    UDim2.fromOffset(18, 34),
    9
)
Version.TextColor3 = COLORS.blue2

local Subtitle = label(
    Header,
    "ESP EXPERIMENTAL • DIAGNÓSTICO COMPACTO",
    UDim2.new(1, -190, 0, 17),
    UDim2.fromOffset(48, 34),
    8
)
Subtitle.TextColor3 = COLORS.sub

local Min = new("TextButton", {
    Parent = Header,
    Size = UDim2.fromOffset(38, 36),
    Position = UDim2.new(1, -88, 0, 12),
    Text = "—",
    BackgroundColor3 = COLORS.panel2,
    TextColor3 = COLORS.text,
    Font = Enum.Font.GothamBold,
    TextSize = 19,
    BorderSizePixel = 0
})
round(Min, 10)

local Close = new("TextButton", {
    Parent = Header,
    Size = UDim2.fromOffset(38, 36),
    Position = UDim2.new(1, -44, 0, 12),
    Text = "×",
    BackgroundColor3 = COLORS.red,
    TextColor3 = COLORS.text,
    Font = Enum.Font.GothamBold,
    TextSize = 21,
    BorderSizePixel = 0
})
round(Close, 10)

-- STATUS

local Status = label(
    Main,
    "ESP desligado • diagnóstico parado.",
    UDim2.new(1, -36, 0, 21),
    UDim2.fromOffset(18, 67),
    9
)
Status.TextColor3 = COLORS.sub

-- BOTÕES

local ESPButton = new("TextButton", {
    Parent = Main,
    Size = UDim2.new(0.22, -20, 0, 40),
    Position = UDim2.fromOffset(18, 91),
    Text = "ATIVAR ESP",
    BackgroundColor3 = COLORS.blue2,
    TextColor3 = COLORS.text,
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    BorderSizePixel = 0
})
round(ESPButton, 9)

local DiagnosticButton = new("TextButton", {
    Parent = Main,
    Size = UDim2.new(0.39, -19, 0, 40),
    Position = UDim2.new(0.22, 4, 0, 91),
    Text = "INICIAR DIAGNÓSTICO",
    BackgroundColor3 = COLORS.blue2,
    TextColor3 = COLORS.text,
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    BorderSizePixel = 0
})
round(DiagnosticButton, 9)

local ExportButton = new("TextButton", {
    Parent = Main,
    Size = UDim2.new(0.39, -21, 0, 40),
    Position = UDim2.new(0.61, 3, 0, 91),
    Text = "EXPORTAR DIAGNÓSTICO",
    BackgroundColor3 = COLORS.blue,
    TextColor3 = COLORS.text,
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    BorderSizePixel = 0
})
round(ExportButton, 9)

-- RESUMO

local Summary = label(
    Main,
    "",
    UDim2.new(1, -36, 0, 25),
    UDim2.fromOffset(18, 137),
    9
)
Summary.TextColor3 = COLORS.sub

-- ÁREA ROLÁVEL

local Viewer = new("ScrollingFrame", {
    Parent = Main,
    Position = UDim2.fromOffset(18, 168),
    Size = UDim2.new(1, -36, 1, -177),

    BackgroundColor3 = COLORS.panel,
    BackgroundTransparency = 0,
    BorderSizePixel = 0,

    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,

    ScrollBarThickness = 5,
    ScrollBarImageColor3 = COLORS.scroll,
    ScrollingDirection = Enum.ScrollingDirection.Y
})
round(Viewer, 10)

local ViewerText = new("TextLabel", {
    Parent = Viewer,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(10, 8),
    Size = UDim2.new(1, -20, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,

    Text = "",
    TextColor3 = COLORS.text,
    Font = Enum.Font.Code,
    TextSize = 9,

    TextWrapped = false,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top
})

-- MINI BUTTON

local Mini = new("TextButton", {
    Parent = Gui,
    Visible = false,

    Size = UDim2.fromOffset(58, 58),
    Position = UDim2.fromScale(0.07, 0.25),

    Text = "V1.1",
    BackgroundColor3 = COLORS.blue,
    TextColor3 = COLORS.text,

    Font = Enum.Font.GothamBold,
    TextSize = 13,

    BorderSizePixel = 0
})
round(Mini, 18)

-- ============================================================
-- DRAG
-- ============================================================

local function makeDraggable(target, handle)
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPos = nil

    local function update(input)
        local delta = input.Position - dragStart

        target.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end

    State.Connections[#State.Connections + 1] =
        handle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then

                dragging = true
                dragStart = input.Position
                startPos = target.Position

                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)

    State.Connections[#State.Connections + 1] =
        handle.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end)

    State.Connections[#State.Connections + 1] =
        UserInputService.InputChanged:Connect(function(input)
            if input == dragInput and dragging then
                update(input)
            end
        end)
end

makeDraggable(Main, Header)
makeDraggable(Mini, Mini)

-- ============================================================
-- PREVIEW
-- ============================================================

local function getObservedCount()
    local n = 0
    for _ in pairs(State.Observed) do n = n + 1 end
    return n
end

local function statusName()
    if State.DiagnosticEnabled then
        return "GRAVANDO"
    end
    return "PARADO"
end

local function updatePreview()
    local ally, enemy, unknown = countClassifications()

    Summary.Text = string.format(
        "ESP: %s   •   DIAGNÓSTICO: %s   •   BOTS: %d   •   A:%d I:%d ?: %d   •   ERROS: %d   •   %s",
        State.ESPEnabled and "ATIVO" or "OFF",
        statusName(),
        getObservedCount(),
        ally,
        enemy,
        unknown,
        State.ErrorCount,
        formatMB(State.EstimatedBytes)
    )

    local lines = {}

    lines[#lines + 1] = "══════════════════════════════════════════"
    lines[#lines + 1] = "PSICOSENATICO • ESP RESEARCH V1.1"
    lines[#lines + 1] = "══════════════════════════════════════════"
    lines[#lines + 1] = ""

    lines[#lines + 1] = "STATUS"
    lines[#lines + 1] = "  ESP: " .. (State.ESPEnabled and "ATIVO" or "DESLIGADO")
    lines[#lines + 1] = "  Diagnóstico: " .. statusName()
    lines[#lines + 1] = "  Bots observados: " .. tostring(getObservedCount())
    lines[#lines + 1] = "  ESPs ativos: " .. tostring(activeESPCount())
    lines[#lines + 1] = "  Eventos gravados: " .. tostring(#State.Events)
    lines[#lines + 1] = "  Erros: " .. tostring(State.ErrorCount)
    lines[#lines + 1] = "  Tamanho estimado: " .. formatMB(State.EstimatedBytes)
    lines[#lines + 1] = ""

    lines[#lines + 1] = "CLASSIFICAÇÃO ATUAL"
    lines[#lines + 1] = "  Aliados: " .. tostring(ally)
    lines[#lines + 1] = "  Inimigos: " .. tostring(enemy)
    lines[#lines + 1] = "  Desconhecidos: " .. tostring(unknown)
    lines[#lines + 1] = ""

    lines[#lines + 1] = "ÚLTIMOS EVENTOS"
    lines[#lines + 1] = "══════════════════════════════════════════"

    local startIndex = math.max(1, #State.LiveLogs - 120)

    for i = startIndex, #State.LiveLogs do
        local item = State.LiveLogs[i]

        lines[#lines + 1] = string.format(
            "[%.2f] %-24s %s",
            item.time or 0,
            tostring(item.type),
            tostring(item.message)
        )
    end

    ViewerText.Text = table.concat(lines, "\n")
end

-- ============================================================
-- CONTROLES
-- ============================================================

ESPButton.Activated:Connect(function()
    State.ESPEnabled = not State.ESPEnabled

    if State.ESPEnabled then
        ESPButton.Text = "DESATIVAR ESP"
        ESPButton.BackgroundColor3 = COLORS.blue2

        Status.Text = "ESP ativo • ALIADOS VERDES / INIMIGOS VERMELHOS • classificação por Team."
        Status.TextColor3 = COLORS.green

        appendLiveLog("ESP_ENABLED", "ESP experimental ativado.")

        ensureMonitoring()
        reclassifyAll("ESP_ENABLED")
    else
        ESPButton.Text = "ATIVAR ESP"
        ESPButton.BackgroundColor3 = COLORS.blue2

        Status.Text = State.DiagnosticEnabled
            and "ESP desligado • diagnóstico continua gravando."
            or "ESP desligado • diagnóstico parado."

        Status.TextColor3 = COLORS.sub

        appendLiveLog("ESP_DISABLED", "ESP experimental desativado.")
        removeAllESP("USER_DISABLED")
        restoreNativeHighlights(nil)
    end

    updatePreview()
end)

DiagnosticButton.Activated:Connect(function()
    if not State.DiagnosticEnabled then
        startDiagnostic()

        DiagnosticButton.Text = "PARAR DIAGNÓSTICO"
        Status.Text = State.ESPEnabled
            and "ESP ativo • diagnóstico gravando."
            or "Diagnóstico gravando • ESP desligado."

        Status.TextColor3 = COLORS.green
    else
        stopDiagnostic()

        DiagnosticButton.Text = "INICIAR DIAGNÓSTICO"
        Status.Text = "Diagnóstico parado • dados preservados para exportação."
        Status.TextColor3 = COLORS.sub
    end

    updatePreview()
end)

ExportButton.Activated:Connect(function()
    if not State.DiagnosticEverStarted then
        Status.Text = "Nenhum diagnóstico realizado. Inicie o diagnóstico primeiro."
        Status.TextColor3 = COLORS.yellow
        return
    end

    Status.Text = "Preparando diagnóstico ESP Research V1.1..."
    Status.TextColor3 = COLORS.sub

    local data, err = jsonExport()

    if not data then
        Status.Text = "Falha ao gerar JSON V1.1: " .. tostring(err)
        Status.TextColor3 = COLORS.red
        return
    end

    -- Tenta descarregar qualquer lote remoto pendente sem bloquear a exportação local.
    RemoteDiagnostic.forceFlush()

    local filename =
        "Psicosenatico_ESPResearch_V1_1_"
        .. tostring(game.PlaceId)
        .. "_"
        .. tostring(os.time())
        .. ".json"

    local exported = false
    local method = nil

    if typeof(writefile) == "function" then
        local ok = pcall(function()
            writefile(filename, data)
        end)

        if ok then
            exported = true
            method = "writefile"
        end
    end

    if not exported and typeof(setclipboard) == "function" then
        local ok = pcall(function()
            setclipboard(data)
        end)

        if ok then
            exported = true
            method = "clipboard"
        end
    end

    if exported then
        State.EstimatedBytes = #data

        if method == "writefile" then
            Status.Text = "✓ DIAGNÓSTICO V1.1 EXPORTADO COM SUCESSO: " .. filename
        else
            Status.Text = "✓ JSON V1.1 COPIADO PARA A ÁREA DE TRANSFERÊNCIA."
        end

        Status.TextColor3 = COLORS.green
    else
        Status.Text = "Não foi possível exportar: writefile/setclipboard indisponíveis."
        Status.TextColor3 = COLORS.red
    end

    updatePreview()
end)

Min.Activated:Connect(function()
    Main.Visible = false
    Mini.Visible = true
end)

Mini.Activated:Connect(function()
    Mini.Visible = false
    Main.Visible = true
end)

local function cleanup()
    if State.DiagnosticEnabled then
        RemoteDiagnostic.counter("events", #State.Events)
        RemoteDiagnostic.counter("errors", State.ErrorCount)
        RemoteDiagnostic.finish("interrupted", "Interface fechada durante o diagnóstico")
        State.DiagnosticEnabled = false
        State.DiagnosticEndUnix = unix()
    else
        RemoteDiagnostic.forceFlush()
    end

    State.ESPEnabled = false
    removeAllESP("GUI_CLOSED")
    restoreNativeHighlights(nil)

    for model in pairs(State.ModelConnections) do
        disconnectModelConnections(model)
    end

    disconnectSoldiersMonitoring()

    for _, connection in ipairs(State.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    State.Connections = {}

    pcall(function()
        Gui:Destroy()
    end)
end

Close.Activated:Connect(cleanup)

-- ============================================================
-- RECLASSIFICA SE O JOGADOR TROCAR DE EQUIPE
-- ============================================================

State.Connections[#State.Connections + 1] =
    LocalPlayer:GetPropertyChangedSignal("Team"):Connect(function()
        local team = select(1, getLocalTeam())

        addDiagnosticEvent(
            "PLAYER_TEAM_CHANGED",
            nil,
            { newTeam = team },
            "Equipe do jogador mudou para " .. tostring(team)
        )

        reclassifyAll("PLAYER_TEAM_CHANGED")
        updatePreview()
    end)

-- ============================================================
-- LOOP SOMENTE DE UI
-- Não cria snapshots periódicos e não faz JSONEncode completo.
-- ============================================================

task.spawn(function()
    while Gui.Parent do
        pcall(updatePreview)
        task.wait(1)
    end
end)

appendLiveLog("SYSTEM", "ESP Research V1 inicializado.")
appendLiveLog("SYSTEM", "Aguardando ativação do ESP ou início do diagnóstico.")
updatePreview()
