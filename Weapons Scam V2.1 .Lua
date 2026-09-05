-- PSICOSENATICO • WEAPON RESEARCH V2.3.6
-- Base íntegra V2.3.3 + SHOT-LOCK/OBB V2.3.5 + HP inter-shot/collision-group diagnostics V2.3.6.
local SOURCE_COMMIT="5cdbbafada11c51b457eaea9e33741dd15330e91"
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
    "V2_3_6.intershot.patch"
}
local chunks={}
for i,name in ipairs(PARTS) do
    local ok,body=pcall(function() return game:HttpGet(BASE..name) end)
    if not ok or type(body)~="string" or #body==0 then
        error("PSICOSENATICO V2.3.6: falha ao carregar parte "..tostring(i).." ("..name.."): "..tostring(body))
    end
    chunks[i]=body
end
local source=table.concat(chunks)
if not string.find(source,'C.VERSION="V2.3.6"',1,true) then
    error("PSICOSENATICO V2.3.6: patch final não encontrado na fonte remontada")
end
local compiler=loadstring
if type(compiler)~="function" then error("PSICOSENATICO V2.3.6: loadstring indisponível neste ambiente") end
local fn,err=compiler(source)
if not fn then error("PSICOSENATICO V2.3.6: erro de compilação: "..tostring(err)) end
return fn()