-- PSICOSENATICO • PESQUISA DE ARMAS V2.2.1
-- Fluxo automático de 4 missões + pausa sem reset + HUD minimizado + leitura de possíveis limites do mapa.

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local HttpService=game:GetService("HttpService")
local UserInputService=game:GetService("UserInputService")
local CoreGui=game:GetService("CoreGui")
local Workspace=game:GetService("Workspace")
local CollectionService=game:GetService("CollectionService")

local LP=Players.LocalPlayer or Players.PlayerAdded:Wait()

local C={
 VERSION="V2.2.1",
 GUI="PsicosenaticoWeaponResearch_V2_2_1",
 SHOTS=3,
 MAX_EVENTS=2200,
 MAX_LIVE=90,
 BOUNDARY_DISTANCE=10000,
 PHASES={"CLEAR","WALL","TARGET_BEHIND_WALL","TARGET_CLEAR"},
 LABELS={
  CLEAR="TIRO LIVRE",
  WALL="PAREDE",
  TARGET_BEHIND_WALL="ALVO + PAREDE",
  TARGET_CLEAR="ALVO LIVRE"
 },
 HELP={
  CLEAR="Atire para o céu/espaço sem alvo.",
  WALL="Atire diretamente em uma parede.",
  TARGET_BEHIND_WALL="Atire em um alvo com uma parede no meio.",
  TARGET_CLEAR="Atire diretamente em um alvo sem parede."
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
local OLD={PsicosenaticoWeaponResearch_V2_1=true,PsicosenaticoWeaponResearch_V2_2=true,[C.GUI]=true}
for _,x in ipairs(GP:GetChildren()) do
 if OLD[x.Name] then pcall(function() x:Destroy() end) end
end

local S={
 Recording=false,Started=false,Completed=false,
 StartUnix=nil,EndUnix=nil,Errors=0,
 Events={},Live={},Markers={},Shots={},
 PhaseIndex=0,CurrentPhase=nil,PhaseShots=0,PhaseStats={},
 ActiveTool=nil,Tools={},ToolConnections={},Connections={},
 Architecture=nil,SourceInspection={},BoundarySurvey={},LastAssessment=nil
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
 if not S.Recording or #S.Events>=C.MAX_EVENTS then return end
 S.Events[#S.Events+1]={
  unix=unix(),time=clock(),type=kind,
  phase=S.CurrentPhase,phaseIndex=S.PhaseIndex,phaseShots=S.PhaseShots,
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
  r.sourceReadable=true;r.sourceLength=#v;r.source=v
  if #v==0 then r.note="PROPRIEDADE_ACESSIVEL_MAS_CONTEUDO_VAZIO" end
 else r.error=tostring(v) end
 return r
end

local function inspectArchitecture(reason)
 local root=ReplicatedStorage:FindFirstChild("BlasterSystem")
 local out={reason=reason,time=clock(),found=root~=nil,rootPath=root and full(root) or nil,targets={},remotes={},sourceInspection={}}
 if not root then S.Architecture=out;log("ARCHITECTURE_SCAN",{found=false},"BlasterSystem não encontrado");return end
 local wanted={canpierce=true,castrays=true,shoot=true,shootprojectile=true,replicateprojectile=true,projectilehit=true}
 for _,o in ipairs(root:GetDescendants()) do
  if wanted[string.lower(o.Name)] then
   local item={name=o.Name,class=o.ClassName,path=full(o)}
   out.targets[#out.targets+1]=item
   if o:IsA("RemoteEvent") or o:IsA("RemoteFunction") or o:IsA("UnreliableRemoteEvent") then out.remotes[#out.remotes+1]=item end
   if o:IsA("ModuleScript") then
    local si=inspectSource(o)
    out.sourceInspection[#out.sourceInspection+1]=si
    S.SourceInspection[si.path]=si
   end
  end
 end
 table.sort(out.targets,function(a,b) return a.path<b.path end)
 S.Architecture=out
 log("ARCHITECTURE_SCAN",{reason=reason,targetCount=#out.targets,remoteCount=#out.remotes,moduleCount=#out.sourceInspection},
  string.format("Arquitetura: %d alvos",#out.targets))
end

local function hasLimitWord(text)
 text=string.lower(tostring(text or ""))
 for _,w in ipairs(C.LIMIT_WORDS) do
  if string.find(text,w,1,true) then return true,w end
 end
 return false,nil
end

local function classify(inst,hasHumanoid)
 if not inst then return "SEM_IMPACTO",0,{} end
 if hasHumanoid then return "PERSONAGEM",0,{"modelo possui Humanoid"} end

 local score,reasons=0,{}
 local hit,w=hasLimitWord(inst.Name.." "..full(inst))
 if hit then score+=5;reasons[#reasons+1]="nome/caminho sugere limite: "..w end

 local tr=tonumber(prop(inst,"Transparency"))
 local cq=prop(inst,"CanQuery")
 local cc=prop(inst,"CanCollide")
 local size=prop(inst,"Size")
 if tr and tr>=0.95 then score+=3;reasons[#reasons+1]="quase/invisível" end
 if cq==true and cc==false then score+=1;reasons[#reasons+1]="CanQuery=true e CanCollide=false" end
 if typeof(size)=="Vector3" then
  local m=math.max(size.X,size.Y,size.Z)
  if m>=2000 then score+=3;reasons[#reasons+1]="dimensão muito grande"
  elseif m>=500 then score+=1;reasons[#reasons+1]="dimensão grande" end
 end

 local attrs,tags={},{}
 pcall(function() attrs=inst:GetAttributes() end)
 pcall(function() tags=CollectionService:GetTags(inst) end)
 for k,v in pairs(attrs) do
  local ok2,key=hasLimitWord(tostring(k).."="..tostring(v))
  if ok2 then score+=5;reasons[#reasons+1]="atributo sugere limite: "..key;break end
 end
 for _,tag in ipairs(tags) do
  local ok2,key=hasLimitWord(tag)
  if ok2 then score+=5;reasons[#reasons+1]="tag sugere limite: "..tostring(tag);break end
 end

 return score>=5 and "POSSIVEL_LIMITE_MAPA" or "GEOMETRIA_MAPA",score,reasons
end

local function describe(result,origin)
 if not result then return nil end
 local inst=result.Instance
 local model=inst and inst:FindFirstAncestorOfClass("Model") or nil
 local hum=model and model:FindFirstChildOfClass("Humanoid") or nil
 local class,score,reasons=classify(inst,hum~=nil)
 local size=prop(inst,"Size")
 local attrs,tags={},{}
 pcall(function() attrs=inst:GetAttributes() end)
 pcall(function() tags=CollectionService:GetTags(inst) end)
 return {
  instance=inst and full(inst) or nil,instanceName=inst and inst.Name or nil,instanceClass=inst and inst.ClassName or nil,
  model=model and full(model) or nil,modelName=model and model.Name or nil,hasHumanoid=hum~=nil,
  material=tostring(result.Material),distance=(result.Position-origin).Magnitude,
  position={result.Position.X,result.Position.Y,result.Position.Z},normal={result.Normal.X,result.Normal.Y,result.Normal.Z},
  classification=class,boundaryScore=score,boundaryReasons=reasons,
  transparency=prop(inst,"Transparency"),canCollide=prop(inst,"CanCollide"),canQuery=prop(inst,"CanQuery"),
  canTouch=prop(inst,"CanTouch"),anchored=prop(inst,"Anchored"),collisionGroup=prop(inst,"CollisionGroup"),
  size=typeof(size)=="Vector3" and {size.X,size.Y,size.Z} or nil,tags=tags,attributes=attrs
 }
end

local function assessment(ref)
 if not ref or not ref.ok then return "LEITURA_INDISPONIVEL" end
 if not ref.firstHit then return "CAMINHO_LIVRE" end
 if ref.firstHit.classification=="POSSIVEL_LIMITE_MAPA" then return "POSSIVEL_LIMITE_MAPA" end
 if ref.firstHit.classification=="PERSONAGEM" then return "PERSONAGEM" end
 return "GEOMETRIA_MAPA"
end

local function referenceRay(tool)
 local cam=Workspace.CurrentCamera
 if not cam then return {ok=false,reason="SEM_CAMERA"} end
 local vp=cam.ViewportSize
 local ray=cam:ViewportPointToRay(vp.X/2,vp.Y/2)
 local range=tonumber(attr(tool or S.ActiveTool,"range")) or 2000
 local dir=ray.Direction.Unit*range

 local ex={cam}
 if LP.Character then ex[#ex+1]=LP.Character end
 local p=RaycastParams.new()
 p.FilterType=Enum.RaycastFilterType.Exclude;p.FilterDescendantsInstances=ex;p.IgnoreWater=false
 local ok,first=pcall(function() return Workspace:Raycast(ray.Origin,dir,p) end)
 if not ok then return {ok=false,reason=tostring(first),range=range} end

 local out={
  ok=true,hit=first~=nil,origin={ray.Origin.X,ray.Origin.Y,ray.Origin.Z},
  direction={dir.X,dir.Y,dir.Z},range=range,
  firstHit=describe(first,ray.Origin),nextHit=nil
 }

 if first and first.Instance then
  local d=(first.Position-ray.Origin).Magnitude
  local rem=range-d-0.05
  if rem>0 then
   local p2=RaycastParams.new()
   local ex2={cam,first.Instance}
   if LP.Character then ex2[#ex2+1]=LP.Character end
   p2.FilterType=Enum.RaycastFilterType.Exclude;p2.FilterDescendantsInstances=ex2;p2.IgnoreWater=false
   local o2=first.Position+ray.Direction.Unit*0.05
   local ok2,second=pcall(function() return Workspace:Raycast(o2,ray.Direction.Unit*rem,p2) end)
   if ok2 and second then out.nextHit=describe(second,o2) end
  end
 end
 out.assessment=assessment(out)
 return out
end

local function validatePhase(phase,ref)
 local first=ref and ref.firstHit or nil
 local second=ref and ref.nextHit or nil
 local a=ref and ref.assessment or "LEITURA_INDISPONIVEL"
 if phase=="CLEAR" then
  if a=="CAMINHO_LIVRE" then return "COMPATIVEL","nenhum obstáculo dentro do alcance" end
  if a=="POSSIVEL_LIMITE_MAPA" then return "COMPATIVEL_COM_LIMITE","possível limite/barreira do mapa" end
  return "REVISAR","o tiro livre encontrou geometria/personagem"
 elseif phase=="WALL" then
  if first and not first.hasHumanoid then
   return first.classification=="POSSIVEL_LIMITE_MAPA" and "REVISAR_LIMITE" or "COMPATIVEL",
          first.classification=="POSSIVEL_LIMITE_MAPA" and "obstáculo pode ser limite do mapa" or "primeiro impacto é geometria"
  end
  return "REVISAR","parede não foi o primeiro impacto"
 elseif phase=="TARGET_BEHIND_WALL" then
  if first and not first.hasHumanoid and second and second.hasHumanoid then return "FORTE_COMPATIBILIDADE","geometria primeiro e personagem logo atrás" end
  if first and not first.hasHumanoid then return "INCONCLUSIVO","há geometria primeiro; nextHit não confirmou personagem" end
  return "REVISAR","primeiro impacto não foi geometria"
 elseif phase=="TARGET_CLEAR" then
  if first and first.hasHumanoid then return "COMPATIVEL","personagem é o primeiro impacto" end
  return "REVISAR","personagem não foi o primeiro impacto"
 end
 return "SEM_FASE","fase desconhecida"
end

local function boundarySurvey()
 local cam=Workspace.CurrentCamera
 if not cam then return end
 local origin=cam.CFrame.Position
 local dirs={
  {"CIMA",Vector3.new(0,1,0)},{"NORTE",Vector3.new(0,0,-1)},{"SUL",Vector3.new(0,0,1)},
  {"LESTE",Vector3.new(1,0,0)},{"OESTE",Vector3.new(-1,0,0)}
 }
 local p=RaycastParams.new();p.FilterType=Enum.RaycastFilterType.Exclude;p.IgnoreWater=false
 p.FilterDescendantsInstances=LP.Character and {LP.Character,cam} or {cam}
 S.BoundarySurvey={}
 for _,v in ipairs(dirs) do
  local ok,r=pcall(function() return Workspace:Raycast(origin,v[2]*C.BOUNDARY_DISTANCE,p) end)
  S.BoundarySurvey[#S.BoundarySurvey+1]={direction=v[1],ok=ok,hit=ok and r~=nil or false,firstHit=ok and describe(r,origin) or nil,error=ok and nil or tostring(r)}
 end
 log("BOUNDARY_SURVEY",{rays=S.BoundarySurvey},"Leitura auxiliar de possíveis limites concluída")
end

local function phaseLabel() return C.LABELS[S.CurrentPhase] or "-" end
local function phaseHelp() return C.HELP[S.CurrentPhase] or "Aguardando início." end

local function phaseMarker(reason)
 if not S.CurrentPhase then return end
 local m={
  time=clock(),unix=unix(),kind=S.CurrentPhase,label=phaseLabel(),phaseIndex=S.PhaseIndex,reason=reason,
  weapon=weapon(S.ActiveTool),referenceRay=S.ActiveTool and referenceRay(S.ActiveTool) or nil
 }
 S.Markers[#S.Markers+1]=m
 log("PHASE_MARKER",m,string.format("MISSÃO %d/4 • %s",S.PhaseIndex,m.label))
end

local function setPhase(index,reason)
 S.PhaseIndex=index;S.CurrentPhase=C.PHASES[index];S.PhaseShots=0
 if not S.CurrentPhase then return end
 S.PhaseStats[S.CurrentPhase]=S.PhaseStats[S.CurrentPhase] or {required=C.SHOTS,confirmed=0,completed=false}
 phaseMarker(reason or "AUTO")
end

local function advancePhase()
 if S.PhaseShots<C.SHOTS then return end
 local st=S.PhaseStats[S.CurrentPhase];if st then st.completed=true end
 local nxt=S.PhaseIndex+1
 if nxt>#C.PHASES then
  log("ALL_PHASES_COMPLETED",{totalShots=#S.Shots},"4 missões concluídas")
  S.Completed=true;S.Recording=false;S.EndUnix=unix()
 else
  setPhase(nxt,"AUTO_ADVANCE")
 end
end

local function addToolConn(tool,c)
 S.ToolConnections[tool]=S.ToolConnections[tool] or {}
 table.insert(S.ToolConnections[tool],c)
end

local function registerWeapon(tool,reason)
 if not isWeapon(tool) or S.Tools[tool] then return end
 S.Tools[tool]={name=tool.Name,reason=reason,firstPath=full(tool),initial=weapon(tool),lastAmmo=tonumber(attr(tool,"_ammo"))}
 log("WEAPON_FOUND",{reason=reason,snapshot=weapon(tool)},"Arma: "..tool.Name)

 addToolConn(tool,tool.Equipped:Connect(function()
  S.ActiveTool=tool
  local d=S.Tools[tool];if d then d.lastAmmo=tonumber(attr(tool,"_ammo")) end
  log("WEAPON_EQUIPPED",{snapshot=weapon(tool)},tool.Name.." equipada")
 end))

 addToolConn(tool,tool.Unequipped:Connect(function()
  if S.ActiveTool==tool then S.ActiveTool=nil end
  log("WEAPON_UNEQUIPPED",{name=tool.Name},tool.Name.." desequipada")
 end))

 addToolConn(tool,tool.Activated:Connect(function()
  if not S.Recording then return end
  local ref=referenceRay(tool)
  log("SHOT_TRIGGER",{phase=S.CurrentPhase,phaseIndex=S.PhaseIndex,phaseShots=S.PhaseShots,weapon=weapon(tool),referenceRay=ref},
      tool.Name.." • "..phaseLabel().." • gatilho")
 end))

 for _,name in ipairs(C.ATTRS) do
  local ok,sig=pcall(function() return tool:GetAttributeChangedSignal(name) end)
  if ok and sig then
   addToolConn(tool,sig:Connect(function()
    local value=attr(tool,name)
    local d=S.Tools[tool]
    if name=="_ammo" and d then
     local before,after=tonumber(d.lastAmmo),tonumber(value)
     if before and after and after<before and S.Recording and not S.Completed and S.CurrentPhase then
      local raw=before-after
      local remain=math.max(0,C.SHOTS-S.PhaseShots)
      local counted=math.min(raw,remain)
      local ref=referenceRay(tool)
      local shot={
       time=clock(),unix=unix(),source="AMMO_DECREASE",
       phase=S.CurrentPhase,phaseIndex=S.PhaseIndex,phaseShotBefore=S.PhaseShots,
       ammoBefore=before,ammoAfter=after,ammoDelta=raw,countedForPhase=counted,overflowNotCounted=math.max(0,raw-counted),
       weapon=weapon(tool),referenceRay=ref,assessment=ref.assessment
      }
      shot.phaseValidation,shot.phaseValidationReason=validatePhase(S.CurrentPhase,ref)
      S.Shots[#S.Shots+1]=shot;S.LastAssessment=ref.assessment
      if counted>0 then
       S.PhaseShots+=counted
       local st=S.PhaseStats[S.CurrentPhase];if st then st.confirmed=S.PhaseShots end
      end
      log("SHOT_AMMO_CONFIRMED",shot,string.format("%s • %s • %d/%d • %s",tool.Name,phaseLabel(),S.PhaseShots,C.SHOTS,tostring(ref.assessment)))
      live("VALIDACAO",tostring(shot.phaseValidation).." • "..tostring(shot.phaseValidationReason))
      advancePhase()
     end
     d.lastAmmo=after or value
    elseif S.Recording then
     log("ATTRIBUTE_CHANGED",{weapon=tool.Name,attribute=name,value=value},tool.Name.." • "..name.."="..tostring(value))
    end
   end))
  end
 end
end

local function scanWeapons(reason)
 local bp=LP:FindFirstChildOfClass("Backpack")
 local ch=LP.Character
 if bp then for _,o in ipairs(bp:GetChildren()) do if o:IsA("Tool") then registerWeapon(o,reason or "BACKPACK_SCAN") end end end
 if ch then
  for _,o in ipairs(ch:GetChildren()) do
   if o:IsA("Tool") then registerWeapon(o,reason or "CHARACTER_SCAN");if isWeapon(o) then S.ActiveTool=o end end
  end
 end
end

local function connectCharacter(ch)
 S.Connections[#S.Connections+1]=ch.ChildAdded:Connect(function(o)
  if o:IsA("Tool") then task.defer(function() registerWeapon(o,"CHARACTER_ADDED");if isWeapon(o) then S.ActiveTool=o end end) end
 end)
end

local function connectBackpack()
 local bp=LP:FindFirstChildOfClass("Backpack");if not bp then return end
 S.Connections[#S.Connections+1]=bp.ChildAdded:Connect(function(o)
  if o:IsA("Tool") then task.defer(registerWeapon,o,"BACKPACK_ADDED") end
 end)
end

if LP.Character then connectCharacter(LP.Character) end
connectBackpack()
S.Connections[#S.Connections+1]=LP.CharacterAdded:Connect(function(ch)
 S.ActiveTool=nil;task.wait(0.35);connectCharacter(ch);scanWeapons("RESPAWN_SCAN")
end)

local function resetSession()
 S.Events={};S.Markers={};S.Shots={};S.Errors=0;S.PhaseStats={};S.BoundarySurvey={};S.LastAssessment=nil
 S.PhaseIndex=0;S.CurrentPhase=nil;S.PhaseShots=0;S.Completed=false;S.SourceInspection={}
 S.StartUnix=unix();S.EndUnix=nil
end

local function beginSession()
 if not S.ActiveTool or not isWeapon(S.ActiveTool) then live("AVISO","Equipe uma arma antes de iniciar.");return false end
 resetSession();S.Started=true;S.Recording=true
 log("DIAGNOSTIC_STARTED",{},"Pesquisa V2.2.1 iniciada")
 inspectArchitecture("DIAGNOSTIC_START");boundarySurvey();setPhase(1,"SESSION_START")
 return true
end

local function pauseSession()
 if not S.Recording then return end
 log("SESSION_PAUSED",{phase=S.CurrentPhase,phaseIndex=S.PhaseIndex,phaseShots=S.PhaseShots},"Pausado sem apagar progresso")
 S.Recording=false
end

local function resumeSession()
 if not S.Started or S.Completed then return false end
 if not S.ActiveTool or not isWeapon(S.ActiveTool) then live("AVISO","Equipe uma arma antes de retomar.");return false end
 S.Recording=true
 log("SESSION_RESUMED",{phase=S.CurrentPhase,phaseIndex=S.PhaseIndex,phaseShots=S.PhaseShots},"Retomado na mesma missão")
 return true
end

local function serializeTools()
 local out={}
 for tool,d in pairs(S.Tools) do
  out[#out+1]={name=d.name,reason=d.reason,firstPath=d.firstPath,initial=d.initial,final=tool and tool.Parent and weapon(tool) or nil}
 end
 table.sort(out,function(a,b) return tostring(a.name)<tostring(b.name) end)
 return out
end

local function exportTable()
 return {
  format="Psicosenatico Weapon Research",version=C.VERSION,focus="BULLET_NOCLIP_WALL_PENETRATION",generatedAtUnix=unix(),
  diagnostic={status=S.Completed and "COMPLETED" or (S.Recording and "RECORDING" or "PAUSED_OR_STOPPED"),startedAtUnix=S.StartUnix,finishedAtUnix=S.EndUnix},
  automaticFlow={shotsPerPhase=C.SHOTS,currentPhase=S.CurrentPhase,currentPhaseIndex=S.PhaseIndex,currentPhaseShots=S.PhaseShots,completed=S.Completed,phaseStats=S.PhaseStats},
  summary={events=#S.Events,markers=#S.Markers,confirmedShotRecords=#S.Shots,errors=S.Errors},
  architecture=S.Architecture,sourceInspection=S.SourceInspection,boundarySurvey=S.BoundarySurvey,
  tools=serializeTools(),markers=S.Markers,shots=S.Shots,events=S.Events,
  interpretationRules={
   "referenceRay é uma leitura geométrica local do cenário.",
   "nextHit ignora apenas a primeira peça e não simula canPierce.",
   "POSSIVEL_LIMITE_MAPA é heurístico: nome/tags/atributos/transparência/dimensões.",
   "Barreiras sem geometria consultável por raycast ou regras exclusivamente do servidor podem não ser detectadas.",
   "Nenhum RemoteEvent é disparado e nenhum ModuleScript é executado via require()."
  }
 }
end

local function encode()
 local ok,v=pcall(function() return HttpService:JSONEncode(exportTable()) end)
 return ok and v or nil,ok and nil or v
end

local COL={
 bg=Color3.fromRGB(10,10,13),panel=Color3.fromRGB(19,19,24),panel2=Color3.fromRGB(28,28,35),
 text=Color3.fromRGB(245,245,248),sub=Color3.fromRGB(158,158,172),
 blue=Color3.fromRGB(22,55,105),blue2=Color3.fromRGB(32,82,145),
 green=Color3.fromRGB(65,210,118),red=Color3.fromRGB(235,38,52),yellow=Color3.fromRGB(242,184,57)
}
local function new(class,p)
 local o=Instance.new(class);for k,v in pairs(p or {}) do o[k]=v end;return o
end
local function round(o,r) new("UICorner",{Parent=o,CornerRadius=UDim.new(0,r or 8)}) end
local function label(parent,text,size,pos,ts)
 return new("TextLabel",{Parent=parent,BackgroundTransparency=1,Text=text,Size=size,Position=pos,TextColor3=COL.text,Font=Enum.Font.Gotham,TextSize=ts or 10,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center})
end

local Gui=new("ScreenGui",{Parent=GP,Name=C.GUI,ResetOnSpawn=false,IgnoreGuiInset=true})
local Main=new("Frame",{Parent=Gui,BackgroundColor3=COL.bg,BorderSizePixel=0,AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5)})
round(Main,15)

local function resize()
 local cam=Workspace.CurrentCamera;if not cam then return end
 local v=cam.ViewportSize
 Main.Size=UDim2.fromOffset(math.max(320,math.min(math.floor(v.X*0.94),v.X-14)),math.max(285,math.min(math.floor(v.Y*0.72),v.Y-14)))
end
resize()

local Header=new("Frame",{Parent=Main,Size=UDim2.new(1,0,0,56),BackgroundColor3=COL.panel,BorderSizePixel=0});round(Header,15)
label(Header,"PSICOSENATICO • PESQUISA DE ARMAS",UDim2.new(1,-140,0,24),UDim2.fromOffset(14,5),14)
local Ver=label(Header,"V2.2.1",UDim2.fromOffset(48,16),UDim2.fromOffset(14,32),9);Ver.TextColor3=COL.blue2
local Sub=label(Header,"PENETRAÇÃO DE PAREDE • AUTOMÁTICO",UDim2.new(1,-190,0,16),UDim2.fromOffset(66,32),8);Sub.TextColor3=COL.sub

local Min=new("TextButton",{Parent=Header,Size=UDim2.fromOffset(36,32),Position=UDim2.new(1,-82,0,11),Text="—",BackgroundColor3=COL.panel2,TextColor3=COL.text,Font=Enum.Font.GothamBold,TextSize=17,BorderSizePixel=0});round(Min,9)
local Close=new("TextButton",{Parent=Header,Size=UDim2.fromOffset(36,32),Position=UDim2.new(1,-41,0,11),Text="×",BackgroundColor3=COL.red,TextColor3=COL.text,Font=Enum.Font.GothamBold,TextSize=19,BorderSizePixel=0});round(Close,9)

local Status=label(Main,"Pronto • equipe uma arma.",UDim2.new(1,-28,0,19),UDim2.fromOffset(14,59),9);Status.TextColor3=COL.sub
local Start=new("TextButton",{Parent=Main,Size=UDim2.new(0.5,-17,0,34),Position=UDim2.fromOffset(14,81),Text="INICIAR",BackgroundColor3=COL.blue2,TextColor3=COL.text,Font=Enum.Font.GothamBold,TextSize=10,BorderSizePixel=0});round(Start,8)
local Export=new("TextButton",{Parent=Main,Size=UDim2.new(0.5,-17,0,34),Position=UDim2.new(0.5,3,0,81),Text="EXPORTAR",BackgroundColor3=COL.blue,TextColor3=COL.text,Font=Enum.Font.GothamBold,TextSize=10,BorderSizePixel=0});round(Export,8)

local Mission=new("Frame",{Parent=Main,Position=UDim2.fromOffset(14,120),Size=UDim2.new(1,-28,0,48),BackgroundColor3=COL.panel2,BorderSizePixel=0});round(Mission,8)
local MTitle=label(Mission,"MISSÃO: AGUARDANDO",UDim2.new(1,-18,0,20),UDim2.fromOffset(9,4),10);MTitle.Font=Enum.Font.GothamBold
local MHelp=label(Mission,"O fluxo será automático após iniciar.",UDim2.new(1,-18,0,18),UDim2.fromOffset(9,25),8);MHelp.TextColor3=COL.sub
local Summary=label(Main,"",UDim2.new(1,-28,0,18),UDim2.fromOffset(14,171),8);Summary.TextColor3=COL.sub

local Viewer=new("ScrollingFrame",{Parent=Main,Position=UDim2.fromOffset(14,193),Size=UDim2.new(1,-28,1,-202),BackgroundColor3=COL.panel,BorderSizePixel=0,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=5,ScrollingDirection=Enum.ScrollingDirection.Y});round(Viewer,9)
local Text=new("TextLabel",{Parent=Viewer,BackgroundTransparency=1,Position=UDim2.fromOffset(8,7),Size=UDim2.new(1,-16,0,0),AutomaticSize=Enum.AutomaticSize.Y,Text="",TextColor3=COL.text,Font=Enum.Font.Code,TextSize=9,TextWrapped=false,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top})

local HUD=new("Frame",{Parent=Gui,Visible=false,Active=true,Size=UDim2.fromOffset(340,74),Position=UDim2.fromScale(0.04,0.18),BackgroundColor3=COL.bg,BorderSizePixel=0});round(HUD,12)
local HTitle=label(HUD,"AGUARDANDO",UDim2.new(1,-78,0,24),UDim2.fromOffset(12,7),10);HTitle.Font=Enum.Font.GothamBold
local HHelp=label(HUD,"",UDim2.new(1,-78,0,36),UDim2.fromOffset(12,31),8);HHelp.TextWrapped=true;HHelp.TextColor3=COL.sub
local Open=new("TextButton",{Parent=HUD,Size=UDim2.fromOffset(60,48),Position=UDim2.new(1,-68,0,13),Text="ABRIR",BackgroundColor3=COL.blue,TextColor3=COL.text,Font=Enum.Font.GothamBold,TextSize=9,BorderSizePixel=0});round(Open,8)

local function draggable(target,handle)
 local dragging,input,start,pos=false,nil,nil,nil
 S.Connections[#S.Connections+1]=handle.InputBegan:Connect(function(i)
  if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
   dragging=true;start=i.Position;pos=target.Position
   i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dragging=false end end)
  end
 end)
 S.Connections[#S.Connections+1]=handle.InputChanged:Connect(function(i)
  if i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch then input=i end
 end)
 S.Connections[#S.Connections+1]=UserInputService.InputChanged:Connect(function(i)
  if dragging and i==input then
   local d=i.Position-start
   target.Position=UDim2.new(pos.X.Scale,pos.X.Offset+d.X,pos.Y.Scale,pos.Y.Offset+d.Y)
  end
 end)
end
draggable(Main,Header);draggable(HUD,HUD)

local function updateUI()
 local active=S.ActiveTool and S.ActiveTool.Name or "NENHUMA"
 local state=S.Completed and "CONCLUÍDO" or (S.Recording and "GRAVANDO" or (S.Started and "PAUSADO" or "PRONTO"))
 Summary.Text=string.format("%s • ARMA:%s • FASE:%s • TIROS:%d • ERROS:%d",state,active,phaseLabel(),#S.Shots,S.Errors)

 if S.Completed then
  MTitle.Text="✓ TESTE CONCLUÍDO • 4/4";MHelp.Text="As 12 leituras foram concluídas. Exporte o JSON."
  HTitle.Text="✓ TESTE CONCLUÍDO";HHelp.Text="4/4 missões concluídas • exporte o JSON."
 elseif not S.Started or not S.CurrentPhase then
  MTitle.Text="MISSÃO: AGUARDANDO";MHelp.Text="Inicie com uma arma equipada."
  HTitle.Text="AGUARDANDO";HHelp.Text="Equipe uma arma e inicie a coleta."
 else
  local pre=S.Recording and "" or "PAUSADO • "
  MTitle.Text=string.format("%sMISSÃO %d/4 • %s • %d/%d",pre,S.PhaseIndex,phaseLabel(),S.PhaseShots,C.SHOTS)
  MHelp.Text=phaseHelp()
  HTitle.Text=string.format("%s%d/4 • %s • %d/%d",pre,S.PhaseIndex,phaseLabel(),S.PhaseShots,C.SHOTS)
  HHelp.Text=phaseHelp().."\n"..(S.LastAssessment and ("Última leitura: "..S.LastAssessment) or "Sem leitura ainda.")
 end

 local lines={
  "PESQUISA DE ARMAS V2.2.1","────────────────────────────────────────",
  "FLUXO AUTOMÁTICO • 3 tiros por missão","",
  "1 TIRO LIVRE → céu/espaço sem alvo",
  "2 PAREDE → diretamente na parede",
  "3 ALVO + PAREDE → alvo com parede no meio",
  "4 ALVO LIVRE → alvo sem parede","",
  "LIMITE DO MAPA",
  "CAMINHO_LIVRE = nenhum impacto no alcance",
  "POSSIVEL_LIMITE_MAPA = indícios de barreira/limite",
  "GEOMETRIA_MAPA = peça normal do mapa",
  "PERSONAGEM = modelo com Humanoid","",
  "PAUSAR NÃO APAGA O PROGRESSO","","ÚLTIMOS EVENTOS","────────────────────────────────────────"
 }
 for i=math.max(1,#S.Live-65),#S.Live do
  local e=S.Live[i];lines[#lines+1]=string.format("[%.3f] %-18s %s",e.time or 0,tostring(e.type),tostring(e.message))
 end
 Text.Text=table.concat(lines,"\n")
end

Start.Activated:Connect(function()
 if not S.Started or S.Completed then
  if beginSession() then Start.Text="PAUSAR";Status.Text="Gravando • siga a missão mostrada.";Status.TextColor3=COL.green
  else Status.Text="Equipe uma arma antes de iniciar.";Status.TextColor3=COL.red end
 elseif S.Recording then
  pauseSession();Start.Text="RETOMAR";Status.Text="Pausado • progresso preservado.";Status.TextColor3=COL.yellow
 else
  if resumeSession() then Start.Text="PAUSAR";Status.Text="Retomado • continue a mesma missão.";Status.TextColor3=COL.green
  else Status.Text="Equipe uma arma antes de retomar.";Status.TextColor3=COL.red end
 end
 updateUI()
end)

Export.Activated:Connect(function()
 if not S.Started then Status.Text="Inicie a coleta antes de exportar.";Status.TextColor3=COL.yellow;return end
 local data,err=encode()
 if not data then Status.Text="Falha JSON: "..tostring(err);Status.TextColor3=COL.red;return end
 local name="Psicosenatico_WeaponResearch_V2_2_1_"..tostring(game.PlaceId).."_"..tostring(os.time())..".json"
 local saved=false
 if typeof(writefile)=="function" then saved=pcall(function() writefile(name,data) end) end
 if saved then Status.Text="✓ ARQUIVO EXPORTADO: "..name;Status.TextColor3=COL.green
 elseif typeof(setclipboard)=="function" and pcall(function() setclipboard(data) end) then Status.Text="✓ JSON COPIADO.";Status.TextColor3=COL.green
 else Status.Text="Não foi possível salvar ou copiar o JSON.";Status.TextColor3=COL.red end
end)

Min.Activated:Connect(function() Main.Visible=false;HUD.Visible=true;updateUI() end)
Open.Activated:Connect(function() HUD.Visible=false;Main.Visible=true end)

local function cleanup()
 S.Recording=false
 for _,list in pairs(S.ToolConnections) do for _,c in ipairs(list) do pcall(function() c:Disconnect() end) end end
 for _,c in ipairs(S.Connections) do pcall(function() c:Disconnect() end) end
 pcall(function() Gui:Destroy() end)
 local rt=ENV[RUNTIME_KEY]
 if type(rt)=="table" and rt.cleanup==cleanup then ENV[RUNTIME_KEY]=nil end
end

ENV[RUNTIME_KEY]={version=C.VERSION,cleanup=cleanup}
Close.Activated:Connect(cleanup)

if Workspace.CurrentCamera then
 local ok,sig=pcall(function() return Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize") end)
 if ok and sig then S.Connections[#S.Connections+1]=sig:Connect(resize) end
end

scanWeapons("INITIAL_SCAN")
live("SISTEMA","Pesquisa V2.2.1 pronta.")
live("SISTEMA","Fluxo automático • pausa preserva o progresso.")
updateUI()

task.spawn(function()
 while Gui.Parent do pcall(updateUI);task.wait(0.75) end
end)
