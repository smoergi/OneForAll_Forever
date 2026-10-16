local _, FLT = ...
local UI = FLT.UI

-- "What can I learn next": spells and ranks a class trainer teaches. For your
-- own class everything you do not know yet up to level 60 (own race only);
-- any other class can be picked at the top and shows its whole list.
-- Opened from the spellbook button in the Talent Trees tab.
-- Spell list: Data/TrainerSpells.lua (generated from the Forever client data).
-- Known spells are read from your spellbook. Training costs are not in the
-- client data: they are remembered when you open a class trainer
-- (OneForAllDB.trainerCosts[class]["Name|rank"] = { c = copper, l = level }).
-- Spells taught by a quest instead of the trainer get a yellow "!".

local CLASS_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local QUEST_TEX = "Interface\\GossipFrame\\AvailableQuestIcon"
local CLASSES = {
  { id = 1, token = "WARRIOR", name = "Warrior" }, { id = 2, token = "PALADIN", name = "Paladin" },
  { id = 3, token = "HUNTER", name = "Hunter" },   { id = 4, token = "ROGUE", name = "Rogue" },
  { id = 5, token = "PRIEST", name = "Priest" },   { id = 7, token = "SHAMAN", name = "Shaman" },
  { id = 8, token = "MAGE", name = "Mage" },       { id = 9, token = "WARLOCK", name = "Warlock" },
  { id = 11, token = "DRUID", name = "Druid" },
}
local function classByID(id) for _, c in ipairs(CLASSES) do if c.id == id then return c end end end

local _, myToken, myClass = UnitClass("player")
myClass = tonumber(myClass)
local viewClass = myClass

local function classIconCoords(token)
  local tc = type(CLASS_ICON_TCOORDS) == "table" and CLASS_ICON_TCOORDS[token]
  if not tc then return nil end
  local dx, dy = (tc[2] - tc[1]) * 0.06, (tc[4] - tc[3]) * 0.06
  return tc[1] + dx, tc[2] - dx, tc[3] + dy, tc[4] - dy
end

local function costsDB(token)
  if type(OneForAllDB) ~= "table" or not token then return {} end
  OneForAllDB.trainerCosts = OneForAllDB.trainerCosts or {}
  OneForAllDB.trainerCosts[token] = OneForAllDB.trainerCosts[token] or {}
  return OneForAllDB.trainerCosts[token]
end

local function rankOf(text)
  return tonumber(type(text) == "string" and text:match("(%d+)") or nil) or 0
end

-- spellbook: highest known rank per spell name
local function knownSpells()
  local known = {}
  local book = BOOKTYPE_SPELL or "spell"
  if GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
    for tab = 1, GetNumSpellTabs() do
      local _, _, offset, num = GetSpellTabInfo(tab)
      for i = (offset or 0) + 1, (offset or 0) + (num or 0) do
        local name, sub = GetSpellBookItemName(i, book)
        if name then
          local r = rankOf(sub)
          if (known[name] or -1) < r then known[name] = r end
        end
      end
    end
  end
  return known
end

local function money(c)
  if FLT.QoL and FLT.QoL.Money then return FLT.QoL.Money(c) end
  return tostring(c)
end

-- learn costs (and the real level) while a class trainer of your class is open
-- the spell behind a trainer line, read from a hidden tooltip (names and rank
-- texts are not reliable enough to match our list)
local scanTip
local function serviceSpellID(i)
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "OneForAllTrainerScanTip", nil, "GameTooltipTemplate")
  end
  local id
  pcall(function()
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:SetTrainerService(i)
    id = select(2, scanTip:GetSpell())
    scanTip:Hide()
  end)
  return tonumber(id)
end
local trainerRaw = {}
local function readTrainer()
  if not GetNumTrainerServices or not GetTrainerServiceInfo then return end
  if IsTradeskillTrainer and IsTradeskillTrainer() then return end
  local db = costsDB(myToken)
  trainerRaw = {}
  for i = 1, GetNumTrainerServices() do
    local name, sub, category = GetTrainerServiceInfo(i)
    if name and category ~= "header" then
      local cost = GetTrainerServiceCost and GetTrainerServiceCost(i)
      local lvl = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i)
      local id = serviceSpellID(i)
      local e = {}
      if tonumber(cost) then e.c = cost end
      if tonumber(lvl) and lvl > 0 then e.l = lvl end
      db[name .. "|" .. rankOf(sub)] = e
      if id then db["#" .. id] = e end
      trainerRaw[#trainerRaw + 1] = { name, tostring(sub), tostring(category), tostring(cost), tostring(lvl), tostring(id) }
    end
  end
  if FLT.RefreshTrainerSpells then FLT.RefreshTrainerSpells() end
end

-- /ofa trainer: what the last trainer visit read (for bug reports)
function FLT.PrintTrainerDebug()
  local say = FLT.Msg or print
  if #trainerRaw == 0 then say("Open your class trainer first, then type /ofa trainer again."); return end
  say(#trainerRaw .. " trainer lines read (name | rank text | type | cost | level | spell ID):")
  for i = 1, math.min(12, #trainerRaw) do say("  " .. table.concat(trainerRaw[i], " | ")) end
end

local ev = CreateFrame("Frame")
-- not every event exists in every client (e.g. LEARNED_SPELL_IN_TAB is missing in Forever)
for _, e in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_LEVEL_UP" }) do
  pcall(ev.RegisterEvent, ev, e)
end
local function onEventSafe(_, event)
  if event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then readTrainer()
  elseif FLT.RefreshTrainerSpells then
    if C_Timer and C_Timer.After then C_Timer.After(0.3, FLT.RefreshTrainerSpells) else FLT.RefreshTrainerSpells() end
  end
end
ev:SetScript("OnEvent", function(...) FLT.SafeCall("Trainer", onEventSafe, ...) end)

-- the list: { level, spellID, name, rank, cost or nil, icon, quest, talent }, sorted by level.
-- Own class: only what is not known yet (up to level 60), own race only.
-- Other classes: everything.
local function spellList(cid)
  local c = classByID(cid)
  local list = FLT.TRAINER_SPELLS and FLT.TRAINER_SPELLS[cid] or {}
  local own = cid == myClass
  local known = own and knownSpells() or {}
  local raceID = tonumber((select(3, UnitRace("player"))))
  local raceBit = raceID and 2 ^ (raceID - 1) or 0
  local level = UnitLevel("player") or 1
  local maxLevel = 60
  local db = costsDB(c and c.token)
  local out = {}
  for _, s in ipairs(list) do
    local lvl, id, name, rank, race, talent, icon, quest = s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8]
    local learned = db["#" .. id] or db[name .. "|" .. rank]
    lvl = (learned and learned.l) or lvl
    local show = lvl <= maxLevel
    if own and show then
      local okRace = race == 0 or raceID == nil or (math.floor(race / raceBit) % 2 == 1)
      local have = known[name]
      local isKnown = have and have >= rank
      if not isKnown and IsSpellKnown and pcall(IsSpellKnown, id) and IsSpellKnown(id) then isKnown = true end
      show = okRace and not isKnown and (not talent or have)
    end
    if show then out[#out + 1] = { lvl, id, name, rank, learned and learned.c, icon, quest, talent } end
  end
  table.sort(out, function(a, b)
    if a[1] ~= b[1] then return a[1] < b[1] end
    if a[3] ~= b[3] then return a[3] < b[3] end
    return a[4] < b[4]
  end)
  return out, level, own
end
FLT._trainerMissing = function() return spellList(myClass) end -- test hook

local frame
local ROW_W = 412
local function createFrame()
  local f = CreateFrame("Frame", "OneForAllTrainerSpells", UIParent)
  f:SetSize(470, 600); f:SetPoint("CENTER", 0, 20)
  f:SetFrameStrata("DIALOG"); f:SetToplevel(true); f:EnableMouse(true); f:SetClampedToScreen(true)
  f:SetMovable(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  UI.FramedPanel(f)
  for _, tx in ipairs(UI.OrnateFrame(f, f, 16, 3, "OVERLAY", 4) or {}) do tx:SetVertexColor(FLT.SkinC(1, 1, 1, 1)) end

  -- title: class crest in a gold frame, "Class trainer - Priest", subtitle
  local crestF = CreateFrame("Frame", nil, f); crestF:SetSize(46, 46); crestF:SetPoint("TOPLEFT", 16, -14)
  f.crest = crestF:CreateTexture(nil, "ARTWORK"); f.crest:SetPoint("TOPLEFT", 3, -3); f.crest:SetPoint("BOTTOMRIGHT", -3, 3)
  local cfr = crestF:CreateTexture(nil, "OVERLAY"); cfr:SetAllPoints(); FLT.SetTex(cfr, UI.ASSET_ROOT .. "talent_frame")
  f.title = FLT.NewFS(f, nil, "OVERLAY", "GameFontNormalLarge"); f.title:SetPoint("TOPLEFT", crestF, "TOPRIGHT", 12, -3)
  f.title:SetTextColor(FLT.SkinC(1, 0.82, 0.20))
  do local font, _, flags = f.title:GetFont(); if font then f.title:SetFont(font, 20, flags) end end
  f.sub = FLT.NewFS(f, nil, "OVERLAY", "GameFontHighlight"); f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
  f.sub:SetTextColor(0.85, 0.82, 0.74)
  local close = UI.CloseButton(f); close:SetPoint("TOPRIGHT", -12, -12)

  -- class picker: one crest per class
  f.classButtons = {}
  local x = 16
  for _, c in ipairs(CLASSES) do
    local b = CreateFrame("Button", nil, f); b:SetSize(36, 36); b:SetPoint("TOPLEFT", x, -72); x = x + 40
    local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetPoint("TOPLEFT", 3, -3); ic:SetPoint("BOTTOMRIGHT", -3, 3)
    ic:SetTexture(CLASS_TEX)
    local l, r, tt, bo = classIconCoords(c.token)
    if l then ic:SetTexCoord(l, r, tt, bo) end
    local ring = b:CreateTexture(nil, "OVERLAY"); ring:SetAllPoints(); FLT.SetTex(ring, UI.ASSET_ROOT .. "talent_frame")
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); FLT.SetTex(hl, UI.ASSET_ROOT .. "talent_frame"); hl:SetAllPoints(); hl:SetBlendMode("ADD")
    hl:SetVertexColor(FLT.SkinC(1, 0.86, 0.40, 0.85)); b:SetHighlightTexture(hl)
    b.icon, b.ring = ic, ring
    b:SetScript("OnClick", function() viewClass = c.id; if f.sf then f.sf:SetVerticalScroll(0) end; FLT.RefreshTrainerSpells() end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(c.name, 1, 0.82, 0)
      GameTooltip:AddLine(c.id == myClass and "Your class: what you can learn next" or "All spells this trainer teaches", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.classButtons[c.id] = b
  end
  local dv = f:CreateTexture(nil, "ARTWORK"); FLT.SetTex(dv, UI.ASSET_ROOT .. "divider_ornate"); dv:SetHeight(14)
  dv:SetPoint("TOPLEFT", 12, -114); dv:SetPoint("TOPRIGHT", -12, -114)

  local sf = FLT.SkinBlizz(CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate"))
  sf:SetPoint("TOPLEFT", 14, -132); sf:SetPoint("BOTTOMRIGHT", -32, 62)
  local child = CreateFrame("Frame", nil, sf); child:SetSize(ROW_W, 10); sf:SetScrollChild(child)
  if UI.AutoHideScrollBar then UI.AutoHideScrollBar(sf) end
  f.sf, f.child = sf, child

  -- footer: divider, total on the left, legend on the right
  local fdv = f:CreateTexture(nil, "ARTWORK"); FLT.SetTex(fdv, UI.ASSET_ROOT .. "divider_ornate"); fdv:SetHeight(14)
  fdv:SetPoint("BOTTOMLEFT", 12, 48); fdv:SetPoint("BOTTOMRIGHT", -12, 48)
  f.total = FLT.NewFS(f, nil, "OVERLAY", "GameFontHighlight"); f.total:SetPoint("BOTTOMLEFT", 20, 22)
  f.legend = FLT.NewFS(f, nil, "OVERLAY", "GameFontHighlightSmall"); f.legend:SetPoint("BOTTOMRIGHT", -20, 23); f.legend:SetJustifyH("RIGHT")
  f.legend:SetText("|T" .. QUEST_TEX .. ":14:12|t = Quest     |cff9d9d9d?|r = cost not known yet")
  f.legend:SetTextColor(0.80, 0.77, 0.70)
  local lh = CreateFrame("Frame", nil, f); lh:SetAllPoints(f.legend)
  lh:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("Costs", 1, 0.82, 0)
    GameTooltip:AddLine("Training costs are not part of the game data. They are filled in when you open your class trainer.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  lh:SetScript("OnLeave", function() GameTooltip:Hide() end)

  f.rows, f.heads = {}, {}
  if UISpecialFrames then table.insert(UISpecialFrames, "OneForAllTrainerSpells") end
  f:SetScript("OnShow", function() FLT.RefreshTrainerSpells() end)
  f:Hide()
  return f
end

local ROW_H = 32
local function getRow(f, i)
  local r = f.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, f.child); r:SetSize(ROW_W, ROW_H - 2)
  r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 1, 1, 0.03)
  local hi = r:CreateTexture(nil, "HIGHLIGHT"); hi:SetAllPoints(); hi:SetColorTexture(FLT.SkinC(0.90, 0.66, 0.22, 0.12))
  local iconF = CreateFrame("Frame", nil, r); iconF:SetSize(28, 28); iconF:SetPoint("LEFT", 8, 0)
  r.icon = iconF:CreateTexture(nil, "ARTWORK"); r.icon:SetPoint("TOPLEFT", 2, -2); r.icon:SetPoint("BOTTOMRIGHT", -2, 2); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local ifr = iconF:CreateTexture(nil, "OVERLAY"); ifr:SetAllPoints(); FLT.SetTex(ifr, UI.ASSET_ROOT .. "talent_frame")
  ifr:SetVertexColor(FLT.SkinC(0.66, 0.48, 0.16, 0.98))
  -- yellow "!" on the icon: taught by a quest
  r.quest = iconF:CreateTexture(nil, "OVERLAY", nil, 2); r.quest:SetSize(12, 16); r.quest:SetPoint("BOTTOMRIGHT", 5, -3)
  r.quest:SetTexture(QUEST_TEX)
  r.name = FLT.NewFS(r, nil, "OVERLAY", "GameFontHighlight"); r.name:SetPoint("LEFT", 46, 0); r.name:SetWidth(280); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
  do local font, _, flags = r.name:GetFont(); if font then r.name:SetFont(font, 14, flags) end end
  r.cost = FLT.NewFS(r, nil, "OVERLAY", "GameFontHighlight"); r.cost:SetPoint("RIGHT", -10, 0); r.cost:SetJustifyH("RIGHT")
  r:SetScript("OnEnter", function(self)
    if not self.id then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not pcall(GameTooltip.SetSpellByID, GameTooltip, self.id) then GameTooltip:SetText(self.label or "") end
    if self.questName then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(self.questName == "class quest" and "Learned from a class quest, not at the trainer."
        or ("Learned from the quest " .. self.questName .. ", not at the trainer."), 1, 0.82, 0, true)
    end
    if self.talent then GameTooltip:AddLine("Higher rank of a talent: only when you have the talent.", 0.7, 0.7, 0.7, true) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.rows[i] = r
  return r
end

-- level band: warm gold bar with a thin frame (not collapsible, so no chevron)
local HEAD_H = 30
local function getHead(f, i)
  local h = f.heads[i]
  if h then return h end
  h = CreateFrame("Frame", nil, f.child); h:SetSize(ROW_W, HEAD_H)
  local base = h:CreateTexture(nil, "BACKGROUND"); base:SetPoint("TOPLEFT", 1, -1); base:SetPoint("BOTTOMRIGHT", -1, 1)
  base:SetColorTexture(1, 1, 1, 1)
  -- dark bronze with only a hint of gold (the plain gold looked too heavy)
  local r1, g1, b1 = FLT.SkinC(0.20, 0.15, 0.07)
  local r2, g2, b2 = FLT.SkinC(0.10, 0.08, 0.04)
  if base.SetGradient and CreateColor then
    pcall(base.SetGradient, base, "VERTICAL", CreateColor(r2, g2, b2, 0.92), CreateColor(r1, g1, b1, 0.92))
  else
    base:SetColorTexture(r1, g1, b1, 0.92)
  end
  for _, tx in ipairs(UI.OrnateFrame(h, h, 8, 1, "OVERLAY", 1) or {}) do tx:SetVertexColor(FLT.SkinC(0.70, 0.56, 0.32, 0.85)) end
  h.text = FLT.NewFS(h, nil, "OVERLAY", "GameFontNormalLarge"); h.text:SetPoint("LEFT", 12, 0)
  do local font, _, flags = h.text:GetFont(); if font then h.text:SetFont(font, 15, flags) end end
  h.right = FLT.NewFS(h, nil, "OVERLAY", "GameFontHighlightSmall"); h.right:SetPoint("RIGHT", -12, 0)
  f.heads[i] = h
  return h
end

local function spellIcon(id, fileID)
  if fileID and fileID > 0 then return fileID end
  local tex
  if C_Spell and C_Spell.GetSpellTexture then pcall(function() tex = C_Spell.GetSpellTexture(id) end) end
  if not tex and GetSpellTexture then pcall(function() tex = GetSpellTexture(id) end) end
  if not tex and GetSpellInfo then pcall(function() tex = select(3, GetSpellInfo(id)) end) end
  return tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function FLT.RefreshTrainerSpells()
  local f = frame
  if not f or not f:IsShown() then return end
  local c = classByID(viewClass) or classByID(myClass) or CLASSES[1]
  viewClass = c.id
  local list, level, own = spellList(c.id)
  local l, r, tt, b = classIconCoords(c.token)
  f.crest:SetTexture(CLASS_TEX); if l then f.crest:SetTexCoord(l, r, tt, b) end
  f.title:SetText("Class trainer - " .. c.name)
  if own then f.sub:SetText("Spells and ranks you have not learned yet, up to level 60")
  else f.sub:SetText("Everything this trainer teaches, level 1 to 60") end
  for id, btn in pairs(f.classButtons) do
    local on = id == c.id
    btn.icon:SetAlpha(on and 1 or 0.6); FLT.Desat(btn.icon, not on)
    if on then btn.ring:SetVertexColor(FLT.SkinC(1, 0.84, 0.36, 1)) else btn.ring:SetVertexColor(FLT.SkinC(0.55, 0.42, 0.22, 1)) end
  end
  for _, row in ipairs(f.rows) do row:Hide() end
  for _, h in ipairs(f.heads) do h:Hide() end
  local y, ri, hi = 0, 0, 0
  local lastGroup, stripe = nil, 0
  local nowCost, nowCount, nowUnknown = 0, 0, 0
  for _, s in ipairs(list) do
    local lvl, id, name, rank, cost, icon, quest, talent = s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8]
    local group = (own and lvl <= level) and "now" or lvl
    if group ~= lastGroup then
      lastGroup = group
      hi = hi + 1
      if hi > 1 then y = y - 6 end
      local h = getHead(f, hi)
      h:ClearAllPoints(); h:SetPoint("TOPLEFT", 0, y); y = y - HEAD_H - 2
      if group == "now" then
        h.text:SetText("Available now"); h.text:SetTextColor(0.45, 1.00, 0.50)
      else
        h.text:SetText("Level " .. lvl); h.text:SetTextColor(FLT.SkinC(1, 0.84, 0.30))
      end
      h.right:SetText("")
      h:Show()
      stripe = 0
    end
    ri = ri + 1; stripe = stripe + 1
    local row = getRow(f, ri)
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, y); y = y - ROW_H
    row.bg:SetAlpha(stripe % 2 == 1 and 1 or 0)
    row.id, row.label, row.questName, row.talent = id, name, quest, talent
    row.name:SetText(name .. (rank > 0 and ("   |cff9d9d9dRank " .. rank .. "|r") or "") .. (talent and "  |cff9d9d9d(talent)|r" or ""))
    row.icon:SetTexture(spellIcon(id, icon))
    row.quest:SetShown(quest and true or false)
    if group == "now" or not own then row.name:SetTextColor(1, 1, 1) else row.name:SetTextColor(0.80, 0.78, 0.72) end
    if quest then row.cost:SetText("|cffffd200Quest|r")
    else row.cost:SetText(cost and money(cost) or "|cff9d9d9d?|r") end
    row:Show()
    if group == "now" and not quest then
      nowCount = nowCount + 1
      if cost then nowCost = nowCost + cost else nowUnknown = nowUnknown + 1 end
    end
  end
  if #list == 0 then
    local h = getHead(f, 1); h:ClearAllPoints(); h:SetPoint("TOPLEFT", 0, 0)
    h.text:SetText("Nothing left to learn"); h.text:SetTextColor(0.75, 0.75, 0.75); h.right:SetText(""); h:Show()
    y = -HEAD_H
  end
  f.child:SetHeight(math.max(10, -y + 4))
  if not own then
    f.total:SetText(#list .. " spells and ranks")
  elseif nowCount > 0 then
    f.total:SetText(string.format("Available now: %d  |  Cost: %s%s", nowCount, money(nowCost), nowUnknown > 0 and " + ?" or ""))
  else
    f.total:SetText("Nothing to learn at the trainer right now")
  end
end

-- classID: class to show (the class picked in the talent planner); default your own
function FLT.ToggleTrainerSpells(classID)
  if not frame then frame = createFrame() end
  if frame:IsShown() and (not classID or classID == viewClass) then frame:Hide(); return end
  viewClass = (classID and classByID(classID)) and classID or myClass
  if frame:IsShown() then FLT.RefreshTrainerSpells() else frame:Show(); frame:Raise() end
end
