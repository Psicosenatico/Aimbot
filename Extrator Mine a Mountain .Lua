local PREFIX = "MAM2_RT"
local env = (getgenv and getgenv()) or _G

local state = env.__MAM2_RUNTIME_CAPTURE_V1
if type(state) == "table" and state.installed then
    print("[MAM2-RT] Capturador já está instalado.")
    return
end

state = {
    installed = true,
    loadCount = 0,
    requestCount = 0,
}
env.__MAM2_RUNTIME_CAPTURE_V1 = state

local function log(msg)
    print("[MAM2-RT] " .. tostring(msg))
end

local function safeWrite(name, data)
    if type(writefile) ~= "function" then
        return false, "writefile indisponível"
    end
    local ok, err = pcall(writefile, name, tostring(data or ""))
    return ok, err
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

local function appendIndex(line)
    local name = PREFIX .. "_00_index.txt"
    local old = ""

    if type(isfile) == "function" and type(readfile) == "function" then
        pcall(function()
            if isfile(name) then
                old = readfile(name)
            end
        end)
    end

    safeWrite(name, old .. tostring(line) .. "\n")
end

local function saveLoadstring(source, chunkname, method)
    if type(source) ~= "string" then
        return
    end

    state.loadCount = state.loadCount + 1
    local id = state.loadCount

    local rawName = string.format("%s_%02d_loadstring_raw.txt", PREFIX, id)
    local metaName = string.format("%s_%02d_loadstring_meta.txt", PREFIX, id)

    local meta = table.concat({
        "type=loadstring",
        "method=" .. tostring(method or "unknown"),
        "chunkname=" .. redact(chunkname or "<nil>"),
        "bytes=" .. tostring(#source),
        "hash=" .. rollingHash(source),
    }, "\n")

    safeWrite(rawName, source)
    safeWrite(metaName, meta)

    appendIndex(string.format(
        "LOADSTRING #%02d | bytes=%d | chunk=%s | file=%s",
        id, #source, redact(chunkname or "<nil>"), rawName
    ))

    log(string.format(
        "loadstring #%02d capturado (%d bytes) -> %s",
        id, #source, rawName
    ))
end

-- ============================================================
-- Hook de loadstring
-- ============================================================
local originalLoadstring = loadstring

if type(originalLoadstring) == "function" and type(hookfunction) == "function" then
    local previous
    previous = hookfunction(originalLoadstring, function(source, chunkname, ...)
        pcall(saveLoadstring, source, chunkname, "hookfunction")
        return previous(source, chunkname, ...)
    end)

    state.originalLoadstring = previous
    log("Hook loadstring instalado via hookfunction.")

elseif type(originalLoadstring) == "function" then
    local wrapped = function(source, chunkname, ...)
        pcall(saveLoadstring, source, chunkname, "global-wrapper")
        return originalLoadstring(source, chunkname, ...)
    end

    pcall(function()
        env.loadstring = wrapped
    end)

    pcall(function()
        _G.loadstring = wrapped
    end)

    log("Hook loadstring instalado por wrapper global.")
else
    log("AVISO: loadstring não foi encontrado.")
end

-- ============================================================
-- Captura de request mantendo o comportamento original
-- ============================================================
local function summarizeRequestArg(arg)
    if type(arg) == "string" then
        return "url=" .. redact(arg)
    end

    if type(arg) == "table" then
        local parts = {}
        local url = arg.Url or arg.URL or arg.url
        local method = arg.Method or arg.method

        if url then
            parts[#parts + 1] = "url=" .. redact(url)
        end

        if method then
            parts[#parts + 1] = "method=" .. tostring(method)
        end

        return table.concat(parts, "\n")
    end

    return "arg_type=" .. type(arg)
end

local function saveRequest(arg, response, label)
    state.requestCount = state.requestCount + 1
    local id = state.requestCount

    local metaName = string.format("%s_REQ_%02d_meta.txt", PREFIX, id)
    local bodyName = string.format("%s_REQ_%02d_body.txt", PREFIX, id)

    local status = nil
    local body = nil

    if type(response) == "table" then
        status = response.StatusCode or response.Status or response.status
        body = response.Body or response.body
    elseif type(response) == "string" then
        body = response
    end

    local meta = table.concat({
        "type=request",
        "label=" .. tostring(label),
        summarizeRequestArg(arg),
        "status=" .. tostring(status or "<unknown>"),
        "body_bytes=" .. tostring(type(body) == "string" and #body or 0),
    }, "\n")

    safeWrite(metaName, meta)

    if type(body) == "string" and #body > 0 then
        -- Preserva o corpo exato para análise.
        safeWrite(bodyName, body)
    end

    appendIndex(string.format(
        "REQUEST #%02d | %s | body=%d | meta=%s",
        id,
        tostring(label),
        type(body) == "string" and #body or 0,
        metaName
    ))

    log(string.format(
        "request #%02d registrado (%s, body=%d bytes)",
        id,
        tostring(label),
        type(body) == "string" and #body or 0
    ))
end

local function hookRequestFunction(container, key, label)
    if type(container) ~= "table" then
        return false
    end

    local fn = rawget(container, key)
    if type(fn) ~= "function" then
        return false
    end

    if type(hookfunction) == "function" then
        local previous
        previous = hookfunction(fn, function(arg, ...)
            local response = previous(arg, ...)
            pcall(saveRequest, arg, response, label)
            return response
        end)
        return true
    end

    local wrapped = function(arg, ...)
        local response = fn(arg, ...)
        pcall(saveRequest, arg, response, label)
        return response
    end

    rawset(container, key, wrapped)
    return true
end

local hookedAnyRequest = false

pcall(function()
    hookedAnyRequest = hookRequestFunction(env, "request", "request") or hookedAnyRequest
end)

pcall(function()
    hookedAnyRequest = hookRequestFunction(env, "http_request", "http_request") or hookedAnyRequest
end)

pcall(function()
    if type(env.syn) == "table" then
        hookedAnyRequest = hookRequestFunction(env.syn, "request", "syn.request") or hookedAnyRequest
    end
end)

if hookedAnyRequest then
    log("Hook de request instalado.")
else
    log("Nenhuma função request conhecida foi encontrada; loadstring ainda será capturado.")
end

appendIndex("=== MAM2 Runtime Capture iniciado ===")
appendIndex("Parâmetros key/token/license/auth são redigidos nos metadados.")
appendIndex("Payloads brutos são preservados para análise.")

log("PRONTO.")
log("Agora execute o loader original Mine a Mountain 2 e autentique com sua key premium.")
log("Depois envie todos os arquivos MAM2_RT_* gerados.")
