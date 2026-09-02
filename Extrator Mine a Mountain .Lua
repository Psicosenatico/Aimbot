--[[
    Mine a Mountain 2 — Extrator Estático Multicamadas V1

    OBJETIVO:
      Obter o conteúdo real servido por:
        https://api.xgrs.lol/storage/xgrs-loader

      SEM executar os payloads recebidos.

    O extrator:
      - baixa a camada inicial com game:HttpGet;
      - salva cada camada em .txt;
      - procura URLs e indicadores importantes;
      - se a camada for apenas outro loader do tipo
        loadstring(game:HttpGet("URL"))()
        segue automaticamente para a próxima URL;
      - para quando encontra um payload real/dinâmico;
      - nunca chama loadstring no conteúdo recebido.

    Arquivos gerados:
      MAM2_00_report.txt
      MAM2_01_layer_raw.txt
      MAM2_02_layer_raw.txt
      ...
      MAM2_candidates.txt
]]

local START_URL = "https://api.xgrs.lol/storage/xgrs-loader"
local MAX_LAYERS = 8

local report = {}
local candidates = {}
local seenCandidate = {}
local visitedUrls = {}

local function log(msg)
    msg = tostring(msg)
    report[#report + 1] = msg
    print("[MAM2-EXTRACT] " .. msg)
end

local function save(name, data)
    if type(writefile) ~= "function" then
        warn("[MAM2-EXTRACT] writefile indisponível: " .. tostring(name))
        return false
    end

    local ok, err = pcall(writefile, name, tostring(data or ""))
    if not ok then
        warn("[MAM2-EXTRACT] falha ao salvar " .. tostring(name) .. ": " .. tostring(err))
        return false
    end

    return true
end

local function addCandidate(kind, value)
    if type(value) ~= "string" or value == "" then
        return
    end

    local key = tostring(kind) .. "\0" .. value
    if seenCandidate[key] then
        return
    end

    seenCandidate[key] = true
    candidates[#candidates + 1] = "[" .. tostring(kind) .. "] " .. value
end

local function rollingHash(s)
    local h = 2166136261
    for i = 1, #s do
        h = (h * 131 + string.byte(s, i)) % 4294967296
    end
    return string.format("%08X", h)
end

local function countPlain(haystack, needle)
    local total = 0
    local pos = 1

    while true do
        local a, b = string.find(haystack, needle, pos, true)
        if not a then
            break
        end

        total = total + 1
        pos = b + 1
    end

    return total
end

local PROBES = {
    "loadstring",
    "HttpGet",
    "request",
    "http_request",
    "syn.request",
    "getgenv",
    "getfenv",
    "setfenv",
    "hookfunction",
    "hookmetamethod",
    "getrawmetatable",
    "getnamecallmethod",
    "getgc",
    "debug",
    "getconstants",
    "getprotos",
    "getupvalues",
    "writefile",
    "readfile",
    "isfile",
    "delfile",
    "setclipboard",
    "key",
    "Key",
    "KEY",
    "getkey",
    "get-key",
    "check-key",
    "premium",
    "free",
    "auth",
    "token",
    "license",
    "Workspace",
    "Players",
    "ReplicatedStorage",
    "RunService",
    "UserInputService",
    "TweenService",
    "HttpService",
    "RemoteEvent",
    "RemoteFunction",
    "FireServer",
    "InvokeServer",
    "Raycast",
    "VirtualInputManager",
    "VirtualUser",
}

local function scanLayer(layer, src, url)
    log("")
    log("=== CAMADA " .. tostring(layer) .. " ===")
    log("URL: " .. tostring(url))
    log("Bytes: " .. tostring(#src))
    log("Hash rolling: " .. rollingHash(src))
    log("Linhas: " .. tostring(select(2, src:gsub("\n", "\n")) + 1))

    local hits = 0
    for _, probe in ipairs(PROBES) do
        local n = countPlain(src, probe)
        if n > 0 then
            hits = hits + 1
            log(string.format("  %-24s : %d", probe, n))
        end
    end

    if hits == 0 then
        log("Nenhum indicador da lista apareceu em texto claro.")
    end

    -- URLs normais em texto claro.
    for found in src:gmatch("https?://[^%s\"'%)%]%}<>]+") do
        addCandidate("URL_LAYER_" .. tostring(layer), found)
    end

    -- Strings que parecem domínios.
    for host in src:gmatch("[%w_%-]+%.[%a][%w%.%-_]+") do
        if #host >= 6 then
            addCandidate("HOST_LAYER_" .. tostring(layer), host)
        end
    end
end

local function extractDirectLoaderUrl(src)
    -- Casos mais comuns:
    -- loadstring(game:HttpGet("https://..."))()
    -- loadstring(game:HttpGet('https://...'))()
    -- loadstring(game.HttpGet(game,"https://..."))()

    local u =
        src:match('HttpGet%s*%(%s*"([^"]+)"%s*%)')
        or src:match("HttpGet%s*%(%s*'([^']+)'%s*%)")
        or src:match('HttpGet%s*%(%s*game%s*,%s*"([^"]+)"%s*%)')
        or src:match("HttpGet%s*%(%s*game%s*,%s*'([^']+)'%s*%)")

    if not u then
        return nil
    end

    -- Só segue automaticamente quando o conteúdo realmente se parece
    -- com um loader pequeno/simples. Payloads reais são apenas salvos.
    local compact = src:gsub("%s+", "")

    local hasLoad = compact:find("loadstring", 1, true) ~= nil
    local hasHttp = compact:find("HttpGet", 1, true) ~= nil

    if hasLoad and hasHttp and #src <= 5000 then
        return u
    end

    return nil
end

local function fetch(url)
    local ok, result = pcall(function()
        return game:HttpGet(url)
    end)

    if not ok then
        return nil, tostring(result)
    end

    if type(result) ~= "string" then
        return nil, "HttpGet retornou tipo " .. typeof(result)
    end

    return result, nil
end

log("Mine a Mountain 2 — Extrator Estático Multicamadas V1")
log("Início.")
log("IMPORTANTE: nenhum payload recebido será executado.")

local currentUrl = START_URL
local finalLayer = 0

for layer = 1, MAX_LAYERS do
    if visitedUrls[currentUrl] then
        log("")
        log("Loop de URL detectado: " .. tostring(currentUrl))
        break
    end

    visitedUrls[currentUrl] = true

    local src, err = fetch(currentUrl)
    if not src then
        log("")
        log("ERRO ao baixar camada " .. tostring(layer) .. ": " .. tostring(err))
        break
    end

    finalLayer = layer

    local fileName = string.format("MAM2_%02d_layer_raw.txt", layer)
    local saved = save(fileName, src)

    scanLayer(layer, src, currentUrl)

    if saved then
        log("Salvo em: " .. fileName)
    end

    local nextUrl = extractDirectLoaderUrl(src)

    if nextUrl and nextUrl ~= currentUrl then
        log("Outra camada de loader detectada.")
        log("Próxima URL: " .. tostring(nextUrl))
        addCandidate("FOLLOW_LAYER_" .. tostring(layer), nextUrl)
        currentUrl = nextUrl
    else
        log("")
        log("Camada " .. tostring(layer) .. " tratada como payload final/complexo.")
        log("A cadeia automática foi encerrada sem executar o conteúdo.")
        break
    end
end

table.sort(candidates)

save("MAM2_candidates.txt", table.concat(candidates, "\n"))

log("")
log("=== RESUMO ===")
log("Camadas obtidas: " .. tostring(finalLayer))
log("URLs/candidatos: " .. tostring(#candidates))
log("Nenhum conteúdo baixado foi passado para loadstring.")
log("")
log("Envie para análise:")
for i = 1, finalLayer do
    log(string.format("  MAM2_%02d_layer_raw.txt", i))
end
log("  MAM2_00_report.txt")
log("  MAM2_candidates.txt")

save("MAM2_00_report.txt", table.concat(report, "\n"))

if type(writefile) ~= "function" then
    local summary = table.concat(report, "\n")
    if type(setclipboard) == "function" then
        pcall(setclipboard, summary)
        warn("[MAM2-EXTRACT] writefile não existe; relatório copiado para a área de transferência.")
    end
else
    print("[MAM2-EXTRACT] CONCLUÍDO.")
end
