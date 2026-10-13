local _, FLT = ...
local UI = FLT.UI
local makeTexture, makeButton = UI.makeTexture, UI.makeButton

-- Settings tab (gear icon, leftmost). Collects all options of the addon.
-- Layout: two columns of sections. Every section has a header band with an
-- icon; options show a short grey description under their label. Sections
-- size themselves to their content, so the columns stay tidy.

local GOLD = {1, 0.82, 0.20}
local COL_W = 488
local COL_X = {8, 508}

local function db()
  if type(ForeverCompanionDB) ~= "table" then return {} end
  return ForeverCompanionDB
end

local function createSettingsPanel(parent)
  local panel = CreateFrame("Frame", nil, parent)
  UI.PlacePanel(panel, parent)
  UI.TitleBand(panel, { emblem = UI.ASSET_ROOT .. "emblem_settings", art = UI.ASSET_ROOT .. "settings_banner",
    title = "Settings", subtitle = "Options apply to your whole account unless marked \"this character\".", fadeRight = 200 })
  local TOP = -66 -- below the title band

  local refreshers = {}
  local colY = { TOP - 10, TOP - 10 }

  -- A section in column col (1 = left, 2 = right). Returns an object with
  -- :check(label, hint, get, set[, x, compact]), :button(...), :text(...), :finish().
  local function section(col, label, icon)
    local box = CreateFrame("Frame", nil, panel)
    box:SetPoint("TOPLEFT", COL_X[col], colY[col]); box:SetWidth(COL_W)
    UI.FramedPanel(box)
    local band = makeTexture(box, "BORDER", 0.09, 0.075, 0.05, 0.85); band:SetPoint("TOPLEFT", 3, -3); band:SetPoint("TOPRIGHT", -3, -3); band:SetHeight(28)
    local dv = box:CreateTexture(nil, "ARTWORK"); FLT.SetTex(dv, UI.ASSET_ROOT .. "divider_ornate"); dv:SetHeight(12); dv:SetPoint("TOPLEFT", 4, -25); dv:SetPoint("TOPRIGHT", -4, -25)
    local ic = box:CreateTexture(nil, "OVERLAY"); ic:SetSize(20, 20); ic:SetPoint("TOPLEFT", 10, -6); FLT.SetTex(ic, icon); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if ic.AddMaskTexture and box.CreateMaskTexture then
      local m = box:CreateMaskTexture(); FLT.SetTex(m, UI.ASSET_ROOT .. "talent_icon_mask2", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE"); m:SetAllPoints(ic); ic:AddMaskTexture(m)
    end
    local t = FLT.NewFS(box, nil, "OVERLAY", "GameFontNormal"); t:SetPoint("LEFT", ic, "RIGHT", 8, 0); t:SetText(label); t:SetTextColor(FLT.SkinC(unpack(GOLD)))

    local s = { y = -40, rowMax = -40, box = box }
    function s:check(text, hint, get, set, x, compact)
      local cx = 12 + (x or 0)
      local cb = FLT.SkinBlizz(CreateFrame("CheckButton", nil, box, "UICheckButtonTemplate"))
      cb:SetSize(24, 24); cb:SetPoint("TOPLEFT", cx, self.y)
      local l = FLT.NewFS(box, nil, "OVERLAY", "GameFontHighlight")
      l:SetPoint("TOPLEFT", cb, "TOPRIGHT", 4, -5); l:SetText(text)
      cb:SetScript("OnClick", function(btn) set(btn:GetChecked() and true or false) end)
      local h = 30
      if hint and not compact then
        local d = FLT.NewFS(box, nil, "OVERLAY", "GameFontDisableSmall")
        d:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -3); d:SetWidth(COL_W - cx - 44); d:SetJustifyH("LEFT"); d:SetText(hint)
        h = 26 + math.max(12, d:GetStringHeight() or 12) + 4
      end
      if hint then
        cb:SetScript("OnEnter", function(btn)
          GameTooltip:SetOwner(btn, "ANCHOR_RIGHT"); GameTooltip:AddLine(text, 1, 0.82, 0)
          GameTooltip:AddLine(hint, 1, 1, 1, true); GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
      end
      refreshers[#refreshers + 1] = function() cb:SetChecked(get()) end
      self.rowMax = math.min(self.rowMax, self.y - h)
      return cb
    end
    function s:nextRow() self.y = self.rowMax end
    function s:button(text, w, onClick, x)
      local b = UI.GoldButton(box, text, w, 24, nil, 12); b:SetPoint("TOPLEFT", 12 + (x or 0), self.y - 2)
      b:SetScript("OnClick", onClick)
      self.rowMax = math.min(self.rowMax, self.y - 34)
      return b
    end
    function s:text(str)
      local d = FLT.NewFS(box, nil, "OVERLAY", "GameFontDisableSmall")
      d:SetPoint("TOPLEFT", 14, self.y - 2); d:SetWidth(COL_W - 28); d:SetJustifyH("LEFT"); d:SetText(str)
      self.rowMax = math.min(self.rowMax, self.y - math.max(14, d:GetStringHeight() or 14) - 10)
      self:nextRow()
    end
    function s:finish()
      self:nextRow()
      local height = -self.y + 6
      box:SetHeight(height)
      colY[col] = colY[col] - height - 12
    end
    return s
  end

  -- LEFT COLUMN ----------------------------------------------------------------
  -- Tabs (per character), two per row in tab-bar order. The arrows move a
  -- tab left / right in the tab bar; Settings and General stay in front.
  local tabs = section(1, "Shown tabs  |cff9d9d9d(this character)|r", "Interface\\Icons\\INV_Misc_Book_09")
  local cells = {}
  local function sortable() return UI.SortableTabs and UI.SortableTabs() or {} end
  local function refreshCells()
    local list = sortable()
    for i, c in ipairs(cells) do
      local spec = list[i]
      c.key = spec and spec.key
      c.label:SetText(spec and spec.label or "")
      c.cb:SetChecked(spec and UI.IsTabVisible(spec.key) or false)
      c.left:SetEnabled(i > 1); c.right:SetEnabled(i < #list)
      c.left:SetAlpha(i > 1 and 1 or 0.3); c.right:SetAlpha(i < #list and 1 or 0.3)
    end
  end
  local function arrow(parent, x, y, tex, tip, dir, cell)
    local b = CreateFrame("Button", nil, parent); b:SetSize(20, 20); b:SetPoint("TOPLEFT", x, y)
    b:SetNormalTexture(tex .. "-Up"); b:SetPushedTexture(tex .. "-Down"); b:SetDisabledTexture(tex .. "-Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", function() if cell.key and UI.MoveTab then UI.MoveTab(cell.key, dir); refreshCells() end end)
    b:SetScript("OnEnter", function(btn) GameTooltip:SetOwner(btn, "ANCHOR_RIGHT"); GameTooltip:AddLine(tip, 1, 0.82, 0); GameTooltip:Show() end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
  end
  local n = #sortable()
  for i = 1, n do
    local x = 12 + ((i - 1) % 2) * 230
    local y = tabs.y
    local cell = {}
    local cb = FLT.SkinBlizz(CreateFrame("CheckButton", nil, tabs.box, "UICheckButtonTemplate"))
    cb:SetSize(24, 24); cb:SetPoint("TOPLEFT", x, y)
    local l = FLT.NewFS(tabs.box, nil, "OVERLAY", "GameFontHighlight"); l:SetPoint("TOPLEFT", cb, "TOPRIGHT", 4, -5)
    cb:SetScript("OnClick", function(btn) if cell.key then UI.SetTabVisible(cell.key, btn:GetChecked() and true or false) end end)
    cb:SetScript("OnEnter", function(btn) GameTooltip:SetOwner(btn, "ANCHOR_RIGHT"); GameTooltip:AddLine("Show or hide this tab for the current character.", 1, 1, 1, true); GameTooltip:Show() end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cell.cb, cell.label = cb, l
    cell.left = arrow(tabs.box, x + 160, y - 2, "Interface\\Buttons\\UI-SpellbookIcon-PrevPage", "Move left in the tab bar", -1, cell)
    cell.right = arrow(tabs.box, x + 182, y - 2, "Interface\\Buttons\\UI-SpellbookIcon-NextPage", "Move right in the tab bar", 1, cell)
    cells[i] = cell
    tabs.rowMax = math.min(tabs.rowMax, y - 30)
    if i % 2 == 0 then tabs:nextRow() end
  end
  tabs:nextRow()
  local ro = tabs:button("Reset order", 120, function() if UI.ResetTabOrder then UI.ResetTabOrder(); refreshCells() end end)
  ro:SetScript("OnEnter", function(btn) GameTooltip:SetOwner(btn, "ANCHOR_RIGHT"); GameTooltip:AddLine("Back to the default tab order for this character.", 1, 1, 1, true); GameTooltip:Show() end)
  ro:SetScript("OnLeave", function() GameTooltip:Hide() end)
  tabs:nextRow()
  refreshers[#refreshers + 1] = refreshCells
  tabs:finish()

  -- Dungeon list brackets, one per row
  local function browseCfg()
    local d = db()
    d.dungeonBrowse = d.dungeonBrowse or {}
    d.dungeonBrowse.hiddenBrackets = d.dungeonBrowse.hiddenBrackets or {}
    return d.dungeonBrowse
  end
  local used = {}
  for _, d in ipairs(FLT.DUNGEONS or {}) do
    for _, br in ipairs(UI.DUNGEON_BRACKETS or {}) do
      if (d.minLevel or 0) >= br.min and (d.minLevel or 0) <= br.max then used[br.id] = true end
    end
  end
  local dun = section(1, "Dungeon list", "Interface\\Icons\\INV_Misc_Map_01")
  -- Left: the level brackets one below the other. Right: the other switches.
  local left, right = {}, {}
  for _, br in ipairs(UI.DUNGEON_BRACKETS or {}) do
    if used[br.id] then
      local id = br.id
      left[#left + 1] = { br.label, "Hide a bracket you no longer need, e.g. once you have outleveled it.",
        function() return not browseCfg().hiddenBrackets[id] end,
        function(v) browseCfg().hiddenBrackets[id] = (not v) or nil; if UI.RefreshDungeonList then UI.RefreshDungeonList() end end }
    end
  end
  right[#right + 1] = { "Only dungeons for my level", "Hides dungeons that are more than 3 levels above you or that you have clearly outleveled.",
    function() return browseCfg().onlyFit and true or false end,
    function(v) browseCfg().onlyFit = v or nil; if UI.RefreshDungeonList then UI.RefreshDungeonList() end end }
  right[#right + 1] = { "Highest levels first", "Shows the high-level brackets at the top of the dungeon list and sorts the dungeons from the highest level down.",
    function() return browseCfg().highFirst and true or false end,
    function(v) browseCfg().highFirst = v or nil; if UI.RefreshDungeonList then UI.RefreshDungeonList() end end }
  right[#right + 1] = { "Show recipe drops in boss loot", "Lists the recipes a boss can drop below its loot, with the yellow / green / blue markers.",
    function() return db().dungeonRecipes ~= false end,
    function(v) db().dungeonRecipes = v end }
  for i = 1, math.max(#left, #right) do
    local l, r = left[i], right[i]
    if l then dun:check(l[1], l[2], l[3], l[4], 0, true) end
    if r then dun:check(r[1], r[2], r[3], r[4], 220, true) end
    dun:nextRow()
  end
  dun:finish()

  -- RIGHT COLUMN ---------------------------------------------------------------
  local gen = section(2, "General", "Interface\\Icons\\INV_Misc_Gear_01")
  gen:check("Tell me about new versions", "Prints a short note in the chat when another OneForAll user (guild, group or recipe sharing) runs a newer version.",
    function() return db().versionNotice ~= false end,
    function(v) db().versionNotice = v end); gen:nextRow()
  gen:check("Share recipes with other OneForAll users", "Exchanges known recipes with OneForAll users outside your guild (blue marker in All recipes). When off, you do not share yours and do not see theirs either. Guild members are always shared.",
    function() return FLT.IsRecipeShareEnabled and FLT.IsRecipeShareEnabled() end,
    function(v) if FLT.SetRecipeShareEnabled then FLT.SetRecipeShareEnabled(v) end end); gen:nextRow()
  gen:finish()

  local function shareCfg()
    local d = db(); d.questShare = d.questShare or {}
    return d.questShare
  end
  local alerts = section(2, "Popups & alerts", "Interface\\Icons\\INV_Misc_Bell_01")
  alerts:check("Nearby Library Book alerts", "Popup when you are close to a missing library book.",
    function() return FLT.IsNearbyAlertsEnabled and FLT:IsNearbyAlertsEnabled() end,
    function(v) if FLT.SetNearbyAlertsEnabled then FLT:SetNearbyAlertsEnabled(v) end end); alerts:nextRow()
  alerts:check("Pet ability alerts  |cff9d9d9d(Hunter)|r", "Popup when a beast nearby teaches a higher ability rank your pets can learn.",
    function() return FLT.IsPetTeachAlertsEnabled and FLT:IsPetTeachAlertsEnabled() end,
    function(v) if FLT.SetPetTeachAlertsEnabled then FLT:SetPetTeachAlertsEnabled(v) end end); alerts:nextRow()
  alerts:check("Quest share popup in dungeons", "Opens when a group member can still accept one of your dungeon quests.",
    function() return shareCfg().popup ~= false end,
    function(v) shareCfg().popup = v end); alerts:nextRow()
  alerts:check("Emote when sharing a quest", "Posts an emote such as \"shares the quest ... (OneForAll addon)\".",
    function() return shareCfg().emote ~= false end,
    function(v) shareCfg().emote = v end); alerts:nextRow()
  alerts:finish()

  -- Skin: gold (default) or silver; applied on the next /reload.
  local look = section(2, "Skin", "Interface\\Icons\\INV_Misc_Gem_Pearl_04")
  local skinButtons = {}
  local SKINS = { { key = "gold", label = "Gold" }, { key = "silver", label = "Dark Silver" } }
  for i, sk in ipairs(SKINS) do
    local key = sk.key
    local b = look:button(sk.label, 110, function()
      UI.AskSkin(key)
    end, (i - 1) * 120)
    skinButtons[key] = b
  end
  refreshers[#refreshers + 1] = function()
    for key, b in pairs(skinButtons) do b:SetActive(FLT.GetSkin() == key) end
  end
  look:nextRow()
  look:text("Dark Silver turns the gold frames, buttons and highlights grey and dims the pictures a little. Switching reloads the interface.")
  look:finish()

  local win = section(1, "Window", "Interface\\Icons\\INV_Misc_Spyglass_02")
  local rb = win:button("Reset size & position", 180, function() if UI.ResetWindow then UI.ResetWindow() end end)
  -- the grip hint lives in the tooltip to keep the page compact
  rb:SetScript("OnEnter", function(btn)
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT"); GameTooltip:AddLine("Window size", 1, 0.82, 0)
    GameTooltip:AddLine("Bottom-right grip: scale the window (60-140 %). Bottom-middle grip: change its height.", 1, 1, 1, true); GameTooltip:Show()
  end)
  rb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  win:button("Noteworthy changes", 160, function() if FLT.ShowNews then FLT.ShowNews() end end, 192)
  win:nextRow()
  win:finish()

  local footer = FLT.NewFS(panel, nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", 14, 8)
  footer:SetText("Like OneForAll or have an idea? Leave a comment on CurseForge - feedback and suggestions are always welcome.")

  panel:SetScript("OnShow", function() for _, f in ipairs(refreshers) do f() end end)
  panel:Hide()
  return panel
end

UI.RegisterPanel({ key="settings", label="Settings", order=0, tabWidth=27, icon="Interface\\Icons\\INV_Misc_Gear_01", create=createSettingsPanel })
