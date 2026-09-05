-- PSICOSENATICO • WEAPON RESEARCH V2.3.11
-- Base íntegra V2.3.10 + barreira efetiva por segmento, direção/Team e export físico corrigido.
local SOURCE_COMMIT="63a384f11fdc52856230ebae2b0fd1532d9aa862"
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
    "V2_3_11.barrier_segment_direction_team_export.patch"
}
local chunks={}
for i,name in ipairs(PARTS) do
    local ok,body=pcall(function() return game:HttpGet(BASE..name) end)
    if not ok or type(body)~="string" or #body==0 then
        error("PSICOSENATICO V2.3.11: falha ao carregar parte "..tostring(i).." ("..name.."): "..tostring(body))
    end
    chunks[i]=body
end
local source=table.concat(chunks)
if not string.find(source,'C.VERSION="V2.3.11"',1,true) then
    error("PSICOSENATICO V2.3.11: patch final não encontrado")
end
if not string.find(source,'effectiveBarrierRuleV2311',1,true) then
    error("PSICOSENATICO V2.3.11: regra de barreira efetiva ausente")
end
if not string.find(source,'Psicosenatico_WeaponResearch_V2_3_11_',1,true) then
    error("PSICOSENATICO V2.3.11: export físico V2_3_11 ausente")
end
local compiler=loadstring
if type(compiler)~="function" then error("PSICOSENATICO V2.3.11: loadstring indisponível neste ambiente") end
local fn,err=compiler(source)
if not fn then error("PSICOSENATICO V2.3.11: erro de compilação: "..tostring(err)) end
return fn()