-- PSICOSENATICO • BULLET NOCLIP TEST V0.2
-- Loader versionado da fonte validada.
local SOURCE_COMMIT="897e533e9234d726baca63dfbe47ca3636c83e7e"
local BASE="https://raw.githubusercontent.com/Psicosenatico/Aimbot/"..SOURCE_COMMIT.."/bullet_noclip_test_parts/"
local PARTS={"V0_2.part1","V0_2.part2","V0_2.part3","V0_2.part4","V0_2.part5"}
local chunks={}
for i,name in ipairs(PARTS) do
    local ok,body=pcall(function() return game:HttpGet(BASE..name) end)
    if not ok or type(body)~="string" or #body==0 then
        error("PSICOSENATICO V0.2: falha ao carregar parte "..tostring(i).." ("..name.."): "..tostring(body))
    end
    chunks[i]=body
end
local source=table.concat(chunks)
if not string.find(source,'VERSION="V0.2"',1,true) then
    error("PSICOSENATICO V0.2: fonte remontada não corresponde à versão esperada")
end
local compiler=loadstring
if type(compiler)~="function" then error("PSICOSENATICO V0.2: loadstring indisponível") end
local fn,err=compiler(source)
if not fn then error("PSICOSENATICO V0.2: erro de compilação: "..tostring(err)) end
return fn()
