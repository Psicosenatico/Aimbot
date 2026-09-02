local START_URL = "https://api.xgrs.lol/storage/xgrs-loader"
local PREFIX = "MAM2_V2"

-- ============================================================
-- Sinal imediato: se isto aparecer, o chunk começou a rodar.
-- ============================================================
print("[MAM2-V2] INICIO DO CAPTURADOR")
warn("[MAM2-V2] INICIO DO CAPTURADOR")

pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "MAM2 Capturador V2",
        Text = "Iniciado. Preparando captura...",
        Duration = 5
    })
end)

-- ============================================================
-- Utilidades sem dependências externas
-- ============================================================
local function safeGlobal(name)
    local ok, value = pcall(function()
        return _G and _G[name]
    end)
    if ok then
        return value
    end
    return nil
end

local function getEnvironment()
    local ok, env = pcall(function()
        local gg = safeGlobal("getgenv")
        if type(gg) == "function" then
            local e = gg()
            if type(e) == "table" then
                return e
            end
        end

        if type(_G) == "table" then
            return _G
        end

        return {}
    end)

    if ok and type(env) == "table" then
        return env
    end

    return {}
end

local env = getEnvironment()

local function getFunction(name)
    local v = nil

    pcall(function()
        v = env[name]
    end)

    if type(v) == "function" then
        return v
    end

    pcall(function()
        if type(_G) == "table" then
            v = _G[name]
        end
    end)

    if type(v) == "function" then
        return v
    end

    return nil
end

local writefileFn = getFunction("writefile")
local readfileFn = getFunction("readfile")
local isfileFn = getFunction("isfile")
local hookfunctionFn = getFunction("hookfunction")
local originalLoadstring = getFunction("loadstring")

local function safeWrite(name, data)
    if type(writefileFn) ~= "function" then
        return false, "writefile indisponivel"
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

    local ok, data = pcall(function()
        if type(isfileFn) == "function" then
            local exists = isfileFn(name)
            if not exists then
                return nil
            end
        end
        return readfileFn(name)
    end)

    if ok and type(data) == "string" then
        return data
    end

    return nil
end

local function appendFile(name, line)
    local old = safeRead(name) or ""
    safeWrite(name, old .. tostring(line) .. "\n")
end

local INDEX_FILE = PREFIX .. "_00_index.txt"

local function log(msg)
    msg = tostring(msg)
    print("[MAM2-V2] " .. msg)
    appendFile(INDEX_FILE, msg)
end

local function redact(text)
    text = tostring(text or "")

    text = text:gsub("([?&][Kk][Ee][Yy]=)[^&%s]+", "%1<REDACTED>")
    text = text:gsub("([?&][Tt][Oo][Kk][Ee][Nn]=)[^&%s]+", "%1<REDACTED>")
    text = text:gsub("([?&][Ll][Ii][Cc][Ee][Nn][Ss][Ee]=)[^&%s]+", "%1<REDACTED>")
    text = text:gsub("([?&][Aa][Uu][Tt][Hh]=)[^&%s]+", "%1<REDACTED>")

    text = text:gsub('("[Kk][Ee][Yy]"%s*:%s*")[^"]+(")', '%1<REDACTED>%2')
    text = text:gsub('("[Tt][Oo][Kk][Ee][Nn]"%s*:%s*")[^"]+(")', '%1<REDACTED>%2')
    text = text:gsub('("[Ll][Ii][Cc][Ee][Nn][Ss][Ee]"%s*:%s*")[^"]+(")', '%1<REDACTED>%2')
    text = text:gsub('("[Aa][Uu][Tt][Hh]"%s*:%s*")[^"]+(")', '%1<REDACTED>%2')

    return text
end

local function rollingHash(s)
    s = tostring(s or "")
    local h = 2166136261

    for i = 1, #s do
        h = (h * 131 + string.byte(s, i)) % 4294967296
    end

    return string.format("%08X", h)
end

-- ============================================================
-- Diagnóstico ANTES dos hooks
-- ============================================================
local capabilities = {}

local function cap(name, value)
    capabilities[#capabilities + 1] =
        string.format("%-20s = %s", name, tostring(value))
end

cap("getgenv", type(safeGlobal("getgenv")) == "function")
cap("_G_table", type(_G) == "table")
cap("loadstring", type(originalLoadstring) == "function")
cap("hookfunction", type(hookfunctionFn) == "function")
cap("writefile", type(writefileFn) == "function")
cap("readfile", type(readfileFn) == "function")
cap("isfile", type(isfileFn) == "function")
cap("request", type(getFunction("request")) == "function")
cap("http_request", type(getFunction("http_request")) == "function")

local synRequest = nil
pcall(function()
    local synTable = env.syn
    if type(synTable) == "table" and type(synTable.request) == "function" then
        synRequest = synTable.request
    end
end)
cap("syn.request", type(synRequest) == "function")

safeWrite(PREFIX .. "_00_capabilities.txt", table.concat(capabilities, "\n"))
log("Diagnostico inicial salvo.")
for _, line in ipairs(capabilities) do
    print("[MAM2-V2] " .. line)
end

-- ============================================================
-- Estado local
-- ============================================================
local state = {
    loadCount = 0,
    requestCount = 0,
    loadHookMethod = "none",
    requestHooks = 0
}

pcall(function()
    env.__MAM2_RUNTIME_CAPTURE_V2 = state
end)

-- ============================================================
-- Captura de loadstring
-- ============================================================
local function saveLoadstring(source, chunkname, method)
    if type(source) ~= "string" then
        return
    end

    state.loadCount = state.loadCount + 1
    local id = state.loadCount

    local rawName =
        string.format("%s_LS_%02d_raw.txt", PREFIX, id)

    local metaName =
        string.format("%s_LS_%02d_meta.txt", PREFIX, id)

    safeWrite(rawName, source)

    local meta = table.concat({
        "type=loadstring",
        "method=" .. tostring(method or "unknown"),
        "chunkname=" .. redact(chunkname or "<nil>"),
        "bytes=" .. tostring(#source),
        "hash=" .. rollingHash(source)
    }, "\n")

    safeWrite(metaName, meta)

    log(string.format(
        "LOADSTRING #%02d | %d bytes | chunk=%s | %s",
        id,
        #source,
        redact(chunkname or "<nil>"),
        rawName
    ))
end

local loadHookInstalled = false

if type(originalLoadstring) == "function"
and type(hookfunctionFn) == "function" then

    local previous = nil

    local okHook, hookResult = pcall(function()
        previous = hookfunctionFn(
            originalLoadstring,
            function(source, chunkname, ...)
                pcall(saveLoadstring, source, chunkname, "hookfunction")

                if type(previous) == "function" then
                    return previous(source, chunkname, ...)
                end

                return originalLoadstring(source, chunkname, ...)
            end
        )

        return previous
    end)

    if okHook and type(hookResult) == "function" then
        loadHookInstalled = true
        state.loadHookMethod = "hookfunction"
        log("Hook de loadstring instalado via hookfunction.")
    else
        log("hookfunction(loadstring) falhou, mas o capturador continuara.")
        log("Detalhe: " .. tostring(hookResult))
    end
end

-- Fallback global seguro.
if not loadHookInstalled and type(originalLoadstring) == "function" then
    local wrapped = function(source, chunkname, ...)
        pcall(saveLoadstring, source, chunkname, "global-wrapper")
        return originalLoadstring(source, chunkname, ...)
    end

    local wrote = false

    local okEnv = pcall(function()
        env.loadstring = wrapped
        wrote = (env.loadstring == wrapped)
    end)

    local okG = pcall(function()
        if type(_G) == "table" then
            _G.loadstring = wrapped
            wrote = wrote or (_G.loadstring == wrapped)
        end
    end)

    if (okEnv or okG) and wrote then
        loadHookInstalled = true
        state.loadHookMethod = "global-wrapper"
        log("Fallback global de loadstring instalado.")
    else
        log("Nao foi possivel substituir loadstring global.")
    end
end

if not loadHookInstalled then
    log("AVISO: loadstrings posteriores podem nao ser interceptados.")
end

-- ============================================================
-- Captura de requests
-- ============================================================
local hookedRequestFns = {}

local function alreadyHooked(fn)
    for _, existing in ipairs(hookedRequestFns) do
        if existing == fn then
            return true
        end
    end
    return false
end

local function registerHooked(fn)
    hookedRequestFns[#hookedRequestFns + 1] = fn
end

local function summarizeRequestArg(arg)
    if type(arg) == "string" then
        return "url=" .. redact(arg)
    end

    if type(arg) == "table" then
        local lines = {}
        local url = arg.Url or arg.URL or arg.url
        local method = arg.Method or arg.method

        if url then
            lines[#lines + 1] = "url=" .. redact(url)
        end

        if method then
            lines[#lines + 1] = "method=" .. tostring(method)
        end

        local body = arg.Body or arg.body
        if type(body) == "string" then
            lines[#lines + 1] =
                "request_body_bytes=" .. tostring(#body)
        end

        return table.concat(lines, "\n")
    end

    return "arg_type=" .. type(arg)
end

local function saveRequest(arg, response, label)
    state.requestCount = state.requestCount + 1
    local id = state.requestCount

    local metaName =
        string.format("%s_REQ_%02d_meta.txt", PREFIX, id)

    local bodyName =
        string.format("%s_REQ_%02d_response.txt", PREFIX, id)

    local status = nil
    local body = nil

    if type(response) == "table" then
        status =
            response.StatusCode
            or response.Status
            or response.status

        body =
            response.Body
            or response.body

    elseif type(response) == "string" then
        body = response
    end

    local meta = table.concat({
        "type=request",
        "label=" .. tostring(label),
        summarizeRequestArg(arg),
        "status=" .. tostring(status or "<unknown>"),
        "response_bytes=" ..
            tostring(type(body) == "string" and #body or 0)
    }, "\n")

    safeWrite(metaName, meta)

    if type(body) == "string" and #body > 0 then
        safeWrite(bodyName, body)
    end

    log(string.format(
        "REQUEST #%02d | %s | response=%d bytes",
        id,
        tostring(label),
        type(body) == "string" and #body or 0
    ))
end

local function tryHookRequest(fn, label, setter)
    if type(fn) ~= "function" then
        return false
    end

    if alreadyHooked(fn) then
        log("Request alias ignorado para evitar hook duplicado: " .. label)
        return false
    end

    if type(hookfunctionFn) == "function" then
        local previous = nil

        local ok, result = pcall(function()
            previous = hookfunctionFn(fn, function(arg, ...)
                local response

                if type(previous) == "function" then
                    response = previous(arg, ...)
                else
                    response = fn(arg, ...)
                end

                pcall(saveRequest, arg, response, label)
                return response
            end)

            return previous
        end)

        if ok and type(result) == "function" then
            registerHooked(fn)
            state.requestHooks = state.requestHooks + 1
            log("Hook request instalado: " .. label)
            return true
        end

        log("Hook request falhou em " .. label .. ": " .. tostring(result))
    end

    -- Fallback por substituição, se houver setter.
    if type(setter) == "function" then
        local wrapped = function(arg, ...)
            local response = fn(arg, ...)
            pcall(saveRequest, arg, response, label)
            return response
        end

        local okSet = pcall(function()
            setter(wrapped)
        end)

        if okSet then
            registerHooked(fn)
            state.requestHooks = state.requestHooks + 1
            log("Wrapper request instalado: " .. label)
            return true
        end
    end

    return false
end

local requestFn = getFunction("request")
local httpRequestFn = getFunction("http_request")

tryHookRequest(
    requestFn,
    "request",
    function(wrapped)
        env.request = wrapped
        if type(_G) == "table" then
            _G.request = wrapped
        end
    end
)

tryHookRequest(
    httpRequestFn,
    "http_request",
    function(wrapped)
        env.http_request = wrapped
        if type(_G) == "table" then
            _G.http_request = wrapped
        end
    end
)

if type(synRequest) == "function" then
    tryHookRequest(
        synRequest,
        "syn.request",
        function(wrapped)
            if type(env.syn) == "table" then
                env.syn.request = wrapped
            end
        end
    )
end

-- ============================================================
-- Download controlado da primeira camada
-- ============================================================
log("Baixando xgrs-loader diretamente...")

local loaderSource = nil
local fetchError = nil

local okFetch, fetchResult = pcall(function()
    return game:HttpGet(START_URL)
end)

if okFetch and type(fetchResult) == "string" then
    loaderSource = fetchResult

    safeWrite(
        PREFIX .. "_01_xgrs_loader_raw.txt",
        loaderSource
    )

    safeWrite(
        PREFIX .. "_01_xgrs_loader_meta.txt",
        table.concat({
            "url=" .. START_URL,
            "bytes=" .. tostring(#loaderSource),
            "hash=" .. rollingHash(loaderSource)
        }, "\n")
    )

    log(
        "xgrs-loader obtido e salvo: "
        .. tostring(#loaderSource)
        .. " bytes"
    )
else
    fetchError = tostring(fetchResult)
    log("FALHA ao baixar xgrs-loader: " .. fetchError)
end

-- ============================================================
-- Executa a camada inicial usando o loadstring ORIGINAL.
-- Assim não dependemos do loader de 70 bytes do usuário.
-- ============================================================
if type(loaderSource) == "string" then
    if type(originalLoadstring) ~= "function" then
        log("ERRO: loadstring original nao esta disponivel.")
    else
        log("Compilando xgrs-loader salvo...")

        local okCompile, fnOrErr = pcall(
            originalLoadstring,
            loaderSource,
            "@MAM2_XGRS_LOADER"
        )

        if not okCompile or type(fnOrErr) ~= "function" then
            log("ERRO de compilacao: " .. tostring(fnOrErr))
        else
            log("Compilacao OK. Iniciando xgrs-loader...")
            pcall(function()
                game:GetService("StarterGui"):SetCore(
                    "SendNotification",
                    {
                        Title = "MAM2 Capturador V2",
                        Text = "Captura pronta. Loader iniciado.",
                        Duration = 5
                    }
                )
            end)

            local okRun, runErr = pcall(fnOrErr)

            if okRun then
                log("xgrs-loader retornou sem erro Lua imediato.")
            else
                log("xgrs-loader terminou com erro: " .. tostring(runErr))
            end
        end
    end
end

-- ============================================================
-- Resumo
-- ============================================================
safeWrite(
    PREFIX .. "_99_summary.txt",
    table.concat({
        "capture_version=2",
        "start_url=" .. START_URL,
        "load_hook_method=" .. tostring(state.loadHookMethod),
        "request_hooks=" .. tostring(state.requestHooks),
        "loadstrings_captured=" .. tostring(state.loadCount),
        "requests_captured=" .. tostring(state.requestCount),
        "initial_loader_saved=" ..
            tostring(type(loaderSource) == "string"),
        "initial_loader_bytes=" ..
            tostring(type(loaderSource) == "string" and #loaderSource or 0),
        "fetch_error=" .. tostring(fetchError or "<none>")
    }, "\n")
)

log("V2 finalizou a etapa de inicializacao.")
log("Se o menu de key apareceu, autentique normalmente.")
log("Depois use o script e envie todos os arquivos MAM2_V2_*.")
