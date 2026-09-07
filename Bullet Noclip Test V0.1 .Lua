-- PSICOSENATICO • BULLET NOCLIP TEST V0.13 • STRUCTURAL-SAFE LOADER
-- V0.8 PlayerOnly preservado; V0.13 corrige falso positivo de parede candidata atrás do alvo.
local SOURCE_COMMIT="438b810aff2bc572461b2e5c3ab0ef6642787dd3"
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
    "V0_10.shared_bus_target_context.patch",
    "V0_10.compact_bus.patch",
    "V0_11.bus_session_anchor.patch",
    "V0_12.barrier_segment_direction_team.patch",
    "V0_13.normal_wall_target_segment.patch"
}

local function surfaceFailure(stage,msg)
    local text="Bullet NoClip V0.13 • "..tostring(stage)..": "..tostring(msg)
    pcall(function() warn("PSICOSENATICO • "..text) end)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification",{
            Title="PSICOSENATICO Bullet NoClip",
            Text=text,
            Duration=12
        })
    end)
    return text
end

local chunks={}
for i,name in ipairs(PARTS) do
    local ok,body=pcall(function() return game:HttpGet(BASE..name) end)
    if not ok or type(body)~="string" or #body==0 then
        error(surfaceFailure("CARREGAMENTO","parte "..tostring(i).." ("..name.."): "..tostring(body)))
    end
    chunks[i]=body
end

local source=table.concat(chunks,"\n")
if not string.find(source,'C.VERSION="V0.13"',1,true) then
    error(surfaceFailure("PREFLIGHT","versão V0.13 ausente da fonte remontada"))
end
if not string.find(source,'V013_READY',1,true) then
    error(surfaceFailure("PREFLIGHT","marcador V013_READY ausente"))
end
if not string.find(source,'correctsLegacyBehindTargetFalsePositive=true',1,true) then
    error(surfaceFailure("PREFLIGHT","regra de parede atrás do alvo ausente"))
end
if not string.find(source,'preservesV08Mechanism=true',1,true) then
    error(surfaceFailure("PREFLIGHT","confirmação de preservação PlayerOnly/V0.8 ausente"))
end
if not string.find(source,'Psicosenatico_BulletNoclip_Test_V0_13_',1,true) then
    error(surfaceFailure("PREFLIGHT","nome físico de export V0_13 ausente"))
end

local compiler=loadstring
if type(compiler)~="function" then
    error(surfaceFailure("COMPILADOR","loadstring indisponível neste ambiente"))
end
local fn,compileErr=compiler(source)
if not fn then
    error(surfaceFailure("COMPILAÇÃO",compileErr))
end
local okRun,result=xpcall(fn,function(e)
    local base=tostring(e)
    local okTrace,trace=pcall(function()
        if debug and type(debug.traceback)=="function" then return debug.traceback(base,2) end
        return base
    end)
    return okTrace and trace or base
end)
if not okRun then
    error(surfaceFailure("RUNTIME ANTES/NA INICIALIZAÇÃO",result))
end
return result