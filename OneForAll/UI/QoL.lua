local _, FLT = ...
local UI = FLT.UI

-- Quality of Life tab: one switch per feature (defaults in QoL.lua DEFAULTS).
-- Logic lives in QoL.lua (FLT.QoL).

local unpack = unpack or table.unpack
local GOLD = UI.GOLD
local openDropDown -- below

-- Yellow "!" (tooltip "New") next to options added since the last live release.
-- Kept for all versions of a minor line (5.7.0 ... 5.7.x); emptied when the next minor line
-- (5.8.0) starts (TODO.md "Neu-Markierungen").
local NEW_TAGS = { classBright = "5.7.0", spellbookTrainer = "5.7.0" } -- 5.6.x marks removed when 5.7.0 started (user 22.10.)
-- placed left of the checkbox (or of the label when there is none), user 16.10.
local function newTag(parent, anchor, key, dx)
  if not NEW_TAGS[key] then return end
  local m = UI.NewMark(parent, "New in OneForAll " .. NEW_TAGS[key] .. ".")
  m:SetPoint("RIGHT", anchor, "LEFT", dx or -2, 0)
  return m
end

-- Shared drop-down list (UI.OpenDropDown in Widgets.lua)
openDropDown = function(...) return UI.OpenDropDown(...) end


-- Preview popup: a framed picture that shows what a feature looks like in game.
-- previews[key] = { tex, width, height (shown size), texcoord bottom }
local PREVIEWS = {
  questSparkles = { title = "Quest loot sparkles", tex = "preview_sparkles", w = 300, h = 300, t = 1 },
  bagsFull = { title = "Bags full helper", tex = "preview_bagsfull", w = 560, h = 183, t = 167 / 256 },
  questXP = { title = "Quest XP on the experience bar", tex = "preview_questxp", w = 640, h = 119, t = 190 / 256 },
  mmCollect = { title = "Collect minimap buttons", tex = "preview_collector", w = 384, h = 164, t = 219 / 256 },
}
local previewFrame
local function showPreview(key)
  local pv = PREVIEWS[key]; if not pv then return end
  if not previewFrame then
    local f = CreateFrame("Frame", "OneForAllPreviewFrame", UIParent)
    f:SetFrameStrata("DIALOG"); f:SetToplevel(true); f:EnableMouse(true); f:SetClampedToScreen(true)
    f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    UI.FramedPanel(f)
    f.title = FLT.NewFS(f, nil, "OVERLAY", "GameFontNormalLarge"); f.title:SetPoint("TOPLEFT", 16, -12); f.title:SetTextColor(FLT.SkinC(1, 0.82, 0.20))
    local close = UI.CloseButton(f); close:SetPoint("TOPRIGHT", -10, -10)
    f.pic = f:CreateTexture(nil, "ARTWORK"); f.pic:SetPoint("TOPLEFT", 16, -40)
    f.picFrame = CreateFrame("Frame", nil, f); f.picFrame:SetAllPoints(f.pic)
    UI.OrnateFrame(f.picFrame, f.picFrame, 10, 2, "OVERLAY", 1)
    f.note = FLT.NewFS(f, nil, "OVERLAY", "GameFontDisableSmall"); f.note:SetPoint("BOTTOMLEFT", 16, 10)
    f.note:SetText("Example from the game. Click and drag to move, Escape to close.")
    if UISpecialFrames then table.insert(UISpecialFrames, "OneForAllPreviewFrame") end
    previewFrame = f
  end
  local f = previewFrame
  f.title:SetText(pv.title)
  FLT.SetTex(f.pic, UI.ASSET_ROOT .. pv.tex); f.pic:SetTexCoord(0, 1, 0, pv.t)
  f.pic:SetSize(pv.w, pv.h)
  f:SetSize(math.max(pv.w + 32, 360), pv.h + 74)
  f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  f:Show(); f:Raise()
end

-- "Never suggested" list of the bags full helper: one row per item with an X to
-- take it off the list again, plus "Remove all". Opens below its button.
local neverMenu
local NEVER_ROWS = 10
local function itemLook(id)
  local name, quality, icon
  pcall(function()
    local info = { (C_Item and C_Item.GetItemInfo or GetItemInfo)(id) }
    name, quality, icon = info[1], info[3], info[10]
  end)
  if not icon then pcall(function() icon = (C_Item and C_Item.GetItemIconByID or GetItemIcon)(id) end) end
  if not name then pcall(function() if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end end) end
  return name, quality, icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function showNeverList(owner, onChange)
  local Q = FLT.QoL
  if not neverMenu then
    local catcher = CreateFrame("Button", nil, UIParent); catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG"); catcher:SetFrameLevel(1); catcher:RegisterForClicks("AnyUp"); catcher:Hide()
    local m = CreateFrame("Frame", nil, UIParent); m:SetFrameStrata("FULLSCREEN_DIALOG"); m:SetFrameLevel(20)
    m:EnableMouse(true); m:EnableMouseWheel(true); m:Hide(); m:SetWidth(300)
    UI.FramedPanel(m)
    catcher:SetScript("OnClick", function() m:Hide() end)
    m:SetScript("OnHide", function() catcher:Hide() end)
    m.catcher, m.rows, m.offset = catcher, {}, 0
    m.title = FLT.NewFS(m, nil, "OVERLAY", "GameFontNormal"); m.title:SetPoint("TOPLEFT", 12, -10); m.title:SetTextColor(FLT.SkinC(1, 0.82, 0.20))
    m.empty = FLT.NewFS(m, nil, "OVERLAY", "GameFontDisableSmall"); m.empty:SetPoint("TOPLEFT", 12, -32); m.empty:SetWidth(276); m.empty:SetJustifyH("LEFT")
    m.empty:SetText("Nothing on the list. In the bags full helper, the X button puts an item here so it is never suggested again.")
    m.more = FLT.NewFS(m, nil, "OVERLAY", "GameFontDisableSmall")
    m.clear = UI.GoldButton(m, "Remove all", 110, 22, nil, 11); m.clear:SetPoint("BOTTOMRIGHT", -10, 10)
    m.more:SetPoint("BOTTOMLEFT", 12, 16)
    for i = 1, NEVER_ROWS do
      local r = CreateFrame("Frame", nil, m); r:SetSize(280, 22); r:SetPoint("TOPLEFT", 10, -30 - (i - 1) * 24)
      r:EnableMouse(true)
      local hi = r:CreateTexture(nil, "BACKGROUND"); hi:SetAllPoints(); hi:SetColorTexture(FLT.SkinC(0.90, 0.66, 0.22, 0.12)); hi:Hide()
      r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 2, 0); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      r.text = FLT.NewFS(r, nil, "OVERLAY", "GameFontHighlight"); r.text:SetPoint("LEFT", 26, 0); r.text:SetWidth(222); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
      r.x = CreateFrame("Button", nil, r); r.x:SetSize(16, 16); r.x:SetPoint("RIGHT", -4, 0)
      r.x:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up"); r.x:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
      r.x:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Remove from the list"); GameTooltip:AddLine("The bags full helper may suggest this item again.", 1, 1, 1, true); GameTooltip:Show() end)
      r.x:SetScript("OnLeave", function() GameTooltip:Hide() end)
      r:SetScript("OnEnter", function(self)
        hi:Show()
        if self.id then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); pcall(GameTooltip.SetItemByID, GameTooltip, self.id); GameTooltip:Show() end
      end)
      r:SetScript("OnLeave", function() hi:Hide(); GameTooltip:Hide() end)
      m.rows[i] = r
    end
    m:SetScript("OnMouseWheel", function(self, delta)
      local n = #(self.ids or {})
      self.offset = math.max(0, math.min(math.max(0, n - NEVER_ROWS), self.offset - delta))
      self.fill()
    end)
    neverMenu = m
  end
  local m = neverMenu
  if m:IsShown() and m.owner == owner then m:Hide(); return end
  local retried = false
  m.fill = function()
    local ids = Q.GetNeverItems(); m.ids = ids
    m.offset = math.max(0, math.min(m.offset, #ids - NEVER_ROWS))
    m.title:SetText("Never suggested  |  " .. #ids .. (#ids == 1 and " item" or " items"))
    m.empty:SetShown(#ids == 0)
    local missing = false
    for i, r in ipairs(m.rows) do
      local id = ids[i + m.offset]
      if id then
        local name, quality, icon = itemLook(id)
        if not name then missing = true end
        r.id = id
        r.icon:SetTexture(icon)
        r.text:SetText(name or ("Item " .. id))
        local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        if c then r.text:SetTextColor(c.r, c.g, c.b) else r.text:SetTextColor(0.92, 0.90, 0.84) end
        r.x:SetScript("OnClick", function() Q.RemoveNever(id); m.fill(); if onChange then onChange() end end)
        r:Show()
      else
        r.id = nil; r:Hide()
      end
    end
    local shown = math.min(#ids, NEVER_ROWS)
    if #ids > NEVER_ROWS then m.more:SetText("Scroll for more"); m.more:Show() else m.more:Hide() end
    m.clear:SetEnabled(#ids > 0); m.clear:SetLook(#ids > 0)
    m:SetHeight(#ids == 0 and 110 or (30 + shown * 24 + 40))
    if missing and not retried and C_Timer and C_Timer.After then
      retried = true
      C_Timer.After(0.6, function() if m:IsShown() then m.fill() end end)
    end
  end
  m.clear:SetScript("OnClick", function()
    m:Hide()
    UI.Confirm("Remove all items from the\n\"never suggest\" list?", function() Q.ClearNever(); if onChange then onChange() end end, "Remove all")
  end)
  m.offset = 0
  m.fill()
  m:ClearAllPoints(); m:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
  m.owner = owner
  m.catcher:Show(); m:Show()
end

-- Layout (user 22.10.): a fixed list of groups on the left like Armory and Professions, the options
-- of one group on the right (one per row: switch, name, short description, controls on the right),
-- a search over all options. Opens on Interface.
local CHILD_W = 754          -- scroll child inside the right frame (body 798 - margins - scroll bar)
local ROW_W = CHILD_W - 8
local function createQoLPanel(parent)
  local Q = FLT.QoL
  local panel = CreateFrame("Frame", nil, parent)
  UI.PlacePanel(panel, parent)
  UI.TitleBand(panel, { emblem = UI.ASSET_ROOT .. "emblem_qol", art = UI.ASSET_ROOT .. "qol_banner",
    title = "Quality of Life", subtitle = "Small helpers for everyday play. Switch on what you like.", fadeRight = 200 })

  local nav = CreateFrame("Frame", nil, panel)
  nav:SetPoint("TOPLEFT", 8, -74); nav:SetSize(180, 481) -- fixed like the other tabs' side panels; a bit wider for "Popups & Alerts"
  UI.FramedPanel(nav)
  local body = CreateFrame("Frame", nil, panel)
  body:SetPoint("TOPLEFT", 198, -74); body:SetPoint("BOTTOMRIGHT", -8, 4)
  UI.FramedPanel(body)

  -- header of the right side: icon, group name, one line about it, search
  local hIcon = body:CreateTexture(nil, "ARTWORK"); hIcon:SetSize(30, 30); hIcon:SetPoint("TOPLEFT", 16, -12)
  hIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  if hIcon.AddMaskTexture and body.CreateMaskTexture then
    local m = body:CreateMaskTexture(); FLT.SetTex(m, UI.ASSET_ROOT .. "talent_icon_mask2", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE"); m:SetAllPoints(hIcon); hIcon:AddMaskTexture(m)
  end
  local hTitle = FLT.NewFS(body, nil, "OVERLAY", "GameFontNormalLarge"); hTitle:SetPoint("TOPLEFT", 56, -12); hTitle:SetTextColor(FLT.SkinC(unpack(GOLD)))
  local hSub = FLT.NewFS(body, nil, "OVERLAY", "GameFontHighlightSmall"); hSub:SetPoint("TOPLEFT", 56, -32); hSub:SetTextColor(FLT.SkinC(0.84, 0.81, 0.74))
  local line = UI.makeTexture(body, "ARTWORK", 0.72, 0.50, 0.12, 0.45); line:SetPoint("TOPLEFT", 12, -54); line:SetPoint("TOPRIGHT", -12, -54); line:SetHeight(1)

  local sf = FLT.SkinBlizz(CreateFrame("ScrollFrame", nil, body, "UIPanelScrollFrameTemplate"))
  sf:SetPoint("TOPLEFT", 10, -60); sf:SetPoint("BOTTOMRIGHT", -28, 8)
  local child = CreateFrame("Frame", nil, sf); child:SetSize(CHILD_W, 10); sf:SetScrollChild(child)
  UI.PlaceScrollBar(sf)
  local empty = FLT.NewFS(child, nil, "OVERLAY", "GameFontDisable"); empty:SetPoint("TOPLEFT", 12, -12); empty:SetText("No setting matches your search."); empty:Hide()

  local refreshers, cats, current, search = {}, {}, nil, ""
  local layout, updateCounts -- below

  local function hint(widget, title, text)
    widget:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(title, FLT.SkinC(1, 0.82, 0))
      if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
      GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
  end

  -- nav = shorter name for the button on the left (when the full one touches the count)
  local function category(key, label, icon, desc, nav)
    local c = { key = key, label = label, icon = icon, desc = desc, nav = nav, groups = {}, checks = {} }
    c.title = UI.SectionTitle(child, label, 8, 0, -8); c.title:Hide(); c.title.divider:Hide() -- heading in search results
    cats[#cats + 1] = c
    return c
  end
  local function group(cat, title)
    local g = { cat = cat, rows = {} }
    g.title = UI.SectionTitle(child, title, 8, 0, -8); g.title:Hide(); g.title.divider:Hide()
    g.name = title
    cat.groups[#cat.groups + 1] = g
    return g
  end

  -- one option row: name and a short grey line below; tip = the longer text in the tooltip
  local function row(g, label, desc, tip, indent)
    local r = CreateFrame("Button", nil, child); r:SetSize(ROW_W, 40); r:Hide()
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(FLT.SkinC(0.90, 0.66, 0.22, 0.06))
    r.indent = indent or 0
    r.label = FLT.NewFS(r, nil, "OVERLAY", "GameFontHighlight"); r.label:SetPoint("TOPLEFT", 42 + r.indent, -5); r.label:SetText(label)
    r.desc = FLT.NewFS(r, nil, "OVERLAY", "GameFontDisableSmall"); r.desc:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -3)
    r.desc:SetJustifyH("LEFT"); r.desc:SetWordWrap(false); r.desc:SetText(desc or "")
    r.rightW = 0
    r.find = (label .. " " .. (desc or "") .. " " .. (tip or "") .. " " .. g.name .. " " .. g.cat.label):lower()
    if tip then hint(r, label, tip) end
    r.name, r.tip = label, tip
    g.rows[#g.rows + 1] = r
    return r
  end
  -- controls sit on the right of the row, right to left
  local function place(r, w, gap)
    w:ClearAllPoints(); w:SetPoint("RIGHT", r, "RIGHT", -10 - r.rightW, 0)
    r.rightW = r.rightW + w:GetWidth() + (gap or 6)
  end
  local function button(r, text, w, tip, onClick)
    local b = UI.GoldButton(r, text, w, 22, nil, 11); place(r, b)
    b:SetScript("OnClick", onClick)
    if tip then hint(b, text, tip) end
    return b
  end
  local function dropButton(r, w)
    local b = UI.GoldButton(r, "", w or 128, 22, nil, 11); place(r, b)
    local arrow = b:CreateTexture(nil, "OVERLAY"); arrow:SetSize(12, 12); arrow:SetPoint("RIGHT", -8, 0)
    FLT.SetTex(arrow, UI.ASSET_ROOT .. "chevron"); arrow:SetTexCoord(0, 0.5, 0, 1)
    return b, arrow
  end

  -- switch in front of the row; get/set default to Q.Get/Q.Set(key); clicking the row toggles it too
  local function switch(r, g, key, get, set, onChange)
    local cb = FLT.SkinBlizz(CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate"))
    cb:SetSize(24, 24); cb:SetPoint("LEFT", 12 + r.indent, 0)
    get = get or function() return Q.Get(key) and true or false end
    set = set or function(v) Q.Set(key, v) end
    cb:SetScript("OnClick", function(b) set(b:GetChecked() and true or false); if onChange then onChange() end; updateCounts() end)
    r:SetScript("OnClick", function() cb:Click() end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(get()) end
    if r.tip then hint(cb, r.name, r.tip) end
    g.cat.checks[#g.cat.checks + 1] = get
    if key then
      if newTag(r, cb, key, 4) then g.cat.new = true end
      if PREVIEWS[key] then -- small preview button behind the name for features with a picture
        local pb = CreateFrame("Button", nil, r); pb:SetSize(18, 18); pb:SetPoint("LEFT", r.label, "RIGHT", 6, 0)
        local pic = pb:CreateTexture(nil, "ARTWORK"); pic:SetAllPoints(); FLT.SetTex(pic, "Interface\\Icons\\INV_Misc_Spyglass_02"); pic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        pb:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        pb:SetScript("OnClick", function() showPreview(key) end)
        hint(pb, "Show preview", "A picture of how it looks in the game.")
      end
    end
    r.cb = cb
    return cb
  end
  local function check(g, label, desc, tip, key, indent, get, set)
    local r = row(g, label, desc, tip, indent)
    switch(r, g, key, get, set)
    return r
  end
  -- drop-down on the right; onKey: optional switch in front, the drop-down is greyed out while it is off
  local function choice(g, label, desc, tip, key, options, onKey, indent)
    local r = row(g, label, desc, tip, indent)
    local b, arrow = dropButton(r)
    local function show()
      local cur, text = Q.Get(key), options[1].label
      for _, o in ipairs(options) do if o.key == cur then text = o.label end end
      b:SetLabel(text)
      if onKey then
        local on = Q.Get(onKey) and true or false
        b:SetLook(on); b:SetEnabled(on); arrow:SetAlpha(on and 1 or 0.35)
      end
    end
    b:SetScript("OnClick", function(self) openDropDown(self, options, Q.Get(key), function(v) Q.Set(key, v); show() end) end)
    if tip then hint(b, label, tip) end
    if onKey then switch(r, g, onKey, nil, nil, show) else newTag(r, r.label, key) end
    refreshers[#refreshers + 1] = show
    return r
  end

  ---------------------------------------------------------------------------------------------------
  -- INTERFACE (first, the tab opens here; user 22.10.)
  local c = category("iface", "Interface", "Interface\\Icons\\INV_Misc_Gear_01", "Camera, bags, chat and other helpers for the game's interface.")
  local g = group(c, "General")
  check(g, "Farther camera zoom", "Lets you zoom the camera out further.", nil, "cameraZoom")
  check(g, "Free bag slots on the backpack", "Shows the number of free slots on your backpack.", "Counts all normal bags (quivers, ammo and profession bags are not counted).", "bagSlots")
  g = group(c, "Windows & chat")
  do
    local r = check(g, "Move Blizzard windows", "Drag windows like the character or quest log window anywhere.", "Drag windows such as the character, merchant or quest log window with the left mouse button. Positions are remembered.", "moveWindows")
    button(r, "Reset", 60, "Moved Blizzard windows go back to their default place.", function() Q.ResetWindowPositions() end)
  end
  do -- chat font size: -, value, +
    local r = row(g, "Chat font size", "The same font size for every chat window.", "Go below 10 to switch it off (then the game's own setting is kept).")
    local function step(d)
      local v = tonumber(Q.Get("chatFont"))
      if not v then v = 14 else v = v + d end
      if v < 10 then v = nil elseif v > 24 then v = 24 end
      Q.Set("chatFont", v); r.show()
    end
    button(r, "+", 26, nil, function() step(1) end)
    local val = FLT.NewFS(r, nil, "OVERLAY", "GameFontNormal"); val:SetWidth(46); val:SetJustifyH("CENTER"); val:SetHeight(20); place(r, val, 4)
    button(r, "-", 26, nil, function() step(-1) end)
    r.show = function() local v = tonumber(Q.Get("chatFont")); val:SetText(v and tostring(v) or "Off") end
    refreshers[#refreshers + 1] = r.show
  end
  check(g, "Copy chat button", "Adds a button to every chat window to copy its text.", "A small button at the top right of every chat window. It opens the chat text so you can select and copy it (Ctrl+C).", "copyChat")
  g = group(c, "Minimap")
  do
    local r = check(g, "Collect minimap buttons", "Puts the minimap buttons of other addons into one bar.", "The bar opens from a bigger OneForAll button that you can drag anywhere (it is not tied to the minimap). Right-click that button to open OneForAll. Switching this off puts all buttons back on the minimap.", "mmCollect")
    button(r, "Reset", 60, "Puts the minimap button collector back to its default place next to the minimap.", function() if FLT.ResetMinimapCollector then FLT.ResetMinimapCollector() end end)
  end
  choice(g, "Bar opens", "Where the bar opens next to the OneForAll button.", "Automatic: towards the middle of the screen.", "mmDir", Q.MM_DIR_OPTIONS, nil, 24)

  -- LOOT & VENDORS
  c = category("loot", "Loot & Vendors", "Interface\\Icons\\INV_Misc_Bag_10", "Looting, merchants, full bags and the loot feed.")
  g = group(c, "Looting")
  check(g, "Auto loot", "The game's own Auto Loot setting.", "Same as Options > Controls > Auto Loot.", nil, nil,
    function() return Q.GetCVarSwitch("autoLoot") end, function(v) Q.SetCVarSwitch("autoLoot", v) end)
  check(g, "Quicker loot", "Takes everything at once when the game auto loots.", "Instead of item by item.", "quickLoot")
  g = group(c, "Merchants")
  check(g, "Auto repair", "Repairs all gear at merchants that can repair.", nil, "autoRepair")
  check(g, "Sell junk", "Sells all grey items when you open a merchant.", nil, "sellJunk")
  g = group(c, "Full bags")
  check(g, "Bags full helper", "When loot does not fit, offers to destroy the cheapest item.", "Suggests the cheapest item in your bags (value x stack), destroys it and loots with one click. Quest items, library books, recipes, set pieces, profession tools and items without value are never suggested. Items better than grey need a second click. /ofa cheapest shows it any time.", "bagsFull")
  check(g, "Only grey and white items", "The helper only suggests poor and common items.", nil, "bagsLowOnly", 24)
  do -- items the player put on the "never suggest" list
    local r = row(g, "Never suggested", "Items you blocked with the X button in the helper.", "Open the list to allow single items again, or remove all.", 24)
    local b = dropButton(r, 110)
    local function show() local n = #Q.GetNeverItems(); b:SetLabel(n == 1 and "1 item" or (n .. " items")) end
    b:SetScript("OnClick", function(self) showNeverList(self, show) end)
    refreshers[#refreshers + 1] = show
  end
  g = group(c, "Loot feed")
  check(g, "Show loot feed", "Looted items and money float up next to your character.", "Like scrolling combat text.", "lootFeed")
  choice(g, "Minimum quality", "Items below this quality are not shown.", nil, "lootFeedQuality", Q.QUALITY_OPTIONS, nil, 24)
  check(g, "Show money", "Also shows looted money.", nil, "lootFeedMoney", 24)
  do
    local r = row(g, "Position", "Move the feed, show sample entries or put it back.", nil, 24)
    button(r, "Reset", 70, "Puts the loot feed back to its default place right of your character.", function() Q.ResetLootFeed() end)
    button(r, "Test", 70, "Shows a few sample entries.", function() Q.TestLootFeed() end)
    local move = button(r, "Move", 70, "Shows the loot feed area. Drag it where you want it, then click Lock.", nil)
    local function show() move:SetLabel(Q.IsLootFeedUnlocked() and "Lock" or "Move"); move:SetActive(Q.IsLootFeedUnlocked()) end
    move:SetScript("OnClick", function() Q.SetLootFeedUnlocked(not Q.IsLootFeedUnlocked()); show() end)
    refreshers[#refreshers + 1] = show
  end

  -- QUESTS
  c = category("quests", "Quests", "Interface\\Icons\\INV_Misc_Note_01", "Quest givers and quest items in the world.")
  g = group(c, "Quest givers")
  check(g, "Accept quests automatically", "Accepts quests when you talk to a quest giver. Hold Shift to do it by hand.", nil, "autoAccept")
  check(g, "Turn in quests automatically", "Turns in finished quests. Hold Shift to do it by hand.", "If you can choose between rewards, you still pick yourself.", "autoTurnIn")
  g = group(c, "Experience")
  check(g, "Quest XP on the experience bar", "Shows the XP of your finished quests on the experience bar.", "Marks on the experience bar how much XP your finished quests give when you turn them in. The amount is also shown in the bar's tooltip.", "questXP")
  g = group(c, "In the world")
  check(g, "Quest loot sparkles", "Quest items in the world sparkle again.", "The game's loot glow. Changes graphics settings; after switching it off, restart the game.", "questSparkles")

  -- TOOLTIPS
  c = category("tips", "Tooltips", "Interface\\Icons\\INV_Misc_Spyglass_03", "Extra lines in item and unit tooltips.")
  g = group(c, "Items")
  check(g, "Boss drops", "Shows which dungeon boss drops an item.", nil, "bossDrops")
  check(g, "Gear Value", "Upgrade or downgrade in % against what you wear.", "On gear you can use: how much better (green) or worse (red) it is than what you wear, weighted for your talent spec like Armory > Gear Planner. Also a green arrow on upgrades in your bags, the loot roll window and quest rewards, and a gold star for wishlist items (/ofa rolltest shows an example).", "gearValue")
  check(g, "Recipes: who knows it", "Whether you, an alt or a guild member knows a recipe.", nil, "recipeTip")
  check(g, "Compare items only with Shift", "Hold Shift to see your equipped item next to the tooltip.", "Item tooltips no longer show your equipped item next to them automatically.", nil, nil,
    function() return Q.GetCompareShift() end, function(v) Q.SetCompareShift(v) end)
  g = group(c, "Units")
  check(g, "Target of players", "Shows who a player or NPC under your mouse is targeting.", "\"You\" when it is you.", "unitTarget")

  -- SOCIAL
  c = category("social", "Social", "Interface\\Icons\\INV_Letter_15", "Group invites, duels and thanks.")
  g = group(c, "Groups")
  choice(g, "Group invites from", "Accepts group invites from the players you choose.", "Off: OneForAll does nothing with invites.", "inviteMode", Q.WHO_OPTIONS, "inviteOn")
  choice(g, "Keyword invites from", "Invites players who whisper you the keyword.", "Off: OneForAll does nothing with whispers.", "keywordMode", Q.WHO_OPTIONS, "keywordOn")
  do
    local r = row(g, "Keyword", "The word players whisper you to get an invite.", nil, 24)
    local eb = FLT.SkinBlizz(CreateFrame("EditBox", nil, r, "InputBoxTemplate"))
    eb:SetSize(122, 20); eb:SetAutoFocus(false); eb:SetMaxLetters(24); place(r, eb)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:SetText(Q.Get("keyword") or ""); self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", function(self) Q.Set("keyword", self:GetText()) end)
    r:SetScript("OnClick", function() eb:SetFocus() end)
    refreshers[#refreshers + 1] = function() if not eb:HasFocus() then eb:SetText(Q.Get("keyword") or "") end end
  end
  g = group(c, "Duels")
  choice(g, "Allow duels from", "Duel requests from everyone else are declined.", "Off: OneForAll does nothing with duels.", "duelMode", Q.DUEL_OPTIONS, "duelOn")
  g = group(c, "Buffs")
  check(g, "Thank players who buff you", "Sends a /thank to players outside your group who buff you.", "For buffs that last longer than 2 minutes. It comes 1 second later, not in combat, at most once every 5 minutes per player. Your target is not changed. /ofa thanks shows the last buffs.", "thanksBuff")

  -- WORLD MAP
  c = category("map", "World Map", "Interface\\Icons\\INV_Misc_Map_01", "Icons on the world map.")
  g = group(c, "Map Landmarks")
  check(g, "Map Landmarks", "Dungeon entrances, flight masters, zeppelins and ships on the map.", "Your faction and neutral ones. Click an entrance to open that dungeon in OneForAll, Shift-click it for a map pin. Zeppelins, ships and flight masters show where they go and set a map pin on click.", "mapLandmarks")
  check(g, "Dungeon & raid entrances", "Click to open the dungeon in OneForAll.", nil, "lmDungeons", 24)
  check(g, "Flight masters", "Shows where they fly to.", nil, "lmFlight", 24)
  check(g, "Zeppelins & ships", "Shows where they go.", nil, "lmTransport", 24)
  g = group(c, "Dungeons")
  -- moved from Settings (5.6.8, user 22.10.); on by default: only an explicit "off" turns it off
  check(g, "Dungeon map on M", "Inside a dungeon, M opens OneForAll's dungeon map.", "Inside a dungeon that has a map, the world map key (M) opens OneForAll's dungeon map instead of the world map. Press it again to close. Takes effect outside combat.", nil, nil,
    function() return type(OneForAllDB) == "table" and OneForAllDB.dungeonMapKey ~= false end,
    function(v) if type(OneForAllDB) == "table" then OneForAllDB.dungeonMapKey = v and true or false end; if FLT.ApplyDungeonMapKey then FLT.ApplyDungeonMapKey() end end)

  -- UNIT FRAMES
  c = category("frames", "Unit Frames", "Interface\\Icons\\INV_Misc_Head_Human_01", "Colors and bars of the unit and raid frames.")
  g = group(c, "Player, target & party")
  check(g, "Class colors: player, target & party", "Health bars of players in their class color.", "NPCs keep their normal color.", "classColors")
  check(g, "Brighter colors", "Plain bright bars for the class colors.", "The game's health bar texture is dark; with this the class colors use a plain bright bar.", "classBright", 24)
  g = group(c, "Raid frames")
  check(g, "Class colors: raid frames", "The game's own setting.", "Same as Interface > Display Class Colors.", nil, nil,
    function() return Q.GetCVarSwitch("raidClassColor") end, function(v) Q.SetCVarSwitch("raidClassColor", v) end)
  check(g, "Power bars: raid frames", "Mana, rage and energy bars in the raid frames.", "A game setting.", nil, nil,
    function() return Q.GetCVarSwitch("raidPowerBars") end, function(v) Q.SetCVarSwitch("raidPowerBars", v) end)

  -- SPELLS
  c = category("spells", "Spells", "Interface\\Icons\\INV_Misc_Book_11", "Your action bars and the spellbook.")
  g = group(c, "Action bars")
  do
    local LR = FLT.LowRank
    local r = check(g, "Check low spell ranks", "Offers the highest rank for spells on your bars.", "Looks for spells on your action bars that use a lower rank than one you already know, and offers to put the highest rank there. After a trainer visit it waits until you close the trainer window. Macros are not checked.", "lowRank")
    button(r, "Check now", 90, "Checks your action bars right away.", function() if LR then LR.Check("button") end end)
    r = row(g, "Kept ranks", "Ranks you keep on purpose (Keep in the popup).", "Click one to have it reported again.", 24)
    local b = dropButton(r, 110)
    local function show() local n = LR and #LR.GetKept() or 0; b:SetLabel(n == 1 and "1 spell" or (n .. " spells")) end
    b:SetScript("OnClick", function(self)
      if not LR then return end
      local opts = LR.GetKept()
      if #opts == 0 then opts = { { key = "__none", label = "|cff9d9d9dNothing kept|r" } }
      else opts[#opts + 1] = { key = "__all", label = FLT.SkinHex("ffd35a") .. "Remove all|r" } end
      openDropDown(self, opts, nil, function(k)
        if k == "__all" then LR.ClearKept() elseif k ~= "__none" then LR.RemoveKept(k) end
        show()
      end, 260)
    end)
    refreshers[#refreshers + 1] = show
  end
  g = group(c, "Spellbook")
  check(g, "Trainer button in the spellbook", "A book button in the spellbook (P) opens the trainer window.", "Shows the spells and ranks your class trainer teaches that you do not know yet, next to the spellbook.", "spellbookTrainer",
    nil, nil, function(v) Q.Set("spellbookTrainer", v); local psf = rawget(_G, "PlayerSpellsFrame"); local b = type(psf) == "table" and psf.ofaTrainerButton; if b then b:SetShown(v) end end)
  -- POPUPS & ALERTS (moved from Settings, 5.6.8, user 22.10.)
  c = category("alerts", "Popups & Alerts", "Interface\\Icons\\INV_Misc_Bell_01", "Popups that come up on their own while you play.")
  g = group(c, "Popups")
  check(g, "Durability warning", "Warns when your gear drops to 20% durability.", nil, "durability")
  check(g, "Nearby Library Book alerts", "Popup when you are close to a missing library book.", nil, nil, nil,
    function() return FLT.IsNearbyAlertsEnabled and FLT:IsNearbyAlertsEnabled() and true or false end,
    function(v) if FLT.SetNearbyAlertsEnabled then FLT:SetNearbyAlertsEnabled(v) end end)
  check(g, "Pet ability alerts  |cff9d9d9d(Hunter)|r", "Popup when a beast nearby teaches a higher ability rank your pets can learn.", nil, nil, nil,
    function() return FLT.IsPetTeachAlertsEnabled and FLT:IsPetTeachAlertsEnabled() and true or false end,
    function(v) if FLT.SetPetTeachAlertsEnabled then FLT:SetPetTeachAlertsEnabled(v) end end)
  check(g, "Quest share popup in dungeons", "Opens when a group member can still accept one of your dungeon quests.", nil, nil, nil,
    function() return not (type(OneForAllDB) == "table" and type(OneForAllDB.questShare) == "table" and OneForAllDB.questShare.popup == false) end,
    function(v) if type(OneForAllDB) == "table" then OneForAllDB.questShare = OneForAllDB.questShare or {}; OneForAllDB.questShare.popup = v and true or false end end)
  ---------------------------------------------------------------------------------------------------

  -- left: one button per group with "on / switches"
  local navButtons = {}
  local function selectCat(key)
    current = key
    for _, b in ipairs(navButtons) do b:SetActive(b.key == key) end
    layout()
  end
  local searchBox
  for i, cat in ipairs(cats) do
    local b = UI.NavButton(nav, cat.nav or cat.label, 164, 27, cat.icon); b:SetPoint("TOPLEFT", 8, -12 - (i - 1) * 32)
    b.key = cat.key
    b.count = FLT.NewFS(b, nil, "OVERLAY", "GameFontDisableSmall"); b.count:SetPoint("RIGHT", -5, 0)
    do local font, _, flags = b.count:GetFont(); if font then b.count:SetFont(font, 10, flags) end end
    if cat.new then local m = UI.NewMark(b, "New options in this group."); m:SetPoint("RIGHT", b.count, "LEFT", -2, 0) end
    b:SetScript("OnClick", function() if search ~= "" then searchBox:SetText("") end; selectCat(cat.key) end)
    cat.nav = b
    navButtons[i] = b
  end
  updateCounts = function()
    for _, cat in ipairs(cats) do
      local on = 0
      for _, get in ipairs(cat.checks) do if get() then on = on + 1 end end
      cat.nav.count:SetText(on .. "/" .. #cat.checks)
    end
  end

  -- search over all groups (name, description and tooltip text)
  do
    local box = FLT.SkinBlizz(CreateFrame("EditBox", nil, body, "InputBoxTemplate"))
    box:SetSize(210, 20); box:SetPoint("TOPRIGHT", -46, -18); box:SetAutoFocus(false)
    local ph = FLT.NewFS(box, nil, "OVERLAY", "GameFontDisableSmall"); ph:SetPoint("LEFT", 4, 0); ph:SetText("Search all settings...")
    -- X next to the box, not inside (user 22.10.)
    local clear = UI.GoldButton(body, "X", 20, 20, nil, 10); clear:SetPoint("LEFT", box, "RIGHT", 4, 0); clear:Hide()
    clear:SetScript("OnClick", function() box:SetText(""); box:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self)
      search = (self:GetText() or ""):lower(); ph:SetShown(search == ""); clear:SetShown(search ~= "")
      for _, b in ipairs(navButtons) do b:SetActive(search == "" and b.key == current) end
      layout()
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    searchBox = box
  end

  local function heading(t, y)
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", 8, y); t:Show(); t.divider:Show()
    return y - 30
  end
  local function put(r, y)
    if not r.fitted then -- the grey line ends before the controls on the right
      r.desc:SetWidth(ROW_W - 42 - r.indent - r.rightW - 16); r.fitted = true
    end
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 4, y); r:Show()
    return y - 42
  end
  layout = function()
    for _, cat in ipairs(cats) do
      cat.title:Hide(); cat.title.divider:Hide()
      for _, gr in ipairs(cat.groups) do gr.title:Hide(); gr.title.divider:Hide(); for _, r in ipairs(gr.rows) do r:Hide() end end
    end
    local y = -6
    if search == "" then
      local cat
      for _, x in ipairs(cats) do if x.key == current then cat = x end end
      FLT.SetTex(hIcon, cat.icon); hTitle:SetText(cat.label); hSub:SetText(cat.desc)
      for _, gr in ipairs(cat.groups) do
        y = heading(gr.title, y)
        for _, r in ipairs(gr.rows) do y = put(r, y) end
        y = y - 10
      end
      empty:Hide()
    else
      local n = 0
      for _, cat in ipairs(cats) do
        local first = true
        for _, gr in ipairs(cat.groups) do
          for _, r in ipairs(gr.rows) do
            if r.find:find(search, 1, true) then
              if first then y = heading(cat.title, y); first = false end
              y = put(r, y); n = n + 1
            end
          end
        end
        if not first then y = y - 10 end
      end
      FLT.SetTex(hIcon, "Interface\\Icons\\INV_Misc_Spyglass_02"); hTitle:SetText("Search")
      hSub:SetText(n == 1 and "1 setting found in all groups." or (n .. " settings found in all groups."))
      empty:SetShown(n == 0)
    end
    child:SetHeight(-y + 8)
    if sf.SetVerticalScroll then sf:SetVerticalScroll(0) end
  end
  selectCat("iface")

  panel:SetScript("OnShow", function() for _, f in ipairs(refreshers) do f() end; updateCounts() end)
  panel:SetScript("OnHide", function() UI.CloseDropDown(); if neverMenu then neverMenu:Hide() end end)
  panel:Hide()
  return panel
end

UI.RegisterPanel({ key="qol", label="Quality of Life", order=4, tabWidth=140, create=createQoLPanel })
