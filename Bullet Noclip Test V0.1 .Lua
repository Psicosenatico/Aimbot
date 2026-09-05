-- PSICOSENATICO • BULLET NOCLIP TEST V0.5
-- V0.3 validada + V0.4 filtro explícito + V0.5 diagnóstico RespectCanCollide.
local SOURCE_COMMIT="6a0d7829568e3e38e5e54b5b9c57f20af9c522a0"
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
    "V0_5.respect_can_collide.patch"
}
local chunks={}
for i,name in ipairs(PARTS) do
    local ok,body=pcall(function() return game:HttpGet(BASE..name) end)
    if not ok or type(body)~="string" or #body==0 then
        error("PSICOSENATICO V0.5: falha ao carregar parte "..tostring(i).." ("..name.."): "..tostring(body))
    end
    chunks[i]=body
end
local source=table.concat(chunks)
if not string.find(source,'C.VERSION="V0.5"',1,true) then
    error("PSICOSENATICO V0.5: patch RespectCanCollide não encontrado na fonte remontada")
end
local compiler=loadstring
if type(compiler)~="function" then error("PSICOSENATICO V0.5: loadstring indisponível") end
local fn,err=compiler(source)
if not fn then error("PSICOSENATICO V0.5: erro de compilação: "..tostring(err)) end
return fn()
