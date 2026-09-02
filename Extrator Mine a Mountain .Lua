--[[
    Mine a Mountain 2 — Capturador Luarmor Runtime V2 UI

    FLUXO
      1) Entre no jogo.
      2) Execute ESTE capturador.
      3) Toque em "Iniciar análise".
      4) Execute o script ORIGINAL Mine a Mountain 2.
      5) Faça a autenticação normalmente e use as funções desejadas.
      6) Volte ao capturador e toque em "Finalizar e salvar".
      7) Envie os arquivos MAM2_UI_Sxx_* gerados.

    CONTROLE DA COLETA
      - Antes de "Iniciar análise": os hooks existem, mas NÃO gravam dados.
      - Durante a análise: loadstring / HttpGet / request são registrados.
      - Após "Finalizar e salvar": a coleta é imediatamente desativada.
      - O botão Finalizar cria automaticamente:
            MAM2_UI_Sxx_FINAL.txt
        além dos arquivos brutos gerados durante aquela sessão.

    INTERFACE
      - Simples.
      - Compatível com toque.
      - Arrastável pela barra superior.
      - Não executa o Mine a Mountain 2 por conta própria.
]]

print("[MAM2-UI] Inicializando capturador...")

-- ============================================================
-- Serviços
-- ============================================================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- Ambiente / APIs do executor
-- ============================================================
local function getEnv()
    local env = nil

    pcall(function()
        if type(getgenv) == "function" then
            local e = getgenv()
            if type(e) == "table" then
                env = e
            end
        end
    end)

    if type(env) ~= "table" and type(_G) == "table" then
        env = _G
    end

    return type(env) == "table" and env or {}
end

local ENV = getEnv()

local function getApi(name)
    local value = nil

    pcall(function()
        value = ENV[name]
    end)

    if value ~= nil then
        return value
    end

    pcall(function()
        if type(_G) == "table" then
            value = _G[name]
        end
    end)

    return value
end

local writefileFn = getApi("writefile")
local readfileFn = getApi("readfile")
local isfileFn = getApi("isfile")
local hookfunctionFn = getApi("hookfunction")
local loadstringFn = getApi("loadstring")

-- ============================================================
-- Estado persistente desta execução
-- ============================================================
local STATE_KEY = "__MAM2_LUARMOR_CAPTURE_UI_V2"

local oldState = nil
pcall(function()
    oldState = ENV[STATE_KEY]
end)

-- Se esta mesma V2 já estava aberta, apenas desativa a coleta anterior
-- e remove a interface antiga. Os hooks continuam apontando para o
-- mesmo objeto de estado e serão reaproveitados quando possível.
if type(oldState) == "table" then
    oldState.active = false

    pcall(function()
        if oldState.gui then
            oldState.gui:Destroy()
        end
    end)
end

local state = {
    active = false,
    finalized = false,
    hooksInstalled = false,

    session = 0,
    sessionStartClock = nil,
    sessionEndClock = nil,

    loadCount = 0,
    httpGetCount = 0,
    requestCount = 0,

    loadHookMethod = "none",
    httpGetHookMethod = "none",
    requestHooks = 0,

    files = {},
    events = {},

    gui = nil,
}

pcall(function()
    ENV[STATE_KEY] = state
end)

-- ============================================================
-- Arquivos / log
-- ============================================================
local function safeWrite(name, data)
    if type(writefileFn) ~= "function" then
        return false, "writefile indisponível"
    end

    local ok, err = pcall(function()
        writefileFn(name, tostring(data or ""))
    end)

    if ok then
        return true
    end

    return false, tostring(err)
end

local function safeRead(name)
    if type(readfileFn) ~= "function" then
        return nil
    end

    local ok, value = pcall(function()
        if type(isfileFn) == "function" then
            if not isfileFn(name) then
                return nil
            end
        end

        return readfileFn(name)
    end)

    if ok and type(value) == "string" then
        return value
    end

    return nil
end

local function rollingHash(s)
    s = tostring(s or "")
    local h = 2166136261

    for i = 1, #s do
        h = (h * 131 + string.byte(s, i)) % 4294967296
    end

    return string.format("%08X", h)
end

local function redact(text)
    text = tostring(text or "")

    local patterns = {
        {"([?&][Kk][Ee][Yy]=)[^&%s]+", "%1<REDACTED>"},
        {"([?&][Tt][Oo][Kk][Ee][Nn]=)[^&%s]+", "%1<REDACTED>"},
        {"([?&][Ll][Ii][Cc][Ee][Nn][Ss][Ee]=)[^&%s]+", "%1<REDACTED>"},
        {"([?&][Aa][Uu][Tt][Hh]=)[^&%s]+", "%1<REDACTED>"},
        {'("[Kk][Ee][Yy]"%s*:%s*")[^"]+(")', '%1<REDACTED>%2'},
        {'("[Tt][Oo][Kk][Ee][Nn]"%s*:%s*")[^"]+(")', '%1<REDACTED>%2'},
        {'("[Ll][Ii][Cc][Ee][Nn][Ss][Ee]"%s*:%s*")[^"]+(")', '%1<REDACTED>%2'},
        {'("[Aa][Uu][Tt][Hh]"%s*:%s*")[^"]+(")', '%1<REDACTED>%2'},
    }

    for _, item in ipairs(patterns) do
        text = text:gsub(item[1], item[2])
    end

    return text
end

local function sessionPrefix()
    return string.format("MAM2_UI_S%02d", state.session)
end

local function rememberFile(name)
    state.files[#state.files + 1] = name
end

local function addEvent(text)
    text = tostring(text)
    state.events[#state.events + 1] = text
    print("[MAM2-UI] " .. text)
end

local function saveTracked(name, data)
    local ok, err = safeWrite(name, data)

    if ok then
        rememberFile(name)
    else
        addEvent("Falha ao salvar " .. tostring(name) .. ": " .. tostring(err))
    end

    return ok
end

-- ============================================================
-- Capturas (só gravam quando state.active == true)
-- ============================================================
local function captureLoadstring(source, chunkname, method)
    if not state.active or type(source) ~= "string" then
        return
    end

    state.loadCount = state.loadCount + 1

    local prefix = sessionPrefix()
    local rawName = string.format(
        "%s_LS_%03d_raw.txt",
        prefix,
        state.loadCount
    )

    local metaName = string.format(
        "%s_LS_%03d_meta.txt",
        prefix,
        state.loadCount
    )

    saveTracked(rawName, source)

    saveTracked(metaName, table.concat({
        "type=loadstring",
        "method=" .. tostring(method or "unknown"),
        "chunkname=" .. redact(chunkname or "<nil>"),
        "bytes=" .. tostring(#source),
        "hash=" .. rollingHash(source),
    }, "\n"))

    addEvent(string.format(
        "LOADSTRING #%03d capturado (%d bytes)",
        state.loadCount,
        #source
    ))
end

local function captureHttpGet(url, body)
    if not state.active or type(body) ~= "string" then
        return
    end

    state.httpGetCount = state.httpGetCount + 1

    local prefix = sessionPrefix()
    local bodyName = string.format(
        "%s_HTTPGET_%03d_body.txt",
        prefix,
        state.httpGetCount
    )

    local metaName = string.format(
        "%s_HTTPGET_%03d_meta.txt",
        prefix,
        state.httpGetCount
    )

    saveTracked(bodyName, body)

    saveTracked(metaName, table.concat({
        "type=HttpGet",
        "url=" .. redact(url or "<unknown>"),
        "bytes=" .. tostring(#body),
        "hash=" .. rollingHash(body),
    }, "\n"))

    addEvent(string.format(
        "HTTPGET #%03d capturado (%d bytes)",
        state.httpGetCount,
        #body
    ))
end

local function requestUrl(arg)
    if type(arg) == "string" then
        return arg
    end

    if type(arg) == "table" then
        return arg.Url or arg.URL or arg.url
    end

    return nil
end

local function requestMethod(arg)
    if type(arg) == "table" then
        return arg.Method or arg.method
    end

    return nil
end

local function captureRequest(arg, response, label)
    if not state.active then
        return
    end

    state.requestCount = state.requestCount + 1

    local prefix = sessionPrefix()
    local metaName = string.format(
        "%s_REQ_%03d_meta.txt",
        prefix,
        state.requestCount
    )

    local responseName = string.format(
        "%s_REQ_%03d_response.txt",
        prefix,
        state.requestCount
    )

    local body = nil
    local status = nil

    if type(response) == "table" then
        body = response.Body or response.body
        status =
            response.StatusCode
            or response.Status
            or response.status

    elseif type(response) == "string" then
        body = response
    end

    saveTracked(metaName, table.concat({
        "type=request",
        "label=" .. tostring(label),
        "method=" .. tostring(requestMethod(arg) or "<unknown>"),
        "url=" .. redact(requestUrl(arg) or "<unknown>"),
        "status=" .. tostring(status or "<unknown>"),
        "response_bytes=" ..
            tostring(type(body) == "string" and #body or 0),
    }, "\n"))

    -- Não salva o BODY enviado pelo usuário.
    -- Isso reduz o risco de gravar a chave premium.
    if type(body) == "string" and #body > 0 then
        saveTracked(responseName, body)
    end

    addEvent(string.format(
        "REQUEST #%03d capturado (%d bytes de resposta)",
        state.requestCount,
        type(body) == "string" and #body or 0
    ))
end

-- ============================================================
-- Instalação dos hooks
-- ============================================================
local function installHooks()
    if state.hooksInstalled then
        return true
    end

    local anyHook = false

    -- --------------------------------------------------------
    -- loadstring
    -- --------------------------------------------------------
    if type(loadstringFn) == "function"
    and type(hookfunctionFn) == "function" then

        local previous = nil

        local ok, result = pcall(function()
            previous = hookfunctionFn(
                loadstringFn,
                function(source, chunkname, ...)
                    pcall(
                        captureLoadstring,
                        source,
                        chunkname,
                        "hookfunction"
                    )

                    return previous(source, chunkname, ...)
                end
            )

            return previous
        end)

        if ok and type(result) == "function" then
            state.loadHookMethod = "hookfunction"
            anyHook = true
        end
    end

    -- Fallback global de loadstring
    if state.loadHookMethod == "none"
    and type(loadstringFn) == "function" then

        local wrapper = function(source, chunkname, ...)
            pcall(
                captureLoadstring,
                source,
                chunkname,
                "global-wrapper"
            )

            return loadstringFn(source, chunkname, ...)
        end

        local changed = false

        pcall(function()
            if type(getgenv) == "function" then
                local env = getgenv()
                env.loadstring = wrapper
                changed = (env.loadstring == wrapper)
            end
        end)

        pcall(function()
            if type(_G) == "table" then
                _G.loadstring = wrapper
                changed = changed or (_G.loadstring == wrapper)
            end
        end)

        if changed then
            state.loadHookMethod = "global-wrapper"
            anyHook = true
        end
    end

    -- --------------------------------------------------------
    -- game:HttpGet
    -- --------------------------------------------------------
    local httpGetFn = nil

    pcall(function()
        httpGetFn = game.HttpGet
    end)

    if type(httpGetFn) == "function"
    and type(hookfunctionFn) == "function" then

        local previousHttpGet = nil

        local ok, result = pcall(function()
            previousHttpGet = hookfunctionFn(
                httpGetFn,
                function(self, url, ...)
                    local body = previousHttpGet(self, url, ...)

                    pcall(captureHttpGet, url, body)

                    return body
                end
            )

            return previousHttpGet
        end)

        if ok and type(result) == "function" then
            state.httpGetHookMethod = "hookfunction"
            anyHook = true
        end
    end

    -- --------------------------------------------------------
    -- request / http_request / syn.request
    -- --------------------------------------------------------
    local hookedFunctions = {}

    local function alreadyHooked(fn)
        for _, old in ipairs(hookedFunctions) do
            if old == fn then
                return true
            end
        end
        return false
    end

    local function hookRequest(fn, label)
        if type(fn) ~= "function"
        or type(hookfunctionFn) ~= "function"
        or alreadyHooked(fn) then
            return false
        end

        local previous = nil

        local ok, result = pcall(function()
            previous = hookfunctionFn(
                fn,
                function(arg, ...)
                    local response = previous(arg, ...)

                    pcall(
                        captureRequest,
                        arg,
                        response,
                        label
                    )

                    return response
                end
            )

            return previous
        end)

        if ok and type(result) == "function" then
            hookedFunctions[#hookedFunctions + 1] = fn
            state.requestHooks = state.requestHooks + 1
            anyHook = true
            return true
        end

        return false
    end

    hookRequest(getApi("request"), "request")
    hookRequest(getApi("http_request"), "http_request")

    pcall(function()
        local synTable = getApi("syn")
        if type(synTable) == "table" then
            hookRequest(synTable.request, "syn.request")
        end
    end)

    state.hooksInstalled = true

    return anyHook
end

installHooks()

-- ============================================================
-- Controle de sessão
-- ============================================================
local function resetSessionData()
    state.loadCount = 0
    state.httpGetCount = 0
    state.requestCount = 0
    state.files = {}
    state.events = {}
    state.sessionStartClock = nil
    state.sessionEndClock = nil
    state.finalized = false
end

local function startSession()
    if state.active then
        return false, "A análise já está em andamento."
    end

    state.session = state.session + 1
    resetSessionData()

    state.sessionStartClock = os.clock()
    state.active = true
    state.finalized = false

    addEvent("ANÁLISE INICIADA")
    addEvent("Execute agora o script ORIGINAL Mine a Mountain 2.")

    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "MAM2",
            Text = "Análise iniciada.",
            Duration = 4,
        })
    end)

    return true
end

local function finalReportText()
    local duration = 0

    if state.sessionStartClock and state.sessionEndClock then
        duration = math.max(
            0,
            state.sessionEndClock - state.sessionStartClock
        )
    end

    local lines = {
        "Mine a Mountain 2 — Captura finalizada",
        "========================================",
        "",
        "session=" .. tostring(state.session),
        "duration_seconds=" .. string.format("%.2f", duration),
        "load_hook=" .. tostring(state.loadHookMethod),
        "httpget_hook=" .. tostring(state.httpGetHookMethod),
        "request_hooks=" .. tostring(state.requestHooks),
        "",
        "loadstrings_captured=" .. tostring(state.loadCount),
        "httpgets_captured=" .. tostring(state.httpGetCount),
        "requests_captured=" .. tostring(state.requestCount),
        "",
        "ARQUIVOS GERADOS",
        "----------------",
    }

    for _, name in ipairs(state.files) do
        lines[#lines + 1] = name
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "EVENTOS"
    lines[#lines + 1] = "-------"

    for _, event in ipairs(state.events) do
        lines[#lines + 1] = event
    end

    return table.concat(lines, "\n")
end

local function finalizeSession()
    if not state.active then
        return false, "Nenhuma análise está em andamento."
    end

    -- Primeiro desativa: nada novo é coletado a partir daqui.
    state.active = false
    state.sessionEndClock = os.clock()
    state.finalized = true

    addEvent("ANÁLISE FINALIZADA")

    local finalName =
        string.format("MAM2_UI_S%02d_FINAL.txt", state.session)

    local ok, err = safeWrite(
        finalName,
        finalReportText()
    )

    if ok then
        print("[MAM2-UI] Arquivo final salvo: " .. finalName)

        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = "MAM2",
                Text = "Análise finalizada e arquivo salvo.",
                Duration = 6,
            })
        end)

        return true, finalName
    end

    return false, tostring(err)
end

-- ============================================================
-- Interface
-- ============================================================
local guiParent = nil

pcall(function()
    if type(gethui) == "function" then
        guiParent = gethui()
    end
end)

if not guiParent then
    pcall(function()
        guiParent = game:GetService("CoreGui")
    end)
end

if not guiParent and LocalPlayer then
    guiParent = LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

local function round(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 10)
    c.Parent = obj
end

local function makeLabel(parent, text, size, pos, textSize)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = size
    label.Position = pos
    label.Font = Enum.Font.Gotham
    label.Text = text
    label.TextSize = textSize or 14
    label.TextColor3 = Color3.fromRGB(235, 239, 246)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = parent
    return label
end

local function makeButton(parent, text, size, pos)
    local button = Instance.new("TextButton")
    button.BackgroundColor3 = Color3.fromRGB(30, 47, 71)
    button.BorderSizePixel = 0
    button.Size = size
    button.Position = pos
    button.Font = Enum.Font.GothamSemibold
    button.Text = text
    button.TextSize = 14
    button.TextColor3 = Color3.fromRGB(245, 248, 252)
    button.AutoButtonColor = true
    button.Parent = parent
    round(button, 9)
    return button
end

if guiParent then
    local gui = Instance.new("ScreenGui")
    gui.Name = "MAM2CaptureUIV2"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = guiParent

    state.gui = gui

    local frame = Instance.new("Frame")
    frame.Name = "Main"
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.fromScale(0.5, 0.5)
    frame.Size = UDim2.new(0, 330, 0, 190)
    frame.BackgroundColor3 = Color3.fromRGB(15, 22, 33)
    frame.BorderSizePixel = 0
    frame.Parent = gui
    round(frame, 12)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(63, 96, 137)
    stroke.Transparency = 0.25
    stroke.Thickness = 1
    stroke.Parent = frame

    -- Barra superior = área de arraste
    local header = Instance.new("Frame")
    header.Name = "DragBar"
    header.Size = UDim2.new(1, 0, 0, 42)
    header.BackgroundColor3 = Color3.fromRGB(21, 32, 48)
    header.BorderSizePixel = 0
    header.Active = true
    header.Parent = frame
    round(header, 12)

    -- Cobre apenas os cantos inferiores arredondados do header
    local headerFix = Instance.new("Frame")
    headerFix.Size = UDim2.new(1, 0, 0, 12)
    headerFix.Position = UDim2.new(0, 0, 1, -12)
    headerFix.BackgroundColor3 = header.BackgroundColor3
    headerFix.BorderSizePixel = 0
    headerFix.Parent = header

    local title = makeLabel(
        header,
        "Mine a Mountain 2 | Captura",
        UDim2.new(1, -24, 1, 0),
        UDim2.new(0, 12, 0, 0),
        15
    )
    title.Font = Enum.Font.GothamBold

    local status = makeLabel(
        frame,
        "Status: PARADO",
        UDim2.new(1, -24, 0, 24),
        UDim2.new(0, 12, 0, 54),
        13
    )

    local counters = makeLabel(
        frame,
        "LS: 0   HTTP: 0   REQ: 0",
        UDim2.new(1, -24, 0, 22),
        UDim2.new(0, 12, 0, 78),
        12
    )
    counters.TextColor3 = Color3.fromRGB(174, 188, 207)

    local startButton = makeButton(
        frame,
        "Iniciar análise",
        UDim2.new(1, -24, 0, 36),
        UDim2.new(0, 12, 0, 108)
    )

    local finishButton = makeButton(
        frame,
        "Finalizar e salvar",
        UDim2.new(1, -24, 0, 36),
        UDim2.new(0, 12, 0, 150)
    )

    -- --------------------------------------------------------
    -- Drag por mouse/toque na barra superior
    -- --------------------------------------------------------
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPosition = nil

    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then

            dragging = true
            dragStart = input.Position
            startPosition = frame.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    header.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging
        and input == dragInput
        and dragStart
        and startPosition then

            local delta = input.Position - dragStart

            frame.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end)

    -- --------------------------------------------------------
    -- Botões
    -- --------------------------------------------------------
    startButton.Activated:Connect(function()
        local ok, message = startSession()

        if ok then
            status.Text =
                "Status: ANALISANDO • Sessão "
                .. tostring(state.session)

            startButton.Text = "Análise em andamento"
            finishButton.Text = "Finalizar e salvar"
        else
            status.Text = "Status: " .. tostring(message)
        end
    end)

    finishButton.Activated:Connect(function()
        local ok, message = finalizeSession()

        if ok then
            status.Text = "Status: FINALIZADO E SALVO"
            startButton.Text = "Iniciar nova análise"
            finishButton.Text = "Arquivo salvo"
        else
            status.Text = "Status: " .. tostring(message)
        end
    end)

    -- Atualiza os contadores visualmente.
    task.spawn(function()
        while gui.Parent do
            counters.Text = string.format(
                "LS: %d   HTTP: %d   REQ: %d",
                state.loadCount,
                state.httpGetCount,
                state.requestCount
            )

            task.wait(0.25)
        end
    end)
end

-- ============================================================
-- Diagnóstico das capacidades
-- ============================================================
local capabilitiesName = "MAM2_UI_CAPABILITIES.txt"

safeWrite(capabilitiesName, table.concat({
    "Mine a Mountain 2 — Capturador Luarmor Runtime V2 UI",
    "loadstring=" .. tostring(type(loadstringFn) == "function"),
    "hookfunction=" .. tostring(type(hookfunctionFn) == "function"),
    "writefile=" .. tostring(type(writefileFn) == "function"),
    "readfile=" .. tostring(type(readfileFn) == "function"),
    "isfile=" .. tostring(type(isfileFn) == "function"),
    "load_hook=" .. tostring(state.loadHookMethod),
    "httpget_hook=" .. tostring(state.httpGetHookMethod),
    "request_hooks=" .. tostring(state.requestHooks),
}, "\n"))

print("[MAM2-UI] CAPTURADOR PRONTO.")
print("[MAM2-UI] Toque em 'Iniciar análise' antes de executar o script original.")

pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title = "MAM2 Capturador",
        Text = "Pronto. Toque em Iniciar análise.",
        Duration = 5,
    })
end)
