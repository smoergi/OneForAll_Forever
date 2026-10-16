local _, FLT = ...
local UI = FLT.UI

-- Quality of Life tab: one switch per feature (defaults in QoL.lua DEFAULTS).
-- Logic lives in QoL.lua (FLT.QoL).

local unpack = unpack or table.unpack
local GOLD = UI.GOLD
-- three columns from x 8 to 996, flush with the title band like the other tabs
local COL_W = 320
local COL_X = { 8, 342, 676 }
local openDropDown -- below

-- Yellow "!" (tooltip "New") next to options added since the last live release.
-- Kept for all 5.x versions of a minor line (5.6.0 ... 5.6.x); emptied when the next minor line
-- (5.7.0) starts (TODO.md "Neu-Markierungen").
local NEW_TAGS = { lowRank = "5.6.1", mapLandmarks = "5.6.2", gearValue = "5.6.3" }
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

local function createQoLPanel(parent)
  local Q = FLT.QoL
  local panel = CreateFrame("Frame", nil, parent)
  UI.PlacePanel(panel, parent)
  UI.TitleBand(panel, { emblem = UI.ASSET_ROOT .. "emblem_qol", art = UI.ASSET_ROOT .. "qol_banner",
    title = "Quality of Life", subtitle = "Small helpers for everyday play. Switch on what you like.", fadeRight = 200 })

  -- scrollable page below the title band
  local sf = FLT.SkinBlizz(CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate"))
  sf:SetPoint("TOPLEFT", 0, -70); sf:SetPoint("BOTTOMRIGHT", -8, 4)
  local page = CreateFrame("Frame", nil, sf); page:SetSize(COL_X[3] + COL_W + 4, 10); sf:SetScrollChild(page)
  UI.PlaceScrollBar(sf)

  local refreshers = {}
  local colY = { -4, -4, -4 }

  local function hint(widget, title, text)
    widget:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(title, FLT.SkinC(1, 0.82, 0))
      if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
      GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
  end

  local function section(col, label, icon)
    local box = CreateFrame("Frame", nil, page)
    box:SetPoint("TOPLEFT", COL_X[col], colY[col]); box:SetWidth(COL_W)
    UI.FramedPanel(box)
    local band = UI.makeTexture(box, "BORDER", 0.09, 0.075, 0.05, 0.85); band:SetPoint("TOPLEFT", 3, -3); band:SetPoint("TOPRIGHT", -3, -3); band:SetHeight(28)
    local dv = box:CreateTexture(nil, "ARTWORK"); FLT.SetTex(dv, UI.ASSET_ROOT .. "divider_ornate"); dv:SetHeight(12); dv:SetPoint("TOPLEFT", 4, -25); dv:SetPoint("TOPRIGHT", -4, -25)
    local ic = box:CreateTexture(nil, "OVERLAY"); ic:SetSize(20, 20); ic:SetPoint("TOPLEFT", 10, -6); FLT.SetTex(ic, icon); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if ic.AddMaskTexture and box.CreateMaskTexture then
      local m = box:CreateMaskTexture(); FLT.SetTex(m, UI.ASSET_ROOT .. "talent_icon_mask2", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE"); m:SetAllPoints(ic); ic:AddMaskTexture(m)
    end
    local t = FLT.NewFS(box, nil, "OVERLAY", "GameFontNormal"); t:SetPoint("LEFT", ic, "RIGHT", 8, 0); t:SetText(label); t:SetTextColor(FLT.SkinC(unpack(GOLD)))

    local s = { y = -38 }
    -- switch: get/set default to Q.Get/Q.Set(key)
    function s:check(text, tip, key, x, get, set)
      local cb = FLT.SkinBlizz(CreateFrame("CheckButton", nil, box, "UICheckButtonTemplate"))
      cb:SetSize(24, 24); cb:SetPoint("TOPLEFT", 12 + (x or 0), self.y)
      local l = FLT.NewFS(box, nil, "OVERLAY", "GameFontHighlight"); l:SetPoint("LEFT", cb, "RIGHT", 4, 1); l:SetText(text)
      get = get or function() return Q.Get(key) and true or false end
      set = set or function(v) Q.Set(key, v) end
      cb:SetScript("OnClick", function(b) set(b:GetChecked() and true or false) end)
      if tip then hint(cb, text, tip) end
      refreshers[#refreshers + 1] = function() cb:SetChecked(get()) end
      -- small preview button behind the label for features with a picture
      if key and PREVIEWS[key] then
        local pb = CreateFrame("Button", nil, box); pb:SetSize(18, 18); pb:SetPoint("LEFT", l, "RIGHT", 6, 0)
        local pic = pb:CreateTexture(nil, "ARTWORK"); pic:SetAllPoints(); FLT.SetTex(pic, "Interface\\Icons\\INV_Misc_Spyglass_02"); pic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        pb:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        pb:SetScript("OnClick", function() showPreview(key) end)
        hint(pb, "Show preview", "A picture of how it looks in the game.")
      end
      if key then newTag(box, cb, key, 4) end -- the checkbox art has a transparent margin
      self.y = self.y - 28
      return cb, l
    end
    -- choice: label left, a button on the right that cycles through options
    -- choice: label left, a small drop-down on the right
    -- onKey: optional switch in front; while it is off the drop-down is greyed out
    function s:choice(text, tip, key, options, onKey)
      local l = FLT.NewFS(box, nil, "OVERLAY", "GameFontHighlight")
      local cb
      if onKey then
        cb = FLT.SkinBlizz(CreateFrame("CheckButton", nil, box, "UICheckButtonTemplate"))
        cb:SetSize(24, 24); cb:SetPoint("TOPLEFT", 12, self.y)
        l:SetPoint("LEFT", cb, "RIGHT", 4, 1)
      else
        l:SetPoint("TOPLEFT", 16, self.y - 5)
      end
      l:SetText(text)
      newTag(box, cb or l, key, cb and 4 or -2)
      local b = UI.GoldButton(box, "", 128, 22, nil, 11); b:SetPoint("TOPRIGHT", -12, self.y - 1)
      local arrow = b:CreateTexture(nil, "OVERLAY"); arrow:SetSize(12, 12); arrow:SetPoint("RIGHT", -8, 0)
      FLT.SetTex(arrow, UI.ASSET_ROOT .. "chevron"); arrow:SetTexCoord(0, 0.5, 0, 1)
      local function label()
        local cur = Q.Get(key)
        for _, o in ipairs(options) do if o.key == cur then return o.label end end
        return options[1].label
      end
      local function show()
        b:SetLabel(label())
        if onKey then
          local on = Q.Get(onKey) and true or false
          cb:SetChecked(on); b:SetLook(on); b:SetEnabled(on)
          if on then arrow:SetAlpha(1) else arrow:SetAlpha(0.35) end
        end
      end
      b:SetScript("OnClick", function(self)
        openDropDown(self, options, Q.Get(key), function(v) Q.Set(key, v); show() end)
      end)
      if cb then
        cb:SetScript("OnClick", function(c) Q.Set(onKey, c:GetChecked() and true or false); show() end)
        if tip then hint(cb, text, tip) end
      end
      if tip then hint(b, text, tip) end
      refreshers[#refreshers + 1] = show
      self.y = self.y - 30
      return b
    end
    function s:text(str)
      local d = FLT.NewFS(box, nil, "OVERLAY", "GameFontDisableSmall")
      d:SetPoint("TOPLEFT", 16, self.y - 2); d:SetWidth(COL_W - 32); d:SetJustifyH("LEFT"); d:SetText(str)
      self.y = self.y - math.max(14, d:GetStringHeight() or 14) - 8
      return d
    end
    function s:finish()
      local height = -self.y + 6
      box:SetHeight(height)
      colY[col] = colY[col] - height - 12
    end
    s.box = box
    return s
  end

  -- LEFT COLUMN ----------------------------------------------------------------
  local loot = section(1, "Loot & vendors", "Interface\\Icons\\INV_Misc_Bag_10")
  loot:check("Auto loot", "The game's own Auto Loot setting (same as Options > Controls > Auto Loot).", nil, nil,
    function() return Q.GetCVarSwitch("autoLoot") end, function(v) Q.SetCVarSwitch("autoLoot", v) end)
  loot:check("Quicker loot", "Takes everything at once instead of item by item when the game auto loots.", "quickLoot")
  loot:check("Auto repair", "Repairs all gear at merchants that can repair.", "autoRepair")
  loot:check("Sell junk", "Sells all grey items when you open a merchant.", "sellJunk")
  loot:check("Bags full helper", "When loot does not fit, suggests the cheapest item in your bags (value x stack) and destroys it and loots with one click. Quest items, library books, recipes, set pieces, profession tools and items without value are never suggested. Items better than grey need a second click. /ofa cheapest shows it any time.", "bagsFull")
  loot:check("Only grey and white items", "The bags full helper only suggests poor and common items.", "bagsLowOnly", 24)
  do -- items the player put on the "never suggest" list
    local l = FLT.NewFS(loot.box, nil, "OVERLAY", "GameFontHighlight"); l:SetPoint("TOPLEFT", 40, loot.y - 5); l:SetText("Never suggested")
    newTag(loot.box, l, "bagsNever")
    local b = UI.GoldButton(loot.box, "", 110, 22, nil, 11); b:SetPoint("TOPRIGHT", -12, loot.y - 1)
    local arrow = b:CreateTexture(nil, "OVERLAY"); arrow:SetSize(12, 12); arrow:SetPoint("RIGHT", -8, 0)
    FLT.SetTex(arrow, UI.ASSET_ROOT .. "chevron"); arrow:SetTexCoord(0, 0.5, 0, 1)
    local function show()
      local n = #Q.GetNeverItems()
      b:SetLabel(n == 1 and "1 item" or (n .. " items"))
    end
    b:SetScript("OnClick", function(self) showNeverList(self, show) end)
    hint(b, "Never suggested", "Items you blocked with the X button in the bags full helper. Open the list to allow single items again, or remove all.")
    refreshers[#refreshers + 1] = show
    loot.y = loot.y - 30
  end
  loot:finish()

  local feed = section(1, "Loot feed", "Interface\\Icons\\INV_Misc_Coin_02")
  feed:check("Show loot feed", "Looted items and money float up next to your character, like scrolling combat text.", "lootFeed")
  feed:choice("Minimum quality", "Items below this quality are not shown.", "lootFeedQuality", Q.QUALITY_OPTIONS)
  feed:check("Show money", "Also shows looted money.", "lootFeedMoney")
  do
    local move = UI.GoldButton(feed.box, "Move", 88, 22, nil, 12); move:SetPoint("TOPLEFT", 16, feed.y - 2)
    local test = UI.GoldButton(feed.box, "Test", 88, 22, nil, 12); test:SetPoint("LEFT", move, "RIGHT", 8, 0)
    local reset = UI.GoldButton(feed.box, "Reset", 88, 22, nil, 12); reset:SetPoint("LEFT", test, "RIGHT", 8, 0)
    local function show() move:SetLabel(Q.IsLootFeedUnlocked() and "Lock" or "Move"); move:SetActive(Q.IsLootFeedUnlocked()) end
    move:SetScript("OnClick", function() Q.SetLootFeedUnlocked(not Q.IsLootFeedUnlocked()); show() end)
    test:SetScript("OnClick", function() Q.TestLootFeed() end)
    reset:SetScript("OnClick", function() Q.ResetLootFeed() end)
    hint(move, "Move", "Shows the loot feed area. Drag it where you want it, then click Lock.")
    hint(test, "Test", "Shows a few sample entries.")
    hint(reset, "Reset", "Puts the loot feed back to its default place right of your character.")
    refreshers[#refreshers + 1] = show
    feed.y = feed.y - 32
  end
  feed:finish()

  local spells = section(1, "Spells", "Interface\\Icons\\INV_Misc_Book_11")
  spells:check("Check low spell ranks", "Looks for spells on your action bars that use a lower rank than one you already know, and offers to put the highest rank there. After a trainer visit it waits until you close the trainer window. Macros are not checked.", "lowRank")
  do -- ranks kept on purpose ("Keep" in the popup) + check now
    local LR = FLT.LowRank
    local l = FLT.NewFS(spells.box, nil, "OVERLAY", "GameFontHighlight"); l:SetPoint("TOPLEFT", 40, spells.y - 5); l:SetText("Kept ranks")
    local b = UI.GoldButton(spells.box, "", 110, 22, nil, 11); b:SetPoint("TOPRIGHT", -12, spells.y - 1)
    local arrow = b:CreateTexture(nil, "OVERLAY"); arrow:SetSize(12, 12); arrow:SetPoint("RIGHT", -8, 0)
    FLT.SetTex(arrow, UI.ASSET_ROOT .. "chevron"); arrow:SetTexCoord(0, 0.5, 0, 1)
    local function show()
      local n = LR and #LR.GetKept() or 0
      b:SetLabel(n == 1 and "1 spell" or (n .. " spells"))
    end
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
    hint(b, "Kept ranks", "Ranks you keep on purpose (Keep button in the popup). Click one to have it reported again.")
    refreshers[#refreshers + 1] = show
    spells.y = spells.y - 30
    local now = UI.GoldButton(spells.box, "Check now", 110, 22, nil, 12); now:SetPoint("TOPLEFT", 16, spells.y - 2)
    now:SetScript("OnClick", function() if LR then LR.Check("button") end end)
    hint(now, "Check now", "Checks your action bars right away.")
    spells.y = spells.y - 32
  end
  spells:finish()

  local quests = section(2, "Quests", "Interface\\Icons\\INV_Misc_Note_01")
  quests:check("Accept quests automatically", "Accepts quests when you talk to a quest giver.", "autoAccept")
  quests:check("Turn in quests automatically", "Turns in finished quests. If you can choose between rewards, you still pick yourself.", "autoTurnIn")
  quests:check("Quest loot sparkles", "Quest items in the world sparkle again (the game's loot glow). Changes graphics settings; after switching it off, restart the game.", "questSparkles")
  quests:text("Hold Shift while talking to an NPC to do it by hand.")
  quests:finish()

  local social = section(3, "Social", "Interface\\Icons\\INV_Letter_15")
  social:choice("Group invites from", "Accepts group invites automatically from the players you choose. Off: OneForAll does nothing with invites.", "inviteMode", Q.WHO_OPTIONS, "inviteOn")
  social:choice("Keyword invites from", "Invites players who whisper you the keyword below. Off: OneForAll does nothing with whispers.", "keywordMode", Q.WHO_OPTIONS, "keywordOn")
  do
    local l = FLT.NewFS(social.box, nil, "OVERLAY", "GameFontHighlight"); l:SetPoint("TOPLEFT", 56, social.y - 5); l:SetText("Keyword")
    local eb = FLT.SkinBlizz(CreateFrame("EditBox", nil, social.box, "InputBoxTemplate"))
    eb:SetSize(118, 20); eb:SetPoint("TOPRIGHT", -16, social.y - 2); eb:SetAutoFocus(false); eb:SetMaxLetters(24)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:SetText(Q.Get("keyword") or ""); self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", function(self) Q.Set("keyword", self:GetText()) end)
    refreshers[#refreshers + 1] = function() if not eb:HasFocus() then eb:SetText(Q.Get("keyword") or "") end end
    social.y = social.y - 30
  end
  social:choice("Allow duels from", "Duel requests from everyone else are declined automatically. Off: OneForAll does nothing with duels.", "duelMode", Q.DUEL_OPTIONS, "duelOn")
  social:check("Thank players who buff you", "Sends a /thank emote to players outside your group or raid who give you a buff that lasts longer than 2 minutes. It comes 1 second later, not in combat, at most once every 5 minutes per player. Your target is not changed. /ofa thanks shows the last buffs.", "thanksBuff")
  social:finish()

  -- RIGHT COLUMN ---------------------------------------------------------------
  local tips = section(2, "Tooltips", "Interface\\Icons\\INV_Misc_Spyglass_03")
  tips:check("Boss drops", "Shows which dungeon boss drops an item.", "bossDrops")
  tips:check("Gear Value", "On gear you can use: its Value for your talent spec (the stats weighted like Armory > Gear Planner does) and how much better (green) or worse (red) it is than what you wear.", "gearValue")
  tips:check("Recipes: who knows it", "On recipe items: whether you, one of your other characters or a guild member already knows the recipe.", "recipeTip")
  tips:check("Compare items only with Shift", "Item tooltips no longer show your equipped item next to them automatically; hold Shift to compare.", nil, nil,
    function() return Q.GetCompareShift() end, function(v) Q.SetCompareShift(v) end)
  tips:check("Target of players", "Shows who a player (or NPC) under your mouse is targeting. \"You\" when it is you.", "unitTarget")
  tips:finish()

  local iface = section(3, "Interface", "Interface\\Icons\\INV_Misc_Gear_01")
  iface:check("Farther camera zoom", "Lets you zoom the camera out further.", "cameraZoom")
  iface:check("Free bag slots on the backpack", "Shows the free slots of all normal bags (quivers, ammo and profession bags are not counted).", "bagSlots")
  iface:check("Quest XP on the experience bar", "Marks on the experience bar how much XP your finished quests give when you turn them in. The amount is also shown in the bar's tooltip.", "questXP")
  iface:check("Durability warning", "Warns when your gear drops to 20% durability.", "durability")
  iface:check("Move Blizzard windows", "Drag windows such as the character, merchant or quest log window with the left mouse button. Positions are remembered.", "moveWindows")
  do
    local rb = UI.GoldButton(iface.box, "Reset", 60, 20, nil, 11); rb:SetPoint("TOPRIGHT", -12, iface.y + 26)
    rb:SetScript("OnClick", function() Q.ResetWindowPositions() end)
    hint(rb, "Reset window positions", "Moved Blizzard windows go back to their default place.")
  end
  do -- chat font size: -, value, +
    local l = FLT.NewFS(iface.box, nil, "OVERLAY", "GameFontHighlight"); l:SetPoint("TOPLEFT", 16, iface.y - 5); l:SetText("Chat font size")
    local val = FLT.NewFS(iface.box, nil, "OVERLAY", "GameFontNormal"); val:SetWidth(46); val:SetJustifyH("CENTER")
    local plus = UI.GoldButton(iface.box, "+", 26, 22, nil, 13); plus:SetPoint("TOPRIGHT", -14, iface.y - 1)
    val:SetPoint("RIGHT", plus, "LEFT", -4, 0)
    local minus = UI.GoldButton(iface.box, "-", 26, 22, nil, 13); minus:SetPoint("RIGHT", val, "LEFT", -4, 0)
    local function show()
      local v = tonumber(Q.Get("chatFont"))
      val:SetText(v and tostring(v) or "Off")
    end
    local function step(d)
      local v = tonumber(Q.Get("chatFont"))
      if not v then v = 14 else v = v + d end
      if v < 10 then v = nil elseif v > 24 then v = 24 end
      Q.Set("chatFont", v); show()
    end
    plus:SetScript("OnClick", function() step(1) end); minus:SetScript("OnClick", function() step(-1) end)
    hint(plus, "Chat font size", "Sets the same font size for every chat window. Go below 10 to switch it off (then the game's own setting is kept).")
    refreshers[#refreshers + 1] = show
    iface.y = iface.y - 30
  end
  iface:check("Copy chat button", "Adds a small button to the top right of every chat window. It opens the chat text so you can select and copy it (Ctrl+C).", "copyChat")
  iface:check("Collect minimap buttons", "Puts the minimap buttons of other addons into one bar. It opens from a bigger OneForAll button that you can drag anywhere (it is not tied to the minimap). Right-click that button to open OneForAll. Switching this off puts all buttons back on the minimap.", "mmCollect")
  iface:choice("Bar opens", "Where the bar with the collected buttons opens next to the OneForAll button. Automatic: towards the middle of the screen.", "mmDir", Q.MM_DIR_OPTIONS)
  do
    local rb = UI.GoldButton(iface.box, "Reset", 60, 20, nil, 11); rb:SetPoint("TOPRIGHT", -12, iface.y + 56)
    rb:SetScript("OnClick", function() if FLT.ResetMinimapCollector then FLT.ResetMinimapCollector() end end)
    hint(rb, "Reset button position", "Puts the minimap button collector back to its default place next to the minimap.")
  end
  iface:finish()

  local world = section(2, "World map", "Interface\\Icons\\INV_Misc_Map_01")
  world:check("Map Landmarks", "Icons on the world map for dungeon and raid entrances, flight masters, zeppelins and ships (your faction and neutral ones). Click an entrance to open that dungeon in OneForAll, Shift-click it for a map pin. Zeppelins, ships and flight masters show where they go and set a map pin on click.", "mapLandmarks")
  world:check("Dungeon & raid entrances", nil, "lmDungeons", 24)
  world:check("Flight masters", nil, "lmFlight", 24)
  world:check("Zeppelins & ships", nil, "lmTransport", 24)
  world:finish()

  local frames = section(2, "Unit frames", "Interface\\Icons\\INV_Misc_Head_Human_01")
  frames:check("Class colors: player, target & party", "Colors the health bars of players in their class color. NPCs keep their normal color.", "classColors")
  frames:check("Class colors: raid frames", "The game's own setting (same as Interface > Display Class Colors).", nil, nil,
    function() return Q.GetCVarSwitch("raidClassColor") end, function(v) Q.SetCVarSwitch("raidClassColor", v) end)
  frames:check("Power bars: raid frames", "Shows mana, rage and energy bars in the raid frames (a game setting).", nil, nil,
    function() return Q.GetCVarSwitch("raidPowerBars") end, function(v) Q.SetCVarSwitch("raidPowerBars", v) end)
  frames:finish()

  page:SetHeight(math.max(-colY[1], -colY[2], -colY[3]) + 8)

  panel:SetScript("OnShow", function() for _, f in ipairs(refreshers) do f() end end)
  panel:SetScript("OnHide", function() UI.CloseDropDown(); if neverMenu then neverMenu:Hide() end end)
  panel:Hide()
  return panel
end

UI.RegisterPanel({ key="qol", label="Quality of Life", order=4, tabWidth=140, create=createQoLPanel })
