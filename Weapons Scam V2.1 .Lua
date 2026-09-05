-- PSICOSENATICO • WEAPON RESEARCH V2.3.3
-- Loader versionado: remonta a fonte V2.3.3 validada a partir de partes imutáveis do mesmo repositório.
local SOURCE_COMMIT="38cd27685e40a8bfc90ae7b325ad6f1584789482"
local BASE="https://raw.githubusercontent.com/Psicosenatico/Aimbot/"..SOURCE_COMMIT.."/weapon_research_parts/"
local PARTS={
    "V2_3_3.part1a",
    "V2_3_3.part1b",
    "V2_3_3.part2",
    "V2_3_3.part3",
    "V2_3_3.part4a",
    "V2_3_3.part4b1",
    "V2_3_3.part4b2a",
    "V2_3_3.part4b2b"
}
local chunks={}
for i,name in ipairs(PARTS) do
    local ok,body=pcall(function()
        return game:HttpGet(BASE..name)
    end)
    if not ok or type(body)~="string" or #body==0 then
        error("PSICOSENATICO V2.3.3: falha ao carregar parte "..tostring(i).." ("..name.."): "..tostring(body))
    end
    chunks[i]=body
end
local source=table.concat(chunks)
if not string.find(source,'VERSION="V2.3.3"',1,true) then
    error("PSICOSENATICO V2.3.3: fonte remontada não corresponde à versão esperada")
end
local compiler=loadstring
if type(compiler)~="function" then
    error("PSICOSENATICO V2.3.3: loadstring indisponível neste ambiente")
end
local fn,err=compiler(source)
if not fn then
    error("PSICOSENATICO V2.3.3: erro de compilação: "..tostring(err))
end
return fn()
