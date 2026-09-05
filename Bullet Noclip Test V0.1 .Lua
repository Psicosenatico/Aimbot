-- PSICOSENATICO • BULLET NOCLIP TEST V0.4
-- V0.3 validada + diagnóstico V0.4 de raycast com exclusão explícita das paredes candidatas.
local SOURCE_COMMIT="d64ddd73c18505179b5f526889128a38f3af6ff5"
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
    "V0_4.ui.patch"
}
local chunks={}
for i,name in ipairs(PARTS) do
    local ok,body=pcall(function() return game:HttpGet(BASE..name) end)
    if not ok or type(body)~="string" or #body==0 then
        error("PSICOSENATICO V0.4: falha ao carregar parte "..tostring(i).." ("..name.."): "..tostring(body))
    end
    chunks[i]=body
end
local source=table.concat(chunks)
if not string.find(source,'C.VERSION="V0.4"',1,true) then
    error("PSICOSENATICO V0.4: patch de diagnóstico não encontrado na fonte remontada")
end
local compiler=loadstring
if type(compiler)~="function" then error("PSICOSENATICO V0.4: loadstring indisponível") end
local fn,err=compiler(source)
if not fn then error("PSICOSENATICO V0.4: erro de compilação: "..tostring(err)) end
return fn()
