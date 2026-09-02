--[[
    Purchase Remote Diagnostic V1.0 - SERVER
    Uso: Roblox Studio / jogo próprio.
    Coloque como Script em ServerScriptService.

    Objetivo:
      - Catalogar RemoteEvents/RemoteFunctions potencialmente ligados a compra.
      - Registrar, de forma passiva, RemoteEvents recebidos pelo servidor.
      - Registrar tipos/valores resumidos dos argumentos.
      - Tirar snapshots de valores econômicos do Player no recebimento e logo depois.
      - Exportar tudo como JSON por um RemoteFunction próprio do diagnóstico.

    IMPORTANTE:
      - Este script NÃO altera argumentos.
      - NÃO dispara compras.
      - NÃO falsifica saldo.
      - NÃO substitui OnServerInvoke de RemoteFunctions existentes.
      - Por segurança, executa apenas no Roblox Studio.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

if not RunService:IsStudio() then
    warn("[PurchaseResearch] Diagnóstico bloqueado fora do Roblox Studio.")
    return
end

local CONFIG = {
    Version = "1.0",
    ObserveAllRemoteEvents = false,
    MaxEvents = 2500,
    MaxArgs = 30,
    MaxTableItems = 30,
    MaxTableDepth = 3,
    PostSnapshotDelays = {0.05, 0.30},
    CandidateKeywords = {
        "buy",
        "purchase",
        "shop",
        "store",
        "cash",
        "money",
        "coin",
        "currency",
        "balance",
        "tycoon",
        "button",
        "unlock",
        "upgrade",
        "rebirth",
        "dropper",
        "conveyor",
        "generator",
        "owner",
        "claim",
        "price",
        "cost",
        "item",
        "product",
    },
    EconomyKeywords = {
        "cash",
        "money",
        "coin",
        "currency",
        "balance",
        "credits",
        "funds",
        "wallet",
        "price",
        "cost",
    },
}

local state = {
    version = CONFIG.Version,
    startedUnixMs = DateTime.now().UnixTimestampMillis,
    placeId = game.PlaceId,
    jobId = game.JobId,
    events = {},
    discoveries = {},
    counters = {
        discoveredRemoteEvents = 0,
        discoveredRemoteFunctions = 0,
        observedRemoteEvents = 0,
        receivedCalls = 0,
        droppedEvents = 0,
    },
}

local attachedRemoteEvents = setmetatable({}, {__mode = "k"})
local discoveredInstances = setmetatable({}, {__mode = "k"})
local sequence = 0

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function containsAny(text, keywords)
    text = lower(text)
    for _, keyword in ipairs(keywords) do
        if string.find(text, keyword, 1, true) then
            return true, keyword
        end
    end
    return false, nil
end

local function fullNameSafe(instance)
    local ok, result = pcall(function()
        return instance:GetFullName()
    end)
    return ok and result or instance.Name
end

local function isFiniteNumber(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function summarizeValue(value, depth, seen)
    depth = depth or 0
    seen = seen or {}

    local valueType = typeof(value)

    if valueType == "nil" then
        return {type = "nil"}
    elseif valueType == "boolean" or valueType == "string" then
        return {
            type = valueType,
            value = value,
        }
    elseif valueType == "number" then
        return {
            type = "number",
            value = isFiniteNumber(value) and value or tostring(value),
            finite = isFiniteNumber(value),
            integer = isFiniteNumber(value) and math.floor(value) == value or false,
        }
    elseif valueType == "Instance" then
        return {
            type = "Instance",
            className = value.ClassName,
            name = value.Name,
            path = fullNameSafe(value),
        }
    elseif valueType == "Vector3" then
        return {
            type = "Vector3",
            x = value.X,
            y = value.Y,
            z = value.Z,
        }
    elseif valueType == "Vector2" then
        return {
            type = "Vector2",
            x = value.X,
            y = value.Y,
        }
    elseif valueType == "CFrame" then
        local components = {value:GetComponents()}
        return {
            type = "CFrame",
            components = components,
        }
    elseif valueType == "Color3" then
        return {
            type = "Color3",
            r = value.R,
            g = value.G,
            b = value.B,
        }
    elseif valueType == "EnumItem" then
        return {
            type = "EnumItem",
            value = tostring(value),
        }
    elseif valueType == "table" then
        if depth >= CONFIG.MaxTableDepth then
            return {
                type = "table",
                truncated = "max_depth",
            }
        end

        if seen[value] then
            return {
                type = "table",
                truncated = "cycle",
            }
        end

        seen[value] = true

        local output = {
            type = "table",
            entries = {},
        }

        local count = 0
        for key, item in pairs(value) do
            count += 1
            if count > CONFIG.MaxTableItems then
                output.truncated = "max_items"
                break
            end

            table.insert(output.entries, {
                key = summarizeValue(key, depth + 1, seen),
                value = summarizeValue(item, depth + 1, seen),
            })
        end

        seen[value] = nil
        output.countObserved = math.min(count, CONFIG.MaxTableItems)
        return output
    end

    return {
        type = valueType,
        value = tostring(value),
    }
end

local function summarizeArgs(...)
    local packed = table.pack(...)
    local result = {
        count = packed.n,
        values = {},
    }

    local limit = math.min(packed.n, CONFIG.MaxArgs)
    for index = 1, limit do
        result.values[index] = summarizeValue(packed[index])
    end

    if packed.n > CONFIG.MaxArgs then
        result.truncated = true
    end

    return result
end

local function isEconomyName(name)
    return containsAny(name, CONFIG.EconomyKeywords)
end

local function collectValueObjects(root, output, maxDepth, currentDepth)
    if currentDepth > maxDepth then
        return
    end

    for _, child in ipairs(root:GetChildren()) do
        if child:IsA("IntValue") or child:IsA("NumberValue") then
            local matches = isEconomyName(child.Name)
            if matches then
                table.insert(output, {
                    path = fullNameSafe(child),
                    className = child.ClassName,
                    name = child.Name,
                    value = child.Value,
                })
            end
        end

        if currentDepth < maxDepth then
            collectValueObjects(child, output, maxDepth, currentDepth + 1)
        end
    end
end

local function snapshotEconomy(player)
    local snapshot = {
        unixMs = DateTime.now().UnixTimestampMillis,
        player = {
            name = player.Name,
            userId = player.UserId,
        },
        leaderstats = {},
        attributes = {},
        valueObjects = {},
    }

    local leaderstats = player:FindFirstChild("leaderstats")
    if leaderstats then
        for _, child in ipairs(leaderstats:GetChildren()) do
            if child:IsA("IntValue") or child:IsA("NumberValue") or child:IsA("StringValue") or child:IsA("BoolValue") then
                table.insert(snapshot.leaderstats, {
                    name = child.Name,
                    className = child.ClassName,
                    value = child.Value,
                })
            end
        end
    end

    for attributeName, attributeValue in pairs(player:GetAttributes()) do
        local matches = isEconomyName(attributeName)
        if matches or typeof(attributeValue) == "number" then
            snapshot.attributes[attributeName] = summarizeValue(attributeValue)
        end
    end

    collectValueObjects(player, snapshot.valueObjects, 3, 1)

    return snapshot
end

local function pushEvent(event)
    sequence += 1
    event.sequence = sequence
    event.unixMs = event.unixMs or DateTime.now().UnixTimestampMillis

    table.insert(state.events, event)

    if #state.events > CONFIG.MaxEvents then
        table.remove(state.events, 1)
        state.counters.droppedEvents += 1
    end
end

local function discoveryRecord(instance, candidate, matchedKeyword)
    if discoveredInstances[instance] then
        return
    end
    discoveredInstances[instance] = true

    local className = instance.ClassName

    if className == "RemoteEvent" then
        state.counters.discoveredRemoteEvents += 1
    elseif className == "RemoteFunction" then
        state.counters.discoveredRemoteFunctions += 1
    end

    table.insert(state.discoveries, {
        unixMs = DateTime.now().UnixTimestampMillis,
        className = className,
        name = instance.Name,
        path = fullNameSafe(instance),
        candidate = candidate,
        matchedKeyword = matchedKeyword,
        note = className == "RemoteFunction"
            and "Catalogado somente. OnServerInvoke existente não é sobrescrito."
            or nil,
    })
end

local function classifyRemote(instance)
    local path = fullNameSafe(instance)
    local candidate, keyword = containsAny(path, CONFIG.CandidateKeywords)

    if not candidate then
        for attributeName, attributeValue in pairs(instance:GetAttributes()) do
            local attributeText = attributeName .. " " .. tostring(attributeValue)
            local matched, matchedKeyword = containsAny(attributeText, CONFIG.CandidateKeywords)
            if matched then
                candidate = true
                keyword = matchedKeyword
                break
            end
        end
    end

    return candidate, keyword
end

local function observeRemoteEvent(remoteEvent, candidate)
    if attachedRemoteEvents[remoteEvent] then
        return
    end

    if not candidate and not CONFIG.ObserveAllRemoteEvents then
        return
    end

    attachedRemoteEvents[remoteEvent] = true
    state.counters.observedRemoteEvents += 1

    remoteEvent.OnServerEvent:Connect(function(player, ...)
        state.counters.receivedCalls += 1

        local callSequence = sequence + 1
        local remotePath = fullNameSafe(remoteEvent)

        pushEvent({
            kind = "RemoteEventReceived",
            callId = callSequence,
            remote = {
                name = remoteEvent.Name,
                path = remotePath,
                className = remoteEvent.ClassName,
            },
            player = {
                name = player.Name,
                userId = player.UserId,
            },
            args = summarizeArgs(...),
            economyAtReceipt = snapshotEconomy(player),
        })

        for _, delaySeconds in ipairs(CONFIG.PostSnapshotDelays) do
            task.delay(delaySeconds, function()
                if player.Parent == Players then
                    pushEvent({
                        kind = "PostPurchaseSnapshot",
                        callId = callSequence,
                        delaySeconds = delaySeconds,
                        remotePath = remotePath,
                        economy = snapshotEconomy(player),
                    })
                end
            end)
        end
    end)
end

local function inspectInstance(instance)
    if not (instance:IsA("RemoteEvent") or instance:IsA("RemoteFunction")) then
        return
    end

    local candidate, keyword = classifyRemote(instance)
    discoveryRecord(instance, candidate, keyword)

    if instance:IsA("RemoteEvent") then
        observeRemoteEvent(instance, candidate)
    end
end

for _, descendant in ipairs(game:GetDescendants()) do
    inspectInstance(descendant)
end

game.DescendantAdded:Connect(function(descendant)
    if descendant:IsA("RemoteEvent") or descendant:IsA("RemoteFunction") then
        task.defer(function()
            if descendant.Parent then
                inspectInstance(descendant)
            end
        end)
    end
end)

Players.PlayerAdded:Connect(function(player)
    pushEvent({
        kind = "PlayerAdded",
        player = {
            name = player.Name,
            userId = player.UserId,
        },
    })
end)

Players.PlayerRemoving:Connect(function(player)
    pushEvent({
        kind = "PlayerRemoving",
        player = {
            name = player.Name,
            userId = player.UserId,
        },
    })
end)

local runtimeFolder = ReplicatedStorage:FindFirstChild("PurchaseResearchRuntime")
if runtimeFolder then
    runtimeFolder:Destroy()
end

runtimeFolder = Instance.new("Folder")
runtimeFolder.Name = "PurchaseResearchRuntime"
runtimeFolder.Parent = ReplicatedStorage

local getExport = Instance.new("RemoteFunction")
getExport.Name = "GetExport"
getExport.Parent = runtimeFolder

local getSummary = Instance.new("RemoteFunction")
getSummary.Name = "GetSummary"
getSummary.Parent = runtimeFolder

local function buildPayload(requestingPlayer)
    return {
        meta = {
            tool = "Purchase Remote Diagnostic",
            version = CONFIG.Version,
            generatedUnixMs = DateTime.now().UnixTimestampMillis,
            startedUnixMs = state.startedUnixMs,
            placeId = state.placeId,
            jobId = state.jobId,
            requestedBy = requestingPlayer and {
                name = requestingPlayer.Name,
                userId = requestingPlayer.UserId,
            } or nil,
            observeAllRemoteEvents = CONFIG.ObserveAllRemoteEvents,
            notes = {
                "RemoteEvents são observados passivamente no servidor.",
                "RemoteFunctions existentes são apenas catalogados para evitar alterar OnServerInvoke.",
                "Snapshots pós-evento são aproximados e não garantem ordem relativa a todos os handlers.",
            },
        },
        counters = state.counters,
        discoveries = state.discoveries,
        events = state.events,
    }
end

getExport.OnServerInvoke = function(player)
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(buildPayload(player))
    end)

    if not ok then
        warn("[PurchaseResearch] Falha ao gerar JSON:", encoded)
        return HttpService:JSONEncode({
            error = "Falha ao gerar JSON",
            detail = tostring(encoded),
        })
    end

    return encoded
end

getSummary.OnServerInvoke = function(_player)
    return {
        version = CONFIG.Version,
        discoveries = #state.discoveries,
        events = #state.events,
        counters = state.counters,
    }
end

print(string.format(
    "[PurchaseResearch] V%s iniciado. RemoteEvents descobertos=%d | RemoteFunctions descobertos=%d | RemoteEvents observados=%d",
    CONFIG.Version,
    state.counters.discoveredRemoteEvents,
    state.counters.discoveredRemoteFunctions,
    state.counters.observedRemoteEvents
))
