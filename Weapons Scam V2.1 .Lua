local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local HttpService=game:GetService("HttpService")
local UserInputService=game:GetService("UserInputService")
local CoreGui=game:GetService("CoreGui")
local Workspace=game:GetService("Workspace")
local CollectionService=game:GetService("CollectionService")
local LP=Players.LocalPlayer or Players.PlayerAdded:Wait()
local C={
VERSION="V2.3.1",
GUI="PsicosenaticoWeaponResearch_V2_3_1",
MAX_LIVE=110,
BOUNDARY_DISTANCE=10000,
MAX_HIT_CHAIN=12,
RAY_EPSILON=0.05,
LOCATION_GRID=20,
DAMAGE_TRIGGER_MAX_AGE=1.25,
AUTO_BASELINE_MAX_AGE=0.45,
AUTO_BASELINE_DELAY_MAX=0.06,
DAMAGE_SAMPLE_DELAYS={0.10,0.25,0.50,0.90},
CATEGORY_LABELS={
TIRO_LIVRE="TIRO LIVRE",
PAREDE_OU_ESTRUTURA="PAREDE / ESTRUTURA",
BLOQUEIO_EXPLICITO="BLOQUEIO EXPLÍCITO",
ALVO_ATRAS_PAREDE="ALVO ATRÁS DE PAREDE",
ALVO_ATRAS_BLOQUEIO_EXPLICITO="ALVO ATRÁS DE BLOQUEIO",
ALVO_LIVRE="ALVO LIVRE",
POSSIVEL_LIMITE_MAPA="POSSÍVEL LIMITE DO MAPA",
LEITURA_INDISPONIVEL="LEITURA INDISPONÍVEL"
},
ATTRS={"_ammo","projectileType","raysPerShot","rayRadius","range","fireMode","rateOfFire","damage","spread"},
LIMIT_WORDS={"boundary","bounds","border","limit","limite","barrier","barreira","invisible","invis","ceiling","maplimit","map_limit","killwall","kill_wall"}
}
local ENV=_G
if typeof(getgenv)=="function" then
local ok,e=pcall(getgenv)
if ok and type(e)=="table" then ENV=e end
end
local RUNTIME_KEY="__PSICOSENATICO_WEAPON_RESEARCH_RUNTIME"
local old=ENV[RUNTIME_KEY]
if type(old)=="table" and type(old.cleanup)=="function" then pcall(old.cleanup) end
local function guiParent()
if typeof(gethui)=="function" then
local ok,p=pcall(gethui)
if ok and p then return p end
end
return CoreGui
end
local GP=guiParent()
local OLD={
PsicosenaticoWeaponResearch_V2_1=true,
PsicosenaticoWeaponResearch_V2_2=true,
PsicosenaticoWeaponResearch_V2_2_1=true,
PsicosenaticoWeaponResearch_V2_2_2=true,
PsicosenaticoWeaponResearch_V2_2_3=true,
PsicosenaticoWeaponResearch_V2_2_4=true,
PsicosenaticoWeaponResearch_V2_2_5=true,
PsicosenaticoWeaponResearch_V2_3_0=true,
[C.GUI]=true
}
for _,x in ipairs(GP:GetChildren()) do
if OLD[x.Name] then pcall(function() x:Destroy() end) end
end
local S={
Recording=false,Started=false,Exported=false,ExportBusy=false,
StartUnix=nil,LastPauseUnix=nil,Errors=0,
Events={},Live={},Markers={},Shots={},RoundCount=0,
CategoryCounts={},LastCategory=nil,LastCategoryLabel=nil,LastLocationId=nil,LastLocationText=nil,LastAssessment=nil,
LocationMap={},LocationDefs={},LocationOrder={},
ActiveTool=nil,Tools={},ToolConnections={},Connections={},
Architecture=nil,SourceInspection={},BoundarySurvey={},
ExplicitBlockers={},ExplicitBlockerScanTotal=0,
PendingTriggers={},PendingDamageProbes=0,SessionId=0
}
local function clock() return os.clock() end
local function unix() return os.time() end
local function full(obj)
local ok,v=pcall(function() return obj:GetFullName() end)
return ok and tostring(v) or tostring(obj and obj.Name or "DESCONHECIDO")
end
local function attr(obj,name)
local ok,v=pcall(function() return obj:GetAttribute(name) end)
return ok and v or nil
end
local function prop(obj,name)
local ok,v=pcall(function() return obj[name] end)
return ok and v or nil
end
local function live(kind,msg)
S.Live[#S.Live+1]={time=clock(),type=kind,message=tostring(msg or "")}
while #S.Live>C.MAX_LIVE do table.remove(S.Live,1) end
end
local function log(kind,data,msg)
live(kind,msg)
if kind=="ERROR" then S.Errors+=1 end
if not S.Started then return end
S.Events[#S.Events+1]={
unix=unix(),time=clock(),type=kind,
data=data or {}
}
end
local function isWeapon(tool)
return tool and tool:IsA("Tool") and (
attr(tool,"projectileType")~=nil or attr(tool,"rateOfFire")~=nil or attr(tool,"_ammo")~=nil
)
end
local function weapon(tool)
if not tool then return nil end
local a={}
for _,n in ipairs(C.ATTRS) do a[n]=attr(tool,n) end
return {name=tool.Name,path=full(tool),attributes=a}
end
local function inspectSource(m)
local r={name=m.Name,path=full(m),sourceReadable=false,sourceLength=nil,source=nil,error=nil}
local ok,v=pcall(function() return m.Source end)
if ok and type(v)=="string" then
r.sourceReadable=true
r.sourceLength=#v
r.source=v
if #v==0 then r.note="PROPRIEDADE_ACESSIVEL_MAS_CONTEUDO_VAZIO" end
else
r.error=tostring(v)
end
return r
end
local function inspectArchitecture(reason)
local root=ReplicatedStorage:FindFirstChild("BlasterSystem")
local out={
reason=reason,time=clock(),found=root~=nil,
rootPath=root and full(root) or nil,
targets={},remotes={},sourceInspection={}
}
if not root then
S.Architecture=out
log("ARCHITECTURE_SCAN",{found=false},"BlasterSystem não encontrado")
return
end
local wanted={
canpierce=true,castrays=true,shoot=true,
shootprojectile=true,replicateprojectile=true,projectilehit=true
}
for _,o in ipairs(root:GetDescendants()) do
if wanted[string.lower(o.Name)] then
local item={name=o.Name,class=o.ClassName,path=full(o)}
out.targets[#out.targets+1]=item
if o:IsA("RemoteEvent") or o:IsA("RemoteFunction") or o:IsA("UnreliableRemoteEvent") then
out.remotes[#out.remotes+1]=item
end
if o:IsA("ModuleScript") then
local si=inspectSource(o)
out.sourceInspection[#out.sourceInspection+1]=si
S.SourceInspection[si.path]=si
end
end
end
table.sort(out.targets,function(a,b) return a.path<b.path end)
S.Architecture=out
log("ARCHITECTURE_SCAN",{
reason=reason,targetCount=#out.targets,
remoteCount=#out.remotes,moduleCount=#out.sourceInspection
},string.format("Arquitetura: %d alvos",#out.targets))
end
local function hasLimitWord(text)
text=string.lower(tostring(text or ""))
for _,w in ipairs(C.LIMIT_WORDS) do
if string.find(text,w,1,true) then return true,w end
end
return false,nil
end
local function explicitBlockInfo(inst)
local cur=inst
local depth=0
while cur and cur~=Workspace and depth<=10 do
if attr(cur,"BulletsCannotPierce")==true then
return {
found=true,
path=full(cur),
name=cur.Name,
class=cur.ClassName,
ancestorDepth=depth,
relation=depth==0 and "SELF" or "ANCESTOR"
}
end
cur=cur.Parent
depth+=1
end
local model=inst and inst:FindFirstAncestorOfClass("Model") or nil
if model then
local seen=0
for _,d in ipairs(model:GetDescendants()) do
seen+=1
if seen>160 then break end
if attr(d,"BulletsCannotPierce")==true then
return {
found=true,
path=full(d),
name=d.Name,
class=d.ClassName,
ancestorDepth=nil,
relation="MESMO_MODELO"
}
end
end
end
return {found=false}
end
local function classify(inst,hasHumanoid,explicit)
if not inst then return "SEM_IMPACTO",0,{} end
if hasHumanoid then return "PERSONAGEM",0,{"modelo possui Humanoid"} end
if explicit and explicit.found then
return "BLOQUEIO_EXPLICITO",100,{"BulletsCannotPierce=true em "..tostring(explicit.path)}
end
local score,reasons=0,{}
local hit,w=hasLimitWord(inst.Name.." "..full(inst))
if hit then
score+=5
reasons[#reasons+1]="nome/caminho sugere limite: "..w
end
local tr=tonumber(prop(inst,"Transparency"))
local cq=prop(inst,"CanQuery")
local cc=prop(inst,"CanCollide")
local size=prop(inst,"Size")
if tr and tr>=0.95 then
score+=3
reasons[#reasons+1]="quase/invisível"
end
if cq==true and cc==false then
score+=1
reasons[#reasons+1]="CanQuery=true e CanCollide=false"
end
if typeof(size)=="Vector3" then
local m=math.max(size.X,size.Y,size.Z)
if m>=2000 then
score+=3
reasons[#reasons+1]="dimensão muito grande"
elseif m>=500 then
score+=1
reasons[#reasons+1]="dimensão grande"
end
end
local attrs,tags={},{}
pcall(function() attrs=inst:GetAttributes() end)
pcall(function() tags=CollectionService:GetTags(inst) end)
for k,v in pairs(attrs) do
local ok2,key=hasLimitWord(tostring(k).."="..tostring(v))
if ok2 then
score+=5
reasons[#reasons+1]="atributo sugere limite: "..key
break
end
end
for _,tag in ipairs(tags) do
local ok2=hasLimitWord(tag)
if ok2 then
score+=5
reasons[#reasons+1]="tag sugere limite: "..tostring(tag)
break
end
end
return score>=5 and "POSSIVEL_LIMITE_MAPA" or "GEOMETRIA_MAPA",score,reasons
end
local function describe(result,origin)
if not result then return nil end
local inst=result.Instance
local model=inst and inst:FindFirstAncestorOfClass("Model") or nil
local hum=model and model:FindFirstChildOfClass("Humanoid") or nil
local explicit=explicitBlockInfo(inst)
local class,score,reasons=classify(inst,hum~=nil,explicit)
local size=prop(inst,"Size")
local attrs,tags={},{}
pcall(function() attrs=inst:GetAttributes() end)
pcall(function() tags=CollectionService:GetTags(inst) end)
return {
instance=inst and full(inst) or nil,
instanceName=inst and inst.Name or nil,
instanceClass=inst and inst.ClassName or nil,
model=model and full(model) or nil,
modelName=model and model.Name or nil,
hasHumanoid=hum~=nil,
material=tostring(result.Material),
distance=(result.Position-origin).Magnitude,
position={result.Position.X,result.Position.Y,result.Position.Z},
normal={result.Normal.X,result.Normal.Y,result.Normal.Z},
classification=class,
boundaryScore=score,
boundaryReasons=reasons,
explicitProjectileBlock=explicit.found==true,
explicitBlockPath=explicit.path,
explicitBlockName=explicit.name,
explicitBlockClass=explicit.class,
explicitBlockAncestorDepth=explicit.ancestorDepth,
explicitBlockRelation=explicit.relation,
transparency=prop(inst,"Transparency"),
canCollide=prop(inst,"CanCollide"),
canQuery=prop(inst,"CanQuery"),
canTouch=prop(inst,"CanTouch"),
anchored=prop(inst,"Anchored"),
collisionGroup=prop(inst,"CollisionGroup"),
size=typeof(size)=="Vector3" and {size.X,size.Y,size.Z} or nil,
tags=tags,
attributes=attrs
}
end
local function assessment(ref)
if not ref or not ref.ok then return "LEITURA_INDISPONIVEL" end
if not ref.firstHit then return "CAMINHO_LIVRE" end
if ref.firstHit.classification=="POSSIVEL_LIMITE_MAPA" then return "POSSIVEL_LIMITE_MAPA" end
if ref.firstHit.classification=="BLOQUEIO_EXPLICITO" then return "BLOQUEIO_EXPLICITO" end
if ref.firstHit.classification=="PERSONAGEM" then return "PERSONAGEM" end
return "GEOMETRIA_MAPA"
end
local function referenceRay(tool)
local cam=Workspace.CurrentCamera
if not cam then return {ok=false,reason="SEM_CAMERA"} end
local vp=cam.ViewportSize
local ray=cam:ViewportPointToRay(vp.X/2,vp.Y/2)
local range=tonumber(attr(tool or S.ActiveTool,"range")) or 2000
local unit=ray.Direction.Unit
local dir=unit*range
local excluded={cam}
if LP.Character then excluded[#excluded+1]=LP.Character end
local out={
ok=true,
hit=false,
origin={ray.Origin.X,ray.Origin.Y,ray.Origin.Z},
direction={dir.X,dir.Y,dir.Z},
range=range,
firstHit=nil,
nextHit=nil,
multiHitChain={},
hitChainCount=0,
firstCharacterIndex=nil,
firstExplicitBlockIndex=nil,
explicitBlockCount=0,
explicitBlocks={},
chainStopReason=nil
}
local currentOrigin=ray.Origin
local remaining=range
local targetHumanoid=nil
local targetModel=nil
for index=1,C.MAX_HIT_CHAIN do
if remaining<=C.RAY_EPSILON then
out.chainStopReason="ALCANCE_ESGOTADO"
break
end
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances=excluded
params.IgnoreWater=false
local ok,result=pcall(function()
return Workspace:Raycast(currentOrigin,unit*remaining,params)
end)
if not ok then
if index==1 then
return {ok=false,reason=tostring(result),range=range}
end
out.chainStopReason="ERRO_RAYCAST_"..tostring(index)
break
end
if not result then
out.chainStopReason="CAMINHO_LIVRE_APOS_"..tostring(index-1).."_IMPACTOS"
break
end
local item=describe(result,currentOrigin)
item.chainIndex=index
item.segmentDistance=(result.Position-currentOrigin).Magnitude
item.totalDistance=(result.Position-ray.Origin).Magnitude
out.multiHitChain[#out.multiHitChain+1]=item
out.hit=true
if index==1 then out.firstHit=item end
if index==2 then out.nextHit=item end
if item.explicitProjectileBlock then
out.explicitBlockCount+=1
if not out.firstExplicitBlockIndex then out.firstExplicitBlockIndex=index end
out.explicitBlocks[#out.explicitBlocks+1]={
chainIndex=index,
path=item.explicitBlockPath or item.instance,
name=item.explicitBlockName or item.instanceName,
class=item.explicitBlockClass or item.instanceClass,
totalDistance=item.totalDistance
}
end
if item.hasHumanoid and not out.firstCharacterIndex then
out.firstCharacterIndex=index
out.chainStopReason="PERSONAGEM_ENCONTRADO"
targetModel=result.Instance and result.Instance:FindFirstAncestorOfClass("Model") or nil
targetHumanoid=targetModel and targetModel:FindFirstChildOfClass("Humanoid") or nil
break
end
excluded[#excluded+1]=result.Instance
local travelled=(result.Position-ray.Origin).Magnitude+C.RAY_EPSILON
remaining=range-travelled
currentOrigin=result.Position+unit*C.RAY_EPSILON
if index==C.MAX_HIT_CHAIN then
out.chainStopReason="MAX_CAMADAS_ATINGIDO"
end
end
out.hitChainCount=#out.multiHitChain
out.assessment=assessment(out)
return out,targetHumanoid,targetModel
end
local function categoryLabel(category)
return C.CATEGORY_LABELS[category] or tostring(category or "-")
end
local function classifyShot(ref)
if not ref or not ref.ok then
return "LEITURA_INDISPONIVEL","raycast de referência indisponível"
end
if not ref.hit or not ref.firstHit then
return "TIRO_LIVRE","nenhum impacto dentro do alcance"
end
local characterIndex=ref.firstCharacterIndex
local explicitIndex=ref.firstExplicitBlockIndex
if characterIndex==1 then
return "ALVO_LIVRE","personagem é o primeiro impacto"
end
if explicitIndex and characterIndex and explicitIndex<characterIndex then
return "ALVO_ATRAS_BLOQUEIO_EXPLICITO",string.format(
"BulletsCannotPierce=true na camada %d antes do personagem na camada %d",
explicitIndex,characterIndex
)
end
if characterIndex and characterIndex>1 then
return "ALVO_ATRAS_PAREDE",string.format(
"personagem na camada %d após %d impacto(s) de geometria",
characterIndex,characterIndex-1
)
end
if explicitIndex then
return "BLOQUEIO_EXPLICITO",string.format(
"BulletsCannotPierce=true detectado na camada %d; nenhum personagem confirmado depois",
explicitIndex
)
end
if ref.firstHit.classification=="POSSIVEL_LIMITE_MAPA" then
return "POSSIVEL_LIMITE_MAPA","primeiro impacto possui indícios heurísticos de limite do mapa"
end
return "PAREDE_OU_ESTRUTURA",string.format(
"geometria detectada; cadeia com %d impacto(s); fim: %s",
#(ref.multiHitChain or {}),tostring(ref.chainStopReason or "DESCONHECIDO")
)
end
local function gridNumber(v)
local g=C.LOCATION_GRID
return math.floor((tonumber(v) or 0)/g+0.5)
end
local function locationHit(ref,category)
if not ref then return nil end
local chain=ref.multiHitChain or {}
if (category=="BLOQUEIO_EXPLICITO" or category=="ALVO_ATRAS_BLOQUEIO_EXPLICITO") and ref.firstExplicitBlockIndex then
return chain[ref.firstExplicitBlockIndex]
end
if category=="ALVO_LIVRE" and ref.firstCharacterIndex then
return chain[ref.firstCharacterIndex]
end
return ref.firstHit
end
local function resolveLocation(ref,category,reason)
local item=locationHit(ref,category)
local primaryPath="SEM_OBJETO"
local primaryName="SEM_OBJETO"
local modelPath=nil
local pos=nil
local explicitPath=nil
if item then
primaryPath=item.instance or "SEM_CAMINHO"
primaryName=item.instanceName or item.modelName or "OBJETO"
modelPath=item.model
pos=item.position
if item.explicitProjectileBlock then
explicitPath=item.explicitBlockPath or item.instance
primaryPath=explicitPath or primaryPath
primaryName=item.explicitBlockName or primaryName
end
end
local cell="SEM_POSICAO"
if type(pos)=="table" and #pos>=3 then
cell=string.format("%d:%d:%d",gridNumber(pos[1]),gridNumber(pos[2]),gridNumber(pos[3]))
end
local key=table.concat({tostring(category),tostring(primaryPath),cell},"|")
local id=S.LocationMap[key]
local def=nil
if id then
def=S.LocationDefs[id]
else
id=string.format("L%04d",#S.LocationOrder+1)
def={
id=id,
category=category,
categoryLabel=categoryLabel(category),
primaryPath=primaryPath,
primaryName=primaryName,
modelPath=modelPath,
explicitBlockPath=explicitPath,
positionCell=cell,
firstPosition=pos,
firstSeenUnix=unix(),
firstSeenTime=clock(),
firstReason=reason,
records=0,
rounds=0
}
S.LocationMap[key]=id
S.LocationDefs[id]=def
S.LocationOrder[#S.LocationOrder+1]=id
end
return def
end
local function categorySummary()
local out={}
for k,v in pairs(S.CategoryCounts) do
out[k]={label=categoryLabel(k),records=v}
end
return out
end
local function buildLocationSummary()
local out={}
for _,id in ipairs(S.LocationOrder) do
local d=S.LocationDefs[id]
if d then
out[#out+1]={
id=d.id,
category=d.category,
categoryLabel=d.categoryLabel,
primaryPath=d.primaryPath,
primaryName=d.primaryName,
modelPath=d.modelPath,
explicitBlockPath=d.explicitBlockPath,
positionCell=d.positionCell,
firstPosition=d.firstPosition,
firstSeenUnix=d.firstSeenUnix,
records=0,
rounds=0,
damageObserved=0,
noDamageObserved=0,
noTargetForDamage=0,
totalObservedDamage=0,
targets={}
}
end
end
local byId={}
for _,d in ipairs(out) do byId[d.id]=d end
for _,shot in ipairs(S.Shots) do
local d=byId[shot.locationId]
if d then
d.records+=1
d.rounds+=(tonumber(shot.ammoDelta) or 1)
local p=shot.damageProbe
if p then
if p.status=="QUEDA_DE_HP_OBSERVADA" then
d.damageObserved+=1
d.totalObservedDamage+=(tonumber(p.observedDamage) or 0)
elseif p.status=="SEM_QUEDA_DE_HP_OBSERVADA" then
d.noDamageObserved+=1
elseif p.status=="SEM_ALVO_NO_GATILHO" or p.status=="SEM_HP_ANTES" or p.status=="ALVO_INDISPONIVEL" then
d.noTargetForDamage+=1
end
if p.target and p.target.modelPath then
d.targets[p.target.modelPath]=true
end
end
end
end
for _,d in ipairs(out) do
local arr={}
for targetPath in pairs(d.targets) do arr[#arr+1]=targetPath end
table.sort(arr)
d.targets=arr
end
return out
end
local function boundarySurvey()
local cam=Workspace.CurrentCamera
if not cam then return end
local origin=cam.CFrame.Position
local dirs={
{"CIMA",Vector3.new(0,1,0)},
{"NORTE",Vector3.new(0,0,-1)},
{"SUL",Vector3.new(0,0,1)},
{"LESTE",Vector3.new(1,0,0)},
{"OESTE",Vector3.new(-1,0,0)}
}
local p=RaycastParams.new()
p.FilterType=Enum.RaycastFilterType.Exclude
p.IgnoreWater=false
p.FilterDescendantsInstances=LP.Character and {LP.Character,cam} or {cam}
S.BoundarySurvey={}
for _,v in ipairs(dirs) do
local ok,r=pcall(function()
return Workspace:Raycast(origin,v[2]*C.BOUNDARY_DISTANCE,p)
end)
S.BoundarySurvey[#S.BoundarySurvey+1]={
direction=v[1],
ok=ok,
hit=ok and r~=nil or false,
firstHit=ok and describe(r,origin) or nil,
error=ok and nil or tostring(r)
}
end
log("BOUNDARY_SURVEY",{rays=S.BoundarySurvey},"Leitura auxiliar de possíveis limites concluída")
end
local function objectPosition(o)
if not o then return nil end
if o:IsA("BasePart") then return o.Position end
if o:IsA("Model") then
local ok,p=pcall(function() return o:GetPivot().Position end)
if ok then return p end
end
return nil
end
local function scanExplicitBlockers()
local origin=nil
local ch=LP.Character
local root=ch and ch:FindFirstChild("HumanoidRootPart") or nil
if root then origin=root.Position
elseif Workspace.CurrentCamera then origin=Workspace.CurrentCamera.CFrame.Position end
local found={}
local total=0
local ok,desc=pcall(function() return Workspace:GetDescendants() end)
if ok and type(desc)=="table" then
for _,o in ipairs(desc) do
if attr(o,"BulletsCannotPierce")==true then
total+=1
local pos=objectPosition(o)
local dist=(origin and pos) and (pos-origin).Magnitude or nil
found[#found+1]={
path=full(o),
name=o.Name,
class=o.ClassName,
distanceFromPlayer=dist,
transparency=prop(o,"Transparency"),
canCollide=prop(o,"CanCollide"),
canQuery=prop(o,"CanQuery"),
size=(typeof(prop(o,"Size"))=="Vector3") and {prop(o,"Size").X,prop(o,"Size").Y,prop(o,"Size").Z} or nil,
attributeValue=true
}
end
end
end
table.sort(found,function(a,b)
local da=tonumber(a.distanceFromPlayer) or math.huge
local db=tonumber(b.distanceFromPlayer) or math.huge
if da==db then return tostring(a.path)<tostring(b.path) end
return da<db
end)
S.ExplicitBlockers=found
S.ExplicitBlockerScanTotal=total
log("EXPLICIT_BLOCKER_SCAN",{
total=total,
stored=#found,
nearest=found[1]
},string.format("BulletsCannotPierce=true • %d peça(s) detectada(s)",total))
end
local function lastCategoryLabel()
return S.LastCategoryLabel or "AGUARDANDO DISPARO"
end
local function lastLocationText()
return S.LastLocationText or "O scanner classificará automaticamente cada trajetória."
end
local function targetSnapshot(hum,model,ref)
if not hum then return nil end
local health=tonumber(prop(hum,"Health"))
local maxHealth=tonumber(prop(hum,"MaxHealth"))
return {
modelName=model and model.Name or nil,
modelPath=model and full(model) or nil,
humanoidPath=full(hum),
health=health,
maxHealth=maxHealth,
firstCharacterIndex=ref and ref.firstCharacterIndex or nil,
layersBeforeTarget=(ref and ref.firstCharacterIndex) and math.max(0,ref.firstCharacterIndex-1) or nil,
firstExplicitBlockIndex=ref and ref.firstExplicitBlockIndex or nil,
explicitBlockBeforeTarget=(ref and ref.firstExplicitBlockIndex and ref.firstCharacterIndex and ref.firstExplicitBlockIndex<ref.firstCharacterIndex) and true or false,
explicitBlocks=ref and ref.explicitBlocks or {}
}
end
local function pushPendingTrigger(tool,entry)
local q=S.PendingTriggers[tool]
if type(q)~="table" then q={};S.PendingTriggers[tool]=q end
q[#q+1]=entry
while #q>8 do table.remove(q,1) end
end
local function popPendingTrigger(tool)
local q=S.PendingTriggers[tool]
if type(q)~="table" then return nil,nil end
local now=clock()
while #q>0 do
local e=table.remove(q,1)
local age=now-(tonumber(e.time) or now)
if age>=0 and age<=C.DAMAGE_TRIGGER_MAX_AGE then
return e,age
end
end
return nil,nil
end
local function makeTriggerSnapshot(tool,source)
local ref,targetHumanoid,targetModel=referenceRay(tool)
local target=targetSnapshot(targetHumanoid,targetModel,ref)
return {
time=clock(),
unix=unix(),
sessionId=S.SessionId,
source=source,
referenceRay=ref,
targetHumanoid=targetHumanoid,
targetModel=targetModel,
target=target,
healthBefore=target and target.health or nil,
maxHealth=target and target.maxHealth or nil
}
end
local function popAutoBaseline(tool)
local d=S.Tools[tool]
if type(d)~="table" then return nil,nil end
local b=d.autoBaseline
if type(b)~="table" or b.sessionId~=S.SessionId then return nil,nil end
local now=clock()
local age=now-(tonumber(b.time) or now)
local rof=tonumber(attr(tool,"rateOfFire")) or 600
local interval=rof>0 and (60/rof) or 0.1
local maxAge=math.max(C.AUTO_BASELINE_MAX_AGE,interval*2.5)
local lastUsed=tonumber(d.lastUsedAutoBaselineTime) or -math.huge
if age>=0 and age<=maxAge and (tonumber(b.time) or 0)>lastUsed then
d.lastUsedAutoBaselineTime=b.time
return b,age
end
return nil,nil
end
local function scheduleAutoBaseline(tool)
local d=S.Tools[tool]
if type(d)~="table" then return end
if tostring(attr(tool,"fireMode"))~="Auto" then return end
local rof=tonumber(attr(tool,"rateOfFire")) or 600
local interval=rof>0 and (60/rof) or 0.1
local delay=math.min(C.AUTO_BASELINE_DELAY_MAX,math.max(0.02,interval*0.35))
d.autoBaselineToken=(tonumber(d.autoBaselineToken) or 0)+1
local token=d.autoBaselineToken
local sessionId=S.SessionId
task.delay(delay,function()
if S.SessionId~=sessionId or not S.Recording or S.ExportBusy then return end
local current=S.Tools[tool]
if type(current)~="table" or current.autoBaselineToken~=token then return end
if not tool.Parent then return end
current.autoBaseline=makeTriggerSnapshot(tool,"AUTO_POST_SHOT_BASELINE")
end)
end
local function damageSummary()
local out={
probes=0,damageObserved=0,noDropObserved=0,noTarget=0,pending=0,unmatchedTrigger=0,
toolActivatedMatches=0,autoBaselineMatches=0,
totalObservedDamage=0,byCategory={}
}
for _,shot in ipairs(S.Shots) do
local category=shot.autoCategory or "SEM_CLASSIFICACAO"
local p=shot.damageProbe
local b=out.byCategory[category]
if not b then
b={label=categoryLabel(category),probes=0,damageObserved=0,noDropObserved=0,noTarget=0,pending=0,unmatchedTrigger=0,toolActivatedMatches=0,autoBaselineMatches=0,totalObservedDamage=0}
out.byCategory[category]=b
end
if not shot.triggerMatched then
out.unmatchedTrigger+=1;b.unmatchedTrigger+=1
elseif shot.triggerMatchSource=="AUTO_POST_SHOT_BASELINE" then
out.autoBaselineMatches+=1;b.autoBaselineMatches+=1
else
out.toolActivatedMatches+=1;b.toolActivatedMatches+=1
end
if p then
out.probes+=1;b.probes+=1
if p.status=="QUEDA_DE_HP_OBSERVADA" then
out.damageObserved+=1;b.damageObserved+=1
local d=tonumber(p.observedDamage) or 0
out.totalObservedDamage+=d;b.totalObservedDamage+=d
elseif p.status=="SEM_QUEDA_DE_HP_OBSERVADA" then
out.noDropObserved+=1;b.noDropObserved+=1
elseif p.status=="PENDENTE" then
out.pending+=1;b.pending+=1
elseif p.status=="SEM_ALVO_NO_GATILHO" or p.status=="SEM_HP_ANTES" or p.status=="ALVO_INDISPONIVEL" then
out.noTarget+=1;b.noTarget+=1
end
end
end
return out
end
local function startDamageProbe(shot,trigger)
if not trigger or not trigger.targetHumanoid or trigger.healthBefore==nil then
local status="SEM_ALVO_NO_GATILHO"
if trigger and trigger.targetHumanoid and trigger.healthBefore==nil then status="SEM_HP_ANTES" end
shot.damageProbe={
status=status,
target=trigger and trigger.target or nil,
samples={}
}
return false
end
local hum=trigger.targetHumanoid
local before=tonumber(trigger.healthBefore)
local sessionId=S.SessionId
shot.damageProbe={
status="PENDENTE",
target=trigger.target,
healthBefore=before,
maxHealth=trigger.maxHealth,
baselineSource=trigger.source,
healthAtAmmoDecrease=tonumber(prop(hum,"Health")),
observedDamage=0,
healthMinimum=before,
died=false,
samples={}
}
S.PendingDamageProbes+=1
task.spawn(function()
local lastDelay=0
local minHealth=before
local validSamples=0
local h0=shot.damageProbe.healthAtAmmoDecrease
if type(h0)=="number" then
minHealth=math.min(minHealth,h0)
end
for _,delay in ipairs(C.DAMAGE_SAMPLE_DELAYS) do
task.wait(math.max(0,delay-lastDelay))
lastDelay=delay
if S.SessionId~=sessionId then return end
local exists=hum and hum.Parent~=nil
local h=exists and tonumber(prop(hum,"Health")) or nil
shot.damageProbe.samples[#shot.damageProbe.samples+1]={
delay=delay,
health=h,
targetExists=exists
}
if type(h)=="number" then
validSamples+=1
minHealth=math.min(minHealth,h)
end
end
if S.SessionId~=sessionId then return end
local drop=math.max(0,before-minHealth)
shot.damageProbe.healthMinimum=minHealth
shot.damageProbe.observedDamage=drop
shot.damageProbe.died=minHealth<=0
if validSamples==0 and shot.damageProbe.healthAtAmmoDecrease==nil then
shot.damageProbe.status="ALVO_INDISPONIVEL"
elseif drop>0.001 then
shot.damageProbe.status="QUEDA_DE_HP_OBSERVADA"
else
shot.damageProbe.status="SEM_QUEDA_DE_HP_OBSERVADA"
end
log("DAMAGE_PROBE_RESULT",{
category=shot.autoCategory,
locationId=shot.locationId,
target=shot.damageProbe.target,
healthBefore=before,
healthMinimum=minHealth,
observedDamage=drop,
status=shot.damageProbe.status,
layersBeforeTarget=shot.damageProbe.target and shot.damageProbe.target.layersBeforeTarget or nil
},string.format(
"%s • dano:%s • %.2f → %.2f",
tostring(shot.autoCategory),
tostring(shot.damageProbe.status),
before,
minHealth
))
S.PendingDamageProbes=math.max(0,S.PendingDamageProbes-1)
end)
return true
end
local function addToolConn(tool,c)
S.ToolConnections[tool]=S.ToolConnections[tool] or {}
table.insert(S.ToolConnections[tool],c)
end
local function registerWeapon(tool,reason)
if not isWeapon(tool) or S.Tools[tool] then return end
S.Tools[tool]={
name=tool.Name,
reason=reason,
firstPath=full(tool),
initial=weapon(tool),
lastAmmo=tonumber(attr(tool,"_ammo")),
autoBaseline=nil,
autoBaselineToken=0,
lastUsedAutoBaselineTime=nil
}
log("WEAPON_FOUND",{reason=reason,snapshot=weapon(tool)},"Arma: "..tool.Name)
addToolConn(tool,tool.Equipped:Connect(function()
S.ActiveTool=tool
local d=S.Tools[tool]
if d then
d.lastAmmo=tonumber(attr(tool,"_ammo"))
d.autoBaseline=nil
d.autoBaselineToken=(tonumber(d.autoBaselineToken) or 0)+1
d.lastUsedAutoBaselineTime=nil
end
log("WEAPON_EQUIPPED",{name=tool.Name},tool.Name.." equipada")
end))
addToolConn(tool,tool.Unequipped:Connect(function()
if S.ActiveTool==tool then S.ActiveTool=nil end
local d=S.Tools[tool]
if d then
d.autoBaseline=nil
d.autoBaselineToken=(tonumber(d.autoBaselineToken) or 0)+1
end
log("WEAPON_UNEQUIPPED",{name=tool.Name},tool.Name.." desequipada")
end))
addToolConn(tool,tool.Activated:Connect(function()
if not S.Recording or S.ExportBusy then return end
local trigger=makeTriggerSnapshot(tool,"TOOL_ACTIVATED")
pushPendingTrigger(tool,trigger)
local previewCategory=classifyShot(trigger.referenceRay)
log("SHOT_TRIGGER",{
weapon=tool.Name,
previewCategory=previewCategory,
hasTarget=trigger.target~=nil,
source="TOOL_ACTIVATED"
},tool.Name.." • gatilho • "..categoryLabel(previewCategory))
end))
for _,name in ipairs(C.ATTRS) do
local ok,sig=pcall(function()
return tool:GetAttributeChangedSignal(name)
end)
if ok and sig then
addToolConn(tool,sig:Connect(function()
local value=attr(tool,name)
local d=S.Tools[tool]
if name=="_ammo" and d then
local before,after=tonumber(d.lastAmmo),tonumber(value)
if before and after and after<before and S.Recording and not S.ExportBusy then
local raw=before-after
local trigger,triggerAge=popPendingTrigger(tool)
if not trigger then
trigger,triggerAge=popAutoBaseline(tool)
end
local ref=nil
if trigger and trigger.sessionId==S.SessionId then
ref=trigger.referenceRay
else
trigger=nil
ref=referenceRay(tool)
end
local category,categoryReason=classifyShot(ref)
local loc=resolveLocation(ref,category,categoryReason)
local shotIndex=#S.Shots+1
local shot={
shotIndex=shotIndex,
time=clock(),
unix=unix(),
source="AMMO_DECREASE",
ammoBefore=before,
ammoAfter=after,
ammoDelta=raw,
triggerMatched=trigger~=nil,
triggerAge=triggerAge,
triggerMatchSource=trigger and trigger.source or nil,
referenceRaySource=trigger and trigger.source or "AMMO_DECREASE_FALLBACK",
weapon=weapon(tool),
referenceRay=ref,
assessment=ref and ref.assessment or "LEITURA_INDISPONIVEL",
autoCategory=category,
autoCategoryLabel=categoryLabel(category),
autoCategoryReason=categoryReason,
locationId=loc and loc.id or nil,
locationPrimaryPath=loc and loc.primaryPath or nil,
locationPositionCell=loc and loc.positionCell or nil
}
S.Shots[#S.Shots+1]=shot
S.RoundCount+=raw
S.CategoryCounts[category]=(S.CategoryCounts[category] or 0)+1
S.LastCategory=category
S.LastCategoryLabel=categoryLabel(category)
S.LastLocationId=loc and loc.id or nil
S.LastLocationText=(loc and (loc.id.." • "..tostring(loc.primaryName))) or "SEM LOCAL"
S.LastAssessment=shot.assessment
if loc then
loc.records+=1
loc.rounds+=raw
end
startDamageProbe(shot,trigger)
scheduleAutoBaseline(tool)
log("SHOT_AMMO_CONFIRMED",{
shotIndex=shotIndex,
weapon=tool.Name,
ammoDelta=raw,
category=category,
locationId=shot.locationId,
assessment=shot.assessment,
triggerMatched=shot.triggerMatched,
triggerMatchSource=shot.triggerMatchSource
},string.format(
"#%d • %s • %s • %s",
shotIndex,tool.Name,categoryLabel(category),tostring(shot.locationId or "SEM_LOCAL")
))
live("CLASSIFICACAO",string.format(
"#%d • %s • %s",
shotIndex,categoryLabel(category),tostring(shot.locationId or "SEM_LOCAL")
))
end
d.lastAmmo=after or value
elseif S.Recording then
log("ATTRIBUTE_CHANGED",{
weapon=tool.Name,
attribute=name,
value=value
},tool.Name.." • "..name.."="..tostring(value))
end
end))
end
end
end
local function scanWeapons(reason)
local bp=LP:FindFirstChildOfClass("Backpack")
local ch=LP.Character
if bp then
for _,o in ipairs(bp:GetChildren()) do
if o:IsA("Tool") then registerWeapon(o,reason or "BACKPACK_SCAN") end
end
end
if ch then
for _,o in ipairs(ch:GetChildren()) do
if o:IsA("Tool") then
registerWeapon(o,reason or "CHARACTER_SCAN")
if isWeapon(o) then S.ActiveTool=o end
end
end
end
end
local function connectCharacter(ch)
S.Connections[#S.Connections+1]=ch.ChildAdded:Connect(function(o)
if o:IsA("Tool") then
task.defer(function()
registerWeapon(o,"CHARACTER_ADDED")
if isWeapon(o) then S.ActiveTool=o end
end)
end
end)
end
local function connectBackpack()
local bp=LP:FindFirstChildOfClass("Backpack")
if not bp then return end
S.Connections[#S.Connections+1]=bp.ChildAdded:Connect(function(o)
if o:IsA("Tool") then task.defer(registerWeapon,o,"BACKPACK_ADDED") end
end)
end
if LP.Character then connectCharacter(LP.Character) end
connectBackpack()
S.Connections[#S.Connections+1]=LP.CharacterAdded:Connect(function(ch)
S.ActiveTool=nil
task.wait(0.35)
connectCharacter(ch)
scanWeapons("RESPAWN_SCAN")
end)
local function resetSession()
S.Events={}
S.Markers={}
S.Shots={}
S.RoundCount=0
S.Errors=0
S.CategoryCounts={}
S.LastCategory=nil
S.LastCategoryLabel=nil
S.LastLocationId=nil
S.LastLocationText=nil
S.LastAssessment=nil
S.LocationMap={}
S.LocationDefs={}
S.LocationOrder={}
S.BoundarySurvey={}
S.ExplicitBlockers={}
S.ExplicitBlockerScanTotal=0
S.Exported=false
S.ExportBusy=false
S.PendingTriggers={}
S.PendingDamageProbes=0
S.SessionId+=1
S.SourceInspection={}
for _,d in pairs(S.Tools) do
if type(d)=="table" then
d.autoBaseline=nil
d.autoBaselineToken=(tonumber(d.autoBaselineToken) or 0)+1
d.lastUsedAutoBaselineTime=nil
end
end
S.StartUnix=unix()
S.LastPauseUnix=nil
end
local function beginSession()
if not S.ActiveTool or not isWeapon(S.ActiveTool) then
live("AVISO","Equipe uma arma antes de iniciar.")
return false
end
resetSession()
S.Started=true
S.Recording=true
log("DIAGNOSTIC_STARTED",{mode="OPEN_ENDED_AUTO_CLASSIFICATION"},"Pesquisa V2.3.1 iniciada • sem limite de tiros")
inspectArchitecture("DIAGNOSTIC_START")
scanExplicitBlockers()
boundarySurvey()
return true
end
local function pauseSession(reason)
if not S.Recording then return end
log("SESSION_PAUSED",{
reason=reason or "USER",
shotRecords=#S.Shots,
rounds=S.RoundCount,
pendingDamageProbes=S.PendingDamageProbes
},"Pausado sem apagar os dados")
S.Recording=false
S.LastPauseUnix=unix()
end
local function resumeSession()
if not S.Started or S.ExportBusy then return false end
if not S.ActiveTool or not isWeapon(S.ActiveTool) then
live("AVISO","Equipe uma arma antes de retomar.")
return false
end
S.Recording=true
S.LastPauseUnix=nil
log("SESSION_RESUMED",{
shotRecords=#S.Shots,
rounds=S.RoundCount
},"Coleta livre retomada")
return true
end
local function serializeTools()
local out={}
for tool,d in pairs(S.Tools) do
out[#out+1]={
name=d.name,
reason=d.reason,
firstPath=d.firstPath,
initial=d.initial,
final=tool and tool.Parent and weapon(tool) or nil
}
end
table.sort(out,function(a,b)
return tostring(a.name)<tostring(b.name)
end)
return out
end
local function exportTable()
return {
format="Psicosenatico Weapon Research",
version=C.VERSION,
focus="BULLET_NOCLIP_WALL_PENETRATION",
mode="OPEN_ENDED_AUTO_CLASSIFICATION",
generatedAtUnix=unix(),
diagnostic={
status=S.Recording and "RECORDING" or "PAUSED",
startedAtUnix=S.StartUnix,
lastPauseAtUnix=S.LastPauseUnix,
snapshotAtUnix=unix()
},
openEndedResearch={
shotLimit="UNLIMITED",
automaticClassification=true,
locationGrouping=true,
locationGridStuds=C.LOCATION_GRID,
shotRecords=#S.Shots,
roundsConsumed=S.RoundCount,
uniqueLocations=#S.LocationOrder,
pendingDamageProbes=S.PendingDamageProbes,
maxHitChain=C.MAX_HIT_CHAIN,
damageSampleDelays=C.DAMAGE_SAMPLE_DELAYS,
autoBaselineMaxAge=C.AUTO_BASELINE_MAX_AGE
},
summary={
events=#S.Events,
confirmedShotRecords=#S.Shots,
roundsConsumed=S.RoundCount,
uniqueLocations=#S.LocationOrder,
errors=S.Errors,
byCategory=categorySummary(),
damage=damageSummary()
},
architecture=S.Architecture,
sourceInspection=S.SourceInspection,
boundarySurvey=S.BoundarySurvey,
explicitProjectileBlockers={
attribute="BulletsCannotPierce",
value=true,
totalDetected=S.ExplicitBlockerScanTotal,
stored=S.ExplicitBlockers
},
locations=buildLocationSummary(),
tools=serializeTools(),
shots=S.Shots,
events=S.Events,
interpretationRules={
"Não existe limite programado de tiros; a sessão continua até ser pausada, fechada ou reiniciada.",
"Cada redução confirmada de _ammo gera um registro e é classificada automaticamente pela trajetória observada.",
"TIRO_LIVRE = nenhum impacto no alcance do raycast de referência.",
"PAREDE_OU_ESTRUTURA = geometria sem personagem confirmado depois e sem BulletsCannotPierce=true na cadeia.",
"BLOQUEIO_EXPLICITO = BulletsCannotPierce=true detectado na peça, ancestral ou no mesmo modelo imediato da peça atingida.",
"ALVO_ATRAS_PAREDE = personagem encontrado depois de geometria comum, sem bloqueio explícito antes dele.",
"ALVO_ATRAS_BLOQUEIO_EXPLICITO = BulletsCannotPierce=true aparece antes do personagem na cadeia.",
"ALVO_LIVRE = personagem é o primeiro impacto.",
"locations agrupa tiros por categoria, objeto principal e célula espacial de 20 studs; o caminho e a posição completos continuam no tiro individual.",
"multiHitChain percorre cumulativamente até 12 peças/impactos alinhados e não simula canPierce.",
"damageProbe observa Humanoid.Health usando Tool.Activated e, em armas Auto, uma baseline temporal pós-tiro para o próximo disparo da rajada.",
"QUEDA_DE_HP_OBSERVADA indica correlação temporal com o disparo, não prova causal exclusiva.",
"SEM_QUEDA_DE_HP_OBSERVADA significa somente que nenhuma redução foi observada na janela configurada.",
"POSSIVEL_LIMITE_MAPA é heurístico e não substitui uma regra exclusivamente do servidor.",
"Nenhum RemoteEvent é disparado e nenhum ModuleScript é executado via require()."
}
}
end
local function encode()
local ok,v=pcall(function()
return HttpService:JSONEncode(exportTable())
end)
return ok and v or nil,ok and nil or v
end
local COL={
bg=Color3.fromRGB(10,10,13),
panel=Color3.fromRGB(19,19,24),
panel2=Color3.fromRGB(28,28,35),
text=Color3.fromRGB(245,245,248),
sub=Color3.fromRGB(158,158,172),
blue=Color3.fromRGB(22,55,105),
blue2=Color3.fromRGB(32,82,145),
green=Color3.fromRGB(65,210,118),
red=Color3.fromRGB(235,38,52),
yellow=Color3.fromRGB(242,184,57)
}
local function new(class,p)
local o=Instance.new(class)
for k,v in pairs(p or {}) do o[k]=v end
return o
end
local function round(o,r)
new("UICorner",{Parent=o,CornerRadius=UDim.new(0,r or 8)})
end
local function label(parent,text,size,pos,ts)
return new("TextLabel",{
Parent=parent,
BackgroundTransparency=1,
Text=text,
Size=size,
Position=pos,
TextColor3=COL.text,
Font=Enum.Font.Gotham,
TextSize=ts or 10,
TextXAlignment=Enum.TextXAlignment.Left,
TextYAlignment=Enum.TextYAlignment.Center
})
end
local Gui=new("ScreenGui",{
Parent=GP,
Name=C.GUI,
ResetOnSpawn=false,
IgnoreGuiInset=true
})
local Main=new("Frame",{
Parent=Gui,
BackgroundColor3=COL.bg,
BorderSizePixel=0,
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.fromScale(0.5,0.5)
})
round(Main,15)
local function resize()
local cam=Workspace.CurrentCamera
if not cam then return end
local v=cam.ViewportSize
Main.Size=UDim2.fromOffset(
math.max(320,math.min(math.floor(v.X*0.94),v.X-14)),
math.max(285,math.min(math.floor(v.Y*0.72),v.Y-14))
)
end
resize()
local Header=new("Frame",{
Parent=Main,
Size=UDim2.new(1,0,0,56),
BackgroundColor3=COL.panel,
BorderSizePixel=0
})
round(Header,15)
label(Header,"PSICOSENATICO • PESQUISA DE ARMAS",UDim2.new(1,-140,0,24),UDim2.fromOffset(14,5),14)
local Ver=label(Header,"V2.3.1",UDim2.fromOffset(48,16),UDim2.fromOffset(14,32),9)
Ver.TextColor3=COL.blue2
local Sub=label(Header,"PESQUISA LIVRE • CLASSIFICAÇÃO AUTOMÁTICA",UDim2.new(1,-190,0,16),UDim2.fromOffset(66,32),8)
Sub.TextColor3=COL.sub
local Min=new("TextButton",{
Parent=Header,
Size=UDim2.fromOffset(36,32),
Position=UDim2.new(1,-82,0,11),
Text="—",
BackgroundColor3=COL.panel2,
TextColor3=COL.text,
Font=Enum.Font.GothamBold,
TextSize=17,
BorderSizePixel=0
})
round(Min,9)
local Close=new("TextButton",{
Parent=Header,
Size=UDim2.fromOffset(36,32),
Position=UDim2.new(1,-41,0,11),
Text="×",
BackgroundColor3=COL.red,
TextColor3=COL.text,
Font=Enum.Font.GothamBold,
TextSize=19,
BorderSizePixel=0
})
round(Close,9)
local Status=label(Main,"Pronto • equipe uma arma.",UDim2.new(1,-28,0,19),UDim2.fromOffset(14,59),9)
Status.TextColor3=COL.sub
local Start=new("TextButton",{
Parent=Main,
Size=UDim2.new(0.5,-17,0,34),
Position=UDim2.fromOffset(14,81),
Text="INICIAR",
BackgroundColor3=COL.blue2,
TextColor3=COL.text,
Font=Enum.Font.GothamBold,
TextSize=10,
BorderSizePixel=0
})
round(Start,8)
local Export=new("TextButton",{
Parent=Main,
Size=UDim2.new(0.5,-17,0,34),
Position=UDim2.new(0.5,3,0,81),
Text="EXPORTAR",
BackgroundColor3=COL.blue,
TextColor3=COL.text,
Font=Enum.Font.GothamBold,
TextSize=10,
BorderSizePixel=0
})
round(Export,8)
local Mission=new("Frame",{
Parent=Main,
Position=UDim2.fromOffset(14,120),
Size=UDim2.new(1,-28,0,48),
BackgroundColor3=COL.panel2,
BorderSizePixel=0
})
round(Mission,8)
local MTitle=label(Mission,"MISSÃO: AGUARDANDO",UDim2.new(1,-18,0,20),UDim2.fromOffset(9,4),10)
MTitle.Font=Enum.Font.GothamBold
local MHelp=label(Mission,"O fluxo será automático após iniciar.",UDim2.new(1,-18,0,18),UDim2.fromOffset(9,25),8)
MHelp.TextColor3=COL.sub
local Summary=label(Main,"",UDim2.new(1,-28,0,18),UDim2.fromOffset(14,171),8)
Summary.TextColor3=COL.sub
local Viewer=new("ScrollingFrame",{
Parent=Main,
Position=UDim2.fromOffset(14,193),
Size=UDim2.new(1,-28,1,-202),
BackgroundColor3=COL.panel,
BorderSizePixel=0,
CanvasSize=UDim2.new(),
AutomaticCanvasSize=Enum.AutomaticSize.Y,
ScrollBarThickness=5,
ScrollingDirection=Enum.ScrollingDirection.Y
})
round(Viewer,9)
local Text=new("TextLabel",{
Parent=Viewer,
BackgroundTransparency=1,
Position=UDim2.fromOffset(8,7),
Size=UDim2.new(1,-16,0,0),
AutomaticSize=Enum.AutomaticSize.Y,
Text="",
TextColor3=COL.text,
Font=Enum.Font.Code,
TextSize=9,
TextWrapped=false,
TextXAlignment=Enum.TextXAlignment.Left,
TextYAlignment=Enum.TextYAlignment.Top
})
local HUD=new("Frame",{
Parent=Gui,
Visible=false,
Active=true,
Size=UDim2.fromOffset(340,74),
Position=UDim2.fromScale(0.04,0.18),
BackgroundColor3=COL.bg,
BorderSizePixel=0
})
round(HUD,12)
local HTitle=label(HUD,"AGUARDANDO",UDim2.new(1,-78,0,24),UDim2.fromOffset(12,7),10)
HTitle.Font=Enum.Font.GothamBold
local HHelp=label(HUD,"",UDim2.new(1,-78,0,36),UDim2.fromOffset(12,31),8)
HHelp.TextWrapped=true
HHelp.TextColor3=COL.sub
local Open=new("TextButton",{
Parent=HUD,
Size=UDim2.fromOffset(60,48),
Position=UDim2.new(1,-68,0,13),
Text="ABRIR",
BackgroundColor3=COL.blue,
TextColor3=COL.text,
Font=Enum.Font.GothamBold,
TextSize=9,
BorderSizePixel=0
})
round(Open,8)
local function draggable(target,handle)
local dragging,input,start,pos=false,nil,nil,nil
S.Connections[#S.Connections+1]=handle.InputBegan:Connect(function(i)
if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
dragging=true
start=i.Position
pos=target.Position
i.Changed:Connect(function()
if i.UserInputState==Enum.UserInputState.End then dragging=false end
end)
end
end)
S.Connections[#S.Connections+1]=handle.InputChanged:Connect(function(i)
if i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch then
input=i
end
end)
S.Connections[#S.Connections+1]=UserInputService.InputChanged:Connect(function(i)
if dragging and i==input then
local d=i.Position-start
target.Position=UDim2.new(
pos.X.Scale,pos.X.Offset+d.X,
pos.Y.Scale,pos.Y.Offset+d.Y
)
end
end)
end
draggable(Main,Header)
draggable(HUD,HUD)
local function updateUI()
local active=S.ActiveTool and S.ActiveTool.Name or "NENHUMA"
local state=S.ExportBusy and "EXPORTANDO" or (S.Recording and "GRAVANDO" or (S.Started and "PAUSADO" or "PRONTO"))
Summary.Text=string.format(
"%s • ARMA:%s • TIROS:%d • LOCAIS:%d • ERROS:%d",
state,active,S.RoundCount,#S.LocationOrder,S.Errors
)
if not S.Started then
MTitle.Text="PESQUISA LIVRE • AGUARDANDO"
MHelp.Text="Equipe uma arma e inicie. Não há limite de tiros."
HTitle.Text="PESQUISA LIVRE • AGUARDANDO"
HHelp.Text="O scanner classificará cada disparo automaticamente."
Start.Text="INICIAR"
elseif S.ExportBusy then
MTitle.Text="EXPORTANDO • AGUARDE"
MHelp.Text=string.format("Finalizando %d leitura(s) de HP pendente(s).",S.PendingDamageProbes)
HTitle.Text="EXPORTANDO"
HHelp.Text="Aguardando as últimas leituras de dano."
Start.Text="AGUARDE"
else
local pre=S.Recording and "GRAVANDO" or "PAUSADO"
MTitle.Text=string.format("%s • SEM LIMITE • %d TIROS",pre,S.RoundCount)
MHelp.Text="Último: "..lastCategoryLabel().." • "..lastLocationText()
HTitle.Text=string.format("%s • %d TIROS • %s",pre,S.RoundCount,lastCategoryLabel())
HHelp.Text=lastLocationText().."\n"..(
S.LastAssessment and ("Leitura: "..S.LastAssessment) or "Faça disparos em paredes, bloqueios e alvos."
)
Start.Text=S.Recording and "PAUSAR" or "RETOMAR"
end
local lines={
"PESQUISA DE ARMAS V2.3.1",
"────────────────────────────────────────",
"MODO LIVRE • SEM LIMITE DE TIROS",
"CLASSIFICAÇÃO AUTOMÁTICA POR DISPARO",
"MULTI-HIT • até 12 camadas",
"DANO • HP + baseline para armas Auto",
"",
"LOCAIS IDENTIFICADOS: "..tostring(#S.LocationOrder),
"BLOQUEIOS EXPLÍCITOS NO MAPA: "..tostring(S.ExplicitBlockerScanTotal),
"",
"TIRO LIVRE: "..tostring(S.CategoryCounts.TIRO_LIVRE or 0),
"PAREDE / ESTRUTURA: "..tostring(S.CategoryCounts.PAREDE_OU_ESTRUTURA or 0),
"BLOQUEIO EXPLÍCITO: "..tostring(S.CategoryCounts.BLOQUEIO_EXPLICITO or 0),
"ALVO ATRÁS DE PAREDE: "..tostring(S.CategoryCounts.ALVO_ATRAS_PAREDE or 0),
"ALVO ATRÁS DE BLOQUEIO: "..tostring(S.CategoryCounts.ALVO_ATRAS_BLOQUEIO_EXPLICITO or 0),
"ALVO LIVRE: "..tostring(S.CategoryCounts.ALVO_LIVRE or 0),
"POSSÍVEL LIMITE: "..tostring(S.CategoryCounts.POSSIVEL_LIMITE_MAPA or 0),
"",
"BLOQUEIO_EXPLICITO = BulletsCannotPierce=true",
"O JSON agrupa trajetórias por local automaticamente.",
"PAUSAR NÃO APAGA NADA • RETOMAR CONTINUA O MESMO ARQUIVO",
"EXPORTAR pausa a coleta e espera o dano pendente terminar.",
"",
"ÚLTIMOS EVENTOS",
"────────────────────────────────────────"
}
for i=math.max(1,#S.Live-65),#S.Live do
local e=S.Live[i]
lines[#lines+1]=string.format(
"[%.3f] %-18s %s",
e.time or 0,
tostring(e.type),
tostring(e.message)
)
end
Text.Text=table.concat(lines,"\n")
end
Start.Activated:Connect(function()
if S.ExportBusy then
Status.Text="Aguarde • exportação em andamento."
Status.TextColor3=COL.yellow
updateUI()
return
end
if not S.Started then
if beginSession() then
Status.Text="Gravando sem limite • teste qualquer parede, bloqueio ou alvo."
Status.TextColor3=COL.green
else
Status.Text="Equipe uma arma antes de iniciar."
Status.TextColor3=COL.red
end
elseif S.Recording then
pauseSession("USER")
Status.Text="Pausado • todos os dados foram preservados."
Status.TextColor3=COL.yellow
else
if resumeSession() then
Status.Text="Retomado • a mesma sessão continua."
Status.TextColor3=COL.green
else
Status.Text="Equipe uma arma antes de retomar."
Status.TextColor3=COL.red
end
end
updateUI()
end)
Export.Activated:Connect(function()
if not S.Started then
Status.Text="Inicie a coleta antes de exportar."
Status.TextColor3=COL.yellow
return
end
if S.ExportBusy then
Status.Text="Exportação já está em andamento."
Status.TextColor3=COL.yellow
return
end
if S.Recording then pauseSession("EXPORT") end
S.ExportBusy=true
Status.Text="Preparando JSON • aguardando leituras de dano pendentes."
Status.TextColor3=COL.yellow
updateUI()
local sessionId=S.SessionId
task.spawn(function()
while Gui.Parent and S.SessionId==sessionId and S.PendingDamageProbes>0 do
task.wait(0.05)
end
if not Gui.Parent or S.SessionId~=sessionId then return end
local data,err=encode()
if not data then
S.ExportBusy=false
Status.Text="Falha JSON: "..tostring(err)
Status.TextColor3=COL.red
updateUI()
return
end
local name="Psicosenatico_WeaponResearch_V2_3_1_"
..tostring(game.PlaceId)
.."_"
..tostring(os.time())
..".json"
local saved=false
if typeof(writefile)=="function" then
saved=pcall(function()
writefile(name,data)
end)
end
if saved then
S.Exported=true
Status.Text="✓ ARQUIVO EXPORTADO: "..name
Status.TextColor3=COL.green
elseif typeof(setclipboard)=="function" and pcall(function()
setclipboard(data)
end) then
S.Exported=true
Status.Text="✓ JSON COPIADO."
Status.TextColor3=COL.green
else
Status.Text="Não foi possível salvar ou copiar o JSON."
Status.TextColor3=COL.red
end
S.ExportBusy=false
updateUI()
end)
end)
Min.Activated:Connect(function()
Main.Visible=false
HUD.Visible=true
updateUI()
end)
Open.Activated:Connect(function()
HUD.Visible=false
Main.Visible=true
end)
local function cleanup()
S.Recording=false
S.ExportBusy=false
S.SessionId+=1
for _,list in pairs(S.ToolConnections) do
for _,c in ipairs(list) do
pcall(function() c:Disconnect() end)
end
end
for _,c in ipairs(S.Connections) do
pcall(function() c:Disconnect() end)
end
pcall(function() Gui:Destroy() end)
local rt=ENV[RUNTIME_KEY]
if type(rt)=="table" and rt.cleanup==cleanup then
ENV[RUNTIME_KEY]=nil
end
end
ENV[RUNTIME_KEY]={
version=C.VERSION,
cleanup=cleanup
}
Close.Activated:Connect(cleanup)
if Workspace.CurrentCamera then
local ok,sig=pcall(function()
return Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize")
end)
if ok and sig then
S.Connections[#S.Connections+1]=sig:Connect(resize)
end
end
scanWeapons("INITIAL_SCAN")
live("SISTEMA","Pesquisa V2.3.1 pronta.")
live("SISTEMA","Modo livre • sem limite de tiros • pausa preserva os dados.")
live("SISTEMA","Cada disparo é classificado automaticamente por trajetória e local.")
live("SISTEMA","Multi-hit ativo • até 12 camadas por disparo.")
live("SISTEMA","BulletsCannotPierce=true reconhecido como BLOQUEIO_EXPLICITO.")
live("SISTEMA","Confirmação de dano ativa • baseline adicional para armas Auto.")
updateUI()
task.spawn(function()
while Gui.Parent do
pcall(updateUI)
task.wait(0.75)
end
end)