-- PSICOSENATICO • WEAPON RESEARCH V2.3.13 • STRUCTURAL-SAFE + SOURCE MAP
-- Base V2.3.12 comprovada em runtime; V2.3.13 adiciona apenas hipoteses observacionais Muzzle/Handle/AimPoint.
-- Compatibility prebridge remains BEFORE V2.3.11; V2.3.12 dependencies remain gated explicitly.
-- Runtime errors are mapped back to PART name + local line + assembled line.
-- No gameplay/RemoteEvent/CollisionGroup changes are introduced by V2.3.13.
local SOURCE_COMMIT="036128e763640574b828a7789dfe2bd6e2e9dab2"
local BASE="https://raw.githubusercontent.com/Psicosenatico/Aimbot/"..SOURCE_COMMIT.."/weapon_research_parts/"
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
    "V2_3_13.server_path_hypotheses_v2_structural_safe.patch"
}

local function surfaceFailure(stage,msg)
    local text="Research V2.3.13 • "..tostring(stage)..": "..tostring(msg)
    pcall(function() warn("PSICOSENATICO • "..text) end)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification",{
            Title="PSICOSENATICO Research",
            Text=text,
            Duration=15
        })
    end)
    return text
end

local chunks={}
local sourceMap={}
local newlineCountBefore=0
for i,name in ipairs(PARTS) do
    local ok,body=pcall(function() return game:HttpGet(BASE..name) end)
    if not ok or type(body)~="string" or #body==0 then
        error(surfaceFailure("CARREGAMENTO","parte "..tostring(i).." ("..name.."): "..tostring(body)))
    end
    chunks[i]=body
    local _,insideNewlines=string.gsub(body,"\n","\n")
    local startLine=1+newlineCountBefore
    local endLine=startLine+insideNewlines
    sourceMap[#sourceMap+1]={name=name,index=i,startLine=startLine,endLine=endLine}
    newlineCountBefore=newlineCountBefore+insideNewlines
    if i<#PARTS then newlineCountBefore=newlineCountBefore+1 end
end

local source=table.concat(chunks,"\n")

local function mapSourceLine(lineNo)
    lineNo=tonumber(lineNo)
    if not lineNo then return nil end
    for _,m in ipairs(sourceMap) do
        if lineNo>=m.startLine and lineNo<=m.endLine then
            return m,lineNo-m.startLine+1
        end
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

if not string.find(source,'C.VERSION="V2.3.13"',1,true) then
    error(surfaceFailure("PREFLIGHT","versão V2.3.13 ausente da fonte remontada"))
end
if not string.find(source,'__PSICO_RESEARCH_RUNTIME_PREBRIDGE_READY',1,true) then
    error(surfaceFailure("PREFLIGHT","prebridge anterior à V2.3.11 ausente"))
end
if not string.find(source,'V2311_STRUCTURAL_SAFE_READY',1,true) then
    error(surfaceFailure("PREFLIGHT","base structural-safe V2.3.11 ausente"))
end
if not string.find(source,'V2312_DEPENDENCY_GATE_READY',1,true) then
    error(surfaceFailure("PREFLIGHT","dependency gate V2.3.12 ausente"))
end
if not string.find(source,'V2312_ORIGIN_PIPELINE_READY',1,true) then
    error(surfaceFailure("PREFLIGHT","pipeline Camera/Handle/Muzzle V2.3.12 ausente"))
end
if not string.find(source,'V2312_NORMAL_WALL_SEGMENT_READY',1,true) then
    error(surfaceFailure("PREFLIGHT","correção parede antes/depois do alvo ausente"))
end
if not string.find(source,'V2312_POSTRUN_HOTFIX_READY',1,true) then
    error(surfaceFailure("PREFLIGHT","hotfix Handle/sync V2.3.12 ausente"))
end
if not string.find(source,'V2313_SERVER_PATH_HYPOTHESES_V2_READY',1,true) then
    error(surfaceFailure("PREFLIGHT","hipoteses Muzzle/Handle/AimPoint V2.3.13 V2 ausentes"))
end
if string.find(source,'V2_3_11.barrier_segment_direction_team_export.patch',1,true) then
    error(surfaceFailure("PREFLIGHT","referência ao patch V2.3.11 antigo detectada"))
end
if string.find(source,'V2312_EVENT_BRIDGE_READY',1,true) then
    error(surfaceFailure("PREFLIGHT","bridge tardio antigo V2.3.12 ainda presente na montagem"))
end
if string.find(source,'V2313_SERVER_PATH_HYPOTHESES_READY',1,true) then
    error(surfaceFailure("PREFLIGHT","patch V2.3.13 inicial incompleto ainda presente na montagem"))
end
if not string.find(source,'Psicosenatico_WeaponResearch_V2_3_13_',1,true) then
    error(surfaceFailure("PREFLIGHT","nome físico de export V2_3_13 ausente"))
end
if not string.find(source,'PAREDE_COMUM_ATRAS_DO_ALVO',1,true) then
    error(surfaceFailure("PREFLIGHT","regra explícita de parede atrás do alvo ausente"))
end
if not string.find(source,'MUZZLE_TO_AIM_POINT',1,true) or not string.find(source,'HANDLE_TO_AIM_POINT',1,true) then
    error(surfaceFailure("PREFLIGHT","variantes AimPoint V2.3.13 incompletas"))
end
if not string.find(source,'normalWallBetweenCameraAndTargetV2312',1,true) then
    error(surfaceFailure("PREFLIGHT","campo corrigido de parede comum V2.3.12 não utilizado"))
end

local compiler=loadstring
if type(compiler)~="function" then
    error(surfaceFailure("COMPILADOR","loadstring indisponível neste ambiente"))
end
local fn,compileErr=compiler(source)
if not fn then
    local lineNo=tonumber(string.match(tostring(compileErr),":(%d+):"))
    local m,localLine=mapSourceLine(lineNo)
    local mapped=m and (m.name..":"..tostring(localLine).." • assembled:"..tostring(lineNo)) or ("assembled:"..tostring(lineNo))
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
        local mapped=m and (m.name..":"..tostring(localLine).." • assembled:"..tostring(lineNo)) or ("assembled:"..tostring(lineNo))
        if src and #src>180 then src=string.sub(src,1,180).."..." end
        return base.." • SOURCE_MAP="..mapped..(src and (" • CODE="..src) or "")
    end
    return trace
end)
if not okRun then
    error(surfaceFailure("RUNTIME ANTES/NA INICIALIZAÇÃO",result))
end
return result