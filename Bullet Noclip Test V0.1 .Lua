-- PSICOSENATICO • BULLET NOCLIP TEST V0.10
-- V0.8 mecanismo por CollisionGroup existente + V0.9 barreira de time + V0.10 shared bus/contexto do alvo.
local SOURCE_COMMIT="73a42b65541a06dd4a338136492b93a2e4373226"
local BASE="https://raw.githubusercontent.com/Psicosenatico/Aimbot/"..SOURCE_COMMIT.."/bullet_noclip_test_parts/"
local PARTS={
    "V0_3.part1",
    "V0_4.patch1",
    "V0_3.part2",
    "V0_4.filteredray.patch",
    "V0_3.part3",
    "V0_4.export.patch",
    "V0_3.part4",
    "V0_3.part5",
    "V0_4.ui.patch",
    "V0_5.respect_can_collide.patch",
    "V0_6.collision_group_split.patch",
    "V0_7.wall_traversal.patch",
    "V0_8.existing_group_strategy.patch",
    "V0_9.team_barrier.patch",
    "V0_10.shared_bus_target_context.patch"
}
local chunks={}
for i,name in ipairs(PARTS) do
    local ok,body=pcall(function() return game:HttpGet(BASE..name) end)
    if not ok or type(body)~="string" or #body==0 then
        error("PSICOSENATICO V0.10: falha ao carregar parte "..tostring(i).." ("..name.."): "..tostring(body))
    end
    chunks[i]=body
end
local source=table.concat(chunks)
if not string.find(source,'C.VERSION="V0.10"',1,true) then
    error("PSICOSENATICO V0.10: patch shared bus/contexto não encontrado na fonte remontada")
end
local compiler=loadstring
if type(compiler)~="function" then error("PSICOSENATICO V0.10: loadstring indisponível") end
local fn,err=compiler(source)
if not fn then error("PSICOSENATICO V0.10: erro de compilação: "..tostring(err)) end
return fn()