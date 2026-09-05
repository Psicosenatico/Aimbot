local Players=game:GetService("Players")
local HttpService=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local CoreGui=game:GetService("CoreGui")
local Workspace=game:GetService("Workspace")
local LP=Players.LocalPlayer or Players.PlayerAdded:Wait()

local C={
 VERSION="V0.1", GUI="PsicosenaticoBulletNoclipTest_V0_1",
 KEY="__PSICO_BULLET_NOCLIP_TEST_V0_1", THIN=6, HEIGHT=8, SPAN=12,
}
local ENV=_G
if typeof(getgenv)=="function" then local ok,e=pcall(getgenv); if ok and type(e)=="table" then ENV=e end end
if type(ENV[C.KEY])=="table" and type(ENV[C.KEY].cleanup)=="function" then pcall(ENV[C.KEY].cleanup) end

local S={enabled=false,closed=false,started=os.time(),runId="",events={},shots={},candidates={},order={},counts={NAMED_WALL=0,SHAPE_WALL=0},conns={},toolConns={},errors=0,last="Nenhuma leitura ainda."}
local updateUI=function() end
local function full(o) local ok,v=pcall(function() return o:GetFullName() end); return ok and tostring(v) or tostring(o and o.Name or "?") end
local function event(t,d) S.events[#S.events+1]={index=#S.events+1,unix=os.time(),time=os.clock(),type=t,data=d or {}} end
local function err(w,e) S.errors=S.errors+1; event("ERROR",{where=w,message=tostring(e)}) end
local function map() return Workspace:FindFirstChild("Map") end
local function tycoons() return Workspace:FindFirstChild("Tycoons") end
local function runId() local ok,v=pcall(function() return HttpService:GenerateGUID(false) end); return ok and v or tostring(os.time()) end
S.runId=runId()

local function explicitBlock(p)
 local cur=p
 for _=1,10 do
  if not cur or cur==Workspace then break end
  local ok,v=pcall(function() return cur:GetAttribute("BulletsCannotPierce") end)
  if ok and v==true then return true end
  if string.lower(cur.Name)=="lasergate" then return true end
  cur=cur.Parent
 end
 return false
end
local function protectedMap(p)
 if explicitBlock(p) then return true,"LASERGATE_OR_EXPLICIT" end
 local t=tycoons(); if t and p:IsDescendantOf(t) then return true,"TYCOON_BASE" end
 local m=map(); local combat=m and m:FindFirstChild("CombatObstacles")
 if combat and p:IsDescendantOf(combat) then return true,"COMBAT_OBSTACLE" end
 local q=string.lower(full(p))
 for _,w in ipairs({"ground","mountain","terrainpart","teamcolors","teamcolor","spawn"}) do
  if string.find(q,w,1,true) then return true,"PROTECTED_"..string.upper(w) end
 end
 return false,nil
end
local function hasWallName(p,m)
 local cur=p
 while cur and cur~=m do
  if string.find(string.lower(cur.Name),"wall",1,true) then return true,full(cur) end
  cur=cur.Parent
 end
 return false,nil
end
local function shapeCandidate(p)
 local s=p.Size; local thin=math.min(s.X,s.Z); local span=math.max(s.X,s.Z); local h=s.Y
 local floorLike=h<=thin*0.75
 local ok=not floorLike and thin<=C.THIN and h>=C.HEIGHT and span>=C.SPAN and h>=thin*1.5 and span>=thin*3
 return ok,{size={s.X,s.Y,s.Z},thin=thin,span=span,height=h,profile=ok and "VERTICAL_THIN_PANEL" or (floorLike and "FLOOR_LIKE" or "GENERIC")}
end
local function classify(p)
 if not p or not p:IsA("BasePart") then return nil end
 local m=map(); if not m or not p:IsDescendantOf(m) then return nil end
 local prot,why=protectedMap(p); if prot then return nil,why end
 local named,marker=hasWallName(p,m)
 if named then local _,shape=shapeCandidate(p); return {kind="NAMED_WALL",reason="nome/caminho contém Wall",marker=marker,shape=shape} end
 local ok,shape=shapeCandidate(p)
 if ok then return {kind="SHAPE_WALL",reason="painel vertical fino",marker=full(p),shape=shape} end
 return nil,"MAP_GENERIC_REVIEW"
end
local function apply(p,meta)
 if not p or not p.Parent then return false end
 local ok,e=pcall(function() p.CanQuery=false end)
 if not ok then err("apply",e); return false end
 meta.applied=true; return true
end
local function restore(p,meta)
 if not p or not p.Parent then return false end
 local ok,e=pcall(function() p.CanQuery=meta.originalCanQuery end)
 if not ok then err("restore",e); return false end
 meta.applied=false; return true
end
local function register(p,info)
 if S.closed or S.candidates[p] then return false end
 local ok,cq=pcall(function() return p.CanQuery end); if not ok then return false end
 local meta={path=full(p),name=p.Name,class=p.ClassName,kind=info.kind,reason=info.reason,marker=info.marker,shape=info.shape,originalCanQuery=cq,applied=false}
 S.candidates[p]=meta; S.order[#S.order+1]=p; S.counts[info.kind]=(S.counts[info.kind] or 0)+1
 if S.enabled then apply(p,meta) end
 event("CANDIDATE",{path=meta.path,kind=meta.kind,originalCanQuery=cq})
 return true
end
local function scan(reason)
 local m=map(); if not m then event("SCAN",{reason=reason,map=false}); return 0 end
 local n=0
 for _,o in ipairs(m:GetDescendants()) do if o:IsA("BasePart") then local info=classify(o); if info and register(o,info) then n=n+1 end end end
 event("SCAN",{reason=reason,added=n,total=#S.order,named=S.counts.NAMED_WALL,shape=S.counts.SHAPE_WALL}); return n
end
local function setEnabled(v,reason)
 if S.closed or S.enabled==v then return end
 if v then
  scan("ENABLE_REFRESH")
  local n=0; for p,m in pairs(S.candidates) do if p.Parent and not m.applied and apply(p,m) then n=n+1 end end
  S.enabled=true; event("NOCLIP_ON",{reason=reason,changed=n,total=#S.order})
 else
  S.enabled=false
  local n=0; for p,m in pairs(S.candidates) do if p.Parent and m.applied and restore(p,m) then n=n+1 end end
  event("NOCLIP_OFF",{reason=reason,changed=n,total=#S.order})
 end
end

local function humFrom(i)
 local cur=i
 for _=1,6 do if not cur then break end; if cur:IsA("Model") then local h=cur:FindFirstChildOfClass("Humanoid"); if h then return h,cur end end; cur=cur.Parent end
end
local function weaponInfo(tool)
 local a={}; for _,k in ipairs({"_ammo","range","rateOfFire","fireMode","damage","projectileType","rayRadius","raysPerShot","spread"}) do local ok,v=pcall(function() return tool:GetAttribute(k) end); if ok and v~=nil then a[k]=v end end
 return {name=tool.Name,path=full(tool),attributes=a}
end
local function shotRead(tool,delta)
 if S.closed then return end
 local cam=Workspace.CurrentCamera; if not cam then return end
 local range=tool:GetAttribute("range"); if type(range)~="number" or range<=0 then range=1200 end
 local origin=cam.CFrame.Position; local dir=cam.CFrame.LookVector*range
 local rp=RaycastParams.new(); rp.FilterType=Enum.RaycastFilterType.Exclude; rp.IgnoreWater=true; rp.FilterDescendantsInstances=LP.Character and {LP.Character} or {}
 local hit; local ok,e=pcall(function() hit=Workspace:Raycast(origin,dir,rp) end); if not ok then err("shotRay",e) end
 local h,m=nil,nil; if hit then h,m=humFrom(hit.Instance) end
 local rec={index=#S.shots+1,unix=os.time(),time=os.clock(),enabled=S.enabled,ammoDelta=delta,weapon=weaponInfo(tool),candidateTotal=#S.order,firstQueryableHit=hit and {path=full(hit.Instance),name=hit.Instance.Name,class=hit.Instance.ClassName,material=tostring(hit.Material),distance=(hit.Position-origin).Magnitude,humanoid=h~=nil,humanoidModel=m and full(m) or nil} or nil}
 S.shots[#S.shots+1]=rec
 S.last=hit and ((S.enabled and "ATIVO • pós-parede: " or "OFF • primeiro hit: ")..hit.Instance.Name) or (S.enabled and "ATIVO • caminho livre" or "OFF • caminho livre")
 event("SHOT",{shotIndex=rec.index,enabled=S.enabled,ammoDelta=delta,firstQueryableHit=rec.firstQueryableHit}); updateUI()
end
local function unwatch(tool)
 local list=S.toolConns[tool]; if not list then return end
 for _,c in ipairs(list) do pcall(function() c:Disconnect() end) end; S.toolConns[tool]=nil
end
local function watch(tool)
 if S.closed or not tool or not tool:IsA("Tool") or S.toolConns[tool] then return end
 local ammo=tool:GetAttribute("_ammo"); local rof=tool:GetAttribute("rateOfFire"); if ammo==nil and rof==nil then return end
 local last=ammo; local list={}; S.toolConns[tool]=list
 list[#list+1]=tool:GetAttributeChangedSignal("_ammo"):Connect(function() local cur=tool:GetAttribute("_ammo"); if type(cur)=="number" and type(last)=="number" and cur<last then shotRead(tool,last-cur) end; last=cur end)
 list[#list+1]=tool.AncestryChanged:Connect(function(_,par) if par==nil then unwatch(tool) end end)
 event("WEAPON_WATCH",{path=full(tool),ammo=ammo,rateOfFire=rof})
end
local function scanWeapons(reason)
 local n=0; local b=LP:FindFirstChildOfClass("Backpack")
 if b then for _,x in ipairs(b:GetChildren()) do if x:IsA("Tool") then watch(x); n=n+1 end end end
 if LP.Character then for _,x in ipairs(LP.Character:GetChildren()) do if x:IsA("Tool") then watch(x); n=n+1 end end end
 event("WEAPON_SCAN",{reason=reason,seen=n})
end

local function exportCandidates()
 local out={}; for _,p in ipairs(S.order) do local m=S.candidates[p]; if m then out[#out+1]={path=m.path,kind=m.kind,reason=m.reason,marker=m.marker,shape=m.shape,originalCanQuery=m.originalCanQuery,currentCanQuery=(p and p.Parent) and p.CanQuery or nil,applied=m.applied,alive=p and p.Parent~=nil or false} end end; return out
end
local function payload()
 return {format="Psicosenatico Bullet Noclip Test",version=C.VERSION,runId=S.runId,placeId=game.PlaceId,startedAtUnix=S.started,exportedAtUnix=os.time(),enabledAtExport=S.enabled,
  policy={mode="MAP_WALL_ONLY",mechanism="CanQuery=false somente nas candidatas locais de Workspace.Map; restaura ao desligar/fechar",candidates={"NAMED_WALL","SHAPE_WALL"},protected={"Workspace.Tycoons","LaserGate/BulletsCannotPierce=true","Ground","Mountain","TerrainPart","TeamColors/Spawn","CombatObstacles","Map genérico"},diagnosticNote="SHOT usa o raycast consultável após o estado atual; com No Clip ativo ele mostra o primeiro objeto consultável depois das paredes candidatas."},
  summary={shots=#S.shots,events=#S.events,errors=S.errors,candidateTotal=#S.order,namedWalls=S.counts.NAMED_WALL,shapeWalls=S.counts.SHAPE_WALL},candidates=exportCandidates(),shots=S.shots,events=S.events}
end
local function save()
 local ok,json=pcall(function() return HttpService:JSONEncode(payload()) end); if not ok then err("JSONEncode",json); return false,"Falha ao gerar JSON" end
 local name=string.format("Psicosenatico_BulletNoclip_Test_V0_1_%s_%s.json",tostring(game.PlaceId),tostring(os.time()))
 if typeof(writefile)=="function" then local a,b=pcall(writefile,name,json); if a then event("EXPORT",{method="writefile",file=name,bytes=#json}); return true,"Arquivo exportado: "..name else err("writefile",b) end end
 if typeof(setclipboard)=="function" then local a,b=pcall(setclipboard,json); if a then event("EXPORT",{method="clipboard",bytes=#json}); return true,"JSON copiado" else err("clipboard",b) end end
 return false,"Não foi possível salvar/copiar o JSON"
end

local GP=(function() if typeof(gethui)=="function" then local ok,p=pcall(gethui); if ok and p then return p end end; return CoreGui end)()
for _,x in ipairs(GP:GetChildren()) do if x.Name==C.GUI then pcall(function() x:Destroy() end) end end
local Gui=Instance.new("ScreenGui"); Gui.Name=C.GUI; Gui.ResetOnSpawn=false; Gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; Gui.Parent=GP
local function corner(o,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=o end
local function label(p,t,sz,pos,ts) local x=Instance.new("TextLabel"); x.BackgroundTransparency=1; x.Text=t; x.TextColor3=Color3.fromRGB(235,239,245); x.Font=Enum.Font.Gotham; x.TextSize=ts or 13; x.TextXAlignment=Enum.TextXAlignment.Left; x.Size=sz; x.Position=pos; x.Parent=p; return x end
local function btn(p,t,sz,pos) local b=Instance.new("TextButton"); b.BackgroundColor3=Color3.fromRGB(37,46,62); b.TextColor3=Color3.fromRGB(245,247,250); b.Font=Enum.Font.GothamSemibold; b.TextSize=14; b.Text=t; b.Size=sz; b.Position=pos; b.Parent=p; corner(b,8); return b end
local Main=Instance.new("Frame"); Main.BackgroundColor3=Color3.fromRGB(17,22,31); Main.BorderSizePixel=0; Main.Size=UDim2.fromOffset(390,300); Main.Position=UDim2.new(.5,-195,.5,-150); Main.Parent=Gui; corner(Main,12)
local st=Instance.new("UIStroke"); st.Color=Color3.fromRGB(48,71,107); st.Parent=Main
local Head=Instance.new("Frame"); Head.BackgroundColor3=Color3.fromRGB(23,31,44); Head.BorderSizePixel=0; Head.Size=UDim2.new(1,0,0,44); Head.Parent=Main; corner(Head,12)
local mask=Instance.new("Frame"); mask.BackgroundColor3=Head.BackgroundColor3; mask.BorderSizePixel=0; mask.Size=UDim2.new(1,0,0,12); mask.Position=UDim2.new(0,0,1,-12); mask.Parent=Head
local title=label(Head,"PSICOSENATICO • BULLET NOCLIP TEST",UDim2.new(1,-110,0,21),UDim2.fromOffset(14,5),13); title.Font=Enum.Font.GothamSemibold
local ver=label(Head,C.VERSION,UDim2.new(1,-110,0,16),UDim2.fromOffset(14,24),11); ver.TextColor3=Color3.fromRGB(124,160,217)
local Min=btn(Head,"—",UDim2.fromOffset(38,30),UDim2.new(1,-84,0,7)); local Close=btn(Head,"X",UDim2.fromOffset(38,30),UDim2.new(1,-42,0,7)); Close.BackgroundColor3=Color3.fromRGB(104,42,48)
local State=label(Main,"Estado: DESATIVADO",UDim2.new(1,-28,0,22),UDim2.fromOffset(14,57),14); State.Font=Enum.Font.GothamSemibold
local Toggle=btn(Main,"ATIVAR NO CLIP",UDim2.new(1,-28,0,42),UDim2.fromOffset(14,84)); Toggle.BackgroundColor3=Color3.fromRGB(43,92,61)
local Export=btn(Main,"EXPORTAR DIAGNÓSTICO",UDim2.new(1,-28,0,36),UDim2.fromOffset(14,134)); Export.BackgroundColor3=Color3.fromRGB(41,70,112)
local Stats=label(Main,"Candidatas: 0",UDim2.new(1,-28,0,20),UDim2.fromOffset(14,179),12); Stats.TextColor3=Color3.fromRGB(181,194,214)
local Last=label(Main,"Última leitura: nenhuma.",UDim2.new(1,-28,0,38),UDim2.fromOffset(14,202),12); Last.TextWrapped=true; Last.TextYAlignment=Enum.TextYAlignment.Top
local Reader=Instance.new("TextLabel"); Reader.BackgroundColor3=Color3.fromRGB(12,16,23); Reader.BorderSizePixel=0; Reader.TextColor3=Color3.fromRGB(174,187,206); Reader.Font=Enum.Font.Code; Reader.TextSize=10; Reader.TextXAlignment=Enum.TextXAlignment.Left; Reader.TextYAlignment=Enum.TextYAlignment.Top; Reader.TextWrapped=true; Reader.Size=UDim2.new(1,-28,1,-254); Reader.Position=UDim2.fromOffset(14,242); Reader.Text="Leitor: pronto."; Reader.Parent=Main; corner(Reader,8)
local Float=btn(Gui,"NC",UDim2.fromOffset(56,56),UDim2.new(1,-72,.5,-28)); Float.Visible=false; Float.BackgroundColor3=Color3.fromRGB(20,48,86); corner(Float,28)

local function drag(frame,handle)
 local dragging=false; local inputRef,start,pos
 S.conns[#S.conns+1]=handle.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true; start=i.Position; pos=frame.Position; i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dragging=false end end) end end)
 S.conns[#S.conns+1]=handle.InputChanged:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch then inputRef=i end end)
 S.conns[#S.conns+1]=UIS.InputChanged:Connect(function(i) if dragging and i==inputRef and start and pos then local d=i.Position-start; frame.Position=UDim2.new(pos.X.Scale,pos.X.Offset+d.X,pos.Y.Scale,pos.Y.Offset+d.Y) end end)
end
drag(Main,Head); drag(Float,Float)
updateUI=function()
 if S.closed or not Gui.Parent then return end
 State.Text=S.enabled and "Estado: ATIVO • somente paredes candidatas" or "Estado: DESATIVADO • restaurado"; State.TextColor3=S.enabled and Color3.fromRGB(111,221,145) or Color3.fromRGB(223,190,111)
 Toggle.Text=S.enabled and "DESATIVAR NO CLIP" or "ATIVAR NO CLIP"; Toggle.BackgroundColor3=S.enabled and Color3.fromRGB(108,50,55) or Color3.fromRGB(43,92,61)
 Stats.Text=string.format("Candidatas: %d • Wall: %d • Forma: %d • Tiros: %d",#S.order,S.counts.NAMED_WALL,S.counts.SHAPE_WALL,#S.shots); Last.Text="Última leitura: "..S.last; Float.Text=S.enabled and "NC✓" or "NC"
 Reader.Text=string.format("Leitor\nEstado: %s\nCandidatas ativas: %d\nTiros lidos: %d\nErros: %d",S.enabled and "ATIVO" or "OFF",#S.order,#S.shots,S.errors)
end
local function resize() local cam=Workspace.CurrentCamera; if not cam then return end; local v=cam.ViewportSize; local w=math.max(320,math.min(390,math.floor(v.X*.92))); local h=math.max(285,math.min(300,math.floor(v.Y*.70))); Main.Size=UDim2.fromOffset(w,h); Reader.Size=UDim2.new(1,-28,1,-254) end
local function cleanup()
 if S.closed then return end; S.closed=true; S.enabled=false
 for p,m in pairs(S.candidates) do if p.Parent and m.applied then restore(p,m) end end
 for tool,_ in pairs(S.toolConns) do unwatch(tool) end
 for _,c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end; S.conns={}; event("CLOSED",{shots=#S.shots,candidates=#S.order})
 pcall(function() Gui:Destroy() end); if type(ENV[C.KEY])=="table" and ENV[C.KEY].cleanup==cleanup then ENV[C.KEY]=nil end
end
ENV[C.KEY]={version=C.VERSION,cleanup=cleanup}
Toggle.Activated:Connect(function() setEnabled(not S.enabled,"UI"); updateUI() end)
Export.Activated:Connect(function() local ok,msg=save(); Reader.Text=msg; Export.Text=ok and "EXPORTADO ✓" or "FALHA"; task.delay(1.2,function() if Export.Parent then Export.Text="EXPORTAR DIAGNÓSTICO"; updateUI() end end) end)
Min.Activated:Connect(function() Main.Visible=false; Float.Visible=true end); Float.Activated:Connect(function() Float.Visible=false; Main.Visible=true end); Close.Activated:Connect(cleanup)

local m=map(); if m then S.conns[#S.conns+1]=m.DescendantAdded:Connect(function(o) if o:IsA("BasePart") then task.defer(function() if not S.closed then local info=classify(o); if info and register(o,info) then updateUI() end end end) end end) end
local b=LP:FindFirstChildOfClass("Backpack"); if b then S.conns[#S.conns+1]=b.ChildAdded:Connect(function(x) task.defer(function() watch(x) end) end) end
if LP.Character then S.conns[#S.conns+1]=LP.Character.ChildAdded:Connect(function(x) task.defer(function() watch(x) end) end) end
S.conns[#S.conns+1]=LP.CharacterAdded:Connect(function(ch) task.wait(.5); if S.closed then return end; S.conns[#S.conns+1]=ch.ChildAdded:Connect(function(x) task.defer(function() watch(x) end) end); scanWeapons("RESPAWN"); updateUI() end)
if Workspace.CurrentCamera then local ok,sig=pcall(function() return Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize") end); if ok then S.conns[#S.conns+1]=sig:Connect(resize) end end
scan("INITIAL"); scanWeapons("INITIAL"); event("START",{version=C.VERSION,runId=S.runId,candidates=#S.order,named=S.counts.NAMED_WALL,shape=S.counts.SHAPE_WALL}); resize(); updateUI()
