local _, FLT = ...
local unpack = unpack or table.unpack
local UI = FLT.UI
local makeTexture, makeButton = UI.makeTexture, UI.makeButton

-- Main window: title bar, tab bar and the registered panels (see Widgets.lua).
local frame
local panels = {}      -- key -> panel frame
local tabButtons = {}  -- key -> tab button
local activeTab = "general"

-- Panels are built the first time their tab is opened (saves memory for tabs
-- that are never used in a session).
local function ensurePanel(key)
  if panels[key] then return panels[key] end
  if not frame then return nil end
  for _, spec in ipairs(UI.panels) do
    if spec.key == key then
      local panel = spec.create(frame)
      if panel then
        panels[key] = panel; panel:Hide()
        -- the window's refresh ran before this tab existed: catch up now
        if panel.Refresh then panel:Refresh() end
      end
      return panel
    end
  end
end
function UI.EnsurePanel(key) return ensurePanel(key) end

local function setPanelTab(tab)
  activeTab = tab or "general"
  ensurePanel(activeTab)
  for key, panel in pairs(panels) do
    if key == activeTab then panel:Show() else panel:Hide() end
  end
  for key, b in pairs(tabButtons) do
    if b.SetActive then b:SetActive(key == activeTab)
    elseif key == activeTab then b:LockHighlight() else b:UnlockHighlight() end
  end
end

-- Window scaling: the layout is built for 1040x650 and scaled as a whole
-- (SetScale), so every tab keeps its proportions. Scale and position are
-- saved account-wide in ForeverCompanionDB.window.
local BASE_W, BASE_H = 1040, 650
local MIN_SCALE, MAX_SCALE = 0.6, 1.4
-- The height can additionally be stretched (bottom-edge grip) so lists show
-- more rows; stored in ForeverCompanionDB.window.height.

local applyHeight -- defined below; used by the scale grip as well

local function windowDB()
  if type(ForeverCompanionDB) ~= "table" then return {} end
  ForeverCompanionDB.window = ForeverCompanionDB.window or {}
  return ForeverCompanionDB.window
end

local function clampScale(s)
  s = tonumber(s) or 1
  if s < MIN_SCALE then s = MIN_SCALE elseif s > MAX_SCALE then s = MAX_SCALE end
  return math.floor(s * 100 + 0.5) / 100
end

-- Puts the window's top-left corner exactly on a screen pixel. Otherwise every
-- frame edge inside sits between two pixels and the game's pixel snapping makes
-- thin gold lines jump or change their brightness when the window moves or grows.
local function snapToPixels()
  local left, top = frame:GetLeft(), frame:GetTop()
  local s = frame:GetEffectiveScale()
  if not left or not top or not s or s <= 0 then return end
  local pl, pt = math.floor(left * s + 0.5) / s, math.floor(top * s + 0.5) / s
  if math.abs(pl - left) > 0.001 or math.abs(pt - top) > 0.001 then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pl, pt)
  end
end

local function savePosition()
  snapToPixels()
  local left, top = frame:GetLeft(), frame:GetTop()
  if not left or not top then return end
  local db = windowDB()
  db.left, db.top = left, top
end

-- Keeps the top-left corner in place on screen while the scale changes.
local function applyScale(newScale)
  newScale = clampScale(newScale)
  local oldScale = frame:GetScale() or 1
  local left, top = frame:GetLeft(), frame:GetTop()
  frame:SetScale(newScale)
  if left and top then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * oldScale / newScale, top * oldScale / newScale)
    savePosition()
  end
  windowDB().scale = newScale
  return newScale
end

local function createResizeGrip()
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -9, 9)
  grip:SetFrameLevel(frame:GetFrameLevel() + 20)
  local GRIP = UI.ASSET_ROOT .. "grip_resize"
  grip:SetNormalTexture(GRIP)
  grip:SetHighlightTexture(GRIP)
  local ht = grip:GetHighlightTexture(); if ht and ht.SetBlendMode then ht:SetBlendMode("ADD") end
  grip:SetPushedTexture(GRIP)
  FLT.SkinArtTex(grip:GetNormalTexture()); FLT.SkinArtTex(grip:GetHighlightTexture()); FLT.SkinArtTex(grip:GetPushedTexture())
  local pt = grip:GetPushedTexture(); if pt and pt.SetVertexColor then pt:SetVertexColor(FLT.SkinC(0.7, 0.6, 0.4)) end

  local dragging
  grip:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    dragging = true
    self:SetScript("OnUpdate", function()
      if not dragging then return end
      local cx = GetCursorPosition()                       -- screen pixels
      local parentScale = UIParent:GetEffectiveScale()
      local left = frame:GetLeft() * frame:GetEffectiveScale() -- screen pixels
      local width = cx - left
      if width > 0 then
        local s = clampScale(width / (BASE_W * parentScale))
        if math.abs(s - (frame:GetScale() or 1)) >= 0.01 then applyScale(s) end
      end
    end)
  end)
  local function stop(self)
    dragging = false
    self:SetScript("OnUpdate", nil)
    savePosition()
  end
  grip:SetScript("OnMouseUp", function(self) stop(self); applyHeight(frame:GetHeight()) end)
  grip:SetScript("OnHide", stop)
  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Resize window", 1, 0.82, 0)
    GameTooltip:AddLine("Drag to scale the whole window. /ofa scale resets it.", 1, 1, 1, true)
    GameTooltip:AddLine(string.format("Current size: %d%%", math.floor((frame:GetScale() or 1) * 100 + 0.5)), 0.72, 0.72, 0.72)
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Largest height that still fits on screen at the current scale.
local function maxHeight()
  local screenH = UIParent:GetHeight() * UIParent:GetEffectiveScale()
  return math.max(BASE_H, math.floor(screenH / frame:GetEffectiveScale()) - 20)
end

local function clampHeight(h)
  h = tonumber(h) or BASE_H
  if h < BASE_H then h = BASE_H end
  if frame then local m = maxHeight(); if h > m then h = m end end
  return math.floor(h + 0.5)
end

applyHeight = function(h)
  h = clampHeight(h)
  frame:SetHeight(h)
  windowDB().height = (h > BASE_H) and h or nil
  return h
end

local function createHeightGrip()
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(140, 10)
  grip:SetPoint("BOTTOM", 0, 4)
  grip:SetFrameLevel(frame:GetFrameLevel() + 20)
  grip:SetHeight(16)
  local bar = grip:CreateTexture(nil, "ARTWORK")
  bar:SetSize(64, 16); bar:SetPoint("CENTER")
  FLT.SetTex(bar, UI.ASSET_ROOT .. "grip_height"); bar:SetAlpha(0.8)
  local hi = grip:CreateTexture(nil, "HIGHLIGHT")
  hi:SetSize(64, 16); hi:SetPoint("CENTER")
  FLT.SetTex(hi, UI.ASSET_ROOT .. "grip_height"); hi:SetBlendMode("ADD")

  local dragging
  grip:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    dragging = true
    self:SetScript("OnUpdate", function()
      if not dragging then return end
      local _, cy = GetCursorPosition()                      -- screen pixels
      local eff = frame:GetEffectiveScale()
      local top = frame:GetTop() * eff                        -- screen pixels
      local h = (top - cy) / eff
      if math.abs(h - frame:GetHeight()) >= 1 then applyHeight(h) end
    end)
  end)
  local function stop(self)
    dragging = false
    self:SetScript("OnUpdate", nil)
  end
  grip:SetScript("OnMouseUp", stop)
  grip:SetScript("OnHide", stop)
  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Window height", 1, 0.82, 0)
    GameTooltip:AddLine("Drag up or down to make the window taller and show more rows. /ofa scale resets it.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Tab visibility is stored per character (ForeverCompanionCharDB.tabs).
-- Without a saved choice a tab is shown, unless its panel spec lists the
-- classes it is meant for (spec.classes, e.g. a class-only tab).
local function playerClass()
  if not UnitClass then return nil end
  local _, token = UnitClass("player")
  return token
end

function UI.IsTabVisible(key)
  if key == "general" or key == "settings" then return true end
  local saved = type(ForeverCompanionCharDB) == "table" and ForeverCompanionCharDB.tabs and ForeverCompanionCharDB.tabs[key]
  if saved ~= nil then return saved and true or false end
  for _, spec in ipairs(UI.panels) do
    if spec.key == key and spec.classes then
      local cls = playerClass()
      for _, c in ipairs(spec.classes) do if c == cls then return true end end
      return false
    end
  end
  return true
end

function UI.SetTabVisible(key, visible)
  if key == "general" or key == "settings" or type(ForeverCompanionCharDB) ~= "table" then return end
  ForeverCompanionCharDB.tabs = ForeverCompanionCharDB.tabs or {}
  ForeverCompanionCharDB.tabs[key] = visible and true or false
  UI.LayoutTabs()
end

function UI.ResetTabs()
  if type(ForeverCompanionCharDB) == "table" then ForeverCompanionCharDB.tabs = nil end
  UI.LayoutTabs()
end

-- Tab order (per character, ForeverCompanionCharDB.tabOrder = list of keys).
-- Settings and General always stay in front; the other tabs can be moved.
local FIXED_TABS = { settings = true, general = true }
function UI.SortableTabs()
  local saved = type(ForeverCompanionCharDB) == "table" and ForeverCompanionCharDB.tabOrder
  local pos = {}
  if type(saved) == "table" then for i, k in ipairs(saved) do pos[k] = i end end
  local list = {}
  for i, spec in ipairs(UI.panels) do
    if not FIXED_TABS[spec.key] then list[#list + 1] = { spec = spec, def = i } end
  end
  table.sort(list, function(a, b)
    local pa, pb = pos[a.spec.key], pos[b.spec.key]
    if pa and pb then return pa < pb end
    if pa then return true end
    if pb then return false end
    return a.def < b.def
  end)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.spec end
  return out
end
function UI.OrderedPanels()
  local out = {}
  for _, spec in ipairs(UI.panels) do if FIXED_TABS[spec.key] then out[#out + 1] = spec end end
  for _, spec in ipairs(UI.SortableTabs()) do out[#out + 1] = spec end
  return out
end
function UI.MoveTab(key, dir)
  if type(ForeverCompanionCharDB) ~= "table" then return end
  local list = UI.SortableTabs()
  local idx
  for i, spec in ipairs(list) do if spec.key == key then idx = i end end
  local j = idx and idx + dir
  if not idx or j < 1 or j > #list then return end
  list[idx], list[j] = list[j], list[idx]
  local order = {}
  for i, spec in ipairs(list) do order[i] = spec.key end
  ForeverCompanionCharDB.tabOrder = order
  UI.LayoutTabs()
end
function UI.ResetTabOrder()
  if type(ForeverCompanionCharDB) == "table" then ForeverCompanionCharDB.tabOrder = nil end
  UI.LayoutTabs()
end

function UI.LayoutTabs()
  if not frame then return end
  local x = 18
  for _, spec in ipairs(UI.OrderedPanels()) do
    local b = tabButtons[spec.key]
    if b then
      b:ClearAllPoints()
      if UI.IsTabVisible(spec.key) then
        b:SetPoint("TOPLEFT", x, -35); b:Show()
        x = x + (spec.tabWidth or 130) + 6
      else
        b:Hide()
      end
    end
  end
  if not UI.IsTabVisible(activeTab) and panels[activeTab] then setPanelTab("general") end
end

-- Tab button: same plate skin as the gold buttons; the active tab glows.
local function makeTab(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  local plate = UI.Plate(b, h)
  local label = FLT.NewFS(b, nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("CENTER", 0, 0); label:SetText(text)
  do local font, _, flags = label:GetFont(); if font then label:SetFont(font, 13, flags) end end
  label:SetTextColor(FLT.SkinC(0.96, 0.85, 0.58))
  b._label = label
  function b:SetActive(on)
    plate:SetActive(on)
    if on then label:SetTextColor(FLT.SkinC(1, 0.93, 0.66)) else label:SetTextColor(FLT.SkinC(0.96, 0.85, 0.58)) end
  end
  b:SetScript("OnMouseDown", function() label:SetPoint("CENTER", 1, -1) end)
  b:SetScript("OnMouseUp", function() label:SetPoint("CENTER", 0, 0) end)
  return b
end

-- Ornate gold window frame (Assets\window_frame) drawn over the template's
-- border; the template's own border is hidden.
local function decorateWindow()
  if type(frame.NineSlice) == "table" then frame.NineSlice:SetAlpha(0) end
  for _, k in ipairs({ "TopLeftCorner", "TopRightCorner", "BotLeftCorner", "BotRightCorner", "TopBorder", "BottomBorder", "LeftBorder", "RightBorder" }) do
    if type(frame[k]) == "table" and frame[k].SetAlpha then frame[k]:SetAlpha(0) end
  end
  -- own opaque title bar (the template's bar leaves a see-through strip)
  if type(frame.TitleBg) == "table" and frame.TitleBg.SetAlpha then frame.TitleBg:SetAlpha(0) end
  local bar = frame:CreateTexture(nil, "BORDER", nil, 1)
  bar:SetPoint("TOPLEFT", 3, -3); bar:SetPoint("TOPRIGHT", -3, -3); bar:SetHeight(25)
  bar:SetColorTexture(FLT.SkinC(0.055, 0.047, 0.038, 1))
  local barShine = frame:CreateTexture(nil, "BORDER", nil, 2)
  barShine:SetPoint("TOPLEFT", bar, "TOPLEFT"); barShine:SetPoint("TOPRIGHT", bar, "TOPRIGHT"); barShine:SetHeight(11)
  barShine:SetColorTexture(FLT.SkinC(1, 0.85, 0.45, 0.04))
  local barLine = frame:CreateTexture(nil, "BORDER", nil, 3)
  barLine:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 6, 0); barLine:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -6, 0); barLine:SetHeight(1)
  barLine:SetColorTexture(FLT.SkinC(0.72, 0.50, 0.12, 0.75))
  local deco = CreateFrame("Frame", nil, frame)
  deco:SetAllPoints()
  deco:SetFrameLevel(frame:GetFrameLevel() + 18)
  UI.OrnateFrame(deco, frame, 34, 7, "OVERLAY", 0, UI.ASSET_ROOT .. "window_frame")
  -- the gold top edge covers the template's title position: move the title down
  if type(frame.TitleText) == "table" and frame.TitleText.ClearAllPoints then
    frame.TitleText:ClearAllPoints(); frame.TitleText:SetPoint("TOP", frame, "TOP", 0, -10)
  end
  -- own close button in the gold plate style, centred in the title bar left
  -- of the ornate corner (the template's red button is hidden)
  if type(frame.CloseButton) == "table" and frame.CloseButton.Hide then frame.CloseButton:Hide() end
  local close = UI.GoldButton(frame, "", 24, 20, UI.ASSET_ROOT .. "icon_close", 11)
  close:SetPoint("CENTER", frame, "TOPRIGHT", -44, -15)
  close:SetFrameLevel(frame:GetFrameLevel() + 25)
  if close.icon then close.icon:ClearAllPoints(); close.icon:SetSize(14, 14); close.icon:SetPoint("CENTER", 0, 0) end
  close:SetScript("OnMouseDown", nil); close:SetScript("OnMouseUp", nil)
  close:SetScript("OnClick", function() frame:Hide() end)
  close:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(CLOSE or "Close"); GameTooltip:Show() end)
  close:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- skin switch left of the close button: sun = Gold, moon = Silver
  local silver = FLT.GetSkin() == "silver"
  local skinBtn = UI.GoldButton(frame, "", 24, 20, UI.ASSET_ROOT .. (silver and "icon_moon" or "icon_sun"), 11)
  skinBtn:SetPoint("RIGHT", close, "LEFT", -6, 0)
  skinBtn:SetFrameLevel(frame:GetFrameLevel() + 25)
  if skinBtn.icon then
    skinBtn.icon:ClearAllPoints(); skinBtn.icon:SetSize(14, 14); skinBtn.icon:SetPoint("CENTER", 0, 0)
    if silver then skinBtn.icon:SetVertexColor(0.80, 0.83, 0.88) else skinBtn.icon:SetVertexColor(1, 0.80, 0.30) end
  end
  skinBtn:SetScript("OnMouseDown", nil); skinBtn:SetScript("OnMouseUp", nil)
  skinBtn:SetScript("OnClick", function() UI.AskSkin(silver and "gold" or "silver") end)
  skinBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(silver and "Skin: Dark Silver" or "Skin: Gold")
    GameTooltip:AddLine(silver and "Click to switch to Gold." or "Click to switch to Dark Silver.", 1, 1, 1)
    GameTooltip:Show()
  end)
  skinBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- bug report button left of the skin switch
  local bugBtn = UI.GoldButton(frame, "", 24, 20, UI.ASSET_ROOT .. "icon_bug", 11)
  bugBtn:SetPoint("RIGHT", skinBtn, "LEFT", -6, 0)
  bugBtn:SetFrameLevel(frame:GetFrameLevel() + 25)
  if bugBtn.icon then
    bugBtn.icon:ClearAllPoints(); bugBtn.icon:SetSize(14, 14); bugBtn.icon:SetPoint("CENTER", 0, 0)
    bugBtn.icon:SetVertexColor(FLT.SkinC(1, 0.80, 0.30))
  end
  bugBtn:SetScript("OnMouseDown", nil); bugBtn:SetScript("OnMouseUp", nil)
  bugBtn:SetScript("OnClick", function() UI.ShowBugReport() end)
  bugBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Report a bug")
    GameTooltip:AddLine("Shows the link where you can report bugs and ideas.", 1, 1, 1)
    GameTooltip:Show()
  end)
  bugBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function createUI()
  frame = CreateFrame("Frame", "OneForAllFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(BASE_W, BASE_H)
  frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
  -- Stay above other addons' frames (waypoint arrows, raid frames ...);
  -- drop back while the world map is open so map buttons stay usable.
  frame:SetFrameStrata("DIALOG"); frame:SetToplevel(true)
  if WorldMapFrame and WorldMapFrame.HookScript then
    WorldMapFrame:HookScript("OnShow", function() frame:SetFrameStrata("MEDIUM") end)
    WorldMapFrame:HookScript("OnHide", function() frame:SetFrameStrata("DIALOG") end)
  end
  frame:SetClampedToScreen(true)
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition() end)

  local db = windowDB()
  frame:SetScale(clampScale(db.scale or 1))
  if db.left and db.top then
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.left, db.top)
  else
    frame:SetPoint("CENTER")
  end
  frame:HookScript("OnShow", function() snapToPixels() end)
  decorateWindow()
  createResizeGrip()
  createHeightGrip()
  applyHeight(db.height or BASE_H)
  frame.TitleText:SetText(UI.DISPLAY_NAME .. "  |cffb8b0a0- made by Smoergi|r")
  frame.TitleText:SetTextColor(FLT.SkinC(1, 0.82, 0))

  if frame.Inset and frame.Inset.Bg then frame.Inset.Bg:SetVertexColor(FLT.SkinC(0.11, 0.085, 0.055, 0.98)) end

  -- Close with Escape.
  if UISpecialFrames then
    local found = false
    for _, name in ipairs(UISpecialFrames) do
      if name == frame:GetName() then found = true; break end
    end
    if not found then table.insert(UISpecialFrames, frame:GetName()) end
  end

  -- Tabs sit directly below the title bar, in the order given by each
  -- panel's "order" value. Hidden tabs (General tab settings) are skipped.
  for _, spec in ipairs(UI.panels) do
    local key = spec.key
    local b = makeTab(frame, spec.icon and "" or spec.label, spec.tabWidth or 130, 27)
    if spec.icon then
      local ic = b:CreateTexture(nil, "OVERLAY")
      ic:SetSize(19, 19); ic:SetPoint("CENTER"); FLT.SetTex(ic, spec.icon)
      b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(spec.label); GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    b:SetScript("OnClick", function() setPanelTab(key) end)
    tabButtons[key] = b
  end
  UI.LayoutTabs()

  local tabLine = makeTexture(frame, "ARTWORK", 0.72, 0.50, 0.12, 0.65)
  tabLine:SetPoint("TOPLEFT", 12, -66)
  tabLine:SetPoint("TOPRIGHT", -12, -66)
  tabLine:SetHeight(1)

  setPanelTab("general")
  frame:SetScript("OnShow", function() FLT:Refresh() end)
  frame:Hide()
end

function FLT:UIRefresh()
  -- Bag/bank events fire often; there is nothing to update while the window
  -- is closed. The frame's OnShow handler refreshes it when it is opened.
  if not frame or not frame:IsShown() then return end
  for _, panel in pairs(panels) do
    if panel.Refresh then panel:Refresh() end
  end
end

-- /ofa scale [value]: without a value resets to 100 %; accepts 0.6-1.4 or 60-140.
function UI.ResetWindow() FLT:SetWindowScale(nil) end

function FLT:SetWindowScale(value)
  local s = tonumber(value) or 1
  if s > 5 then s = s / 100 end
  if not frame then createUI() end
  local applied = applyScale(s)
  if not value then
    applyHeight(BASE_H)
    frame:ClearAllPoints(); frame:SetPoint("CENTER"); savePosition()
  else
    applyHeight(frame:GetHeight()) -- keep it on screen at the new scale
  end
  return applied
end

-- Opens the window on a given tab (e.g. "professions", "hunterpets").
function FLT:OpenPanel(key)
  if not frame then createUI() end
  if key and ensurePanel(key) then
    -- a button asked for this tab: show it even if it was hidden in the settings
    if not UI.IsTabVisible(key) then UI.SetTabVisible(key, true) end
    setPanelTab(key)
  end
  frame:Show()
end

function FLT:ToggleUI()
  if not frame then createUI() end
  if frame:IsShown() then frame:Hide(); return end
  -- Inside a dungeon: open straight on that dungeon's bosses & loot.
  local d = FLT.FindCurrentDungeon and FLT.FindCurrentDungeon()
  if d and UI.IsTabVisible("dungeons") and ensurePanel("dungeons") and UI.OpenDungeon then
    setPanelTab("dungeons")
    UI.OpenDungeon(d)
  end
  frame:Show()
end
