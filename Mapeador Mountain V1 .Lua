print("[MAM2-RECON] INICIO")

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- APIs do executor
-- ============================================================
local function envTable()
    local out = nil

    pcall(function()
        if type(getgenv) == "function" then
            local e = getgenv()
            if type(e) == "table" then
                out = e
            end
        end
    end)

    if type(out) ~= "table" and type(_G) == "table" then
        out = _G
    end

    return type(out) == "table" and out or {}
end

local ENV = envTable()

local function api(name)
    local v = nil

    pcall(function()
        v = ENV[name]
    end)

    if v ~= nil then
        return v
    end

    pcall(function()
        if type(_G) == "table" then
            v = _G[name]
        end
    end)

    return v
end

local writefileFn = api("writefile")
local isfileFn = api("isfile")
local setclipboardFn = api("setclipboard")
local hookmetamethodFn = api("hookmetamethod")
local getnamecallmethodFn = api("getnamecallmethod")
local newcclosureFn = api("newcclosure")
local hookfunctionFn = api("hookfunction")
local getgcFn = api("getgc")
local getconstantsFn = api("getconstants")
local getupvaluesFn = api("getupvalues")

-- ============================================================
-- Estado
-- ============================================================
local STATE_KEY = "__MAM2_RECON_RUNTIME_V1"

local previousState = nil
pcall(function()
    previousState = ENV[STATE_KEY]
end)

if type(previousState) == "table" then
    previousState.active = false
    pcall(function()
        if previousState.gui then
            previousState.gui:Destroy()
        end
    end)
end

local state = {
    active = false,
    finalized = false,
    inspecting = false,

    marker = "GERAL",

    remoteCount = 0,
    promptCount = 0,
    clickCount = 0,
    internalTables = 0,
    internalFunctions = 0,

    lines = {},
    gui = nil,

    maxRemoteEvents = 6000,
    maxLines = 30000,
}

pcall(function()
    ENV[STATE_KEY] = state
end)

local function push(text)
    if #state.lines >= state.maxLines then
        return
    end

    state.lines[#state.lines + 1] = tostring(text)
end

local function stamp()
    return string.format("%.3f", os.clock())
end

local function mark(text)
    state.marker = tostring(text)
    push("")
    push("============================================================")
    push("MARKER [" .. stamp() .. "] " .. state.marker)
    push("============================================================")
    print("[MAM2-RECON] MARKER: " .. state.marker)
end

-- ============================================================
-- Sanitização / serialização
-- ============================================================
local function sensitiveString(s)
    local lower = string.lower(s)

    return lower:find("premium", 1, true) ~= nil
        or lower:find("license", 1, true) ~= nil
        or lower:find("authorization", 1, true) ~= nil
        or lower:find("bearer ", 1, true) ~= nil
        or lower:find("session", 1, true) ~= nil
        or lower:find("token", 1, true) ~= nil
        or lower:find("key=", 1, true) ~= nil
end

local function cleanString(s)
    s = tostring(s or "")

    if sensitiveString(s) then
        return "<REDACTED_SENSITIVE_STRING>"
    end

    if #s > 180 then
        return string.format(
            "<LONG_STRING len=%d prefix=%q>",
            #s,
            string.sub(s, 1, 60)
        )
    end

    return s
end

local function safeFullName(inst)
    local ok, result = pcall(function()
        return inst:GetFullName()
    end)

    if ok then
        return result
    end

    return tostring(inst)
end

local function serialize(value, depth, seen)
    depth = depth or 0
    seen = seen or {}

    if depth > 3 then
        return "<max-depth>"
    end

    local kind = typeof(value)

    if kind == "nil" then
        return "nil"
    elseif kind == "boolean" or kind == "number" then
        return tostring(value)
    elseif kind == "string" then
        return string.format("%q", cleanString(value))
    elseif kind == "Instance" then
        local class = "Instance"
        local name = "?"

        pcall(function()
            class = value.ClassName
            name = value.Name
        end)

        return string.format(
            "<%s %s | %s>",
            class,
            cleanString(name),
            cleanString(safeFullName(value))
        )
    elseif kind == "Vector3" then
        return string.format(
            "Vector3(%.4f, %.4f, %.4f)",
            value.X,
            value.Y,
            value.Z
        )
    elseif kind == "Vector2" then
        return string.format(
            "Vector2(%.4f, %.4f)",
            value.X,
            value.Y
        )
    elseif kind == "CFrame" then
        local c = {value:GetComponents()}
        local pieces = {}

        for i = 1, #c do
            pieces[i] = string.format("%.5f", c[i])
        end

        return "CFrame(" .. table.concat(pieces, ", ") .. ")"
    elseif kind == "Color3" then
        return string.format(
            "Color3(%.4f, %.4f, %.4f)",
            value.R,
            value.G,
            value.B
        )
    elseif kind == "EnumItem" then
        return tostring(value)
    elseif kind == "function" then
        return "<function>"
    elseif kind == "RBXScriptConnection" then
        return "<connection>"
    elseif kind == "table" then
        if seen[value] then
            return "<cycle>"
        end

        seen[value] = true

        local out = {}
        local n = 0

        for k, v in pairs(value) do
            n = n + 1

            if n > 24 then
                out[#out + 1] = "..."
                break
            end

            out[#out + 1] =
                "[" .. serialize(k, depth + 1, seen) .. "]="
                .. serialize(v, depth + 1, seen)
        end

        seen[value] = nil

        return "{" .. table.concat(out, ", ") .. "}"
    end

    return "<" .. kind .. ":" .. cleanString(tostring(value)) .. ">"
end

local function packArgs(...)
    local args = table.pack(...)
    local out = {}

    for i = 1, args.n do
        out[i] = serialize(args[i], 0, {})
    end

    return table.concat(out, ", ")
end

-- ============================================================
-- Registro de chamadas Roblox remotas
-- ============================================================
local remoteHookOK = false

if type(hookmetamethodFn) == "function"
and type(getnamecallmethodFn) == "function" then

    local oldNamecall = nil

    local handler = function(self, ...)
        local method = nil

        pcall(function()
            method = getnamecallmethodFn()
        end)

        local capture =
            state.active
            and state.remoteCount < state.maxRemoteEvents
            and (
                method == "FireServer"
                or method == "InvokeServer"
            )

        local isRemote = false

        if capture and typeof(self) == "Instance" then
            pcall(function()
                isRemote =
                    self:IsA("RemoteEvent")
                    or self:IsA("RemoteFunction")
            end)
        end

        if capture and isRemote then
            state.remoteCount = state.remoteCount + 1

            local before = string.format(
                "[REMOTE %04d][%s][%s] %s:%s(%s)",
                state.remoteCount,
                stamp(),
                state.marker,
                cleanString(safeFullName(self)),
                tostring(method),
                packArgs(...)
            )

            push(before)
        end

        if method == "InvokeServer" then
            local results = table.pack(oldNamecall(self, ...))

            if capture and isRemote then
                local rendered = {}

                for i = 1, results.n do
                    rendered[i] = serialize(results[i], 0, {})
                end

                push(
                    string.format(
                        "[RETURN][%s] %s",
                        state.marker,
                        table.concat(rendered, ", ")
                    )
                )
            end

            return table.unpack(results, 1, results.n)
        end

        return oldNamecall(self, ...)
    end

    if type(newcclosureFn) == "function" then
        handler = newcclosureFn(handler)
    end

    local ok, result = pcall(function()
        oldNamecall = hookmetamethodFn(game, "__namecall", handler)
        return oldNamecall
    end)

    if ok and type(result) == "function" then
        remoteHookOK = true
    end
end

-- ============================================================
-- fireproximityprompt
-- ============================================================
local firePromptFn = api("fireproximityprompt")

if type(firePromptFn) == "function"
and type(hookfunctionFn) == "function" then

    local oldFirePrompt = nil

    pcall(function()
        oldFirePrompt = hookfunctionFn(
            firePromptFn,
            function(prompt, ...)
                if state.active
                and typeof(prompt) == "Instance" then

                    state.promptCount = state.promptCount + 1

                    local actionText = ""
                    local objectText = ""

                    pcall(function()
                        actionText = prompt.ActionText
                        objectText = prompt.ObjectText
                    end)

                    push(string.format(
                        "[PROMPT %04d][%s][%s] %s | Action=%q | Object=%q",
                        state.promptCount,
                        stamp(),
                        state.marker,
                        cleanString(safeFullName(prompt)),
                        cleanString(actionText),
                        cleanString(objectText)
                    ))
                end

                return oldFirePrompt(prompt, ...)
            end
        )
    end)
end

-- ============================================================
-- fireclickdetector
-- ============================================================
local fireClickFn = api("fireclickdetector")

if type(fireClickFn) == "function"
and type(hookfunctionFn) == "function" then

    local oldFireClick = nil

    pcall(function()
        oldFireClick = hookfunctionFn(
            fireClickFn,
            function(detector, ...)
                if state.active
                and typeof(detector) == "Instance" then

                    state.clickCount = state.clickCount + 1

                    push(string.format(
                        "[CLICK %04d][%s][%s] %s args=(%s)",
                        state.clickCount,
                        stamp(),
                        state.marker,
                        cleanString(safeFullName(detector)),
                        packArgs(...)
                    ))
                end

                return oldFireClick(detector, ...)
            end
        )
    end)
end

-- ============================================================
-- Snapshot de Toggles / Options
-- ============================================================
local function dumpObjectMap(title, map)
    push("")
    push("---- " .. title .. " ----")

    if type(map) ~= "table" then
        push("<não encontrado>")
        return
    end

    local keys = {}

    for key in pairs(map) do
        keys[#keys + 1] = tostring(key)
    end

    table.sort(keys)

    for _, key in ipairs(keys) do
        local obj = map[key]
        local value = nil
        local typ = nil

        pcall(function()
            value = obj.Value
            typ = obj.Type
        end)

        push(string.format(
            "%s | type=%s | value=%s",
            cleanString(key),
            tostring(typ or typeof(obj)),
            serialize(value, 0, {})
        ))
    end
end

-- ============================================================
-- Inspeção de internos
-- ============================================================
local TARGET_KEYS = {
    "boulderRoots",
    "equipPick",
    "swing",
    "swingGap",
    "pickTarget",
    "boulderHealth",
    "boulderKind",
    "grabCrystal",
    "crystalPrompt",
    "backpackFree",
    "beginLoot",
    "runAutoPlacerStep",
    "runAutoPlacerBestStep",
    "runAutoPlaceRunesStep",
    "nearStep",
    "pickupStep",
    "applyPivot",
    "requestStream",
    "setNoclip",
    "glideStop",
    "buildMineCells",
    "visibleAnchor",
    "coreSpot",
    "anchorSpot",
}

local CONSTANT_NEEDLES = {
    "MinedHP",
    "Collected",
    "No pickaxe",
    "Breaking crystal",
    "Mining surface",
    "Boulder",
    "AutoPickup",
    "boulderFarm",
    "No boulders",
    "Fortune Rune",
    "Selling",
}

local function constantsMatch(constants)
    if type(constants) ~= "table" then
        return false
    end

    for _, constant in pairs(constants) do
        if type(constant) == "string" then
            for _, needle in ipairs(CONSTANT_NEEDLES) do
                if string.find(
                    string.lower(constant),
                    string.lower(needle),
                    1,
                    true
                ) then
                    return true
                end
            end
        end
    end

    return false
end

local function dumpFunctionDetails(label, fn)
    push("")
    push("[FUNCTION] " .. cleanString(label))

    if type(getconstantsFn) == "function" then
        local ok, constants = pcall(getconstantsFn, fn)

        if ok and type(constants) == "table" then
            local rendered = {}
            local count = 0

            for i, value in pairs(constants) do
                count = count + 1

                if count > 100 then
                    rendered[#rendered + 1] = "..."
                    break
                end

                rendered[#rendered + 1] =
                    tostring(i) .. "=" .. serialize(value, 0, {})
            end

            push("  constants: " .. table.concat(rendered, " | "))
        end
    end

    if type(getupvaluesFn) == "function" then
        local ok, upvalues = pcall(getupvaluesFn, fn)

        if ok then
            push("  upvalues: " .. serialize(upvalues, 0, {}))
        end
    end

    pcall(function()
        if debug and debug.info then
            push(
                "  debug.info: "
                .. tostring(debug.info(fn, "sln"))
            )
        end
    end)
end

local function scanRemotesIn(root, label)
    push("")
    push("---- REMOTES VISÍVEIS EM " .. label .. " ----")

    local count = 0
    local ok, descendants = pcall(function()
        return root:GetDescendants()
    end)

    if not ok or type(descendants) ~= "table" then
        push("<falha ao listar>")
        return
    end

    for _, inst in ipairs(descendants) do
        local good = false

        pcall(function()
            good =
                inst:IsA("RemoteEvent")
                or inst:IsA("RemoteFunction")
        end)

        if good then
            count = count + 1
            push(
                string.format(
                    "%03d | %s | %s",
                    count,
                    inst.ClassName,
                    cleanString(safeFullName(inst))
                )
            )

            if count >= 500 then
                push("<limite de 500 remotes atingido>")
                break
            end
        end
    end

    if count == 0 then
        push("<nenhum remote visível>")
    end
end

local function inspectInternals()
    if state.inspecting then
        return
    end

    state.inspecting = true

    push("")
    push("############################################################")
    push("INSPEÇÃO INTERNA [" .. stamp() .. "]")
    push("############################################################")

    local env = envTable()

    dumpObjectMap("TOGGLES", env.Toggles)
    dumpObjectMap("OPTIONS", env.Options)

    scanRemotesIn(ReplicatedStorage, "ReplicatedStorage")

    if type(getgcFn) ~= "function" then
        push("")
        push("getgc indisponível neste executor.")
        state.inspecting = false
        return
    end

    local okGC, objects = pcall(getgcFn, true)

    if not okGC or type(objects) ~= "table" then
        push("getgc(true) falhou.")
        state.inspecting = false
        return
    end

    push("")
    push("---- TABELAS INTERNAS CANDIDATAS ----")

    local tableCandidates = 0
    local functionCandidates = 0

    for index, object in ipairs(objects) do
        if index % 250 == 0 then
            task.wait()
        end

        if type(object) == "table" then
            local hits = {}

            for _, key in ipairs(TARGET_KEYS) do
                local value = rawget(object, key)

                if value ~= nil then
                    hits[#hits + 1] = key
                end
            end

            if #hits >= 3 then
                tableCandidates = tableCandidates + 1
                state.internalTables = state.internalTables + 1

                push("")
                push(string.format(
                    "[TABLE CANDIDATE %03d] gc_index=%d hits=%s",
                    tableCandidates,
                    index,
                    table.concat(hits, ", ")
                ))

                local stringKeys = {}

                for key in pairs(object) do
                    if type(key) == "string" then
                        stringKeys[#stringKeys + 1] = key
                    end
                end

                table.sort(stringKeys)

                if #stringKeys > 120 then
                    while #stringKeys > 120 do
                        table.remove(stringKeys)
                    end
                    stringKeys[#stringKeys + 1] = "..."
                end

                push(
                    "  keys: "
                    .. table.concat(stringKeys, ", ")
                )

                for _, key in ipairs(hits) do
                    local value = rawget(object, key)

                    push(
                        "  "
                        .. key
                        .. " = "
                        .. serialize(value, 0, {})
                    )

                    if type(value) == "function" then
                        dumpFunctionDetails(
                            "table." .. key,
                            value
                        )
                    end
                end

                if tableCandidates >= 40 then
                    push("<limite de tabelas candidatas atingido>")
                    break
                end
            end
        end
    end

    if type(getconstantsFn) == "function" then
        push("")
        push("---- FUNÇÕES GC COM CONSTANTES DE GAMEPLAY ----")

        for index, object in ipairs(objects) do
            if index % 200 == 0 then
                task.wait()
            end

            if type(object) == "function" then
                local okConst, constants =
                    pcall(getconstantsFn, object)

                if okConst
                and constantsMatch(constants) then

                    functionCandidates =
                        functionCandidates + 1

                    state.internalFunctions =
                        state.internalFunctions + 1

                    dumpFunctionDetails(
                        "gc_function_"
                        .. tostring(index),
                        object
                    )

                    if functionCandidates >= 80 then
                        push(
                            "<limite de funções candidatas atingido>"
                        )
                        break
                    end
                end
            end
        end
    end

    push("")
    push(string.format(
        "Inspeção interna concluída: tables=%d functions=%d gc_objects=%d",
        tableCandidates,
        functionCandidates,
        #objects
    ))

    state.inspecting = false
end

-- ============================================================
-- Arquivo único
-- ============================================================
local function nextSessionNumber()
    if type(isfileFn) ~= "function" then
        return 1
    end

    for i = 1, 99 do
        local name =
            string.format("MAM2_RECON_RUNTIME_S%02d.txt", i)

        local exists = false

        pcall(function()
            exists = isfileFn(name)
        end)

        if not exists then
            return i
        end
    end

    return 99
end

local sessionNumber = nextSessionNumber()

local function capabilities()
    return table.concat({
        "hookmetamethod=" .. tostring(
            type(hookmetamethodFn) == "function"
        ),
        "getnamecallmethod=" .. tostring(
            type(getnamecallmethodFn) == "function"
        ),
        "hookfunction=" .. tostring(
            type(hookfunctionFn) == "function"
        ),
        "getgc=" .. tostring(type(getgcFn) == "function"),
        "getconstants=" .. tostring(
            type(getconstantsFn) == "function"
        ),
        "getupvalues=" .. tostring(
            type(getupvaluesFn) == "function"
        ),
        "remote_hook_ok=" .. tostring(remoteHookOK),
    }, "\n")
end

local function begin()
    if state.active then
        return false
    end

    state.finalized = false
    state.active = true

    push("Mine a Mountain 2 — Runtime Reconstruction Mapper V1")
    push("session=" .. tostring(sessionNumber))
    push("started_clock=" .. stamp())
    push("")
    push("CAPABILITIES")
    push(capabilities())

    mark("GERAL / LOADER")

    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "MAM2 Recon",
            Text = "Mapeamento iniciado.",
            Duration = 4,
        })
    end)

    return true
end

local function finish()
    if not state.active then
        return false, "Nenhum mapeamento em andamento."
    end

    state.active = false

    push("")
    push("############################################################")
    push("FINAL")
    push("############################################################")
    push("finished_clock=" .. stamp())
    push("remote_calls=" .. tostring(state.remoteCount))
    push("prompt_calls=" .. tostring(state.promptCount))
    push("click_calls=" .. tostring(state.clickCount))
    push("internal_tables=" .. tostring(state.internalTables))
    push("internal_functions=" .. tostring(state.internalFunctions))

    local name =
        string.format(
            "MAM2_RECON_RUNTIME_S%02d.txt",
            sessionNumber
        )

    local content = table.concat(state.lines, "\n")

    if type(writefileFn) == "function" then
        local ok, err = pcall(function()
            writefileFn(name, content)
        end)

        if ok then
            state.finalized = true

            pcall(function()
                StarterGui:SetCore("SendNotification", {
                    Title = "MAM2 Recon",
                    Text = "Finalizado e salvo em um único arquivo.",
                    Duration = 6,
                })
            end)

            return true, name
        end

        return false, tostring(err)
    end

    if type(setclipboardFn) == "function" then
        pcall(setclipboardFn, content)
        return false, "writefile indisponível; conteúdo copiado."
    end

    return false, "writefile/setclipboard indisponíveis."
end

-- ============================================================
-- UI simples e arrastável
-- ============================================================
local parent = nil

pcall(function()
    if type(gethui) == "function" then
        parent = gethui()
    end
end)

if not parent then
    pcall(function()
        parent = game:GetService("CoreGui")
    end)
end

if not parent and LocalPlayer then
    parent = LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

local function corner(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 9)
    c.Parent = obj
end

local function label(parentObject, text, y, size)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Position = UDim2.new(0, 12, 0, y)
    l.Size = UDim2.new(1, -24, 0, 22)
    l.Font = Enum.Font.Gotham
    l.TextSize = size or 13
    l.TextColor3 = Color3.fromRGB(235, 239, 246)
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = text
    l.Parent = parentObject
    return l
end

local function button(parentObject, text, y)
    local b = Instance.new("TextButton")
    b.Position = UDim2.new(0, 12, 0, y)
    b.Size = UDim2.new(1, -24, 0, 34)
    b.BackgroundColor3 = Color3.fromRGB(29, 47, 72)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = 13
    b.TextColor3 = Color3.fromRGB(245, 248, 252)
    b.Text = text
    b.Parent = parentObject
    corner(b, 8)
    return b
end

if parent then
    local gui = Instance.new("ScreenGui")
    gui.Name = "MAM2ReconRuntimeV1"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent

    state.gui = gui

    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.fromScale(0.5, 0.5)
    frame.Size = UDim2.new(0, 350, 0, 360)
    frame.BackgroundColor3 = Color3.fromRGB(15, 22, 33)
    frame.BorderSizePixel = 0
    frame.Parent = gui
    corner(frame, 12)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(62, 96, 138)
    stroke.Transparency = 0.25
    stroke.Parent = frame

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 42)
    header.BackgroundColor3 = Color3.fromRGB(21, 32, 48)
    header.BorderSizePixel = 0
    header.Active = true
    header.Parent = frame
    corner(header, 12)

    local fix = Instance.new("Frame")
    fix.Position = UDim2.new(0, 0, 1, -12)
    fix.Size = UDim2.new(1, 0, 0, 12)
    fix.BackgroundColor3 = header.BackgroundColor3
    fix.BorderSizePixel = 0
    fix.Parent = header

    local title = label(
        header,
        "MAM2 | Reconstrução Runtime",
        9,
        14
    )
    title.Font = Enum.Font.GothamBold

    local status = label(frame, "Status: PARADO", 50, 12)
    local counter = label(
        frame,
        "Remote: 0 | Prompt: 0 | Internos: 0",
        72,
        11
    )
    counter.TextColor3 = Color3.fromRGB(177, 191, 210)

    local startButton =
        button(frame, "Iniciar mapeamento", 101)

    local boulderButton =
        button(frame, "Marcar: Boulder Farm / mineração", 141)

    local pickupButton =
        button(frame, "Marcar: Auto Pickup / cristais", 181)

    local moneyButton =
        button(frame, "Marcar: Money Farm / venda", 221)

    local internalButton =
        button(frame, "Inspecionar internos", 261)

    local finishButton =
        button(frame, "Finalizar e salvar", 311)

    startButton.Activated:Connect(function()
        if begin() then
            status.Text =
                "Status: MAPEANDO | marcador: GERAL / LOADER"
            startButton.Text = "Mapeamento em andamento"
        end
    end)

    boulderButton.Activated:Connect(function()
        if state.active then
            mark("BOULDER FARM / MINERAÇÃO")
            status.Text =
                "Status: MAPEANDO | Boulder Farm"
        end
    end)

    pickupButton.Activated:Connect(function()
        if state.active then
            mark("AUTO PICKUP / CRISTAIS")
            status.Text =
                "Status: MAPEANDO | Auto Pickup"
        end
    end)

    moneyButton.Activated:Connect(function()
        if state.active then
            mark("MONEY FARM / VENDA / FORTUNE")
            status.Text =
                "Status: MAPEANDO | Money/Venda"
        end
    end)

    internalButton.Activated:Connect(function()
        if not state.active or state.inspecting then
            return
        end

        status.Text = "Status: INSPECIONANDO INTERNOS..."

        task.spawn(function()
            local ok, err = pcall(inspectInternals)

            if not ok then
                push(
                    "ERRO INSPEÇÃO INTERNA: "
                    .. cleanString(tostring(err))
                )
            end

            if state.active then
                status.Text =
                    "Status: MAPEANDO | internos concluídos"
            end
        end)
    end)

    finishButton.Activated:Connect(function()
        if state.inspecting then
            status.Text =
                "Status: aguarde a inspeção interna terminar"
            return
        end

        local ok, result = finish()

        if ok then
            status.Text = "Status: FINALIZADO E SALVO"
            finishButton.Text = "Arquivo salvo"
        else
            status.Text = "Status: " .. tostring(result)
        end
    end)

    task.spawn(function()
        while gui.Parent do
            counter.Text = string.format(
                "Remote: %d | Prompt: %d | Internos: %d",
                state.remoteCount,
                state.promptCount,
                state.internalTables
                    + state.internalFunctions
            )

            task.wait(0.25)
        end
    end)

    -- Drag por mouse/toque na barra superior.
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPosition = nil

    header.InputBegan:Connect(function(input)
        if input.UserInputType
                == Enum.UserInputType.MouseButton1
        or input.UserInputType
                == Enum.UserInputType.Touch then

            dragging = true
            dragStart = input.Position
            startPosition = frame.Position

            input.Changed:Connect(function()
                if input.UserInputState
                        == Enum.UserInputState.End
                or input.UserInputState
                        == Enum.UserInputState.Cancel then

                    dragging = false
                end
            end)
        end
    end)

    header.InputChanged:Connect(function(input)
        if input.UserInputType
                == Enum.UserInputType.MouseMovement
        or input.UserInputType
                == Enum.UserInputType.Touch then

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
end

print("[MAM2-RECON] PRONTO. Toque em Iniciar mapeamento.")

pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title = "MAM2 Recon",
        Text = "Pronto. Inicie o mapeamento antes do script original.",
        Duration = 5,
    })
end)
