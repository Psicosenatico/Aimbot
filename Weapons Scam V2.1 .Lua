-- PSICOSENATICO • WEAPON RESEARCH V2.3.15 • STABLE BOOTSTRAP + 429 RESILIENCE
-- Esta URL principal deve permanecer estável. As partes internas continuam versionadas por SOURCE_COMMIT.
-- Runtime: CDN primária + GitHub Raw fallback + cache por sessão + retry progressivo.
-- Os parts continuam separados apenas para manutenção/histórico; o usuário não precisa trocar a loadstring por versão.

local SOURCE_COMMIT="9b671c5568633fe71a7253368801ccfb2a88e0da"
local REPO_PATH="Psicosenatico/Aimbot"
local PART_DIR="weapon_research_parts/"
local BASES={
    "https://cdn.jsdelivr.net/gh/"..REPO_PATH.."@"..SOURCE_COMMIT.."/"..PART_DIR,
    "https://raw.githubusercontent.com/"..REPO_PATH.."/"..SOURCE_COMMIT.."/"..PART_DIR
}
local PARTS={
    "V2_3_3.part1a",
    "V2_3_3.part1b",
    "V2_3_3.part2",
    "V2_3_3.part3",
    "V2_3_3.part4a",
    "V2_3_3.part4b1",
    "V2_3_3.part4b2a",
    "V2_3_3.part4b2b",
    "V2_3_4.patch1",
    "V2_3_4.shotlock.patch",
    "V2_3_4.clean.patch",
    "V2_3_4.ui.patch",
    "V2_3_4.finalize.patch",
    "V2_3_5.geometry_damage.patch",
    "V2_3_6.intershot.patch",
    "V2_3_7.wall_traversal.patch",
    "V2_3_8.team_barrier.patch",
    "V2_3_9.noclip_sync_target_context.patch",
    "V2_3_9.sync_index_guard.patch",
    "V2_3_10.relative_sync_dynamic_hp.patch",
    "V2_3_10.reconciled_sync_summary.patch",
    "V2_3_11_12.runtime_prebridge.patch",
    "V2_3_11.structural_safe.patch",
    "V2_3_12.dependency_gate.patch",
    "V2_3_12.origin_pipeline_structural_safe.patch",
    "V2_3_12.normal_wall_target_segment.patch",
    "V2_3_12.postrun_diagnostic_hotfix.patch",
    "V2_3_13.server_path_hypotheses_v2_structural_safe.patch",
    "V2_3_14.causal_hp_original_geometry_proxy_structural_safe.patch",
    "V2_3_15.temporal_stability_gate_structural_safe.patch"
}

local BOOT_VERSION="V2.3.15"
local ENV=(type(getgenv)=="function" and getgenv()) or _G
ENV.__PSICO_RESEARCH_PART_CACHE=type(ENV.__PSICO_RESEARCH_PART_CACHE)=="table" and ENV.__PSICO_RESEARCH_PART_CACHE or {}
local CACHE=ENV.__PSICO_RESEARCH_PART_CACHE

local function surfaceFailure(stage,msg)
    local text="Research "..BOOT_VERSION.." • "..tostring(stage)..": "..tostring(msg)
    pcall(function() warn("PSICOSENATICO • "..text) end)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification",{
            Title="PSICOSENATICO Research",
            Text=text,
            Duration=18
        })
    end)
    return text
end

local function validBody(body)
    if type(body)~="string" or #body<8 then return false end
    local lower=string.lower(body)
    if string.find(lower,"http 429",1,true) or string.find(lower,"too many requests",1,true) then return false end
    if string.sub(lower,1,15)=="<!doctype html>" then return false end
    return true
end

local function fetchPart(name,index)
    local cacheKey=SOURCE_COMMIT.."/"..name
    local cached=CACHE[cacheKey]
    if validBody(cached) then return cached,"CACHE" end

    local lastErr="sem tentativa"
    local waits={0.45,1.25,3.0}
    for baseIndex,base in ipairs(BASES) do
        for attempt=1,#waits do
            local url=base..name
            local ok,body=pcall(function() return game:HttpGet(url) end)
            if ok and validBody(body) then
                CACHE[cacheKey]=body
                task.wait(0.10)
                return body,(baseIndex==1 and "JSDELIVR" or "GITHUB_RAW")
            end
            lastErr=tostring(body)
            if string.find(string.lower(lastErr),"429",1,true) or string.find(string.lower(lastErr),"too many",1,true) then
                task.wait(waits[attempt])
            else
                task.wait(math.min(0.20*attempt,0.60))
            end
        end
    end
    error(surfaceFailure("CARREGAMENTO","parte "..tostring(index).." ("..name.."): "..lastErr.." • CDN+RAW esgotados"))
end

local chunks={}
local sourceMap={}
local sourceProviders={}
local newlineCountBefore=0
for i,name in ipairs(PARTS) do
    local body,provider=fetchPart(name,i)
    chunks[i]=body
    sourceProviders[name]=provider
    local _,insideNewlines=string.gsub(body,"\n","\n")
    local startLine=1+newlineCountBefore
    local endLine=startLine+insideNewlines
    sourceMap[#sourceMap+1]={name=name,index=i,startLine=startLine,endLine=endLine,provider=provider}
    newlineCountBefore=newlineCountBefore+insideNewlines
    if i<#PARTS then newlineCountBefore=newlineCountBefore+1 end
end

local source=table.concat(chunks,"\n")

local function mapSourceLine(lineNo)
    lineNo=tonumber(lineNo)
    if not lineNo then return nil end
    for _,m in ipairs(sourceMap) do
        if lineNo>=m.startLine and lineNo<=m.endLine then return m,lineNo-m.startLine+1 end
    end
    return nil
end

local function sourceLineText(lineNo)
    lineNo=tonumber(lineNo)
    if not lineNo or lineNo<1 then return nil end
    local current=0
    for line in string.gmatch(source.."\n","(.-)\n") do
        current=current+1
        if current==lineNo then return line end
    end
    return nil
end

if not string.find(source,'C.VERSION="V2.3.15"',1,true) then error(surfaceFailure("PREFLIGHT","versão V2.3.15 ausente da fonte remontada")) end
if not string.find(source,'__PSICO_RESEARCH_RUNTIME_PREBRIDGE_READY',1,true) then error(surfaceFailure("PREFLIGHT","prebridge anterior à V2.3.11 ausente")) end
if not string.find(source,'V2311_STRUCTURAL_SAFE_READY',1,true) then error(surfaceFailure("PREFLIGHT","base structural-safe V2.3.11 ausente")) end
if not string.find(source,'V2312_DEPENDENCY_GATE_READY',1,true) then error(surfaceFailure("PREFLIGHT","dependency gate V2.3.12 ausente")) end
if not string.find(source,'V2312_ORIGIN_PIPELINE_READY',1,true) then error(surfaceFailure("PREFLIGHT","pipeline Camera/Handle/Muzzle V2.3.12 ausente")) end
if not string.find(source,'V2312_NORMAL_WALL_SEGMENT_READY',1,true) then error(surfaceFailure("PREFLIGHT","correção parede antes/depois do alvo ausente")) end
if not string.find(source,'V2312_POSTRUN_HOTFIX_READY',1,true) then error(surfaceFailure("PREFLIGHT","hotfix Handle/sync V2.3.12 ausente")) end
if not string.find(source,'V2313_SERVER_PATH_HYPOTHESES_V2_READY',1,true) then error(surfaceFailure("PREFLIGHT","hipóteses Muzzle/Handle/AimPoint V2.3.13 ausentes")) end
if not string.find(source,'V2314_CAUSAL_HP_ORIGINAL_GEOMETRY_READY',1,true) then error(surfaceFailure("PREFLIGHT","camada HP causal + proxy geometria V2.3.14 ausente")) end
if not string.find(source,'V2315_TEMPORAL_STABILITY_GATE_READY',1,true) then error(surfaceFailure("PREFLIGHT","gate temporal V2.3.15 ausente")) end
if string.find(source,'V2_3_11.barrier_segment_direction_team_export.patch',1,true) then error(surfaceFailure("PREFLIGHT","patch V2.3.11 antigo detectado")) end
if string.find(source,'V2312_EVENT_BRIDGE_READY',1,true) then error(surfaceFailure("PREFLIGHT","bridge tardio antigo V2.3.12 detectado")) end
if string.find(source,'V2313_SERVER_PATH_HYPOTHESES_READY',1,true) then error(surfaceFailure("PREFLIGHT","patch V2.3.13 inicial incompleto detectado")) end
if not string.find(source,'Psicosenatico_WeaponResearch_V2_3_15_',1,true) then error(surfaceFailure("PREFLIGHT","nome de export V2_3_15 ausente")) end
if not string.find(source,'PAREDE_COMUM_ATRAS_DO_ALVO',1,true) then error(surfaceFailure("PREFLIGHT","regra de parede atrás do alvo ausente")) end
if not string.find(source,'MUZZLE_TO_AIM_POINT',1,true) or not string.find(source,'HANDLE_TO_AIM_POINT',1,true) then error(surfaceFailure("PREFLIGHT","variantes AimPoint incompletas")) end
if not string.find(source,'normalWallBetweenCameraAndTargetV2312',1,true) then error(surfaceFailure("PREFLIGHT","campo corrigido de parede comum ausente")) end
if not string.find(source,'QUEDA_HP_CONFIAVEL_COMPATIVEL_COM_ARMA',1,true) then error(surfaceFailure("PREFLIGHT","classificação causal de HP V2.3.14 ausente")) end
if not string.find(source,'CANDIDATO_FORTE_PENETRACAO_AUTORITATIVA_NAO_PROVADA',1,true) then error(surfaceFailure("PREFLIGHT","classe conservadora V2.3.14 ausente")) end
if not string.find(source,'CANDIDATO_FORTE_TEMPORALMENTE_ESTAVEL_NAO_PROVADO',1,true) then error(surfaceFailure("PREFLIGHT","classe temporalmente estável V2.3.15 ausente")) end
if not string.find(source,'CANDIDATO_DESCARTADO_GEOMETRIA_MUDOU_ENTRE_GATILHO_E_AMMO',1,true) then error(surfaceFailure("PREFLIGHT","regra de demotion temporal V2.3.15 ausente")) end

local compiler=loadstring
if type(compiler)~="function" then error(surfaceFailure("COMPILADOR","loadstring indisponível neste ambiente")) end
local fn,compileErr=compiler(source)
if not fn then
    local lineNo=tonumber(string.match(tostring(compileErr),":(%d+):"))
    local m,localLine=mapSourceLine(lineNo)
    local mapped=m and (m.name..":"..tostring(localLine).." • assembled:"..tostring(lineNo).." • "..tostring(m.provider)) or ("assembled:"..tostring(lineNo))
    error(surfaceFailure("COMPILAÇÃO",tostring(compileErr).." • "..mapped))
end

local okRun,result=xpcall(fn,function(e)
    local base=tostring(e)
    local okTrace,trace=pcall(function()
        if debug and type(debug.traceback)=="function" then return debug.traceback(base,2) end
        return base
    end)
    trace=okTrace and trace or base
    local lineNo=tonumber(string.match(base,":(%d+):")) or tonumber(string.match(trace,":(%d+):"))
    if lineNo then
        local m,localLine=mapSourceLine(lineNo)
        local src=sourceLineText(lineNo)
        local mapped=m and (m.name..":"..tostring(localLine).." • assembled:"..tostring(lineNo).." • "..tostring(m.provider)) or ("assembled:"..tostring(lineNo))
        if src and #src>180 then src=string.sub(src,1,180).."..." end
        return base.." • SOURCE_MAP="..mapped..(src and (" • CODE="..src) or "")
    end
    return trace
end)
if not okRun then error(surfaceFailure("RUNTIME ANTES/NA INICIALIZAÇÃO",result)) end
return result