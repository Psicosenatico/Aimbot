-- PSICOSENATICO • WEAPON RESEARCH V2.3.10
-- Base íntegra V2.3.9 + sync relativo NoClip por sessão e HP pré-trigger dependente da cadência.
local SOURCE_COMMIT="886f644d50d252b1a6b2618d1705ec5c1bfbba14"
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
    "V2_3_10.relative_sync_dynamic_hp.patch"
}
local chunks={}
for i,name in ipairs(PARTS) do
    local ok,body=pcall(function() return game:HttpGet(BASE..name) end)
    if not ok or type(body)~="string" or #body==0 then
        error("PSICOSENATICO V2.3.10: falha ao carregar parte "..tostring(i).." ("..name.."): "..tostring(body))
    end
    chunks[i]=body
end
local source=table.concat(chunks)
if not string.find(source,'C.VERSION="V2.3.10"',1,true) then
    error("PSICOSENATICO V2.3.10: patch final de sync relativo/HP não encontrado")
end
if not string.find(source,'NOCLIP_ANCHOR_MAX_DT',1,true) then
    error("PSICOSENATICO V2.3.10: âncora temporal do sync não encontrada")
end
local compiler=loadstring
if type(compiler)~="function" then error("PSICOSENATICO V2.3.10: loadstring indisponível neste ambiente") end
local fn,err=compiler(source)
if not fn then error("PSICOSENATICO V2.3.10: erro de compilação: "..tostring(err)) end
return fn()