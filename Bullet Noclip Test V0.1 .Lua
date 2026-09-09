-- PSICOSENATICO • BULLET NOCLIP TEST V0.19 • NATIVE CANPIERCE + SAFE DEFAULT BYPASS + 429 RESILIENCE
-- Functional rule: everything outside Workspace.Tycoons is bullet-passable; Humanoids remain targets.
-- V0.19 keeps the native canPierce hook and uses only an empirically safe EXISTING CollisionGroup to skip static non-Tycoon BaseParts in ray group Default.
-- CanCollide/CanQuery are never written. V0.14/V0.15/V0.16/V0.17 remain intentionally NOT loaded directly.
-- Stable main loader; internal parts are pinned to an immutable SOURCE_COMMIT.

local SOURCE_COMMIT="3f34c0ebb5561017423ce0a9413ee51fe1e9a6b8"
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
    "V0_18.native_canpierce_hook_structural_safe.patch",
    "V0_19.native_plus_default_bypass_structural_safe.patch"
}

local BOOT_VERSION="V0.19"
local ENV=(type(getgenv)=="function" and getgenv()) or _G
ENV.__PSICO_NOCLIP_PART_CACHE=type(ENV.__PSICO_NOCLIP_PART_CACHE)=="table" and ENV.__PSICO_NOCLIP_PART_CACHE or {}
local CACHE=ENV.__PSICO_NOCLIP_PART_CACHE

local function surfaceFailure(stage,msg)
    local text="Bullet NoClip "..BOOT_VERSION.." • "..tostring(stage)..": "..tostring(msg)
    pcall(function() warn("PSICOSENATICO • "..text) end)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification",{Title="PSICOSENATICO Bullet NoClip",Text=text,Duration=12})
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
            if string.find(low,"429",1,true) or string.find(low,"too many",1,true) then task.wait(waits[attempt])
            else task.wait(math.min(0.18*attempt,0.55)) end
        end
    end
    error(surfaceFailure("CARREGAMENTO","parte "..tostring(index).." ("..name.."): "..lastErr.." • CDN+RAW esgotados"))
end

local chunks={}
for i,name in ipairs(PARTS) do chunks[i]=fetchPart(name,i) end
local source=table.concat(chunks,"\n")

if not string.find(source,'C.VERSION="V0.19"',1,true) then error(surfaceFailure("PREFLIGHT","versão V0.19 ausente")) end
if not string.find(source,'V013_READY',1,true) then error(surfaceFailure("PREFLIGHT","base diagnóstica V0.13 ausente")) end
if not string.find(source,'V018_NATIVE_CANPIERCE_READY',1,true) then error(surfaceFailure("PREFLIGHT","hook nativo canPierce V0.18 ausente")) end
if not string.find(source,'V019_NATIVE_PLUS_DEFAULT_BYPASS_READY',1,true) then error(surfaceFailure("PREFLIGHT","V0.19 native+Default bypass ausente")) end
if string.find(source,'V014_ALL_NON_TYCOON_READY',1,true) then error(surfaceFailure("PREFLIGHT","V0.14 foi carregada diretamente")) end
if string.find(source,'V015_UNIVERSAL_RAY_CORRIDOR_READY',1,true) then error(surfaceFailure("PREFLIGHT","V0.15 física foi carregada indevidamente")) end
if string.find(source,'V016_PHYSICAL_SAFE_READY',1,true) then error(surfaceFailure("PREFLIGHT","V0.16 cadeia antiga foi carregada diretamente")) end
if string.find(source,'V017_RAYEXCLUDE_SAFE_READY',1,true) then error(surfaceFailure("PREFLIGHT","V0.17 RayExclude foi carregada indevidamente")) end
if not string.find(source,'directCanPierceHook=true',1,true) then error(surfaceFailure("PREFLIGHT","autoridade canPierce direta ausente")) end
if not string.find(source,'defaultRayBypass=true',1,true) then error(surfaceFailure("PREFLIGHT","bypass Default V0.19 ausente")) end
if not string.find(source,'physicalCharacterCollisionPreserved=true',1,true) then error(surfaceFailure("PREFLIGHT","garantia de colisão do personagem ausente")) end
if not string.find(source,'reusableHookState=true',1,true) then error(surfaceFailure("PREFLIGHT","estado de hook reutilizável ausente")) end
if not string.find(source,'writesCanCollide=false',1,true) or not string.find(source,'writesCanQuery=false',1,true) then error(surfaceFailure("PREFLIGHT","garantia CanCollide/CanQuery ausente")) end
if not string.find(source,'writesCollisionGroup=true',1,true) then error(surfaceFailure("PREFLIGHT","estratégia CollisionGroup segura V0.19 ausente")) end
if not string.find(source,'writesTags=false',1,true) then error(surfaceFailure("PREFLIGHT","garantia sem tags ausente")) end
if not string.find(source,'Psicosenatico_BulletNoclip_Test_V0_19_',1,true) then error(surfaceFailure("PREFLIGHT","export V0.19 ausente")) end

local compiler=loadstring
if type(compiler)~="function" then error(surfaceFailure("COMPILADOR","loadstring indisponível neste ambiente")) end
local fn,compileErr=compiler(source)
if not fn then error(surfaceFailure("COMPILAÇÃO",compileErr)) end
local okRun,result=xpcall(fn,function(e)
    local base=tostring(e)
    local okTrace,trace=pcall(function() if debug and type(debug.traceback)=="function" then return debug.traceback(base,2) end return base end)
    return okTrace and trace or base
end)
if not okRun then error(surfaceFailure("RUNTIME ANTES/NA INICIALIZAÇÃO",result)) end
return result