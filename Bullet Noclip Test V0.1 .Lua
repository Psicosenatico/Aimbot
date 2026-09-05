-- PSICOSENATICO • BULLET NOCLIP TEST V0.6
-- V0.3/V0.4/V0.5 diagnósticos + V0.6 CollisionGroup Split e identidade por debugId.
local SOURCE_COMMIT="5cdbbafada11c51b457eaea9e33741dd15330e91"
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
    "V0_6.collision_group_split.patch"
}
local chunks={}
for i,name in ipairs(PARTS) do
    local ok,body=pcall(function() return game:HttpGet(BASE..name) end)
    if not ok or type(body)~="string" or #body==0 then
        error("PSICOSENATICO V0.6: falha ao carregar parte "..tostring(i).." ("..name.."): "..tostring(body))
    end
    chunks[i]=body
end
local source=table.concat(chunks)
if not string.find(source,'C.VERSION="V0.6"',1,true) then
    error("PSICOSENATICO V0.6: patch CollisionGroup Split não encontrado na fonte remontada")
end
local compiler=loadstring
if type(compiler)~="function" then error("PSICOSENATICO V0.6: loadstring indisponível") end
local fn,err=compiler(source)
if not fn then error("PSICOSENATICO V0.6: erro de compilação: "..tostring(err)) end
return fn()