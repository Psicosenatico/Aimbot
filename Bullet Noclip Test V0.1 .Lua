-- PSICOSENATICO • BULLET NOCLIP TEST V0.15 • UNIVERSAL RAY CORRIDOR + 429 RESILIENCE
-- Functional rule: traverse all Workspace geometry except Workspace.Tycoons; humanoid parts remain targets.
-- V0.15 adds temporary aim-corridor query/collision suppression so the local shot path is independent of ray CollisionGroup.
-- Stable main loader; internal parts are pinned to an immutable SOURCE_COMMIT.

local SOURCE_COMMIT="09e09871bdd4d86f343e9be0f8c738233be4d500"
local REPO_PATH="Psicosenatico/Aimbot"
local PART_DIR="bullet_noclip_test_parts/"
local BASES={
    "https://cdn.jsdelivr.net/gh/"..REPO_PATH.."@"..SOURCE_COMMIT.."/"..PART_DIR,
    "https://raw.githubusercontent.com/"..REPO_PATH.."/"..SOURCE_COMMIT.."/"..PART_DIR
}
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
    "V0_13.normal_wall_target_segment.patch",
    "V0_14.all_non_tycoon_geometry.patch",
    "V0_15.universal_ray_corridor.patch"
}

local BOOT_VERSION="V0.15"
local ENV=(type(getgenv)=="function" and getgenv()) or _G
ENV.__PSICO_NOCLIP_PART_CACHE=type(ENV.__PSICO_NOCLIP_PART_CACHE)=="table" and ENV.__PSICO_NOCLIP_PART_CACHE or {}
local CACHE=ENV.__PSICO_NOCLIP_PART_CACHE

local function surfaceFailure(stage,msg)
    local text="Bullet NoClip "..BOOT_VERSION.." • "..tostring(stage)..": "..tostring(msg)
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

local function validBody(body)
    if type(body)~="string" or #body<8 then return false end
    local lower=string.lower(body)
    if string.find(lower,"http 429",1,true) or string.find(lower,"too many requests",1,true) then return false end
    if string.sub(lower,1,15)=="<!doctype html>" then return false end
    return true
end

local function fetchPart(name,index)
    local key=SOURCE_COMMIT.."/"..name
    local cached=CACHE[key]
    if validBody(cached) then return cached,"CACHE" end
    local waits={0.45,1.25,3.0}
    local lastErr="sem tentativa"
    for baseIndex,base in ipairs(BASES) do
        for attempt=1,#waits do
            local ok,body=pcall(function() return game:HttpGet(base..name) end)
            if ok and validBody(body) then
                CACHE[key]=body
                task.wait(0.08)
                return body,(baseIndex==1 and "JSDELIVR" or "GITHUB_RAW")
            end
            lastErr=tostring(body)
            local low=string.lower(lastErr)
            if string.find(low,"429",1,true) or string.find(low,"too many",1,true) then
                task.wait(waits[attempt])
            else
                task.wait(math.min(0.18*attempt,0.55))
            end
        end
    end
    error(surfaceFailure("CARREGAMENTO","parte "..tostring(index).." ("..name.."): "..lastErr.." • CDN+RAW esgotados"))
end

local chunks={}
for i,name in ipairs(PARTS) do
    local body=fetchPart(name,i)
    chunks[i]=body
end

local source=table.concat(chunks,"\n")
if not string.find(source,'C.VERSION="V0.15"',1,true) then error(surfaceFailure("PREFLIGHT","versão V0.15 ausente")) end
if not string.find(source,'V014_ALL_NON_TYCOON_READY',1,true) then error(surfaceFailure("PREFLIGHT","base V0.14 ausente")) end
if not string.find(source,'V015_UNIVERSAL_RAY_CORRIDOR_READY',1,true) then error(surfaceFailure("PREFLIGHT","patch V0.15 ausente")) end
if not string.find(source,'Psicosenatico_BulletNoclip_Test_V0_15_',1,true) then error(surfaceFailure("PREFLIGHT","export V0.15 ausente")) end

local compiler=loadstring
if type(compiler)~="function" then error(surfaceFailure("COMPILADOR","loadstring indisponível neste ambiente")) end
local fn,compileErr=compiler(source)
if not fn then error(surfaceFailure("COMPILAÇÃO",compileErr)) end
local okRun,result=xpcall(fn,function(e)
    local base=tostring(e)
    local okTrace,trace=pcall(function()
        if debug and type(debug.traceback)=="function" then return debug.traceback(base,2) end
        return base
    end)
    return okTrace and trace or base
end)
if not okRun then error(surfaceFailure("RUNTIME ANTES/NA INICIALIZAÇÃO",result)) end
return result