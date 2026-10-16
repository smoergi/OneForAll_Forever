local ADDON, FLT = ...

local ASSET_ROOT = FLT.ASSET_ROOT or ("Interface\\AddOns\\" .. ADDON .. "\\Assets\\")


-- Class list (id, name, tree names) comes from TalentData.lua.
local CLASSES = {}
for _,id in ipairs({1,2,3,4,5,7,8,9,11}) do
  local d=FLT.TALENT_DATA[id]
  CLASSES[#CLASSES+1]={ id=id, token=d.token, name=d.name, trees=d.trees }
end

-- Fallback store until SavedVariables are available; after ADDON_LOADED the
-- plans live in OneForAllDB.talentPlans and survive /reload and logout.
local plannerState = {}

-- Talent icon layout. Keep enough breathing room for the native Quickslot frame
-- while still fitting four columns and seven rows in each OneForAll tree panel.
local TALENT_BUTTON_SIZE = 40
local TALENT_ICON_INSET = 3
local GRID_X0 = 49 -- centers the 4-column grid in the 282px tree panel
local GRID_Y0 = 46
local GRID_X_STEP = 48 -- same as GRID_Y_STEP: equal spacing in both directions
local GRID_Y_STEP = 48

local function tex(parent, layer, r,g,b,a)
  local t=parent:CreateTexture(nil,layer or "BACKGROUND")
  t:SetColorTexture(FLT.SkinC(r,g,b,a))
  return t
end

local function button(parent,text,w,h)
  local b=CreateFrame("Button",nil,parent)
  b:SetSize(w,h)
  local bg=tex(b,"BACKGROUND",0.075,0.065,0.05,0.98); bg:SetAllPoints(); b.bg=bg
  local hi=tex(b,"HIGHLIGHT",0.78,0.55,0.18,0.18); hi:SetAllPoints(); b:SetHighlightTexture(hi)
  for _,p in ipairs({{"TOPLEFT","TOPRIGHT",nil,1},{"BOTTOMLEFT","BOTTOMRIGHT",nil,1},{"TOPLEFT","BOTTOMLEFT",1,nil},{"TOPRIGHT","BOTTOMRIGHT",1,nil}}) do
    local e=tex(b,"ARTWORK",0.72,0.50,0.16,0.70)
    e:SetPoint(p[1],b,p[1],0,0); e:SetPoint(p[2],b,p[2],0,0)
    if p[3] then e:SetWidth(p[3]) end; if p[4] then e:SetHeight(p[4]) end
  end
  local fs=FLT.NewFS(b, nil,"OVERLAY","GameFontNormalSmall")
  fs:SetPoint("CENTER"); fs:SetText(text); fs:SetTextColor(FLT.SkinC(0.96,0.78,0.34)); b:SetFontString(fs); b.label=fs
  return b
end

local function setButtonSelected(b, selected)
  if not b then return end
  if selected then
    b.bg:SetColorTexture(FLT.SkinC(0.20,0.13,0.035,0.98))
    b.label:SetTextColor(FLT.SkinC(1.0,0.84,0.24))
  else
    b.bg:SetColorTexture(FLT.SkinC(0.075,0.065,0.05,0.98))
    b.label:SetTextColor(FLT.SkinC(0.86,0.76,0.56))
  end
end

local function spellName(spellID)
  if not spellID then return nil end
  if C_Spell and C_Spell.GetSpellName then
    local ok,v=pcall(C_Spell.GetSpellName,spellID); if ok then return v end
  end
  if GetSpellInfo then return GetSpellInfo(spellID) end
end
local function spellIcon(spellID)
  if not spellID then return nil end
  if C_Spell and C_Spell.GetSpellTexture then
    local ok,v=pcall(C_Spell.GetSpellTexture,spellID); if ok then return v end
  end
  if GetSpellTexture then return GetSpellTexture(spellID) end
end

local function classByID(id)
  for _,c in ipairs(CLASSES) do if c.id==id then return c end end
end

local function getSpecID(classID)
  if not GetSpecializationInfoForClassID then return nil end
  local ok,specID=pcall(GetSpecializationInfoForClassID,classID,1)
  if ok then return specID end
end

local function apiReady()
  return C_ClassTalents and C_ClassTalents.InitializeViewLoadout and C_ClassTalents.ViewLoadout
    and C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo
    and Constants and Constants.TraitConsts and Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID
end

local function stateFor(classID)
  local store=(OneForAllDB and OneForAllDB.talentPlans) or plannerState
  store[classID]=store[classID] or { ranks={}, entries={} }
  return store[classID]
end

-- Two saved presets per class (OneForAllDB.talentPresets[classID][1|2]).
-- The planner edits a working copy (stateFor); "Save Preset" stores it in the
-- open preset, choosing a preset loads it into the working copy.
local presetFallback = {}
local function presetsFor(classID)
  local store = presetFallback
  if type(OneForAllDB)=="table" then
    OneForAllDB.talentPresets = OneForAllDB.talentPresets or {}
    store = OneForAllDB.talentPresets
  end
  if not store[classID] then
    -- first use: the existing plan becomes preset 1
    local st=stateFor(classID)
    local p1={ranks={},entries={}}
    for k,v in pairs(st.ranks) do p1.ranks[k]=v end
    for k,v in pairs(st.entries) do p1.entries[k]=v end
    store[classID]={ p1, {ranks={},entries={}} }
  end
  return store[classID]
end
local function copyInto(dst, src)
  wipe(dst.ranks); wipe(dst.entries)
  for k,v in pairs(src.ranks or {}) do dst.ranks[k]=v end
  for k,v in pairs(src.entries or {}) do dst.entries[k]=v end
end
local function samePlan(a, b)
  for k,v in pairs(a.ranks) do if (b.ranks[k] or 0)~=v then return false end end
  for k,v in pairs(b.ranks) do if (a.ranks[k] or 0)~=v then return false end end
  return true
end

local function buildEntries(st)
  local entries={}
  for nodeID,rank in pairs(st.ranks) do
    if rank and rank>0 then
      entries[#entries+1]={nodeID=nodeID,ranksPurchased=rank,selectionEntryID=st.entries[nodeID]}
    end
  end
  return entries
end

local function spent(st)
  local n=0
  for _,rank in pairs(st.ranks) do n=n+(rank or 0) end
  return n
end

local function applyPreview(specID, st)
  if not apiReady() then return nil,"Talent preview APIs are not available on this client." end
  local ok,err=pcall(C_ClassTalents.InitializeViewLoadout,specID,60)
  if not ok then return nil,tostring(err) end
  local entries=buildEntries(st)
  local ok2,res=pcall(C_ClassTalents.ViewLoadout,entries)
  if not ok2 or res==false then return nil,not ok2 and tostring(res) or "The preview loadout was rejected." end
  return Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID
end

local function entryDetails(configID, nodeInfo, preferredEntry)
  if not nodeInfo then return nil end
  local entryID=preferredEntry
  if not entryID and nodeInfo.activeEntry then
    if type(nodeInfo.activeEntry)=="table" then entryID=nodeInfo.activeEntry.entryID else entryID=nodeInfo.activeEntry end
  end
  if not entryID and nodeInfo.entryIDs then entryID=nodeInfo.entryIDs[1] end
  if not entryID then return nil end
  local ei=C_Traits.GetEntryInfo and C_Traits.GetEntryInfo(configID,entryID)
  local di=ei and ei.definitionID and C_Traits.GetDefinitionInfo and C_Traits.GetDefinitionInfo(ei.definitionID)
  local sid=di and (di.spellID or di.overriddenSpellID)
  local name=(di and di.overrideName) or spellName(sid) or ("Talent "..tostring(entryID))
  local icon=(di and di.overrideIcon) or spellIcon(sid) or "Interface\\Icons\\INV_Misc_QuestionMark"
  return entryID,di,sid,name,icon
end

local function collectNodes(configID)
  local ci=C_Traits.GetConfigInfo(configID)
  if not ci or not ci.treeIDs then return {},{} end
  local treeGroups={}
  local all={}
  for _,treeID in ipairs(ci.treeIDs) do
    local group={treeID=treeID,nodes={}}
    for _,nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
      local ni=C_Traits.GetNodeInfo(configID,nodeID)
      if ni and ni.isVisible~=false and ni.posX and ni.posY then
        local rec={id=nodeID,info=ni,treeID=treeID,subTreeID=ni.subTreeID,x=ni.posX,y=ni.posY}
        group.nodes[#group.nodes+1]=rec; all[#all+1]=rec
      end
    end
    if #group.nodes>0 then treeGroups[#treeGroups+1]=group end
  end
  return treeGroups,all
end

-- Places the client's talent nodes using TalentData.lua. Nodes are matched by
-- spell ID (TalentSpellIDs.lua), falling back to the talent name; each reference talent is used once (some client builds expose
-- duplicate nodes). Returns nil if too few talents match (then the fallback
-- layout in TalentLayoutFallback.lua is used), otherwise the placed nodes and
-- the number of client nodes that had no reference entry.
local function referenceLayout(configID, all, classID, st)
  local data=FLT.TALENT_DATA and FLT.TALENT_DATA[classID]
  if not data then return nil end
  local byName={}
  for _,t in ipairs(data.talents) do byName[string.lower(t[5])]=t end
  local aliases=FLT.TALENT_NAME_ALIASES or {}
  local bySpell=(FLT.TALENT_SPELL_IDS and FLT.TALENT_SPELL_IDS[classID]) or {}
  local placed,seen,unmatched={},{},0
  for _,n in ipairs(all) do
    local _,_,sid,name=entryDetails(configID,n.info,st.entries[n.id])
    -- Spell ID first (language independent), talent name as fallback.
    -- A spell ID whose talent was renamed or removed by a patch falls back to the name.
    local key=sid and bySpell[sid] and string.lower(bySpell[sid])
    if not (key and byName[key]) then
      key=string.lower(name or "")
      key=aliases[key] or key
    end
    local ref=byName[key]
    if ref and not seen[key] then
      seen[key]=true
      placed[#placed+1]={node=n,tree=ref[1],row=ref[2],col=ref[3],maxRanks=ref[4],key=key,req=ref[6] and string.lower(ref[6]) or nil}
    elseif not ref then
      unmatched=unmatched+1
    end
  end
  if #placed < #data.talents*0.6 then return nil end
  return placed,unmatched
end

-- Points spent per talent tree of the active talents { tree1, tree2, tree3 } (Gear Planner Value picks the
-- tree with the most points). Forever: the trait tree of the active config, nodes placed into trees with
-- TalentData.lua like the planner does; older clients: GetTalentTabInfo. nil when nothing can be read.
function FLT.TalentPointsPerTree()
  local _, _, classID = UnitClass("player")
  if classID and C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo then
    local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
    if ok and configID then
      local _, all = collectNodes(configID)
      local placed = referenceLayout(configID, all, classID, { entries = {} })
      if placed then
        local pts = { 0, 0, 0 }
        for _, p in ipairs(placed) do
          local ni = p.node.info
          pts[p.tree] = (pts[p.tree] or 0) + (ni.currentRank or ni.ranksPurchased or 0)
        end
        return pts
      end
    end
  end
  if GetTalentTabInfo then
    local pts = {}
    for i = 1, 3 do
      local ok, a, b, c, d, e = pcall(GetTalentTabInfo, i)
      if not ok then return nil end
      -- Classic Era: name, icon, pointsSpent, file; later clients: id, name, description, icon, pointsSpent
      pts[i] = (type(a) == "string" and tonumber(c)) or tonumber(e) or 0
    end
    return pts
  end
end

-- /ofa talentdump: records node ID, entry ID and spell ID of every talent of
-- all classes (via the same preview API the planner uses) into
-- OneForAllDB.talentDump. Used to make TalentData.lua independent of the
-- client language. Run it once on an English client and send the
-- SavedVariables file (WTF\Account\<name>\SavedVariables\OneForAll.lua).
function FLT:DumpTalents()
  if not apiReady() then return nil,"Talent preview APIs are not available on this client." end
  if type(OneForAllDB)~="table" then return nil,"Saved variables are not loaded yet." end
  local dump={ build=(GetBuildInfo and select(2,GetBuildInfo())) or "?", locale=GetLocale and GetLocale() or "?", time=time and time() or 0, classes={} }
  local classes,talents=0,0
  for classID,data in pairs(FLT.TALENT_DATA or {}) do
    local specID=getSpecID(classID)
    local configID=specID and applyPreview(specID,{ranks={},entries={}})
    if configID then
      local groups=collectNodes(configID)
      local rows={}
      for ti,group in ipairs(groups) do
        for _,n in ipairs(group.nodes) do
          local entryID,di,sid,name=entryDetails(configID,n.info)
          local entryIDs=n.info.entryIDs and table.concat(n.info.entryIDs,",") or ""
          rows[#rows+1]=string.format("%d;%d;%s;%s;%s;%s;%s;%s;%s", ti, n.id, tostring(entryID or ""), entryIDs,
            tostring(sid or ""), tostring(di and di.definitionID or ""), tostring(n.info.maxRanks or ""),
            string.format("%.0f,%.0f", n.x or 0, n.y or 0), name or "")
          talents=talents+1
        end
      end
      dump.classes[data.token or tostring(classID)]={ classID=classID, specID=specID, rows=rows }
      classes=classes+1
    end
  end
  OneForAllDB.talentDump=dump
  -- The planner re-applies its own preview the next time it is shown.
  return classes,talents
end

function FLT:CreateTalentPlannerPanel(parent)
  local panel=CreateFrame("Frame",nil,parent)
  local UI=FLT.UI
  UI.PlacePanel(panel,parent)
  panel:Hide()

  -- Title band (mirrored banner art, so the mage is visible on the right).
  UI.TitleBand(panel,{ emblem=ASSET_ROOT.."emblem_talents", art=ASSET_ROOT.."talents_banner",
    title="Talent Trees", subtitle="Plan talents for every class. See your next spells to learn.", fadeRight=60 })

  local selectedClass=select(3,UnitClass("player"))
  selectedClass=tonumber(selectedClass)
  if not classByID(selectedClass) then selectedClass=8 end
  local classButtons={}
  local nodeButtons={}
  local treePanels={}
  local statusText
  local summary={}
  local currentConfig,currentSpec
  local currentMeta,currentPrereqs={},{}
  local treeOffset={0,0,0}

  local function gridLeft(treeIndex,col)
    return GRID_X0+(col-1)*GRID_X_STEP+(treeOffset[treeIndex] or 0)
  end

  -- Class selector lives in a narrow left rail. This frees a full horizontal
  -- row and gives the talent trees more vertical room.
  local rail=CreateFrame("Frame",nil,panel); rail:SetPoint("TOPLEFT",8,-74); rail:SetPoint("BOTTOMLEFT",8,4); rail:SetWidth(122)
  UI.FramedPanel(rail)
  -- top of the rail: spellbook -> what the class trainer teaches next
  do
    local sb=CreateFrame("Button",nil,rail); sb:SetSize(40,40); sb:SetPoint("TOPLEFT",12,-10)
    local ic=sb:CreateTexture(nil,"ARTWORK"); ic:SetPoint("TOPLEFT",3,-3); ic:SetPoint("BOTTOMRIGHT",-3,3)
    ic:SetTexture("Interface\\Icons\\INV_Misc_Book_09"); ic:SetTexCoord(0.08,0.92,0.08,0.92)
    local fr=sb:CreateTexture(nil,"OVERLAY"); fr:SetAllPoints(); FLT.SetTex(fr,ASSET_ROOT.."talent_frame"); fr:SetVertexColor(FLT.SkinC(0.66,0.48,0.16,0.98))
    local hl=sb:CreateTexture(nil,"HIGHLIGHT"); FLT.SetTex(hl,ASSET_ROOT.."talent_frame"); hl:SetAllPoints(); hl:SetVertexColor(FLT.SkinC(1,0.86,0.40,0.85)); hl:SetBlendMode("ADD")
    sb:SetHighlightTexture(hl)
    local l=UI.SmallCaps(rail,"Trainer",12,9,UI.HEAD_GOLD); l:SetPoint("LEFT",sb,"RIGHT",8,7)
    local l2=FLT.NewFS(rail,nil,"OVERLAY","GameFontDisableSmall"); l2:SetPoint("TOPLEFT",l,"BOTTOMLEFT",0,-2); l2:SetText("Next spells")
    sb:SetScript("OnClick",function() if FLT.ToggleTrainerSpells then FLT.ToggleTrainerSpells(selectedClass) end end)
    sb:SetScript("OnEnter",function(self)
      GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:AddLine("What can I learn next?",FLT.SkinC(1,0.82,0))
      GameTooltip:AddLine("Spells and ranks a class trainer teaches. For your own class: everything you do not know yet, up to level 60.",1,1,1,true)
      GameTooltip:Show()
    end)
    sb:SetScript("OnLeave",function() GameTooltip:Hide() end)
    local d0=rail:CreateTexture(nil,"ARTWORK"); FLT.SetTex(d0, ASSET_ROOT.."divider_ornate"); d0:SetHeight(12)
    d0:SetPoint("TOPLEFT",4,-54); d0:SetPoint("TOPRIGHT",-4,-54)
  end
  local chooser=UI.SmallCaps(rail,"Class",13,10,UI.HEAD_GOLD); chooser:SetPoint("TOPLEFT",12,-70)
  local cy=-88
  for _,c in ipairs(CLASSES) do
    local b=UI.NavButton(rail,c.name,104,24,"Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"); b:SetPoint("TOPLEFT",9,cy); cy=cy-26; classButtons[c.id]=b
    -- class crest from the character-creation atlas (slightly cropped)
    local tc=type(CLASS_ICON_TCOORDS)=="table" and CLASS_ICON_TCOORDS[c.token]
    if tc and b.icon then
      local dx,dy=(tc[2]-tc[1])*0.06,(tc[4]-tc[3])*0.06
      b.icon:SetTexCoord(tc[1]+dx,tc[2]-dx,tc[3]+dy,tc[4]-dy)
    elseif b.icon then b.icon:Hide(); b._label:SetPoint("LEFT",10,0) end
    local classID=c.id
    b:SetScript("OnClick",function() selectedClass=classID; panel:RefreshTalentPlanner() end)
  end

  local header=CreateFrame("Frame",nil,panel)
  header:SetPoint("TOPLEFT",138,-74); header:SetSize(858,28)
  local hbg=tex(header,"BACKGROUND",0.075,0.062,0.040,0.96); hbg:SetPoint("TOPLEFT",2,-2); hbg:SetPoint("BOTTOMRIGHT",-2,2)
  UI.OrnateFrame(header,header,10,1,"OVERLAY",1)
  local headerStatOrder={"level","available","spent","remaining"}
  local function stat(label)
    local f=FLT.NewFS(header, nil,"OVERLAY","GameFontHighlightSmall")
    f:SetJustifyH("CENTER")
    f:SetText(label)
    return f
  end
  summary.level=stat("Level: 9"); summary.available=stat("Available: 51"); summary.spent=stat("Spent: 0"); summary.remaining=stat("Remaining: 51")

  local function layoutHeaderStats()
    local w=header:GetWidth() or 0
    if w<=0 then return end
    local margin=72
    local span=math.max(0,w-(margin*2))
    for i,key in ipairs(headerStatOrder) do
      local f=summary[key]
      if f then
        local x=margin+((i-1)*(span/3))-(w/2)
        f:ClearAllPoints()
        f:SetPoint("CENTER",header,"CENTER",x,0)
      end
    end
  end

  -- Presets: 1 / 2, Save Preset, Reset (both with a confirmation)
  local activePreset={} -- classID -> 1|2 (starts at 1 every session)
  local function presetIndex() return activePreset[selectedClass] or 1 end
  local div=rail:CreateTexture(nil,"ARTWORK"); FLT.SetTex(div, ASSET_ROOT.."divider_ornate"); div:SetHeight(12)
  div:SetPoint("TOPLEFT",4,cy-2); div:SetPoint("TOPRIGHT",-4,cy-2)
  local plabel=UI.SmallCaps(rail,"Preset",13,10,UI.HEAD_GOLD); plabel:SetPoint("TOPLEFT",12,cy-18)
  local presetButtons={}
  for i=1,2 do
    local b=UI.GoldButton(rail,tostring(i),49,24,nil,13); b:SetPoint("TOPLEFT",9+(i-1)*55,cy-34); presetButtons[i]=b
    b:SetScript("OnClick",function()
      activePreset[selectedClass]=i
      copyInto(stateFor(selectedClass),presetsFor(selectedClass)[i])
      panel:RefreshTalentPlanner()
    end)
  end
  local unsaved=FLT.NewFS(rail, nil,"OVERLAY","GameFontDisableSmall"); unsaved:SetPoint("TOPLEFT",12,cy-62); unsaved:SetWidth(100); unsaved:SetJustifyH("LEFT")
  local save=UI.GoldButton(rail,"Save Preset",104,24,nil,12); save:SetPoint("TOPLEFT",9,cy-76)
  save:SetScript("OnClick",function()
    local i=presetIndex(); local class=classByID(selectedClass)
    UI.Confirm(string.format("Save the current talents as %sPreset %d|r for %s?\nThe saved preset is replaced.",FLT.SkinHex("ffd200"),i,class and class.name or ""),function()
      copyInto(presetsFor(selectedClass)[i],stateFor(selectedClass)); panel:RefreshTalentPlanner()
    end,"Save")
  end)
  local reset=UI.GoldButton(rail,"Reset",104,24,nil,12); reset:SetPoint("TOPLEFT",9,cy-104)
  reset:SetScript("OnClick",function()
    local i=presetIndex(); local class=classByID(selectedClass)
    UI.Confirm(string.format("Reset %sPreset %d|r for %s?\nAll talent points of this preset are removed.",FLT.SkinHex("ffd200"),i,class and class.name or ""),function()
      local st=stateFor(selectedClass); wipe(st.ranks); wipe(st.entries)
      copyInto(presetsFor(selectedClass)[i],st); panel:RefreshTalentPlanner()
    end,"Reset")
  end)
  local function updatePresetButtons()
    local i=presetIndex()
    for k,b in ipairs(presetButtons) do b:SetActive(k==i) end
    local dirty=not samePlan(stateFor(selectedClass),presetsFor(selectedClass)[i])
    unsaved:SetText(dirty and "|cffff9933Unsaved changes|r" or "")
  end
  -- first look at a class this session: show its preset 1
  local loaded={}
  local function ensureLoaded()
    if loaded[selectedClass] then return end
    loaded[selectedClass]=true
    activePreset[selectedClass]=1
    copyInto(stateFor(selectedClass),presetsFor(selectedClass)[1])
  end

  local treeTop=-108
  for i=1,3 do
    local p=CreateFrame("Frame",nil,panel); treePanels[i]=p
    p:SetPoint("TOPLEFT",138+(i-1)*288,treeTop); p:SetSize(282,382)
    UI.FramedPanel(p)
    local title=FLT.NewFS(p, nil,"OVERLAY","GameFontNormalLarge"); title:SetPoint("TOP",0,-9); title:SetText("Tree "..i); title:SetTextColor(FLT.SkinC(1,0.82,0.20)); p.title=title
    local pts=FLT.NewFS(p, nil,"OVERLAY","GameFontNormalSmall"); pts:SetPoint("TOP",0,-31); pts:SetText("0 points"); pts:SetTextColor(FLT.SkinC(0.72,0.72,0.72)); p.points=pts
  end

  local footer=CreateFrame("Frame",nil,panel)
  footer:SetPoint("BOTTOMLEFT",138,4); footer:SetSize(858,32)
  local fbg=tex(footer,"BACKGROUND",0.075,0.062,0.040,0.96); fbg:SetPoint("TOPLEFT",2,-2); fbg:SetPoint("BOTTOMRIGHT",-2,2)
  UI.OrnateFrame(footer,footer,10,1,"OVERLAY",1)
  statusText=FLT.NewFS(footer, nil,"OVERLAY","GameFontHighlightSmall")
  statusText:SetPoint("CENTER",-25,0); statusText:SetWidth(560); statusText:SetJustifyH("CENTER")
  local clickHint=FLT.NewFS(footer, nil,"OVERLAY","GameFontHighlightSmall")
  clickHint:SetPoint("RIGHT",-12,0); clickHint:SetJustifyH("RIGHT"); clickHint:SetText("Left + / Right -")

  local function ensureNodeButton(index)
    if nodeButtons[index] then return nodeButtons[index] end
    local b=CreateFrame("Button",nil,panel); nodeButtons[index]=b; b:SetSize(TALENT_BUTTON_SIZE,TALENT_BUTTON_SIZE); b:RegisterForClicks("LeftButtonUp","RightButtonUp")

    -- Talent button: soft glow (learned), icon with slightly rounded corners,
    -- a thin metal frame tinted by state, rank in a small dark badge.
    local glow=b:CreateTexture(nil,"BACKGROUND")
    FLT.SetTex(glow, ASSET_ROOT.."talent_glow"); glow:SetPoint("TOPLEFT",-9,9); glow:SetPoint("BOTTOMRIGHT",9,-9)
    glow:SetVertexColor(FLT.SkinC(1,0.78,0.30,0.75)); glow:Hide(); b.glow=glow
    local shadow=b:CreateTexture(nil,"BACKGROUND",nil,1); shadow:SetColorTexture(FLT.SkinC(0,0,0,0.55))
    shadow:SetPoint("TOPLEFT",2,-2); shadow:SetPoint("BOTTOMRIGHT",-2,2); b.shadow=shadow

    local ic=b:CreateTexture(nil,"ARTWORK")
    ic:SetPoint("TOPLEFT",TALENT_ICON_INSET,-TALENT_ICON_INSET)
    ic:SetPoint("BOTTOMRIGHT",-TALENT_ICON_INSET,TALENT_ICON_INSET)
    ic:SetTexCoord(0.07,0.93,0.07,0.93); b.icon=ic
    if b.CreateMaskTexture and ic.AddMaskTexture then
      local mask=b:CreateMaskTexture()
      FLT.SetTex(mask, ASSET_ROOT.."talent_icon_mask2","CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
      mask:SetAllPoints(ic)
      ic:AddMaskTexture(mask)
      b.iconMask=mask
    end

    local slot=b:CreateTexture(nil,"OVERLAY")
    FLT.SetTex(slot, ASSET_ROOT.."talent_frame"); slot:SetAllPoints()
    slot:SetVertexColor(FLT.SkinC(0.66,0.48,0.16,0.98)); b.slot=slot

    local hi=b:CreateTexture(nil,"HIGHLIGHT")
    FLT.SetTex(hi, ASSET_ROOT.."talent_frame"); hi:SetAllPoints(); hi:SetVertexColor(FLT.SkinC(1,0.86,0.40,0.85)); hi:SetBlendMode("ADD")
    b:SetHighlightTexture(hi)

    -- Rank badge on its own child frame: the button's HIGHLIGHT layer (gold frame
    -- on mouseover) is drawn above all of the button's own layers and would
    -- otherwise cover the "2/3". The child frame takes no mouse input.
    local top=CreateFrame("Frame",nil,b); top:SetAllPoints(); top:SetFrameLevel(b:GetFrameLevel()+2); b.rankHolder=top
    local badge=top:CreateTexture(nil,"OVERLAY",nil,2); FLT.SetTex(badge, ASSET_ROOT.."rr_fill"); badge:SetVertexColor(FLT.SkinC(0.04,0.035,0.03,0.92))
    badge:SetSize(24,13); badge:SetPoint("BOTTOMRIGHT",3,-3); b.badge=badge
    local rank=FLT.NewFS(top, nil,"OVERLAY","NumberFontNormalSmall"); rank:SetDrawLayer("OVERLAY",3); rank:SetPoint("CENTER",badge,"CENTER",0,0); rank:SetShadowOffset(1,-1); b.rank=rank
    return b
  end

  -- Connection lines are pooled per tree panel: textures are reused on every
  -- refresh instead of creating new ones for each click.
  local linePools={{},{},{}}
  local lineUsed={0,0,0}
  local function clearConnections()
    for i=1,3 do
      for _,t in ipairs(linePools[i]) do t:Hide() end
      lineUsed[i]=0
    end
  end
  local function lineTexture(treeIndex)
    lineUsed[treeIndex]=lineUsed[treeIndex]+1
    local t=linePools[treeIndex][lineUsed[treeIndex]]
    if not t then
      t=treePanels[treeIndex]:CreateTexture(nil,"ARTWORK")
      linePools[treeIndex][lineUsed[treeIndex]]=t
    end
    t:ClearAllPoints(); t:Show()
    return t
  end

  local function addConnectionSegment(treeIndex, x, y, w, h, active)
    local parent=treePanels[treeIndex]
    local shadow=lineTexture(treeIndex)
    shadow:SetColorTexture(FLT.SkinC(0,0,0,0.45))
    shadow:SetPoint("TOPLEFT",parent,"TOPLEFT",x+1,-(y-1)); shadow:SetSize(math.max(2,w),math.max(2,h))

    local t=lineTexture(treeIndex)
    t:SetColorTexture(FLT.SkinC(active and 0.92 or 0.42,active and 0.72 or 0.36,0.24,active and 0.95 or 0.72))
    t:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y); t:SetSize(math.max(2,w),math.max(2,h))
  end

  local function pointsAbove(st, treeIndex, row)
    local n=0
    for nodeID,rank in pairs(st.ranks) do
      local m=currentMeta[nodeID]
      if m and m.tree==treeIndex and m.row<row then n=n+(rank or 0) end
    end
    return n
  end

  local function requirementsMet(meta, st)
    if not meta then return false,"Talent data unavailable" end
    local required=math.max(0,(meta.row-1)*5)
    local above=pointsAbove(st,meta.tree,meta.row)
    if above<required then
      return false,string.format("Requires %d points in earlier rows of this tree",required)
    end
    for _,parentID in ipairs(currentPrereqs[meta.id] or {}) do
      local pm=currentMeta[parentID]
      local have=st.ranks[parentID] or 0
      local need=(pm and pm.maxRanks) or 1
      if have<need then
        return false,string.format("Requires %s %d/%d",(pm and pm.name) or "prerequisite talent",have,need)
      end
    end
    return true
  end

  local function stateIsValid(st, treeIndex)
    for nodeID,rank in pairs(st.ranks) do
      local m=currentMeta[nodeID]
      if rank and rank>0 and m and (not treeIndex or m.tree==treeIndex) then
        local ok=requirementsMet(m,st)
        if not ok then return false end
      end
    end
    return true
  end

  local function buildPrerequisitesAndConnections(st, useReference)
    wipe(currentPrereqs)
    clearConnections()
    local pairsSeen={}
    local pairsList={}
    local function addPair(parent,child)
      if not parent or not child or parent==child or parent.tree~=child.tree then return end
      local key=parent.id..":"..child.id
      if pairsSeen[key] then return end
      pairsSeen[key]=true
      currentPrereqs[child.id]=currentPrereqs[child.id] or {}
      currentPrereqs[child.id][#currentPrereqs[child.id]+1]=parent.id
      pairsList[#pairsList+1]={parent=parent,child=child}
    end

    if useReference then
      -- Prerequisites come from TalentData.lua (matched by talent name).
      local byKey={}
      for _,m in pairs(currentMeta) do if m.key then byKey[m.key]=m end end
      for _,m in pairs(currentMeta) do
        if m.req then addPair(byKey[m.req],m) end
      end
    else
      -- Fallback: use the live client talent graph.
      for _,m in pairs(currentMeta) do
        for _,edge in ipairs((m.node.info and m.node.info.visibleEdges) or {}) do
          local target=edge.targetNode or edge.targetNodeID or edge.targetNodeId or edge.nodeID
          if type(target)=="table" then target=target.nodeID or target.ID or target.id end
          local other=currentMeta[target]
          if other then
            if m.row<other.row then addPair(m,other) elseif other.row<m.row then addPair(other,m) end
          end
        end
      end
    end

    for _,pair in ipairs(pairsList) do
      local a,b=pair.parent,pair.child
      local active=(st.ranks[a.id] or 0)>=(a.maxRanks or 1)
      local x1=gridLeft(a.tree,a.col)+(TALENT_BUTTON_SIZE/2)
      local x2=gridLeft(b.tree,b.col)+(TALENT_BUTTON_SIZE/2)
      if a.row==b.row then
        -- Same row (e.g. Paladin Divine Precision <- Holy Shock): horizontal
        -- line between the two buttons at mid height.
        local ymid=GRID_Y0+(a.row-1)*GRID_Y_STEP+(TALENT_BUTTON_SIZE/2)-1
        local left=math.min(x1,x2)+(TALENT_BUTTON_SIZE/2)
        local right=math.max(x1,x2)-(TALENT_BUTTON_SIZE/2)
        if right>left then addConnectionSegment(a.tree,left,ymid,right-left,3,active) end
      else
        local y1=GRID_Y0+(a.row-1)*GRID_Y_STEP+TALENT_BUTTON_SIZE
        local y2=GRID_Y0+(b.row-1)*GRID_Y_STEP
        if y2>y1 then addConnectionSegment(a.tree,x1-1,y1,3,y2-y1,active) end
        if x1~=x2 then
          local minx=math.min(x1,x2); addConnectionSegment(a.tree,minx,y2-1,math.abs(x2-x1),3,active)
        end
      end
    end
  end

  local function refreshPreview()
    for _,b in ipairs(nodeButtons) do b:Hide(); b.node=nil end
    clearConnections()
    wipe(currentMeta); wipe(currentPrereqs)
    local class=classByID(selectedClass); if not class then return end
    for cid,b in pairs(classButtons) do b:SetActive(cid==selectedClass) end
    local st=stateFor(selectedClass)
    local s=spent(st)
    summary.level:SetText("Level: "..tostring(math.min(60,9+s)))
    summary.spent:SetText("Spent: "..s); summary.remaining:SetText("Remaining: "..math.max(0,51-s))
    for i=1,3 do treePanels[i].title:SetText(class.trees[i] or ("Tree "..i)); treePanels[i].points:SetText("0 points") end

    currentSpec=getSpecID(selectedClass)
    if not currentSpec then statusText:SetText("No Forever talent specialization data was found for "..class.name.."."); return end
    local configID,err=applyPreview(currentSpec,st)
    if not configID then configID,err=applyPreview(currentSpec,{ranks={},entries={}}) end
    currentConfig=configID
    if not configID then statusText:SetText("Talent planner unavailable: "..tostring(err or "unknown client API error")); return end

    local groups,all=collectNodes(configID)
    local currentNodes={}
    for _,n in ipairs(all) do currentNodes[n.id]=n end
    -- Saved plans may reference nodes that no longer exist after a client
    -- update; drop them so point totals stay correct.
    if #all>0 then
      for nodeID in pairs(st.ranks) do
        if not currentNodes[nodeID] then st.ranks[nodeID]=nil; st.entries[nodeID]=nil end
      end
    end
    local placed,unmatched=referenceLayout(configID,all,selectedClass,st)
    local useReference=placed~=nil
    if not placed then
      placed=FLT.TalentFallbackLayout(groups,all,class,configID)
      unmatched=nil
    end

    -- Trees that only use three of the four columns are centered.
    local maxCol={0,0,0}
    for _,p in ipairs(placed) do maxCol[p.tree]=math.max(maxCol[p.tree],p.col) end
    for i=1,3 do treeOffset[i]=(maxCol[i]>0 and maxCol[i]<=3) and math.floor(GRID_X_STEP/2) or 0 end

    local perTree={0,0,0}
    for slot,p in ipairs(placed) do
      local n=p.node
      local b=ensureNodeButton(slot); b.node=n
      local ni=n.info
      local entryID,_,sid,name,icon=entryDetails(configID,ni,st.entries[n.id])
      st.entries[n.id]=entryID or st.entries[n.id]
      b.name=name; b.entryID=entryID; b.spellID=sid; b.maxRanks=ni.maxRanks or p.maxRanks or 1
      currentMeta[n.id]={id=n.id,tree=p.tree,row=p.row,col=p.col,node=n,button=b,maxRanks=b.maxRanks,name=name,entryID=entryID,key=p.key,req=p.req}
      perTree[p.tree]=perTree[p.tree]+(st.ranks[n.id] or 0)
      FLT.SetTex(b.icon, icon)
      b:ClearAllPoints(); b:SetParent(treePanels[p.tree]); b:SetPoint("TOPLEFT",gridLeft(p.tree,p.col),-GRID_Y0-(p.row-1)*GRID_Y_STEP); b:Show()
    end

    buildPrerequisitesAndConnections(st,useReference)

    -- Second pass: appearance, interaction and tooltips now use the complete graph.
    for nodeID,m in pairs(currentMeta) do
      local b=m.button; local rank=st.ranks[nodeID] or 0
      local unlocked=requirementsMet(m,st)
      b.rank:SetText(string.format("%d/%d",rank,b.maxRanks or 1))
      local er,eg,eb
      if rank>0 then
        b.icon:SetVertexColor(FLT.SkinC(1,1,1,1)); er,eg,eb=0.98,0.76,0.24
      elseif unlocked then
        b.icon:SetVertexColor(FLT.SkinC(0.95,0.95,0.95,1)); er,eg,eb=0.66,0.48,0.16
      else
        b.icon:SetVertexColor(FLT.SkinC(0.40,0.40,0.40,0.82)); er,eg,eb=0.40,0.29,0.10
      end
      if b.slot then b.slot:SetVertexColor(FLT.SkinC(er,eg,eb,0.98)) end
      if b.glow then b.glow:SetShown(rank>0) end
      if rank>0 and rank>=(b.maxRanks or 1) then b.rank:SetTextColor(FLT.SkinC(1,0.82,0.25))
      elseif rank>0 then b.rank:SetTextColor(FLT.SkinC(0.45,1,0.45))
      else b.rank:SetTextColor(FLT.SkinC(unlocked and 0.92 or 0.6, unlocked and 0.92 or 0.6, unlocked and 0.92 or 0.6)) end

      b:SetScript("OnClick",function(self,mouse)
        local pstate=stateFor(selectedClass); local old=pstate.ranks[nodeID] or 0
        if mouse=="LeftButton" then
          if spent(pstate)>=51 or old>=(self.maxRanks or 1) then return end
          local ok,reason=requirementsMet(m,pstate)
          if not ok then statusText:SetText(reason or "Requirements not yet met"); return end
          pstate.ranks[nodeID]=old+1; pstate.entries[nodeID]=self.entryID
        elseif mouse=="RightButton" then
          if old<=0 then return end
          pstate.ranks[nodeID]=(old-1)>0 and (old-1) or nil
          if not stateIsValid(pstate,m.tree) then
            pstate.ranks[nodeID]=old
            statusText:SetText("Remove dependent/lower-row talent points first.")
            return
          end
        end
        panel:RefreshTalentPlanner() -- re-applies the preview loadout
      end)

      b:SetScript("OnEnter",function(self)
        if not currentConfig then return end
        local pstate=stateFor(selectedClass); local r=pstate.ranks[nodeID] or 0
        local ok,reason=requirementsMet(m,pstate)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:ClearLines(); GameTooltip:AddLine(self.name or "Talent",1,0.82,0)
        GameTooltip:AddLine(string.format("Rank %d/%d",r,self.maxRanks or 1),0.90,0.90,0.90)
        local showRank=math.max(1,math.min(self.maxRanks or 1,r>0 and r or 1))
        if self.entryID and C_Traits.GetTraitDescription then
          local okd,desc=pcall(C_Traits.GetTraitDescription,self.entryID,showRank)
          if okd and desc and desc~="" then
            GameTooltip:AddLine(desc,0.92,0.92,0.92,true)
          elseif not self.descRetry then
            -- The description is empty until the client has loaded the
            -- talent's spell data. Load it and redraw while still hovered.
            self.descRetry=true
            local btn=self
            local function redraw()
              if GameTooltip:GetOwner()==btn and (not btn.IsMouseOver or btn:IsMouseOver()) then
                local handler=btn:GetScript("OnEnter"); if handler then handler(btn) end
              end
            end
            if btn.spellID and Spell and Spell.CreateFromSpellID then
              local okS,spellObj=pcall(Spell.CreateFromSpellID,Spell,btn.spellID)
              if okS and spellObj and spellObj.ContinueOnSpellLoad then pcall(spellObj.ContinueOnSpellLoad,spellObj,redraw) end
            elseif btn.spellID and C_Spell and C_Spell.RequestLoadSpellData then
              pcall(C_Spell.RequestLoadSpellData,btn.spellID)
            end
            -- Fallback for clients that report the load before the text is ready.
            if C_Timer and C_Timer.After then C_Timer.After(0.15,redraw) end
          end
          if r<(self.maxRanks or 1) then
            local ok2,nextDesc=pcall(C_Traits.GetTraitDescription,self.entryID,r+1)
            if ok2 and nextDesc and nextDesc~="" and nextDesc~=desc then GameTooltip:AddLine("Next rank:",0.65,0.85,1); GameTooltip:AddLine(nextDesc,0.75,0.82,0.92,true) end
          end
        end
        if not ok and r==0 then GameTooltip:AddLine(reason or "Requirements not yet met",1,0.30,0.25) end
        GameTooltip:AddLine(" "); GameTooltip:AddLine("Left-click: add point",0.72,0.72,0.72); GameTooltip:AddLine("Right-click: remove point",0.72,0.72,0.72)
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave",function(self) self.descRetry=nil; GameTooltip:Hide() end)
    end

    for i=1,3 do treePanels[i].points:SetText((perTree[i] or 0).." points") end
    s=spent(st)
    summary.level:SetText("Level: "..tostring(math.min(60,9+s)))
    summary.spent:SetText("Spent: "..s); summary.remaining:SetText("Remaining: "..math.max(0,51-s))
    local line=string.format("%s: %d   |   %s: %d   |   %s: %d",class.trees[1],perTree[1] or 0,class.trees[2],perTree[2] or 0,class.trees[3],perTree[3] or 0)
    if not useReference then
      line=line.."   |cffff8040(estimated layout: client talents did not match the reference data)|r"
    elseif unmatched and unmatched>0 then
      line=line..string.format("   |cffff8040(%d client talent%s not in reference data)|r",unmatched,unmatched==1 and "" or "s")
    end
    statusText:SetText(line)
    updatePresetButtons()
  end

  function panel:RefreshTalentPlanner()
    ensureLoaded()
    layoutHeaderStats()
    refreshPreview()
    updatePresetButtons()
  end
  panel:SetScript("OnShow",function()
    ensureLoaded()
    layoutHeaderStats()
    refreshPreview()
    updatePresetButtons()
  end)
  panel:SetScript("OnSizeChanged",function()
    layoutHeaderStats()
  end)
  return panel
end

FLT.UI.RegisterPanel({ key="talents", label="Talent Trees", order=5, tabWidth=132,
  create=function(parent) return FLT:CreateTalentPlannerPanel(parent) end })

