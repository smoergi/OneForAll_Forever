local _, FLT = ...
local UI = FLT.UI

-- Quality of Life tab: one switch per feature (all off by default).
-- Logic lives in QoL.lua (FLT.QoL).

local unpack = unpack or table.unpack
local GOLD = UI.GOLD
-- three columns from x 8 to 996, flush with the title band like the other tabs
local COL_W = 320
local COL_X = { 8, 342, 676 }
local openDropDown -- below

-- Shared drop-down list (one at a time); a click outside closes it.
local ddMenu, ddCatcher
openDropDown = function(owner, options, current, onPick)
  if not ddMenu then
    ddCatcher = CreateFrame("Button", nil, UIParent); ddCatcher:SetAllPoints(UIParent)
    ddCatcher:SetFrameStrata("FULLSCREEN_DIALOG"); ddCatcher:SetFrameLevel(1)
    ddCatcher:RegisterForClicks("AnyUp"); ddCatcher:Hide()
    ddMenu = CreateFrame("Frame", nil, UIParent); ddMenu:SetFrameStrata("FULLSCREEN_DIALOG"); ddMenu:SetFrameLevel(20)
    ddMenu:EnableMouse(true); ddMenu:Hide()
    UI.FramedPanel(ddMenu)
    ddMenu.rows = {}
    ddCatcher:SetScript("OnClick", function() ddMenu:Hide() end)
    ddMenu:SetScript("OnHide", function() ddCatcher:Hide() end)
  end
  if ddMenu:IsShown() and ddMenu.owner == owner then ddMenu:Hide(); return end
  local w = owner:GetWidth() or 170
  for _, r in ipairs(ddMenu.rows) do r:Hide() end
  for i, o in ipairs(options) do
    local r = ddMenu.rows[i]
    if not r then
      r = CreateFrame("Button", nil, ddMenu); r:SetHeight(22)
      local hi = r:CreateTexture(nil, "HIGHLIGHT"); hi:SetAllPoints(); hi:SetColorTexture(FLT.SkinC(0.90, 0.66, 0.22, 0.18))
      r.text = FLT.NewFS(r, nil, "OVERLAY", "GameFontHighlight"); r.text:SetPoint("LEFT", 22, 0)
      r.check = r:CreateTexture(nil, "OVERLAY"); r.check:SetSize(14, 14); r.check:SetPoint("LEFT", 5, 0)
      r.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check"); FLT.SkinBlizz(r)
      ddMenu.rows[i] = r
    end
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 22); r:SetWidth(w - 8)
    r.text:SetText(o.label)
    local sel = (o.key == current)
    r.check:SetShown(sel)
    if sel then r.text:SetTextColor(FLT.SkinC(1, 0.82, 0.2)) else r.text:SetTextColor(0.92, 0.90, 0.84) end
    r:SetScript("OnClick", function() ddMenu:Hide(); onPick(o.key) end)
    r:Show()
  end
  ddMenu:SetSize(w, #options * 22 + 8)
  ddMenu:ClearAllPoints(); ddMenu:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
  ddMenu.owner = owner
  ddCatcher:Show(); ddMenu:Show()
end


-- Preview popup: a framed picture that shows what a feature looks like in game.
-- previews[key] = { tex, width, height (shown size), texcoord bottom }
local PREVIEWS = {
  questSparkles = { title = "Quest loot sparkles", tex = "preview_sparkles", w = 300, h = 300, t = 1 },
  bagsFull = { title = "Bags full helper", tex = "preview_bagsfull", w = 560, h = 183, t = 167 / 256 },
  questXP = { title = "Quest XP on the experience bar", tex = "preview_questxp", w = 640, h = 119, t = 190 / 256 },
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
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -2, -2); FLT.SkinBlizz(close)
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

local function createQoLPanel(parent)
  local Q = FLT.QoL
  local panel = CreateFrame("Frame", nil, parent)
  UI.PlacePanel(panel, parent)
  UI.TitleBand(panel, { emblem = UI.ASSET_ROOT .. "emblem_qol", art = UI.ASSET_ROOT .. "qol_banner",
    title = "Quality of Life", subtitle = "Small helpers for everyday play. Everything is off until you switch it on. Hold Shift to pause the automations.", fadeRight = 200 })

  -- scrollable page below the title band
  local sf = FLT.SkinBlizz(CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate"))
  sf:SetPoint("TOPLEFT", 0, -70); sf:SetPoint("BOTTOMRIGHT", 0, 4)
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
  social:check("Thank players who buff you", "Sends a /thank emote to players outside your group or raid who buff you (not in combat, at most once every few minutes per player).", "thanksBuff")
  social:finish()

  -- RIGHT COLUMN ---------------------------------------------------------------
  local tips = section(2, "Tooltips", "Interface\\Icons\\INV_Misc_Spyglass_03")
  tips:check("Boss drops", "Shows which dungeon boss drops an item.", "bossDrops")
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
  iface:finish()

  local frames = section(2, "Unit frames", "Interface\\Icons\\INV_Misc_Head_Human_01")
  frames:check("Class colors: player, target & party", "Colors the health bars of players in their class color. NPCs keep their normal color.", "classColors")
  frames:check("Class colors: raid frames", "The game's own setting (same as Interface > Display Class Colors).", nil, nil,
    function() return Q.GetCVarSwitch("raidClassColor") end, function(v) Q.SetCVarSwitch("raidClassColor", v) end)
  frames:check("Power bars: raid frames", "Shows mana, rage and energy bars in the raid frames (a game setting).", nil, nil,
    function() return Q.GetCVarSwitch("raidPowerBars") end, function(v) Q.SetCVarSwitch("raidPowerBars", v) end)
  frames:finish()

  page:SetHeight(math.max(-colY[1], -colY[2], -colY[3]) + 8)

  panel:SetScript("OnShow", function() for _, f in ipairs(refreshers) do f() end end)
  panel:SetScript("OnHide", function() if ddMenu then ddMenu:Hide() end end)
  panel:Hide()
  return panel
end

UI.RegisterPanel({ key="qol", label="Quality of Life", order=8, tabWidth=140, create=createQoLPanel })
