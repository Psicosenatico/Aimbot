-- PSICOSENATICO • WEAPON RESEARCH V2.3.17 • STABLE BOOTSTRAP + 429 RESILIENCE
-- Esta URL principal deve permanecer estável. As partes internas continuam versionadas por SOURCE_COMMIT.
-- Runtime: CDN primária + GitHub Raw fallback + cache por sessão + retry progressivo.
-- V2.3.17 preserva sync robusto/Tycoon-only e recupera castRays/canPierce via decompile sem require ou tiros obrigatórios.

local SOURCE_COMMIT="abeb4995b49a2054b1c3dfa36a0f468bc26c4eca"
local REPO_PATH="Psicosenatico/Aimbot"
local PART_DIR="weapon_research_parts/"
local BASES={
    "https://cdn.jsdelivr.net/gh/"..REPO_PATH.."@"..SOURCE_COMMIT.."/"..PART_DIR,
    "https://raw.githubusercontent.com/"..REPO_PATH.."/"..SOURCE_COMMIT.."/"..PART_DIR
}
local PARTS={
    "V2_3_3.part1a","V2_3_3.part1b","V2_3_3.part2","V2_3_3.part3","V2_3_3.part4a","V2_3_3.part4b1","V2_3_3.part4b2a","V2_3_3.part4b2b",
    "V2_3_4.patch1","V2_3_4.shotlock.patch","V2_3_4.clean.patch","V2_3_4.ui.patch","V2_3_4.finalize.patch",
    "V2_3_5.geometry_damage.patch","V2_3_6.intershot.patch","V2_3_7.wall_traversal.patch","V2_3_8.team_barrier.patch",
    "V2_3_9.noclip_sync_target_context.patch","V2_3_9.sync_index_guard.patch","V2_3_10.relative_sync_dynamic_hp.patch","V2_3_10.reconciled_sync_summary.patch",
    "V2_3_11_12.runtime_prebridge.patch","V2_3_11.structural_safe.patch","V2_3_12.dependency_gate.patch","V2_3_12.origin_pipeline_structural_safe.patch",
    "V2_3_12.normal_wall_target_segment.patch","V2_3_12.postrun_diagnostic_hotfix.patch","V2_3_13.server_path_hypotheses_v2_structural_safe.patch",
    "V2_3_14.causal_hp_original_geometry_proxy_structural_safe.patch","V2_3_15.temporal_stability_gate_structural_safe.patch",
    "V2_3_16.sync_repair_functional_policy_structural_safe.patch","V2_3_16b.sync_capture_hotfix.patch","V2_3_16c.final_sync_export_restore.patch",
    "V2_3_17.source_recovery_structural_safe.patch","V2_3_17b.source_only_export.patch"
}

local BOOT_VERSION="V2.3.17"
local ENV=(type(getgenv)=="function" and getgenv()) or _G
ENV.__PSICO_RESEARCH_PART_CACHE=type(ENV.__PSICO_RESEARCH_PART_CACHE)=="table" and ENV.__PSICO_RESEARCH_PART_CACHE or {}
local CACHE=ENV.__PSICO_RESEARCH_PART_CACHE

local function surfaceFailure(stage,msg)
 local text="Research "..BOOT_VERSION.." • "..tostring(stage)..": "..tostring(msg)
 pcall(function() warn("PSICOSENATICO • "..text) end)
 pcall(function() game:GetService("StarterGui"):SetCore("SendNotification",{Title="PSICOSENATICO Research",Text=text,Duration=18}) end)
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
 local key=SOURCE_COMMIT.."/"..name
 local cached=CACHE[key]
 if validBody(cached) then return cached,"CACHE" end
 local waits={0.45,1.25,3.0}
 local lastErr="sem tentativa"
 for baseIndex,base in ipairs(BASES) do
  for attempt=1,#waits do
   local ok,body=pcall(function() return game:HttpGet(base..name) end)
   if ok and validBody(body) then CACHE[key]=body;task.wait(0.10);return body,(baseIndex==1 and "JSDELIVR" or "GITHUB_RAW") end
   lastErr=tostring(body)
   local low=string.lower(lastErr)
   if string.find(low,"429",1,true) or string.find(low,"too many requests",1,true) then task.wait(waits[attempt]) else task.wait(math.min(0.20*attempt,0.60)) end
  end
 end
 error(surfaceFailure("CARREGAMENTO","parte "..tostring(index).." ("..name.."): "..lastErr.." • CDN+RAW esgotados"))
end

local chunks={}
local sourceMap={}
local newlineCountBefore=0
for i,name in ipairs(PARTS) do
 local body,provider=fetchPart(name,i)
 chunks[i]=body
 local _,inside=string.gsub(body,"\n","\n")
 local startLine=1+newlineCountBefore
 local endLine=startLine+inside
 sourceMap[#sourceMap+1]={name=name,index=i,startLine=startLine,endLine=endLine,provider=provider}
 newlineCountBefore=newlineCountBefore+inside
 if i<#PARTS then newlineCountBefore+=1 end
end
local source=table.concat(chunks,"\n")

local function mapSourceLine(lineNo)
 lineNo=tonumber(lineNo);if not lineNo then return nil end
 for _,m in ipairs(sourceMap) do if lineNo>=m.startLine and lineNo<=m.endLine then return m,lineNo-m.startLine+1 end end
 return nil
end
local function sourceLineText(lineNo)
 lineNo=tonumber(lineNo);if not lineNo or lineNo<1 then return nil end
 local current=0
 for line in string.gmatch(source.."\n","(.-)\n") do current+=1;if current==lineNo then return line end end
 return nil
end

if not string.find(source,'C.VERSION="V2.3.17"',1,true) then error(surfaceFailure("PREFLIGHT","versão V2.3.17 ausente")) end
if not string.find(source,'__PSICO_RESEARCH_RUNTIME_PREBRIDGE_READY',1,true) then error(surfaceFailure("PREFLIGHT","prebridge ausente")) end
if not string.find(source,'V2311_STRUCTURAL_SAFE_READY',1,true) then error(surfaceFailure("PREFLIGHT","V2.3.11 ausente")) end
if not string.find(source,'V2312_DEPENDENCY_GATE_READY',1,true) then error(surfaceFailure("PREFLIGHT","dependency gate V2.3.12 ausente")) end
if not string.find(source,'V2312_ORIGIN_PIPELINE_READY',1,true) then error(surfaceFailure("PREFLIGHT","pipeline V2.3.12 ausente")) end
if not string.find(source,'V2312_NORMAL_WALL_SEGMENT_READY',1,true) then error(surfaceFailure("PREFLIGHT","segmento parede V2.3.12 ausente")) end
if not string.find(source,'V2312_POSTRUN_HOTFIX_READY',1,true) then error(surfaceFailure("PREFLIGHT","hotfix V2.3.12 ausente")) end
if not string.find(source,'V2313_SERVER_PATH_HYPOTHESES_V2_READY',1,true) then error(surfaceFailure("PREFLIGHT","V2.3.13 ausente")) end
if not string.find(source,'V2314_CAUSAL_HP_ORIGINAL_GEOMETRY_READY',1,true) then error(surfaceFailure("PREFLIGHT","V2.3.14 ausente")) end
if not string.find(source,'V2315_TEMPORAL_STABILITY_GATE_READY',1,true) then error(surfaceFailure("PREFLIGHT","V2.3.15 ausente")) end
if not string.find(source,'V2316_ROBUST_SYNC_POLICY_READY',1,true) then error(surfaceFailure("PREFLIGHT","V2.3.16 ausente")) end
if not string.find(source,'V2316B_SYNC_CAPTURE_HOTFIX_READY',1,true) then error(surfaceFailure("PREFLIGHT","hotfix V2.3.16B ausente")) end
if not string.find(source,'V2316C_FINAL_SYNC_EXPORT_READY',1,true) then error(surfaceFailure("PREFLIGHT","restauração final V2.3.16C ausente")) end
if not string.find(source,'V2317_SOURCE_RECOVERY_READY',1,true) then error(surfaceFailure("PREFLIGHT","source recovery V2.3.17 ausente")) end
if not string.find(source,'V2317B_SOURCE_ONLY_EXPORT_READY',1,true) then error(surfaceFailure("PREFLIGHT","source-only export V2.3.17B ausente")) end
if string.find(source,'V2313_SERVER_PATH_HYPOTHESES_READY',1,true) then error(surfaceFailure("PREFLIGHT","V2.3.13 inicial incompleto detectado")) end
if not string.find(source,'SEQUENCE_SCORED_MONOTONIC_OFFSET',1,true) then error(surfaceFailure("PREFLIGHT","sync robusto V2.3.16 ausente")) end
if not string.find(source,'ONLY_WORKSPACE_TYCOONS_PROTECTED',1,true) then error(surfaceFailure("PREFLIGHT","política Tycoon-only ausente")) end
if not string.find(source,'SEQUENCE_SCORED_OFFSET_MULTI_RETURN_FIXED',1,true) then error(surfaceFailure("PREFLIGHT","hotfix multi-return V2.3.16B ausente")) end
if not string.find(source,'FINAL_POST_WRAPPER_SYNC_RESTORE',1,true) then error(surfaceFailure("PREFLIGHT","autoridade final de sync V2.3.16C ausente")) end
if not string.find(source,'decompilePreferred=true',1,true) then error(surfaceFailure("PREFLIGHT","marcador decompile V2.3.17 ausente")) end
if not string.find(source,'requiresShots=false',1,true) then error(surfaceFailure("PREFLIGHT","source-only sem tiros V2.3.17B ausente")) end
if not string.find(source,'noRequire=true',1,true) or not string.find(source,'noRemoteCalls=true',1,true) then error(surfaceFailure("PREFLIGHT","garantia read-only V2.3.17 ausente")) end
if not string.find(source,'Psicosenatico_WeaponResearch_V2_3_17_',1,true) then error(surfaceFailure("PREFLIGHT","export V2.3.17 ausente")) end
if not string.find(source,'normalWallBetweenCameraAndTargetV2312',1,true) then error(surfaceFailure("PREFLIGHT","campo parede corrigido ausente")) end
if not string.find(source,'QUEDA_HP_CONFIAVEL_COMPATIVEL_COM_ARMA',1,true) then error(surfaceFailure("PREFLIGHT","HP causal ausente")) end
if not string.find(source,'CANDIDATO_DESCARTADO_GEOMETRIA_MUDOU_ENTRE_GATILHO_E_AMMO',1,true) then error(surfaceFailure("PREFLIGHT","gate temporal ausente")) end

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
 local okTrace,trace=pcall(function() if debug and type(debug.traceback)=="function" then return debug.traceback(base,2) end return base end)
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