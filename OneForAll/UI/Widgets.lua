local ADDON, FLT = ...

-- Shared UI building blocks and the panel registry used by every tab.
-- Each tab lives in its own file under UI/ and registers itself with
-- UI.RegisterPanel(); MainFrame.lua builds the window and tab bar from that.
local UI = {}
FLT.UI = UI

UI.DISPLAY_NAME = FLT.DISPLAY_NAME or "OneForAll"
UI.ASSET_ROOT = FLT.ASSET_ROOT or ("Interface\\AddOns\\" .. ADDON .. "\\Assets\\")
local ASSET_ROOT = UI.ASSET_ROOT

-- Skins ----------------------------------------------------------------------
-- "gold" (default) or "silver". The silver skin is applied while the UI is
-- built: gold/bronze colours become silver grey (FLT.SkinC), gold frame art is
-- desaturated (FLT.SetTex) and banner/dungeon pictures are dimmed a little.
-- Item quality, level and status colours are left alone. Needs a /reload.
local function skinIsSilver()
  return type(ForeverCompanionDB) == "table" and ForeverCompanionDB.skin == "silver"
end
FLT.SkinIsSilver = skinIsSilver
function FLT.GetSkin() return skinIsSilver() and "silver" or "gold" end
function FLT.SetSkin(name)
  if type(ForeverCompanionDB) ~= "table" then return end
  ForeverCompanionDB.skin = (name == "silver") and "silver" or nil
end

local SILVER_TINT = { 0.94, 0.97, 1.02 }
local SILVER_GAIN = 0.90 -- brightness of silver compared with the gold it replaces
local SILVER_ART = 0.78  -- brightness of desaturated gold frame art
function FLT.SkinC(r, g, b, ...)
  if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" or not skinIsSilver() then return r, g, b, ... end
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  if mx <= 0.001 or r < mx - 0.0001 then return r, g, b, ... end -- warm colours have red on top
  local d = mx - mn
  if d / mx < 0.15 then return r, g, b, ... end
  local h = ((g - b) / d) * 60
  -- gold, amber and bronze only (not yellow, orange, red)
  if h < 22 or h > 56 or g / r < 0.6 then return r, g, b, ... end
  local L = math.min(1, (0.299 * r + 0.587 * g + 0.114 * b) * SILVER_GAIN)
  return math.min(1, L * SILVER_TINT[1]), math.min(1, L * SILVER_TINT[2]), math.min(1, L * SILVER_TINT[3]), ...
end

-- frame art drawn in gold that is turned silver by desaturating it
local GOLD_ART = {
  ornate_frame=true, window_frame=true, btn_normal=true, btn_active=true, btn_glow=true, rr_ring=true,
  chevron=true, sort_arrows=true, divider_ornate=true, gem_rim=true, thumb_wide_frame=true,
  talent_frame=true, talent_glow=true, frame_ring=true, frame_boss2=true, frame_badge=true, ring_gold=true,
  talent_button_border=true, icon_map=true, icon_back=true, icon_close=true, grip_resize=true, grip_height=true,
  minimap_icon=true, leather=true,
}
-- Pixel snapping: switching it off (beta3/4) made thin gold lines darker and lighter
-- with every pixel of window height. The game's default snapping keeps them crisp,
-- so noSnap does nothing any more (kept as a hook, see DESIGN.md).
local function noSnap(x)
  return x
end
UI.NoSnap = noSnap

-- Small yellow "!" for features that are new since the last live release, with a
-- "New" tooltip. Returns the frame (anchor it yourself).
function UI.NewMark(parent, tip)
  local f = CreateFrame("Frame", nil, parent); f:SetSize(12, 16); f:EnableMouse(true)
  local t = f:CreateTexture(nil, "OVERLAY"); t:SetAllPoints(); t:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
  f:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("New", 1, 0.82, 0)
    GameTooltip:AddLine(tip or "New in this version.", 1, 1, 1, true); GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end
function FLT.SetTex(tex, path, ...)
  tex:SetTexture(path, ...)
  noSnap(tex)
  if type(path) ~= "string" or not tex.SetVertexColor or not skinIsSilver() then return end
  local name = path:match("[Aa]ssets\\(.+)$")
  if not name then return end
  if GOLD_ART[name] or name:match("^emblem_") then
    if tex.SetDesaturated then tex:SetDesaturated(true) end
    tex._ofaSilver = true
    tex:SetVertexColor(SILVER_ART * SILVER_TINT[1], SILVER_ART * SILVER_TINT[2], SILVER_ART * SILVER_TINT[3])
  elseif name:match("_banner$") or name:match("^Dungeons\\") then
    tex:SetVertexColor(0.80, 0.80, 0.83)
  end
end
-- Blizzard template parts (scroll bars, check boxes, input boxes) are drawn
-- in gold too; in the silver skin all their textures are desaturated.
function FLT.SkinBlizz(f)
  if not f or not skinIsSilver() then return f end
  local function walk(o)
    if o.GetRegions then
      for _, r in ipairs({ o:GetRegions() }) do
        if r.SetDesaturated and r.GetObjectType and r:GetObjectType() == "Texture" then r:SetDesaturated(true) end
      end
    end
    if o.GetChildren then for _, c in ipairs({ o:GetChildren() }) do walk(c) end end
  end
  walk(f)
  return f
end
-- a texture that got a gold asset some other way (e.g. SetNormalTexture)
function FLT.SkinArtTex(tex)
  if tex and tex.SetDesaturated and skinIsSilver() then
    tex:SetDesaturated(true); tex._ofaSilver = true
    tex:SetVertexColor(SILVER_ART * SILVER_TINT[1], SILVER_ART * SILVER_TINT[2], SILVER_ART * SILVER_TINT[3])
  end
end
-- inline colour code ("|cffRRGGBB") in the current skin
function FLT.SkinHex(hex)
  if not skinIsSilver() then return "|cff" .. hex end
  local r, g, b = tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
  r, g, b = FLT.SkinC(r, g, b)
  return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
-- keeps silver art grey when code toggles desaturation (disabled looks)
function FLT.Desat(tex, on)
  if tex and tex.SetDesaturated then tex:SetDesaturated((on or tex._ofaSilver) and true or false) end
end
function FLT.NewFS(owner, ...)
  local fs = owner:CreateFontString(...)
  if skinIsSilver() and fs.GetTextColor then
    local r, g, b, a = fs:GetTextColor()
    if r then fs:SetTextColor(FLT.SkinC(r, g, b, a)) end
  end
  return fs
end

local LAYOUT = {
  BOOK_CONTENT_WIDTH = 958,
  DUNGEON_BROWSE_WIDTH = 950,
  DUNGEON_ROW_WIDTH = 930,
  QUEST_LIST_WIDTH = 350,
  QUEST_ROW_WIDTH = 338,
  QUEST_DETAIL_CHILD_WIDTH = 450,
}
UI.LAYOUT = LAYOUT

local function makeTexture(parent, layer, r, g, b, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(FLT.SkinC(r, g, b, a))
  return noSnap(t)
end

local function makeButton(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)

  local bg = makeTexture(b, "BACKGROUND", 0.075, 0.065, 0.050, 0.98)
  bg:SetAllPoints()
  b._bg = bg

  local inner = makeTexture(b, "BORDER", 0.30, 0.22, 0.10, 0.28)
  inner:SetPoint("TOPLEFT", 2, -2)
  inner:SetPoint("BOTTOMRIGHT", -2, 2)
  b._inner = inner

  local function edge(point1, point2, x1, y1, x2, y2, width, height)
    local t = makeTexture(b, "ARTWORK", 0.72, 0.50, 0.16, 0.72)
    t:SetPoint(point1, b, point1, x1, y1)
    t:SetPoint(point2, b, point2, x2, y2)
    if width then t:SetWidth(width) end
    if height then t:SetHeight(height) end
    return t
  end
  edge("TOPLEFT", "TOPRIGHT", 0, 0, 0, 0, nil, 1)
  edge("BOTTOMLEFT", "BOTTOMRIGHT", 0, 0, 0, 0, nil, 1)
  edge("TOPLEFT", "BOTTOMLEFT", 0, 0, 0, 0, 1, nil)
  edge("TOPRIGHT", "BOTTOMRIGHT", 0, 0, 0, 0, 1, nil)

  local highlight = makeTexture(b, "HIGHLIGHT", 0.78, 0.55, 0.18, 0.18)
  highlight:SetPoint("TOPLEFT", 1, -1)
  highlight:SetPoint("BOTTOMRIGHT", -1, 1)
  b:SetHighlightTexture(highlight)

  local label = FLT.NewFS(b, nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("CENTER", 0, 0)
  label:SetText(text)
  label:SetTextColor(FLT.SkinC(0.96, 0.78, 0.34))
  b:SetFontString(label)
  b._label = label

  b:SetScript("OnMouseDown", function(self)
    if self:IsEnabled() then
      self._bg:SetColorTexture(FLT.SkinC(0.11, 0.085, 0.050, 1.00))
      self._label:ClearAllPoints()
      if self._labelLeft then self._label:SetPoint("LEFT", self._labelLeft + 1, -1) else self._label:SetPoint("CENTER", 1, -1) end
    end
  end)
  b:SetScript("OnMouseUp", function(self)
    self._bg:SetColorTexture(FLT.SkinC(0.075, 0.065, 0.050, 0.98))
    self._label:ClearAllPoints()
    if self._labelLeft then self._label:SetPoint("LEFT", self._labelLeft, 0) else self._label:SetPoint("CENTER", 0, 0) end
  end)

  return b
end

local function addDivider(parent, x)
  local line = makeTexture(parent, "ARTWORK", 0.55, 0.42, 0.18, 0.35)
  line:SetPoint("TOPLEFT", x, -2)
  line:SetPoint("BOTTOMLEFT", x, 2)
  line:SetWidth(1)
end


local TAB_BANNERS = {
  general={
    texture=ASSET_ROOT.."general_banner",
  },
  settings={
    texture=ASSET_ROOT.."settings_banner",
  },
  dungeons={
    texture=ASSET_ROOT.."dungeons_banner",
  },
  books={
    texture=ASSET_ROOT.."books_banner",
  },
  professions={
    texture=ASSET_ROOT.."professions_banner",
  },
  talents={
    texture=ASSET_ROOT.."talents_banner",
  },
  pets={
    texture=ASSET_ROOT.."pets_banner",
  },
  qol={
    texture=ASSET_ROOT.."qol_banner",
  },
}

local function createPanelBanner(parent, kind, topOffset, leftInset, rightInset, height)
  local cfg = TAB_BANNERS[kind] or TAB_BANNERS.general
  local banner = CreateFrame("Frame", nil, parent)
  banner:SetPoint("TOPLEFT", leftInset or 8, topOffset or -8)
  banner:SetPoint("TOPRIGHT", rightInset or -8, topOffset or -8)
  banner:SetHeight(height or 56)

  local bg = makeTexture(banner, "BACKGROUND", 0.06, 0.045, 0.025, 0.98)
  bg:SetAllPoints()
  local top = makeTexture(banner, "ARTWORK", 0.72, 0.50, 0.12, 0.62)
  top:SetPoint("TOPLEFT", 0, 0); top:SetPoint("TOPRIGHT", 0, 0); top:SetHeight(1)
  local bottom = makeTexture(banner, "ARTWORK", 0.72, 0.50, 0.12, 0.45)
  bottom:SetPoint("BOTTOMLEFT", 0, 0); bottom:SetPoint("BOTTOMRIGHT", 0, 0); bottom:SetHeight(1)
  local left = makeTexture(banner, "ARTWORK", 0.72, 0.50, 0.12, 0.35)
  left:SetPoint("TOPLEFT", 0, 0); left:SetPoint("BOTTOMLEFT", 0, 0); left:SetWidth(1)
  local right = makeTexture(banner, "ARTWORK", 0.72, 0.50, 0.12, 0.35)
  right:SetPoint("TOPRIGHT", 0, 0); right:SetPoint("BOTTOMRIGHT", 0, 0); right:SetWidth(1)

  if cfg.texture then
    local art = banner:CreateTexture(nil, "ARTWORK")
    art:SetAllPoints()
    FLT.SetTex(art, cfg.texture)
    -- a flatter banner shows the middle strip of the picture (no squashing)
    local f = (height or 56) / 56
    art:SetTexCoord(0, 1, 0.5 - f / 2, 0.5 + f / 2)
    local shade = makeTexture(banner, "OVERLAY", 0.02, 0.02, 0.02, 0.28)
    shade:SetAllPoints()
  end

  return banner
end


-- Art-based building blocks ---------------------------------------------------
-- RoundRect: a rounded rectangle from a 9-sliced white texture (corner radius =
-- c px), tinted with SetVertexColor. Card: border + fill (1 px border).
-- OrnateFrame: the gold panel frame from Assets\ornate_frame (corners c px).
local unpack = unpack or table.unpack
local RR_TEX = ASSET_ROOT .. "rr_fill"
local ORNATE_TEX = ASSET_ROOT .. "ornate_frame"

local function sliceTex(owner, layer, sub, tex, l, r, t, b)
  local x = owner:CreateTexture(nil, layer, nil, sub)
  FLT.SetTex(x, tex); x:SetTexCoord(l, r, t, b)
  return noSnap(x)
end

local function RoundRect(owner, anchor, layer, sub, c, inset, cr, cg, cb, ca)
  anchor = anchor or owner; inset = inset or 0
  local p = {}
  local A, B = 0.25, 0.75
  local tl = sliceTex(owner, layer, sub, RR_TEX, 0, A, 0, A); tl:SetSize(c, c); tl:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset, -inset)
  local tr = sliceTex(owner, layer, sub, RR_TEX, B, 1, 0, A); tr:SetSize(c, c); tr:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -inset, -inset)
  local bl = sliceTex(owner, layer, sub, RR_TEX, 0, A, B, 1); bl:SetSize(c, c); bl:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", inset, inset)
  local br = sliceTex(owner, layer, sub, RR_TEX, B, 1, B, 1); br:SetSize(c, c); br:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -inset, inset)
  local top = sliceTex(owner, layer, sub, RR_TEX, A, B, 0, A); top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  local bot = sliceTex(owner, layer, sub, RR_TEX, A, B, B, 1); bot:SetPoint("TOPLEFT", bl, "TOPRIGHT"); bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  local lef = sliceTex(owner, layer, sub, RR_TEX, 0, A, A, B); lef:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); lef:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
  local rig = sliceTex(owner, layer, sub, RR_TEX, B, 1, A, B); rig:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); rig:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  local mid = sliceTex(owner, layer, sub, RR_TEX, A, B, A, B); mid:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT"); mid:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
  p.pieces = { tl, tr, bl, br, top, bot, lef, rig, mid }
  function p:SetColor(r, g, b, a) for _, t in ipairs(self.pieces) do t:SetVertexColor(FLT.SkinC(r, g, b, a or 1)) end end
  function p:SetShown(v) for _, t in ipairs(self.pieces) do t:SetShown(v) end end
  p:SetColor(cr or 1, cg or 1, cb or 1, ca or 1)
  return p
end

local function Card(owner, anchor, c, border, fill, layer, sub)
  layer = layer or "BACKGROUND"; sub = sub or 0
  local card = {}
  card.border = RoundRect(owner, anchor, layer, sub, c, 0, unpack(border))
  card.fill = RoundRect(owner, anchor, layer, sub + 1, math.max(1, c - 1), 1, unpack(fill))
  function card:SetBorder(r, g, b, a) self.border:SetColor(r, g, b, a) end
  function card:SetFill(r, g, b, a) self.fill:SetColor(r, g, b, a) end
  return card
end

local function OrnateFrame(owner, anchor, c, outset, layer, sub, tex)
  anchor = anchor or owner; outset = outset or 0; layer = layer or "OVERLAY"; sub = sub or 0
  tex = tex or ORNATE_TEX
  local function piece(l, r, t, b) return sliceTex(owner, layer, sub, tex, l, r, t, b) end
  local tl = piece(0, 0.25, 0, 0.5);    tl:SetSize(c, c); tl:SetPoint("TOPLEFT", anchor, "TOPLEFT", -outset, outset)
  local tr = piece(0.25, 0.5, 0, 0.5);  tr:SetSize(c, c); tr:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", outset, outset)
  local bl = piece(0, 0.25, 0.5, 1);    bl:SetSize(c, c); bl:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -outset, -outset)
  local br = piece(0.25, 0.5, 0.5, 1);  br:SetSize(c, c); br:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", outset, -outset)
  local top = piece(0.5, 0.75, 0, 0.5); top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  local bot = piece(0.5, 0.75, 0.5, 1); bot:SetPoint("TOPLEFT", bl, "TOPRIGHT"); bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  local lef = piece(0.75, 1, 0, 0.5);   lef:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); lef:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
  local rig = piece(0.75, 1, 0.5, 1);   rig:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); rig:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  return { tl, tr, bl, br, top, bot, lef, rig }
end

-- Nine: 9-sliced texture (64x64 file, 16 px corners) drawn around anchor,
-- grown by "out" px on every side (room for a glow baked into the texture).
local function Nine(owner, anchor, tex, c, out, layer, sub)
  local A, B = 0.25, 0.75
  local function piece(l, r, t, b) return sliceTex(owner, layer, sub, tex, l, r, t, b) end
  local tl = piece(0, A, 0, A); tl:SetSize(c, c); tl:SetPoint("TOPLEFT", anchor, "TOPLEFT", -out, out)
  local tr = piece(B, 1, 0, A); tr:SetSize(c, c); tr:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", out, out)
  local bl = piece(0, A, B, 1); bl:SetSize(c, c); bl:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -out, -out)
  local br = piece(B, 1, B, 1); br:SetSize(c, c); br:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", out, -out)
  local top = piece(A, B, 0, A); top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  local bot = piece(A, B, B, 1); bot:SetPoint("TOPLEFT", bl, "TOPRIGHT"); bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  local lef = piece(0, A, A, B); lef:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); lef:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
  local rig = piece(B, 1, A, B); rig:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); rig:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  local mid = piece(A, B, A, B); mid:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT"); mid:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
  local o = { pieces = { tl, tr, bl, br, top, bot, lef, rig, mid } }
  function o:SetShown(v) for _, t in ipairs(self.pieces) do t:SetShown(v) end end
  function o:SetAlpha(a) for _, t in ipairs(self.pieces) do t:SetAlpha(a) end end
  function o:SetDesaturated(v) for _, t in ipairs(self.pieces) do FLT.Desat(t, v) end end
  return o
end

-- Plate: the button/tab skin. Bronze bevel normally, glowing gold bevel with
-- a warm gradient when active, a soft gold glow on hover.
local BTN_NORMAL_TEX, BTN_ACTIVE_TEX = ASSET_ROOT .. "btn_normal", ASSET_ROOT .. "btn_active"
local BTN_GLOW_TEX = ASSET_ROOT .. "btn_glow"
local function Plate(b, h)
  local c = math.min(11, math.floor(h * 0.42))
  local glow = Nine(b, b, BTN_GLOW_TEX, c, math.floor(10 * c / 16 + 0.5), "BACKGROUND", -1); glow:SetShown(false)
  local normal = Nine(b, b, BTN_NORMAL_TEX, c, 0, "BACKGROUND", 0)
  local active = Nine(b, b, BTN_ACTIVE_TEX, c, 0, "BACKGROUND", 1); active:SetShown(false)
  local hover = Nine(b, b, BTN_ACTIVE_TEX, c, 0, "HIGHLIGHT", 0); hover:SetAlpha(0.28)
  local p = {}
  function p:SetActive(on)
    on = on and true or false
    active:SetShown(on); glow:SetShown(on); normal:SetShown(not on)
  end
  function p:SetEnabledLook(on)
    normal:SetDesaturated(not on); normal:SetAlpha(on and 1 or 0.6); hover:SetShown(on and true or false)
  end
  return p
end

-- GoldButton: plate button with optional icon. b:SetActive(on) for toggles.
local function GoldButton(parent, text, w, h, icon, fontSize)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  local plate = Plate(b, h)
  local label = FLT.NewFS(b, nil, "OVERLAY", "GameFontNormal")
  do local font, _, flags = label:GetFont(); if font then label:SetFont(font, fontSize or 12, flags) end end
  label:SetText(text); label:SetTextColor(FLT.SkinC(0.95, 0.82, 0.50))
  local function place(dx, dy)
    label:ClearAllPoints()
    if b.icon then
      local tw = (label:GetStringWidth() or 0) + (b.icon:GetWidth() or 14) + 5
      b.icon:ClearAllPoints(); b.icon:SetPoint("LEFT", b, "CENTER", -tw / 2 + dx, dy)
      label:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
    else
      label:SetPoint("CENTER", dx, dy)
    end
  end
  if icon then
    local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(h - 8, h - 8); FLT.SetTex(ic, icon)
    b.icon = ic
  end
  place(0, 0)
  b._label, b.plate = label, plate
  function b:SetActive(on)
    plate:SetActive(on)
    if on then label:SetTextColor(FLT.SkinC(1, 0.93, 0.66)) else label:SetTextColor(FLT.SkinC(0.95, 0.82, 0.50)) end
  end
  function b:SetLook(enabled)
    plate:SetEnabledLook(enabled)
    if enabled then label:SetTextColor(FLT.SkinC(0.95, 0.82, 0.50)) else label:SetTextColor(FLT.SkinC(0.5, 0.5, 0.5)) end
    if b.icon then FLT.Desat(b.icon, not enabled); b.icon:SetAlpha(enabled and 1 or 0.5) end
  end
  function b:SetLabel(t) label:SetText(t); place(0, 0) end
  b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then place(1, -1) end end)
  b:SetScript("OnMouseUp", function() place(0, 0) end)
  return b
end

UI.Nine = Nine
UI.Plate = Plate

-- Shared page layout --------------------------------------------------------
-- Panels sit PANEL_INSET px inside the window on both sides; page content is
-- CONTENT_W wide starting at x=8, so the margin to the gold frame is the same
-- left and right. List scroll bars go into the right margin (PlaceScrollBar).
UI.PANEL_INSET = 18
UI.CONTENT_W = 988
UI.GOLD = {1, 0.82, 0.20}
UI.HEAD_GOLD = {0.90, 0.74, 0.42}

function UI.PlacePanel(panel, parent)
  panel:SetPoint("TOPLEFT", UI.PANEL_INSET, -76)
  panel:SetPoint("BOTTOMRIGHT", -UI.PANEL_INSET, 15)
end

-- Moves a UIPanelScrollFrameTemplate bar into the right page margin and
-- hides it while there is nothing to scroll.
function UI.PlaceScrollBar(sf)
  local bar = sf.ScrollBar
  if type(bar) ~= "table" or not bar.ClearAllPoints then return end
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 1, -16)
  bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 1, 16)
  local function upd() bar:SetShown((sf:GetVerticalScrollRange() or 0) > 0.5) end
  sf:HookScript("OnScrollRangeChanged", upd)
  sf:HookScript("OnShow", upd)
  upd()
end

-- Hides a UIPanelScrollFrameTemplate bar while there is nothing to scroll
-- (also after the window was resized); the bar keeps its place.
function UI.AutoHideScrollBar(sf)
  local bar = sf and sf.ScrollBar
  if type(bar) ~= "table" or not bar.SetShown then return end
  local function upd() bar:SetShown((sf:GetVerticalScrollRange() or 0) > 0.5) end
  sf:HookScript("OnScrollRangeChanged", upd)
  sf:HookScript("OnSizeChanged", upd)
  sf:HookScript("OnShow", upd)
  upd()
end

-- "Small caps": first letter of every word larger, the rest in capitals.
function UI.SmallCaps(parent, text, big, small, color, template)
  local holder = CreateFrame("Frame", nil, parent)
  local prev, total, gap = nil, 0, math.floor(small * 0.35 + 0.5)
  local function add(str, size, spacing)
    local fs = FLT.NewFS(holder, nil, "OVERLAY", template or "GameFontNormal")
    local font, _, flags = fs:GetFont(); if font then fs:SetFont(font, size, flags) end
    fs:SetText(str); fs:SetTextColor(FLT.SkinC(unpack(color)))
    -- common baseline: a font string's box includes room for descenders that
    -- grows with the font size, so bigger letters are moved down accordingly
    total = total + spacing
    fs:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", total, -math.floor(size * 0.22 + 0.5) + math.floor(small * 0.22 + 0.5))
    total = total + (fs:GetStringWidth() or 0); prev = fs
  end
  local first = true
  for word in tostring(text):gmatch("%S+") do
    add(word:sub(1, 1):upper(), big, first and 0 or gap)
    if #word > 1 then add(word:sub(2):upper(), small, 0) end
    first = false
  end
  holder:SetSize(math.max(1, total), big + 2)
  return holder
end

-- Title band at the top of a page: emblem, small-caps title, subtitle and
-- the tab's banner art, faded out behind the title (left) and the right end.
-- opts = { emblem=, title=, subtitle=, art=, width= }
function UI.TitleBand(parent, opts)
  local w = opts.width or UI.CONTENT_W
  local band = CreateFrame("Frame", nil, parent); band:SetPoint("TOPLEFT", 8, -8); band:SetSize(w, 58)
  local bg = makeTexture(band, "BACKGROUND", 0.045, 0.045, 0.058, 0.96); bg:SetPoint("TOPLEFT", 2, -2); bg:SetPoint("BOTTOMRIGHT", -2, 2)
  if opts.art then
    local art = band:CreateTexture(nil, "BORDER", nil, 0); art:SetPoint("TOPLEFT", 2, -2); art:SetPoint("BOTTOMRIGHT", -2, 2)
    FLT.SetTex(art, opts.art)
    if opts.mirror then art:SetTexCoord(1, 0, 0.18, 0.82) else art:SetTexCoord(0, 1, 0.18, 0.82) end
    local shadeL = makeTexture(band, "BORDER", 0.045, 0.045, 0.058, 0.94); shadeL:SetDrawLayer("BORDER", 1)
    shadeL:SetPoint("TOPLEFT", 2, -2); shadeL:SetPoint("BOTTOMLEFT", 2, 2); shadeL:SetWidth(opts.solid or 360)
    local fadeL = band:CreateTexture(nil, "BORDER", nil, 1); FLT.SetTex(fadeL, ASSET_ROOT .. "shade_lr"); fadeL:SetVertexColor(FLT.SkinC(0.18, 0.18, 0.23))
    fadeL:SetPoint("TOPLEFT", shadeL, "TOPRIGHT"); fadeL:SetPoint("BOTTOMLEFT", shadeL, "BOTTOMRIGHT"); fadeL:SetWidth(340)
    local fadeR = band:CreateTexture(nil, "BORDER", nil, 1); FLT.SetTex(fadeR, ASSET_ROOT .. "shade_lr"); fadeR:SetTexCoord(1, 0, 0, 1); fadeR:SetVertexColor(FLT.SkinC(0.18, 0.18, 0.23))
    fadeR:SetPoint("TOPRIGHT", -2, -2); fadeR:SetPoint("BOTTOMRIGHT", -2, 2); fadeR:SetWidth(opts.fadeRight or 300)
  end
  OrnateFrame(band, band, 15, 2, "OVERLAY", 1)
  if opts.emblem then
    local e = band:CreateTexture(nil, "ARTWORK"); e:SetSize(46, 46); e:SetPoint("LEFT", 10, 0); FLT.SetTex(e, opts.emblem)
  end
  local title = UI.SmallCaps(band, opts.title or "", 19, 15, UI.GOLD, "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 66, -9)
  local sub = FLT.NewFS(band, nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", 67, -34); sub:SetText(opts.subtitle or ""); sub:SetTextColor(FLT.SkinC(0.80, 0.77, 0.70))
  band.subtitle = sub
  return band
end

-- Column header strip: small caps, separators. cols = { {x=,w=,text=,justify=} }
function UI.ColumnHeader(parent, cols, width, y)
  local h = CreateFrame("Frame", nil, parent); h:SetPoint("TOPLEFT", 8, y); h:SetSize(width or UI.CONTENT_W, 24)
  local bg = makeTexture(h, "BACKGROUND", 0.075, 0.062, 0.040, 0.96); bg:SetPoint("TOPLEFT", 2, -2); bg:SetPoint("BOTTOMRIGHT", -2, 2)
  OrnateFrame(h, h, 10, 1, "OVERLAY", 1)
  for i, c in ipairs(cols) do
    local holder = CreateFrame("Frame", nil, h); holder:SetPoint("LEFT", c.x, 0); holder:SetSize(c.w or 100, 22)
    local label = UI.SmallCaps(holder, c.text, 12, 9, UI.HEAD_GOLD)
    if c.justify == "CENTER" then label:SetPoint("LEFT", holder, "CENTER", -math.floor(label:GetWidth() / 2), 0)
    else label:SetPoint("LEFT", 10, 0) end
    if i > 1 then
      local sep = makeTexture(h, "ARTWORK", 0.72, 0.50, 0.12, 0.45); sep:SetPoint("LEFT", c.x - 2, 0); sep:SetSize(1, 14)
    end
  end
  return h
end

-- Collapsible section band (landscape silhouette, chevron box, title, info)
-- plus the framed box below it that holds the rows.
-- Returns section = { header=, box=, chevron=, info=, title=, SetCollapsed(on) }
function UI.SectionBand(parent, label, strip, width, onToggle)
  width = width or UI.CONTENT_W
  local holder = CreateFrame("Button", nil, parent); holder:SetSize(width, 34)
  local base = makeTexture(holder, "BACKGROUND", 0.05, 0.05, 0.065, 0.98); base:SetPoint("TOPLEFT", 2, -2); base:SetPoint("BOTTOMRIGHT", -2, 2)
  local sil = holder:CreateTexture(nil, "BORDER"); sil:SetPoint("TOPLEFT", 2, -2); sil:SetPoint("BOTTOMRIGHT", -2, 2)
  strip = (strip or 0) % 3
  FLT.SetTex(sil, ASSET_ROOT .. "band_silhouettes"); sil:SetTexCoord(0, 1, strip * 0.25, strip * 0.25 + 0.25); sil:SetAlpha(0.85)
  local cbox = CreateFrame("Frame", nil, holder); cbox:SetSize(22, 22); cbox:SetPoint("LEFT", 12, 0)
  Card(cbox, cbox, 4, {0.80, 0.60, 0.24, 0.95}, {0.06, 0.05, 0.04, 0.95}, "BACKGROUND", 0)
  local chevron = cbox:CreateTexture(nil, "OVERLAY"); chevron:SetSize(15, 15); chevron:SetPoint("CENTER", 0, 0); FLT.SetTex(chevron, ASSET_ROOT .. "chevron")
  local title = FLT.NewFS(holder, nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("LEFT", 46, 0); title:SetText(label); title:SetTextColor(FLT.SkinC(unpack(UI.GOLD)))
  do local font, _, flags = title:GetFont(); if font then title:SetFont(font, 14, flags) end end
  local info = FLT.NewFS(holder, nil, "OVERLAY", "GameFontHighlightSmall"); info:SetPoint("RIGHT", -20, 0); info:SetJustifyH("RIGHT"); info:SetTextColor(FLT.SkinC(0.85, 0.82, 0.74))
  OrnateFrame(holder, holder, 13, 2, "OVERLAY", 1)
  local hhi = makeTexture(holder, "HIGHLIGHT", 0.80, 0.58, 0.18, 0.10); hhi:SetPoint("TOPLEFT", 2, -2); hhi:SetPoint("BOTTOMRIGHT", -2, 2)
  local box = CreateFrame("Frame", nil, parent); box:SetWidth(width)
  local bfill = makeTexture(box, "BACKGROUND", 0.035, 0.038, 0.048, 0.92); bfill:SetPoint("TOPLEFT", 2, -2); bfill:SetPoint("BOTTOMRIGHT", -2, 2)
  OrnateFrame(box, box, 10, 1, "BORDER", 0)
  local section = { header = holder, box = box, chevron = chevron, info = info, title = title }
  function section:SetCollapsed(on)
    if on then chevron:SetTexCoord(0.5, 1, 0, 1) else chevron:SetTexCoord(0, 0.5, 0, 1) end
  end
  holder:SetScript("OnClick", function() if onToggle then onToggle() end end)
  section:SetCollapsed(false)
  return section
end

-- Gold edge that shows while the mouse is over a button (HIGHLIGHT layer,
-- so it needs no OnEnter/OnLeave scripts and cannot get stuck).
function UI.HoverEdge(b)
  local ring = Nine(b, b, ASSET_ROOT .. "rr_ring", 4, 0, "HIGHLIGHT", 1)
  return ring
end

-- Dark panel with leather grain and a bronze ornate frame.
function UI.FramedPanel(f, inset)
  inset = inset or 2
  local bg = makeTexture(f, "BACKGROUND", 0.040, 0.040, 0.050, 0.95); bg:SetPoint("TOPLEFT", inset, -inset); bg:SetPoint("BOTTOMRIGHT", -inset, inset)
  local lea = f:CreateTexture(nil, "BACKGROUND", nil, 1); lea:SetPoint("TOPLEFT", inset, -inset); lea:SetPoint("BOTTOMRIGHT", -inset, inset)
  FLT.SetTex(lea, ASSET_ROOT .. "leather"); lea:SetVertexColor(FLT.SkinC(0.55, 0.50, 0.46)); lea:SetAlpha(0.55)
  for _, t in ipairs(OrnateFrame(f, f, 12, 1, "OVERLAY", 3)) do t:SetVertexColor(FLT.SkinC(0.62, 0.52, 0.40, 0.9)) end
end

-- Left-aligned navigation button (plate skin, icon, label); b:SetActive(on).
function UI.NavButton(parent, text, w, h, icon)
  local b = CreateFrame("Button", nil, parent); b:SetSize(w, h)
  local plate = Plate(b, h)
  local ic
  if icon then ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(h - 9, h - 9); ic:SetPoint("LEFT", 7, 0); FLT.SetTex(ic, icon) end
  local label = FLT.NewFS(b, nil, "OVERLAY", "GameFontNormal")
  do local font, _, flags = label:GetFont(); if font then label:SetFont(font, 12, flags) end end
  label:SetPoint("LEFT", icon and (h + 2) or 10, 0); label:SetJustifyH("LEFT"); label:SetText(text); label:SetTextColor(FLT.SkinC(0.95, 0.82, 0.50))
  b._label, b.icon = label, ic
  function b:SetActive(on)
    plate:SetActive(on)
    if on then label:SetTextColor(FLT.SkinC(1, 0.93, 0.66)) else label:SetTextColor(FLT.SkinC(0.95, 0.82, 0.50)) end
  end
  return b
end

-- Rounded card for a row/tile with a gold hover ring; returns the card.
function UI.CardRow(b, fill, border)
  local card = Card(b, b, 4, border or {0.28, 0.25, 0.20, 0.90}, fill or {0.060, 0.062, 0.074, 0.97}, "BACKGROUND", 0)
  local hi = b:CreateTexture(nil, "HIGHLIGHT"); hi:SetPoint("TOPLEFT", 1, -1); hi:SetPoint("BOTTOMRIGHT", -1, 1); hi:SetColorTexture(FLT.SkinC(0.90, 0.66, 0.22, 0.07))
  UI.HoverEdge(b)
  -- selection: gold border + warm fill
  function card:SetSelected(on, nfill)
    if on then self:SetBorder(1, 0.80, 0.34, 1); self:SetFill(0.22, 0.155, 0.055, 0.98)
    else self:SetBorder(unpack(border or {0.28, 0.25, 0.20, 0.90})); self:SetFill(unpack(nfill or fill or {0.060, 0.062, 0.074, 0.97})) end
  end
  return card
end

-- Section title with the ornate divider below it.
function UI.SectionTitle(parent, text, x, y, right)
  local t = FLT.NewFS(parent, nil, "OVERLAY", "GameFontNormal"); t:SetPoint("TOPLEFT", x, y); t:SetText(text); t:SetTextColor(FLT.SkinC(unpack(UI.GOLD)))
  do local font, _, flags = t:GetFont(); if font then t:SetFont(font, 14, flags) end end
  local dv = parent:CreateTexture(nil, "ARTWORK"); FLT.SetTex(dv, ASSET_ROOT .. "divider_ornate"); dv:SetHeight(14)
  dv:SetPoint("TOPLEFT", t, "BOTTOMLEFT", -4, -1); dv:SetPoint("RIGHT", parent, "RIGHT", right or -20, 0)
  t.divider = dv
  return t
end

-- Small gem marker (tinted stone in a gold rim). Returns a frame with
-- :SetColor(r,g,b) and the usual Show/Hide/SetShown.
UI.KNOW_COLORS = { me = {0.92, 0.78, 0.35}, guild = {0.45, 0.85, 0.45}, other = {0.45, 0.68, 0.92} }
function UI.Gem(parent, size, r, g, b)
  local f = CreateFrame("Frame", nil, parent); f:SetSize(size, size)
  local fill = f:CreateTexture(nil, "ARTWORK", nil, 1); fill:SetAllPoints(); FLT.SetTex(fill, ASSET_ROOT .. "gem_fill")
  local rim = f:CreateTexture(nil, "ARTWORK", nil, 2); rim:SetAllPoints(); FLT.SetTex(rim, ASSET_ROOT .. "gem_rim")
  function f:SetColor(cr, cg, cb) fill:SetVertexColor(FLT.SkinC(cr, cg, cb)) end
  if r then f:SetColor(r, g, b) end
  return f
end

-- Small confirmation popup: UI.Confirm(text, onYes[, yesLabel[, secureMacro]]).
-- With secureMacro the Yes button runs that macro (e.g. "/reload", which an
-- addon may not call directly) through a secure button; onYes runs first.
local confirmFrame
function UI.Confirm(text, onYes, yesLabel, secureMacro)
  if not confirmFrame then
    local f = CreateFrame("Frame", "OneForAllConfirm", UIParent)
    f:SetSize(380, 130); f:SetPoint("CENTER", 0, 80); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:EnableMouse(true)
    UI.FramedPanel(f)
    for _, t in ipairs(OrnateFrame(f, f, 16, 3, "OVERLAY", 4)) do t:SetVertexColor(FLT.SkinC(1, 1, 1, 1)) end
    f.text = FLT.NewFS(f, nil, "OVERLAY", "GameFontHighlight"); f.text:SetPoint("TOP", 0, -24); f.text:SetWidth(330); f.text:SetJustifyH("CENTER")
    f.yes = GoldButton(f, "Yes", 110, 26, nil, 13); f.yes:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -8, 18)
    f.no = GoldButton(f, "Cancel", 110, 26, nil, 13); f.no:SetPoint("BOTTOMLEFT", f, "BOTTOM", 8, 18)
    f.no:SetScript("OnClick", function() f:Hide() end)
    -- the secure twin of the Yes button is made on first use (out of combat)
    f:SetScript("OnHide", function()
      if f.secureYes and not (InCombatLockdown and InCombatLockdown()) then f.secureYes:Hide(); f.yes:SetAlpha(1) end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "OneForAllConfirm") end
    confirmFrame = f
  end
  local f = confirmFrame
  f.text:SetText(text); f.yes:SetLabel(yesLabel or "Yes")
  f:SetHeight(math.max(120, (f.text:GetStringHeight() or 14) + 84))
  f.yes:SetScript("OnClick", function() f:Hide(); if onYes then onYes() end end)
  local combat = InCombatLockdown and InCombatLockdown()
  if secureMacro and not combat and not f.secureYes then
    local sy = CreateFrame("Button", "OneForAllConfirmSecure", f, "SecureActionButtonTemplate")
    sy:SetAllPoints(f.yes); sy:SetFrameLevel(f.yes:GetFrameLevel() + 5)
    sy:RegisterForClicks("AnyUp", "AnyDown")
    sy:SetAttribute("type", "macro")
    UI.Plate(sy, 26)
    sy.label = FLT.NewFS(sy, nil, "OVERLAY", "GameFontNormal"); sy.label:SetPoint("CENTER")
    do local font, _, flags = sy.label:GetFont(); if font then sy.label:SetFont(font, 13, flags) end end
    sy.label:SetTextColor(FLT.SkinC(0.95, 0.82, 0.50))
    sy:Hide()
    f.secureYes = sy
  end
  local sy = f.secureYes
  if sy then
    if combat then
      if sy:IsShown() then return end -- cannot swap the secure button in combat
    elseif secureMacro then
      sy:SetAttribute("macrotext", secureMacro)
      sy.label:SetText(yesLabel or "Yes")
      sy:SetScript("PreClick", function() if onYes then onYes() end end)
      sy:Show(); f.yes:SetAlpha(0)
    else
      sy:Hide(); f.yes:SetAlpha(1)
    end
  end
  f:Show()
end

-- Bug report window: the GitHub issues link of the public repo in a box that
-- can be copied (WoW cannot open a browser), plus version / class / level.
UI.ISSUES_URL = "https://github.com/smoergi/OneForAll_Forever/issues"
local bugFrame
function UI.ShowBugReport()
  if not bugFrame then
    local f = CreateFrame("Frame", "OneForAllBugReport", UIParent)
    f:SetSize(420, 196); f:SetPoint("CENTER", 0, 80); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:EnableMouse(true)
    UI.FramedPanel(f)
    for _, t in ipairs(OrnateFrame(f, f, 16, 3, "OVERLAY", 4)) do t:SetVertexColor(FLT.SkinC(1, 1, 1, 1)) end
    local title = FLT.NewFS(f, nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOP", 0, -20)
    title:SetText("Report a bug or idea"); title:SetTextColor(FLT.SkinC(1, 0.82, 0.20))
    local text = FLT.NewFS(f, nil, "OVERLAY", "GameFontHighlightSmall"); text:SetPoint("TOP", 0, -46); text:SetWidth(370)
    text:SetJustifyH("CENTER")
    text:SetText("Copy the link (Ctrl+C) and open it in your browser. A screenshot and your addon version help a lot.")
    local box = FLT.SkinBlizz(CreateFrame("EditBox", nil, f, "InputBoxTemplate"))
    box:SetSize(350, 22); box:SetPoint("TOP", 0, -84); box:SetAutoFocus(false); box:SetFontObject("GameFontHighlightSmall")
    -- read only: any typing puts the link back, a click selects it all
    local function reset(b) b:SetText(UI.ISSUES_URL); b:HighlightText(); b:SetCursorPosition(0) end
    box:SetScript("OnTextChanged", function(b, user) if user then reset(b) end end)
    box:SetScript("OnEditFocusGained", function(b) b:HighlightText() end)
    box:SetScript("OnMouseUp", function(b) b:SetFocus(); b:HighlightText() end)
    box:SetScript("OnEscapePressed", function() f:Hide() end)
    f.box = box
    f.info = FLT.NewFS(f, nil, "OVERLAY", "GameFontDisableSmall"); f.info:SetPoint("TOP", 0, -116); f.info:SetWidth(370); f.info:SetJustifyH("CENTER")
    local ok = GoldButton(f, "Close", 110, 26, nil, 13); ok:SetPoint("BOTTOM", 0, 18)
    ok:SetScript("OnClick", function() f:Hide() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "OneForAllBugReport") end
    bugFrame = f
  end
  local f = bugFrame
  local ver
  if C_AddOns and C_AddOns.GetAddOnMetadata then ver = C_AddOns.GetAddOnMetadata(ADDON, "Version")
  elseif GetAddOnMetadata then ver = GetAddOnMetadata(ADDON, "Version") end
  local class = UnitClass and UnitClass("player")
  local level = UnitLevel and UnitLevel("player")
  f.info:SetText(string.format("OneForAll %s  |  %s  |  Level %s", tostring(ver or "?"), tostring(class or "?"), tostring(level or "?")))
  f.box:SetText(UI.ISSUES_URL)
  f:Show()
  f.box:SetFocus(); f.box:HighlightText()
end

-- Asks before switching the skin; the Reload button runs /reload securely.
function UI.AskSkin(key)
  key = (key == "silver") and "silver" or "gold"
  if FLT.GetSkin() == key then return end
  if InCombatLockdown and InCombatLockdown() then
    if FLT.Msg then FLT.Msg("The skin can be changed after combat.") end
    return
  end
  local label = key == "silver" and "Dark Silver" or "Gold"
  UI.Confirm("Switch to the " .. label .. " skin?\nYour interface will reload.", function() FLT.SetSkin(key) end, "Reload", "/reload")
end

UI.GoldButton = GoldButton
UI.RoundRect = RoundRect
UI.Card = Card
UI.OrnateFrame = OrnateFrame
UI.makeTexture = makeTexture
UI.makeButton = makeButton
UI.addDivider = addDivider
UI.createPanelBanner = createPanelBanner

-- Panel registry ------------------------------------------------------------
-- spec = { key=, label=, order=, tabWidth=, create=function(parent) return frame end }
-- A panel may define panel:Refresh(), which runs whenever the window refreshes.
UI.panels = {}
function UI.RegisterPanel(spec)
  UI.panels[#UI.panels + 1] = spec
  table.sort(UI.panels, function(a, b) return (a.order or 99) < (b.order or 99) end)
end
