-- PSICOSENATICO • WEAPON RESEARCH V2.3.4
-- Base íntegra V2.3.3 + patches finais V2.3.4 aplicados após o fechamento completo da fonte.
local SOURCE_COMMIT="04407d662bf732beb4b0ef9d96d84a219cd56069"
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
    "V2_3_4.finalize.patch"
}
local chunks={}
for i,name in ipairs(PARTS) do
    local ok,body=pcall(function()
        return game:HttpGet(BASE..name)
    end)
    if not ok or type(body)~="string" or #body==0 then
        error("PSICOSENATICO V2.3.4: falha ao carregar parte "..tostring(i).." ("..name.."): "..tostring(body))
    end
    chunks[i]=body
end
local source=table.concat(chunks)
if not string.find(source,'C.VERSION="V2.3.4"',1,true) then
    error("PSICOSENATICO V2.3.4: patch SHOT-LOCK não encontrado na fonte remontada")
end
local compiler=loadstring
if type(compiler)~="function" then
    error("PSICOSENATICO V2.3.4: loadstring indisponível neste ambiente")
end
local fn,err=compiler(source)
if not fn then
    error("PSICOSENATICO V2.3.4: erro de compilação: "..tostring(err))
end
return fn()
