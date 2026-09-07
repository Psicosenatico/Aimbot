-- PSICOSENATICO • WEAPON RESEARCH V2.3.12 • STRUCTURAL-SAFE
-- Base V2.3.11 comprovada em runtime + V2.3.12 isolada em closures.
-- Adiciona Camera/Head/HRP/Handle/Muzzle, timeline T0..T6, retry de sync e correção parede antes/depois do alvo.
local SOURCE_COMMIT="d1cece39144e660d21edbeebb61c7d65b7d12e66"
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
    "V2_3_11.structural_safe.patch",
    "V2_3_12.event_bridge.patch",
    "V2_3_12.origin_pipeline_structural_safe.patch",
    "V2_3_12.normal_wall_target_segment.patch"
}

local function surfaceFailure(stage,msg)
    local text="Research V2.3.12 • "..tostring(stage)..": "..tostring(msg)
    pcall(function() warn("PSICOSENATICO • "..text) end)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification",{
            Title="PSICOSENATICO Research",
            Text=text,
            Duration=12
        })
    end)
    return text
end

local chunks={}
for i,name in ipairs(PARTS) do
    local ok,body=pcall(function() return game:HttpGet(BASE..name) end)
    if not ok or type(body)~="string" or #body==0 then
        error(surfaceFailure("CARREGAMENTO","parte "..tostring(i).." ("..name.."): "..tostring(body)))
    end
    chunks[i]=body
end

local source=table.concat(chunks,"\n")
if not string.find(source,'C.VERSION="V2.3.12"',1,true) then
    error(surfaceFailure("PREFLIGHT","versão V2.3.12 ausente da fonte remontada"))
end
if not string.find(source,'V2311_STRUCTURAL_SAFE_READY',1,true) then
    error(surfaceFailure("PREFLIGHT","base structural-safe V2.3.11 ausente"))
end
if not string.find(source,'V2312_EVENT_BRIDGE_READY',1,true) then
    error(surfaceFailure("PREFLIGHT","event bridge estrutural V2.3.12 ausente"))
end
if not string.find(source,'V2312_ORIGIN_PIPELINE_READY',1,true) then
    error(surfaceFailure("PREFLIGHT","pipeline Camera/Handle/Muzzle V2.3.12 ausente"))
end
if not string.find(source,'V2312_NORMAL_WALL_SEGMENT_READY',1,true) then
    error(surfaceFailure("PREFLIGHT","correção parede antes/depois do alvo ausente"))
end
if string.find(source,'V2_3_11.barrier_segment_direction_team_export.patch',1,true) then
    error(surfaceFailure("PREFLIGHT","referência ao patch V2.3.11 antigo detectada"))
end
if not string.find(source,'Psicosenatico_WeaponResearch_V2_3_12_',1,true) then
    error(surfaceFailure("PREFLIGHT","nome físico de export V2_3_12 ausente"))
end
if not string.find(source,'PAREDE_COMUM_ATRAS_DO_ALVO',1,true) then
    error(surfaceFailure("PREFLIGHT","regra explícita de parede atrás do alvo ausente"))
end

local compiler=loadstring
if type(compiler)~="function" then
    error(surfaceFailure("COMPILADOR","loadstring indisponível neste ambiente"))
end
local fn,compileErr=compiler(source)
if not fn then
    error(surfaceFailure("COMPILAÇÃO",compileErr))
end

local okRun,result=xpcall(fn,function(e)
    local base=tostring(e)
    local okTrace,trace=pcall(function()
        if debug and type(debug.traceback)=="function" then return debug.traceback(base,2) end
        return base
    end)
    return okTrace and trace or base
end)
if not okRun then
    error(surfaceFailure("RUNTIME ANTES/NA INICIALIZAÇÃO",result))
end
return result