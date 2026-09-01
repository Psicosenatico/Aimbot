--[[
PSICOSENATICO - AUTO TYCOON - SERVER RESPONSE RESEARCH V2.3.1
DESTINO: LocalScript / ambiente de teste do cliente

OBJETIVO
- Estudar a resposta do servidor VISTA PELO CLIENTE.
- Não finge ser código de servidor.
- Não depende de APIs exclusivas de servidor nem de modo de teste do Studio.
- Não altera Money/Rebirths.
- Não falsifica saldo, Owner, Rebirths ou respostas.
- Não dispara RemoteFunction desconhecida nem RemoteEvent desconhecido.
- Cataloga remotes visíveis, eventos recebidos e mudanças replicadas do Tycoon.
- Correlaciona mudanças de botão/purchase/dinheiro com eventos remotos recebidos.
- Exporta relatório TXT/JSON quando writefile/setclipboard estiver disponível.

IMPORTANTE
- Este script mede "server response as observed by the client".
- Ele NÃO fornece acesso ao estado interno real do servidor.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

local VERSION = "SERVER-RESPONSE-RESEARCH-2.3"
local GUI_NAME = "PsicoTycoonServerResponseResearchV2_3"
local MAX_EVENTS = 3500
local SAMPLE_INTERVAL = 0.20
local CORRELATION_WINDOW = 4.0
local PURCHASE_RESPONSE_WINDOW = 1.0

local Player = Players.LocalPlayer
if not Player then
    warn("[Psico Server Response Research V1] LocalPlayer unavailable")
    return
end

local State = {
    Running = true,
    StartedUnix = os.time(),
    StartedClock = os.clock(),
    Events = {},
    Errors = {},
    Remotes = {},
    MoneyCandidates = {},
    CollectorCandidates = {},
    RebirthCandidates = {},
    LastMoney = nil,
    LastCollector = nil,
    LastRebirths = nil,
    Tycoon = nil,
    ButtonsFolder = nil,
    PurchasesFolder = nil,
    Connections = {},
    TycoonConnections = {},
    RecentRemoteInbound = {},
    Correlations = {},

    VerificationActive = false,
    VerificationSessions = {},
    CurrentVerificationSession = nil,

    PurchaseResponses = {},
    PendingPurchaseResponse = nil,
    ResponseCounters = {
        Accepted = 0,
        Rejected = 0,
        Unresolved = 0,
    },

    LastRemovedButton = nil,
    LastAcceptedResponse = nil,
    PrimaryTycoonMoneySignals = {
        SuccessRemote = "TycoonService.ButtonPurchased",
        RejectRemote = "TycoonService.ButtonCannotPurchase",
        Direction = "SERVER_TO_CLIENT",
        ClientRequestPayloadObserved = false,
        ClientRequestMechanismObserved = false,
        Note = "This client-side observer confirms server responses, not the exact client-to-server purchase request payload.",
        PurchaseAddedPolicy = "PURCHASE_ADDED enriches an existing/recent accepted response; it never starts a new pending response.",
    },
}

local UI = {}

local function elapsed()
    return math.floor((os.clock() - State.StartedClock) * 1000) / 1000
end

local function normalize(value)
    return string.lower(tostring(value or "")):gsub("[%s_%-%./]", "")
end

local function parseNumber(value)
    if value == nil then return nil end
    if type(value) == "number" then return value end
    local s = tostring(value):gsub(",", ""):gsub("%s", ""):gsub("R%$", ""):gsub("%$", "")
    local suffix = string.upper(string.sub(s, -1))
    local mult = 1
    if suffix == "K" then mult = 1e3; s = string.sub(s, 1, -2)
    elseif suffix == "M" then mult = 1e6; s = string.sub(s, 1, -2)
    elseif suffix == "B" then mult = 1e9; s = string.sub(s, 1, -2)
    elseif suffix == "T" then mult = 1e12; s = string.sub(s, 1, -2)
    end
    local n = tonumber(s)
    return n and n * mult or nil
end

local function safeFullName(inst)
    if not inst then return "<nil>" end
    local ok, result = pcall(function() return inst:GetFullName() end)
    return ok and result or "<detached>"
end

local function getAttributes(inst)
    local result = {}
    if not inst then return result end
    local ok, attrs = pcall(function() return inst:GetAttributes() end)
    if ok and type(attrs) == "table" then
        for k, v in pairs(attrs) do
            result[tostring(k)] = tostring(v)
        end
    end
    return result
end

local function attrCI(inst, wanted)
    if not inst then return nil end
    local wantedNorm = normalize(wanted)
    local ok, attrs = pcall(function() return inst:GetAttributes() end)
    if not ok or type(attrs) ~= "table" then return nil end
    for k, v in pairs(attrs) do
        if normalize(k) == wantedNorm then return v end
    end
    return nil
end

local function ownerMatches(owner)
    if owner == nil then return false end
    local textOwner = tostring(owner)
    return textOwner == Player.Name
        or textOwner == tostring(Player.UserId)
        or normalize(textOwner) == normalize(Player.Name)
end

local function addConnection(signal, callback, bucket)
    bucket = bucket or State.Connections
    local connection = signal:Connect(function(...)
        local args = {...}
        local ok, err = pcall(function() callback(unpack(args)) end)
        if not ok then
            table.insert(State.Errors, {
                Time = os.date("%H:%M:%S"),
                Unix = os.time(),
                Elapsed = elapsed(),
                Error = tostring(err),
            })
        end
    end)
    table.insert(bucket, connection)
    return connection
end

local function disconnectAll(bucket)
    for i = #bucket, 1, -1 do
        local c = bucket[i]
        bucket[i] = nil
        pcall(function() c:Disconnect() end)
    end
end

local ALWAYS_STORE_EVENT = {
    VERIFICATION_STARTED = true,
    VERIFICATION_STOPPED = true,
    SERVER_RESPONSE_RESEARCH_READY = true,
}

local function pushEvent(kind, details)
    if not State.VerificationActive and not ALWAYS_STORE_EVENT[kind] then
        return nil
    end

    local item = {
        Time = os.date("%H:%M:%S"),
        Unix = os.time(),
        Elapsed = elapsed(),
        Kind = kind,
        Details = details or {},
    }
    table.insert(State.Events, item)
    while #State.Events > MAX_EVENTS do table.remove(State.Events, 1) end
    return item
end

local function readObjectValue(obj)
    if not obj or not obj.Parent then return nil end
    if obj:IsA("ValueBase") then return parseNumber(obj.Value) end
    if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
        return parseNumber(obj.Text)
    end
    return nil
end

local function findTycoon()
    local tycoons = workspace:FindFirstChild("Tycoons")
    if not tycoons then return nil end
    local best, bestScore = nil, -1
    for _, tycoon in ipairs(tycoons:GetChildren()) do
        local buttons = tycoon:FindFirstChild("Buttons")
        local purchases = tycoon:FindFirstChild("Purchases")
        if buttons and purchases then
            local score = ownerMatches(attrCI(tycoon, "Owner")) and 100 or 0
            for _, folder in ipairs({buttons, purchases}) do
                local checked = 0
                for _, child in ipairs(folder:GetChildren()) do
                    checked = checked + 1
                    if ownerMatches(attrCI(child, "Owner")) then
                        score = score + 40
                        break
                    end
                    if checked >= 100 then break end
                end
            end
            if score > bestScore then
                best, bestScore = tycoon, score
            end
        end
    end
    return bestScore >= 40 and best or nil
end

local function scanNumericCandidates()
    local money, collectors, rebirths = {}, {}, {}
    local function consider(obj, rootKind)
        if not obj then return end
        local isValue = obj:IsA("ValueBase")
        local isText = obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")
        if not isValue and not isText then return end
        local value = readObjectValue(obj)
        if value == nil then return end

        local path = safeFullName(obj)
        local pathNorm = normalize(path)
        local nameNorm = normalize(obj.Name)

        if nameNorm == "money"
        or string.find(nameNorm, "cash", 1, true)
        or string.find(nameNorm, "coin", 1, true)
        or string.find(nameNorm, "saldo", 1, true) then
            table.insert(money, {Path=path, ClassName=obj.ClassName, RootKind=rootKind, Value=value})
        end

        if string.find(pathNorm, "collector", 1, true)
        or string.find(pathNorm, "collect", 1, true) then
            table.insert(collectors, {Path=path, ClassName=obj.ClassName, RootKind=rootKind, Value=value})
        end

        if string.find(nameNorm, "rebirth", 1, true)
        or string.find(nameNorm, "prestige", 1, true) then
            table.insert(rebirths, {Path=path, ClassName=obj.ClassName, RootKind=rootKind, Value=value})
        end
    end

    local function scan(root, kind, limit)
        if not root then return end
        consider(root, kind)
        local n = 0
        for _, d in ipairs(root:GetDescendants()) do
            n += 1
            if n > limit then break end
            consider(d, kind)
        end
    end

    scan(Player:FindFirstChild("leaderstats"), "LEADERSTATS", 160)
    scan(Player:FindFirstChild("PlayerGui"), "PLAYERGUI", 1800)
    scan(State.Tycoon, "TYCOON", 1800)

    State.MoneyCandidates = money
    State.CollectorCandidates = collectors
    State.RebirthCandidates = rebirths
end

local function choosePrimary(list, keyword)
    for _, item in ipairs(list) do
        if item.RootKind == "LEADERSTATS"
        and normalize(item.Path):find(keyword, 1, true) then
            return item
        end
    end
    return list[1]
end

local function trimRecentRemoteInbound()
    local now = elapsed()
    local fresh = {}
    for _, item in ipairs(State.RecentRemoteInbound) do
        if now - item.Elapsed <= CORRELATION_WINDOW then
            table.insert(fresh, item)
        end
    end
    State.RecentRemoteInbound = fresh
end

local function correlate(kind, details)
    trimRecentRemoteInbound()
    if #State.RecentRemoteInbound == 0 then return end
    local related = {}
    for _, remoteEvent in ipairs(State.RecentRemoteInbound) do
        table.insert(related, {
            RemotePath = remoteEvent.Path,
            RemoteName = remoteEvent.Name,
            ClassName = remoteEvent.ClassName,
            EventElapsed = remoteEvent.Elapsed,
            DeltaSeconds = math.floor((elapsed() - remoteEvent.Elapsed) * 1000) / 1000,
            ArgumentCount = remoteEvent.ArgumentCount,
            ArgumentTypes = remoteEvent.ArgumentTypes,
        })
    end
    local record = {
        Time = os.date("%H:%M:%S"),
        Unix = os.time(),
        Elapsed = elapsed(),
        ChangeKind = kind,
        ChangeDetails = details,
        RecentInboundRemotes = related,
    }
    table.insert(State.Correlations, record)
    pushEvent("CORRELATION_OBSERVED", record)
end


local function snapshotEconomy()
    local money = State.MoneyCandidates[1]
    local collector = State.CollectorCandidates[1]
    local rebirth = State.RebirthCandidates[1]

    return {
        Money = money and money.Value or State.LastMoney,
        Collector = collector and collector.Value or State.LastCollector,
        Rebirths = rebirth and rebirth.Value or State.LastRebirths,
    }
end

local function nearestButtonInfo()
    if not State.ButtonsFolder then return nil end

    local character = Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    local best, bestDist = nil, math.huge

    for _, button in ipairs(State.ButtonsFolder:GetChildren()) do
        local part = button:FindFirstChild("Touch", true)
        if part and part:IsA("BasePart") then
            local dist = (part.Position - root.Position).Magnitude
            if dist < bestDist then
                bestDist = dist
                best = {
                    Name = button.Name,
                    Path = safeFullName(button),
                    Distance = math.floor(dist * 100) / 100,
                    Price = attrCI(button, "Price") or attrCI(button, "Cost"),
                    Rebirths = attrCI(button, "RequiredRebirths") or attrCI(button, "Rebirths"),
                    Dependency = attrCI(button, "Dependency"),
                    Attributes = getAttributes(button),
                }
            end
        end
    end

    return best
end

local finalizePendingResponse


local function expirePendingResponse(nowElapsed)
    local pending = State.PendingPurchaseResponse
    if not pending then return end
    local started = pending.StartedElapsed or nowElapsed
    if (nowElapsed - started) > PURCHASE_RESPONSE_WINDOW then
        finalizePendingResponse("UNRESOLVED", "TIMEOUT", nowElapsed)
    end
end

finalizePendingResponse = function(status, remoteName, remoteElapsed)
    if not State.VerificationActive then return end

    local pending = State.PendingPurchaseResponse or {
        StartedUnix = os.time(),
        StartedElapsed = remoteElapsed or elapsed(),
        EconomyBefore = snapshotEconomy(),
        NearbyButton = nearestButtonInfo(),
    }

    pending.Status = status
    pending.RemoteName = remoteName
    pending.SignalDirection = "SERVER_TO_CLIENT"
    pending.RequirementResult =
        status == "ACCEPTED" and "REQUIREMENTS_CONFIRMED_BY_SERVER_RESPONSE" or
        status == "REJECTED" and "REQUIREMENTS_REJECTED_BY_SERVER_RESPONSE" or
        "NO_TERMINAL_SERVER_RESPONSE"

    pending.ResponseElapsed = remoteElapsed or elapsed()
    pending.ResponseUnix = os.time()
    pending.ResponseLatency = pending.ResponseElapsed - (pending.StartedElapsed or pending.ResponseElapsed)
    pending.EconomyAfter = snapshotEconomy()

    if pending.CandidateButton then
        pending.TargetName = pending.CandidateButton.Name
        pending.TargetPath = pending.CandidateButton.Path
        pending.TargetInference = pending.TargetInference or "BUTTON_REMOVED"
    elseif pending.NearbyButton then
        pending.TargetName = pending.NearbyButton.Name
        pending.TargetPath = pending.NearbyButton.Path
        pending.TargetInference = pending.TargetInference or "NEARBY_BUTTON_FALLBACK"
    end

    if status == "REJECTED" and not pending.CandidateButton then
        local nearby = nearestButtonInfo()
        if nearby then
            pending.NearbyButton = nearby
            pending.TargetName = nearby.Name
            pending.TargetPath = nearby.Path
            pending.TargetInference = "NEARBY_BUTTON_AT_REJECTION"
        end
    end

    if status == "ACCEPTED" then
        State.ResponseCounters.Accepted += 1
        State.LastAcceptedResponse = pending
    elseif status == "REJECTED" then
        State.ResponseCounters.Rejected += 1
    else
        State.ResponseCounters.Unresolved += 1
    end

    pending.Id = #State.PurchaseResponses + 1
    table.insert(State.PurchaseResponses, pending)
    State.PendingPurchaseResponse = nil

    pushEvent("PURCHASE_RESPONSE_" .. status, {
        Id = pending.Id,
        RemoteName = remoteName,
        ResponseLatency = pending.ResponseLatency,
        TargetName = pending.TargetName,
        TargetPath = pending.TargetPath,
        TargetInference = pending.TargetInference,
        RequirementResult = pending.RequirementResult,
        SignalDirection = pending.SignalDirection,
        CandidateButton = pending.CandidateButton,
        NearbyButton = pending.NearbyButton,
        EconomyBefore = pending.EconomyBefore,
        EconomyAfter = pending.EconomyAfter,
    })
end

local function notePurchaseStructure(kind, details)
    if not State.VerificationActive then return end

    local nowElapsed = elapsed()

    if State.PendingPurchaseResponse then
        local started = State.PendingPurchaseResponse.StartedElapsed or nowElapsed
        if (nowElapsed - started) > PURCHASE_RESPONSE_WINDOW then
            finalizePendingResponse("UNRESOLVED", "TIMEOUT", nowElapsed)
        end
    end

    if kind == "BUTTON_REMOVED" then
        State.LastRemovedButton = {
            Details = details,
            Elapsed = nowElapsed,
            Unix = os.time(),
        }

        if State.PendingPurchaseResponse then
            finalizePendingResponse("UNRESOLVED", "REPLACED_BY_NEW_BUTTON_REMOVAL", nowElapsed)
        end

        State.PendingPurchaseResponse = {
            StartedUnix = os.time(),
            StartedElapsed = nowElapsed,
            EconomyBefore = snapshotEconomy(),
            CandidateButton = details,
            TargetInference = "BUTTON_REMOVED",
            StructuralEvidence = {},
        }

        table.insert(State.PendingPurchaseResponse.StructuralEvidence, {
            Kind = "BUTTON_REMOVED",
            Elapsed = nowElapsed,
            Details = details,
        })
        State.PendingPurchaseResponse.ButtonRemoved = details
        return
    end

    if kind == "PURCHASE_ADDED" then
        -- Important V2.3 rule:
        -- PURCHASE_ADDED alone must NEVER open a new pending response.
        if State.PendingPurchaseResponse then
            State.PendingPurchaseResponse.StructuralEvidence = State.PendingPurchaseResponse.StructuralEvidence or {}
            table.insert(State.PendingPurchaseResponse.StructuralEvidence, {
                Kind = "PURCHASE_ADDED",
                Elapsed = nowElapsed,
                Details = details,
            })
            State.PendingPurchaseResponse.PurchaseAdded = details

            local candidate = State.PendingPurchaseResponse.CandidateButton
            if candidate and candidate.Name and details and details.Name == candidate.Name then
                State.PendingPurchaseResponse.TargetConfirmedByPurchaseAdded = true
            end
            return
        end

        -- If the accepted response already closed a few milliseconds earlier,
        -- attach PURCHASE_ADDED retroactively instead of creating UNRESOLVED noise.
        local lastAccepted = State.LastAcceptedResponse
        if lastAccepted and lastAccepted.ResponseElapsed and
            (nowElapsed - lastAccepted.ResponseElapsed) <= PURCHASE_RESPONSE_WINDOW then

            lastAccepted.StructuralEvidence = lastAccepted.StructuralEvidence or {}
            table.insert(lastAccepted.StructuralEvidence, {
                Kind = "PURCHASE_ADDED",
                Elapsed = nowElapsed,
                Details = details,
            })
            lastAccepted.PurchaseAdded = details

            if lastAccepted.TargetName and details and details.Name == lastAccepted.TargetName then
                lastAccepted.TargetConfirmedByPurchaseAdded = true
            end

            pushEvent("PURCHASE_RESPONSE_ENRICHED", {
                Id = lastAccepted.Id,
                Status = lastAccepted.Status,
                TargetName = lastAccepted.TargetName,
                TargetPath = lastAccepted.TargetPath,
                PurchaseAdded = details,
                TargetConfirmedByPurchaseAdded = lastAccepted.TargetConfirmedByPurchaseAdded == true,
            })
        end

        return
    end
end

local function catalogRemote(obj)
    if not (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) then return end
    local path = safeFullName(obj)
    if State.Remotes[path] then return end

    local info = {
        Path = path,
        Name = obj.Name,
        ClassName = obj.ClassName,
        Attributes = getAttributes(obj),
        FirstSeenUnix = os.time(),
        FirstSeenElapsed = elapsed(),
        InboundEventsObserved = 0,
    }
    State.Remotes[path] = info
    pushEvent("REMOTE_DISCOVERED", {Path=path, Name=obj.Name, ClassName=obj.ClassName})

    if obj:IsA("RemoteEvent") then
        addConnection(obj.OnClientEvent, function(...)
            local args = {...}
            local types = {}
            for i, value in ipairs(args) do types[i] = typeof(value) end

            info.InboundEventsObserved += 1
            info.LastInboundUnix = os.time()
            info.LastInboundElapsed = elapsed()
            info.LastArgumentCount = #args
            info.LastArgumentTypes = types

            local inbound = {
                Path = path,
                Name = obj.Name,
                ClassName = obj.ClassName,
                Unix = os.time(),
                Elapsed = elapsed(),
                ArgumentCount = #args,
                ArgumentTypes = types,
            }

            table.insert(State.RecentRemoteInbound, inbound)
            trimRecentRemoteInbound()
            pushEvent("REMOTE_ON_CLIENT_EVENT", inbound)

            if obj.Name == "ButtonPurchased" then
                expirePendingResponse(inbound.Elapsed)

                -- If BUTTON_REMOVED happened immediately before this signal,
                -- it is the strongest observable target identity.
                local removed = State.LastRemovedButton
                if removed and (inbound.Elapsed - removed.Elapsed) <= PURCHASE_RESPONSE_WINDOW then
                    if not State.PendingPurchaseResponse then
                        State.PendingPurchaseResponse = {
                            StartedUnix = removed.Unix,
                            StartedElapsed = removed.Elapsed,
                            EconomyBefore = snapshotEconomy(),
                            CandidateButton = removed.Details,
                            ButtonRemoved = removed.Details,
                            TargetInference = "BUTTON_REMOVED",
                            StructuralEvidence = {},
                        }
                    elseif not State.PendingPurchaseResponse.CandidateButton then
                        State.PendingPurchaseResponse.CandidateButton = removed.Details
                        State.PendingPurchaseResponse.ButtonRemoved = removed.Details
                        State.PendingPurchaseResponse.TargetInference = "BUTTON_REMOVED"
                    end
                end

                finalizePendingResponse("ACCEPTED", obj.Name, inbound.Elapsed)

            elseif obj.Name == "ButtonCannotPurchase" then
                -- Rejection normally leaves the target button in place.
                -- Use proximity only at the instant of the rejection and never
                -- carry a previous successful purchase into this record.
                State.PendingPurchaseResponse = {
                    StartedUnix = os.time(),
                    StartedElapsed = inbound.Elapsed,
                    EconomyBefore = snapshotEconomy(),
                    NearbyButton = nearestButtonInfo(),
                    TargetInference = "NEARBY_BUTTON_AT_REJECTION",
                    StructuralEvidence = {},
                }
                finalizePendingResponse("REJECTED", obj.Name, inbound.Elapsed)
            end
        end)
    end
end

local function scanRemotes()
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        catalogRemote(d)
    end
end

local function describeButton(button)
    return {
        Name = button.Name,
        Path = safeFullName(button),
        Attributes = getAttributes(button),
        Price = attrCI(button, "Price") or attrCI(button, "Cost"),
        Rebirths = attrCI(button, "RequiredRebirths") or attrCI(button, "Rebirths"),
        Dependency = attrCI(button, "Dependency"),
        Gamepass = attrCI(button, "Gamepass") or attrCI(button, "GamePassId"),
        DevProduct = attrCI(button, "DevProduct") or attrCI(button, "DeveloperProductId"),
        HasTouch = button:FindFirstChild("Touch", true) ~= nil,
        HasTouchInterest = button:FindFirstChildWhichIsA("TouchTransmitter", true) ~= nil,
        HasPrompt = button:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil,
    }
end

local function describePurchase(purchase)
    local prompt = purchase:FindFirstChildWhichIsA("ProximityPrompt", true)
    local result = {
        Name = purchase.Name,
        Path = safeFullName(purchase),
        Attributes = getAttributes(purchase),
    }
    if prompt then
        result.Prompt = {
            Path = safeFullName(prompt),
            ActionText = prompt.ActionText,
            ObjectText = prompt.ObjectText,
            HoldDuration = prompt.HoldDuration,
            MaxActivationDistance = prompt.MaxActivationDistance,
            Enabled = prompt.Enabled,
        }
    end
    return result
end

local function bindTycoon(tycoon)
    disconnectAll(State.TycoonConnections)
    State.Tycoon = tycoon
    State.ButtonsFolder = tycoon and tycoon:FindFirstChild("Buttons") or nil
    State.PurchasesFolder = tycoon and tycoon:FindFirstChild("Purchases") or nil
    if not State.ButtonsFolder or not State.PurchasesFolder then return end

    pushEvent("TYCOON_BOUND", {
        Path=safeFullName(tycoon),
        Buttons=#State.ButtonsFolder:GetChildren(),
        Purchases=#State.PurchasesFolder:GetChildren(),
    })

    addConnection(State.ButtonsFolder.ChildAdded, function(child)
        local details = describeButton(child)
        pushEvent("BUTTON_ADDED", details)
        correlate("BUTTON_ADDED", details)
    end, State.TycoonConnections)

    addConnection(State.ButtonsFolder.ChildRemoved, function(child)
        local details = describeButton(child)
        pushEvent("BUTTON_REMOVED", details)
        notePurchaseStructure("BUTTON_REMOVED", details)
        correlate("BUTTON_REMOVED", details)
    end, State.TycoonConnections)

    addConnection(State.PurchasesFolder.ChildAdded, function(child)
        local details = describePurchase(child)
        pushEvent("PURCHASE_ADDED", details)
        notePurchaseStructure("PURCHASE_ADDED", details)
        correlate("PURCHASE_ADDED", details)
    end, State.TycoonConnections)
end

local function resolveGuiParent()
    local ok, hui = pcall(function()
        if type(gethui) == "function" then return gethui() end
    end)
    if ok and hui then return hui end

    local probeOk = pcall(function()
        local f = Instance.new("Folder")
        f.Parent = CoreGui
        f:Destroy()
    end)
    if probeOk then return CoreGui end

    return Player:WaitForChild("PlayerGui")
end

local function round(gui, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = gui
end

local function setupDrag(frame, handle)
    local dragging = false
    local dragStart, startPos

    addConnection(handle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)

    addConnection(UserInputService.InputChanged, function(input)
        if not dragging or not dragStart or not startPos then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    addConnection(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end


local function setMinimized(minimized)
    if not UI.Main or not UI.Floating then return end
    UI.Main.Visible = not minimized
    UI.Floating.Visible = minimized
end

local function beginVerification()
    if State.VerificationActive then return end

    State.VerificationActive = true
    State.RecentRemoteInbound = {}
    State.Correlations = {}
    State.Events = {}
    State.PurchaseResponses = {}
    State.PendingPurchaseResponse = nil
    State.LastRemovedButton = nil
    State.LastAcceptedResponse = nil
    State.ResponseCounters = {
        Accepted = 0,
        Rejected = 0,
        Unresolved = 0,
    }

    local session = {
        Id = #State.VerificationSessions + 1,
        StartedUnix = os.time(),
        StartedElapsed = elapsed(),
        StartedMoney = State.LastMoney,
        StartedCollector = State.LastCollector,
        StartedRebirths = State.LastRebirths,
        StartedTycoon = State.Tycoon and safeFullName(State.Tycoon) or nil,
    }

    State.CurrentVerificationSession = session
    table.insert(State.VerificationSessions, session)

    pushEvent("VERIFICATION_STARTED", {
        SessionId = session.Id,
        Money = State.LastMoney,
        Collector = State.LastCollector,
        Rebirths = State.LastRebirths,
        Tycoon = session.StartedTycoon,
    })

    if UI.Toggle and UI.Toggle.Parent then
        UI.Toggle.Text = "Parar verificacao"
        UI.Toggle.BackgroundColor3 = Color3.fromRGB(86,43,48)
    end

    if UI.Status and UI.Status.Parent then
        UI.Status.Text = "VERIFICACAO ATIVA | realize as compras e pare quando terminar"
    end
end

local function stopVerification()
    if not State.VerificationActive then return end

    if State.PendingPurchaseResponse then
        finalizePendingResponse("UNRESOLVED", "NO_TERMINAL_REMOTE", elapsed())
    end

    local session = State.CurrentVerificationSession
    if session then
        session.StoppedUnix = os.time()
        session.StoppedElapsed = elapsed()
        session.StoppedMoney = State.LastMoney
        session.StoppedCollector = State.LastCollector
        session.StoppedRebirths = State.LastRebirths
        session.EventsCaptured = #State.Events
        session.CorrelationsCaptured = #State.Correlations
        session.PurchaseResponsesCaptured = #State.PurchaseResponses
        session.Accepted = State.ResponseCounters.Accepted
        session.Rejected = State.ResponseCounters.Rejected
        session.Unresolved = State.ResponseCounters.Unresolved
    end

    pushEvent("VERIFICATION_STOPPED", {
        SessionId = session and session.Id or nil,
        Money = State.LastMoney,
        Collector = State.LastCollector,
        Rebirths = State.LastRebirths,
        EventsCaptured = #State.Events,
        CorrelationsCaptured = #State.Correlations,
        PurchaseResponsesCaptured = #State.PurchaseResponses,
        Accepted = State.ResponseCounters.Accepted,
        Rejected = State.ResponseCounters.Rejected,
        Unresolved = State.ResponseCounters.Unresolved,
    })

    State.VerificationActive = false
    State.CurrentVerificationSession = nil
    State.RecentRemoteInbound = {}

    if UI.Toggle and UI.Toggle.Parent then
        UI.Toggle.Text = "Iniciar verificacao"
        UI.Toggle.BackgroundColor3 = Color3.fromRGB(18,49,88)
    end

    if UI.Status and UI.Status.Parent then
        UI.Status.Text =
            "VERIFICACAO PAUSADA | Eventos: " .. tostring(#State.Events) ..
            " | Correlacoes: " .. tostring(#State.Correlations)
    end
end

local function createGui()
    local parent = resolveGuiParent()
    local old = parent:FindFirstChild(GUI_NAME)
    if old then old:Destroy() end

    local screen = Instance.new("ScreenGui")
    screen.Name = GUI_NAME
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 1000000
    screen.Parent = parent

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 400, 0, 390)
    main.Position = UDim2.new(0.5, -200, 0.5, -195)
    main.BackgroundColor3 = Color3.fromRGB(18,23,31)
    main.BorderSizePixel = 0
    main.Active = true
    main.Parent = screen
    round(main, 12)

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 48)
    header.BackgroundColor3 = Color3.fromRGB(24,31,43)
    header.BorderSizePixel = 0
    header.Parent = main
    round(header, 12)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -132, 1, 0)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.BackgroundTransparency = 1
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "AUTO TYCOON - SERVER RESPONSE RESEARCH V2.3"
    title.TextColor3 = Color3.fromRGB(83,226,169)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 11
    title.Parent = header

    local minimize = Instance.new("TextButton")
    minimize.Size = UDim2.new(0, 34, 0, 34)
    minimize.Position = UDim2.new(1, -82, 0, 7)
    minimize.BackgroundColor3 = Color3.fromRGB(18,49,88)
    minimize.TextColor3 = Color3.new(1,1,1)
    minimize.Text = "—"
    minimize.Font = Enum.Font.GothamBold
    minimize.Parent = header
    round(minimize, 8)

    local close = Instance.new("TextButton")
    close.Size = UDim2.new(0, 34, 0, 34)
    close.Position = UDim2.new(1, -42, 0, 7)
    close.BackgroundColor3 = Color3.fromRGB(86,43,48)
    close.TextColor3 = Color3.new(1,1,1)
    close.Text = "X"
    close.Font = Enum.Font.GothamBold
    close.Parent = header
    round(close, 8)

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -16, 0, 58)
    status.Position = UDim2.new(0, 8, 0, 56)
    status.BackgroundColor3 = Color3.fromRGB(29,37,51)
    status.TextColor3 = Color3.fromRGB(238,242,250)
    status.TextWrapped = true
    status.Font = Enum.Font.Gotham
    status.TextSize = 10
    status.Text = "Inicializando pesquisa de resposta do servidor..."
    status.Parent = main
    round(status, 8)

    local log = Instance.new("TextLabel")
    log.Size = UDim2.new(1, -16, 1, -210)
    log.Position = UDim2.new(0, 8, 0, 122)
    log.BackgroundColor3 = Color3.fromRGB(14,19,27)
    log.TextColor3 = Color3.fromRGB(238,242,250)
    log.TextXAlignment = Enum.TextXAlignment.Left
    log.TextYAlignment = Enum.TextYAlignment.Top
    log.TextWrapped = true
    log.Font = Enum.Font.Code
    log.TextSize = 10
    log.Text = "Aguardando eventos..."
    log.Parent = main
    round(log, 8)

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(1, -16, 0, 36)
    toggle.Position = UDim2.new(0, 8, 1, -86)
    toggle.BackgroundColor3 = Color3.fromRGB(18,49,88)
    toggle.TextColor3 = Color3.fromRGB(238,242,250)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 11
    toggle.Text = "Iniciar verificacao"
    toggle.Parent = main
    round(toggle, 8)

    local export = Instance.new("TextButton")
    export.Size = UDim2.new(1, -16, 0, 36)
    export.Position = UDim2.new(0, 8, 1, -44)
    export.BackgroundColor3 = Color3.fromRGB(18,49,88)
    export.TextColor3 = Color3.fromRGB(238,242,250)
    export.Font = Enum.Font.GothamBold
    export.TextSize = 11
    export.Text = "Exportar SERVER RESPONSE V2.3 (.txt)"
    export.Parent = main
    round(export, 8)

    local floating = Instance.new("TextButton")
    floating.Name = "RestoreFloatingButton"
    floating.Size = UDim2.new(0, 60, 0, 60)
    floating.Position = UDim2.new(0, 18, 0.5, -30)
    floating.BackgroundColor3 = Color3.fromRGB(18,49,88)
    floating.TextColor3 = Color3.new(1,1,1)
    floating.Text = "SR V2"
    floating.Font = Enum.Font.GothamBold
    floating.TextSize = 11
    floating.Visible = false
    floating.Active = true
    floating.ZIndex = 100
    floating.Parent = screen
    round(floating, 14)

    UI.Screen = screen
    UI.Main = main
    UI.Header = header
    UI.Status = status
    UI.Log = log
    UI.Export = export
    UI.Toggle = toggle
    UI.Minimize = minimize
    UI.Floating = floating

    setupDrag(main, header)
    setupDrag(floating, floating)

    addConnection(minimize.MouseButton1Click, function()
        setMinimized(true)
    end)

    addConnection(floating.MouseButton1Click, function()
        setMinimized(false)
    end)

    addConnection(toggle.MouseButton1Click, function()
        if State.VerificationActive then
            stopVerification()
        else
            beginVerification()
        end
    end)

    addConnection(close.MouseButton1Click, function()
        if State.VerificationActive then
            stopVerification()
        end
        State.Running = false
        disconnectAll(State.TycoonConnections)
        disconnectAll(State.Connections)
        screen:Destroy()
    end)

    addConnection(export.MouseButton1Click, function()
        scanNumericCandidates()

        local remotesArray = {}
        for _, info in pairs(State.Remotes) do table.insert(remotesArray, info) end
        table.sort(remotesArray, function(a,b) return a.Path < b.Path end)

        local payload = {
            Report = "Psicosenatico Auto Tycoon Server Response Research",
            Version = VERSION,
            PlaceId = game.PlaceId,
            JobId = game.JobId,
            Player = {Name=Player.Name, UserId=Player.UserId},
            StartedAtUnix = State.StartedUnix,
            FinishedAtUnix = os.time(),
            Tycoon = State.Tycoon and safeFullName(State.Tycoon) or nil,
            MoneyCandidates = State.MoneyCandidates,
            CollectorCandidates = State.CollectorCandidates,
            RebirthCandidates = State.RebirthCandidates,
            Remotes = remotesArray,
            Correlations = State.Correlations,
            Events = State.Events,
            Errors = State.Errors,
            Verification = {
                Active = State.VerificationActive,
                Sessions = State.VerificationSessions,
                CurrentSession = State.CurrentVerificationSession,
                CapturedEvents = #State.Events,
                CapturedCorrelations = #State.Correlations,
                PurchaseResponses = State.PurchaseResponses,
                ResponseCounters = State.ResponseCounters,
                PrimaryTycoonMoneySignals = State.PrimaryTycoonMoneySignals,
            },
            Policy = {
                Perspective = "server response as observed by client",
                TrueServerAuthority = false,
                ServerOnlyApiDependency = false,
                StudioOnlyDependency = false,
                MoneyMutation = false,
                RebirthMutation = false,
                UnknownRemoteInvocation = false,
                ServerAuthorizationForgery = false,
                OutboundPurchaseRequestCaptured = false,
                OutboundPurchaseRequestPayloadKnown = false,
                Notes = "Inbound RemoteEvent activity and replicated state changes are observational evidence, not internal server state.",
            },
        }

        local ok, content = pcall(function() return HttpService:JSONEncode(payload) end)
        if not ok then
            UI.Status.Text = "Falha ao gerar JSON: " .. tostring(content)
            return
        end

        local filename = "Auto_Tycoon_Server_Response_Research_V2_3_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
        local saved, copied = false, false

        if type(writefile) == "function" then
            saved = pcall(function() writefile(filename, content) end)
        end

        if type(setclipboard) == "function" then
            copied = pcall(function() setclipboard(content) end)
        elseif type(toclipboard) == "function" then
            copied = pcall(function() toclipboard(content) end)
        end

        UI.Status.Text = saved and ("Arquivo exportado: " .. filename)
            or copied and "Relatorio copiado para a area de transferencia"
            or "Relatorio pronto, mas writefile/clipboard indisponiveis"
    end)
end

createGui()
scanRemotes()

addConnection(ReplicatedStorage.DescendantAdded, function(obj)
    catalogRemote(obj)
end)

local tycoon = findTycoon()
if tycoon then
    bindTycoon(tycoon)
else
    pushEvent("TYCOON_NOT_FOUND", {})
end

task.spawn(function()
    while State.Running do
        if not State.Tycoon or not State.Tycoon.Parent then
            local newTycoon = findTycoon()
            if newTycoon and newTycoon ~= State.Tycoon then
                bindTycoon(newTycoon)
            end
        end

        scanNumericCandidates()

        local money = choosePrimary(State.MoneyCandidates, "money")
        local collector = State.CollectorCandidates[1]
        local rebirth = choosePrimary(State.RebirthCandidates, "rebirth")

        local moneyValue = money and money.Value or nil
        local collectorValue = collector and collector.Value or nil
        local rebirthValue = rebirth and rebirth.Value or nil

        if moneyValue ~= State.LastMoney then
            local details = {Before=State.LastMoney, After=moneyValue, Source=money and money.Path or nil}
            pushEvent("MONEY_CHANGED", details)
            correlate("MONEY_CHANGED", details)
            State.LastMoney = moneyValue
        end

        if collectorValue ~= State.LastCollector then
            local details = {Before=State.LastCollector, After=collectorValue, Source=collector and collector.Path or nil}
            pushEvent("COLLECTOR_CHANGED", details)
            correlate("COLLECTOR_CHANGED", details)
            State.LastCollector = collectorValue
        end

        if rebirthValue ~= State.LastRebirths then
            local details = {Before=State.LastRebirths, After=rebirthValue, Source=rebirth and rebirth.Path or nil}
            pushEvent("REBIRTH_CHANGED", details)
            correlate("REBIRTH_CHANGED", details)
            State.LastRebirths = rebirthValue
        end

        if UI.Status and UI.Status.Parent then
            local remoteCount = 0
            for _ in pairs(State.Remotes) do remoteCount += 1 end

            if State.VerificationActive then
                UI.Status.Text =
                    "ATIVA | Aceitas: " .. tostring(State.ResponseCounters.Accepted) ..
                    " | Recusadas: " .. tostring(State.ResponseCounters.Rejected) ..
                    " | Money: " .. tostring(State.LastMoney)
            else
                UI.Status.Text =
                    "PAUSADA | Aceitas: " .. tostring(State.ResponseCounters.Accepted) ..
                    " | Recusadas: " .. tostring(State.ResponseCounters.Rejected) ..
                    " | Nao resolvidas: " .. tostring(State.ResponseCounters.Unresolved)
            end
        end

        if UI.Log and UI.Log.Parent then
            if State.VerificationActive then
                local lines = {}
                local first = math.max(1, #State.Events - 8)
                for i = #State.Events, first, -1 do
                    local e = State.Events[i]
                    table.insert(lines, "[" .. tostring(e.Time) .. "] " .. tostring(e.Kind))
                end
                UI.Log.Text = #lines > 0 and table.concat(lines, "\n") or "Capturando..."
            else
                UI.Log.Text =
                    "Verificacao pausada.\n" ..
                    "Toque em Iniciar verificacao antes das compras.\n" ..
                    "Ao terminar, toque em Parar verificacao e exporte o relatorio.\n" ..
                    "Principal: ButtonPurchased=aceito | ButtonCannotPurchase=recusado."
            end
        end

        task.wait(SAMPLE_INTERVAL)
    end
end)

pushEvent("SERVER_RESPONSE_RESEARCH_READY", {
    Version = VERSION,
    Perspective = "server response as observed by client",
    VerificationDefault = "PAUSED",
})
