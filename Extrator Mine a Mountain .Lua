--[[
    Mine a Mountain 2 — Extrator Estático Multicamadas V2
    Objetivo:
      - Baixar e salvar camadas remotas para análise.
      - NÃO executar nenhum conteúdo remoto recebido.
      - Identificar URLs, loaders, referências a key/premium/free e cache.
      - Encerrar com relatório e lista de candidatos.

    Observação:
      Este extrator é somente para inspeção estática.
      Ele NÃO remove, altera ou contorna validação de chave/acesso premium.
]]

local PREFIX = "MAM2_V2"
local MAX_LAYERS = 6
local MAX_BYTES = 2 * 1024 * 1024
local START_URL = "https://api.xgrs.lol/storage/xgrs-loader"

local seenUrls = {}
local report = {}
local candidates = {}
local saved = {}

local function push(t, s)
    t[#t + 1] = tostring(s)
end

local function safeWrite(path, data)
    if not writefile then
        return false, "writefile indisponível"
    end
    local ok, err = pcall(writefile, path, data)
    return ok, err
end

local function rollingHash(s)
    local h = 2166136261
    for i = 1, #s do
        h = bit32.bxor(h, string.byte(s, i))
        h = (h * 16777619) % 4294967296
    end
    return string.format("%08X", h)
end

local function countPlain(haystack, needle)
    local n, pos = 0, 1
    while true do
        local a, b = string.find(haystack, needle, pos, true)
        if not a then break end
        n += 1
        pos = b + 1
    end
    return n
end

local function addCandidate(kind, value)
    if not value or value == "" then return end
    local key = kind .. "|" .. tostring(value)
    if candidates[key] then return end
    candidates[key] = true
    push(report, string.format("  [%s] %s", kind, value))
end

local function scanInteresting(layer, body)
    local low = body:lower()
    local tags = {
        {"loadstring", "loadstring"}, {"HttpGet", "httpget"},
        {"writefile", "writefile"}, {"readfile", "readfile"},
        {"delfile", "delfile"}, {"makefolder", "makefolder"},
        {"key", "key"}, {"premium", "premium"}, {"free", "free"},
        {"loader", "loader"}, {"luarmor", "luarmor"}, {"xgrs", "xgrs"}
    }
    for _, item in ipairs(tags) do
        local n = countPlain(low, item[2])
        if n > 0 then
            push(report, string.format("  %-22s : %d", item[1], n))
        end
    end

    for url in body:gmatch('https?://[^%s"\']+') do
        addCandidate("URL_LAYER_" .. layer, url)
    end
    for host in body:gmatch('([%w%-_]+%.luarmor%.net)') do
        addCandidate("HOST_LAYER_" .. layer, host)
    end
    for host in body:gmatch('([%w%-_]+%.xgrs%.lol)') do
        addCandidate("HOST_LAYER_" .. layer, host)
    end
    for file in body:gmatch('([%w%-%._]+%.lua)') do
        addCandidate("LUA_LAYER_" .. layer, file)
    end
end

local function fetch(url)
    local ok, data = pcall(function()
        return game:HttpGet(url)
    end)
    if not ok then return nil, tostring(data) end
    if type(data) ~= "string" then return nil, "resposta não textual" end
    if #data > MAX_BYTES then return nil, "resposta acima do limite de segurança" end
    return data
end

local function chooseNextUrl(body)
    local u = body:match('HttpGet%s*%(%s*["\'](https?://.-)["\']')
    if u and not seenUrls[u] then return u end

    for url in body:gmatch('https?://[^%s"\']+') do
        url = url:gsub('[%)%;,%]]+$', '')
        if url:find(".lua", 1, true) and not seenUrls[url] then
            return url
        end
    end

    if body:find("cdn.luarmor.net", 1, true) and body:find("v4_init_marbeg.lua", 1, true) then
        local u2 = "https://cdn.luarmor.net/v4_init_marbeg.lua"
        if not seenUrls[u2] then return u2 end
    end
    return nil
end

push(report, "Mine a Mountain 2 — Extrator Estático Multicamadas V2")
push(report, "Início.")
push(report, "IMPORTANTE: nenhum payload recebido será executado.")
push(report, "Este extrator não remove/contorna validação de chave ou acesso premium.")
push(report, "")

local url = START_URL
for layer = 1, MAX_LAYERS do
    if not url or seenUrls[url] then break end
    seenUrls[url] = true

    push(report, string.format("=== CAMADA %d ===", layer))
    push(report, "URL: " .. url)

    local body, err = fetch(url)
    if not body then
        push(report, "ERRO: " .. tostring(err))
        push(report, "")
        break
    end

    local lineCount = 1
    for _ in body:gmatch("\n") do lineCount += 1 end
    push(report, "Bytes: " .. #body)
    push(report, "Hash rolling: " .. rollingHash(body))
    push(report, "Linhas: " .. lineCount)
    scanInteresting(layer, body)

    local rawPath = string.format("%s_%02d_layer_raw.txt", PREFIX, layer)
    local okWrite, writeErr = safeWrite(rawPath, body)
    if okWrite then
        push(saved, rawPath)
        push(report, "Salvo em: " .. rawPath)
    else
        push(report, "Falha ao salvar: " .. tostring(writeErr))
    end

    local interestingLines = {}
    local idx = 0
    for line in (body .. "\n"):gmatch("(.-)\n") do
        idx += 1
        local low = line:lower()
        if low:find("key", 1, true) or low:find("premium", 1, true)
            or low:find("free", 1, true) or low:find("loadstring", 1, true)
            or low:find("httpget", 1, true) or low:find("writefile", 1, true)
            or low:find("readfile", 1, true) or low:find("luarmor", 1, true)
            or low:find("xgrs", 1, true) then
            push(interestingLines, string.format("[%d] %s", idx, line))
        end
    end

    if #interestingLines > 0 then
        local mapPath = string.format("%s_%02d_map.txt", PREFIX, layer)
        local okMap = safeWrite(mapPath, table.concat(interestingLines, "\n"))
        if okMap then push(saved, mapPath) end
    end

    local nextUrl = chooseNextUrl(body)
    if nextUrl then
        push(report, "Próxima URL: " .. nextUrl)
        push(report, "")
        url = nextUrl
    else
        push(report, "Nenhuma próxima URL estática confiável encontrada.")
        push(report, "A cadeia automática foi encerrada sem executar o conteúdo.")
        push(report, "")
        break
    end
end

push(report, "=== RESUMO ===")
local seenCount = 0
for _ in pairs(seenUrls) do seenCount += 1 end
push(report, "Camadas obtidas: " .. seenCount)

local candidateLines = {}
for k in pairs(candidates) do
    local kind, value = k:match("^(.-)|(.+)$")
    push(candidateLines, string.format("[%s] %s", kind or "CANDIDATE", value or k))
end
table.sort(candidateLines)

local candidatePath = PREFIX .. "_candidates.txt"
safeWrite(candidatePath, table.concat(candidateLines, "\n"))
push(saved, candidatePath)

push(report, "URLs/candidatos: " .. #candidateLines)
push(report, "Nenhum conteúdo baixado foi passado para loadstring.")
push(report, "")
push(report, "Arquivos gerados:")
for _, p in ipairs(saved) do push(report, "  " .. p) end

local reportPath = PREFIX .. "_00_report.txt"
safeWrite(reportPath, table.concat(report, "\n"))

if setclipboard then pcall(setclipboard, table.concat(report, "\n")) end
print(table.concat(report, "\n"))
print("Extrator V2 concluído. Relatório: " .. reportPath)
