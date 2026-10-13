local ADDON, FLT = ...
local UI = FLT.UI
local makeTexture = UI.makeTexture
local createPanelBanner = UI.createPanelBanner
local DISPLAY_NAME = UI.DISPLAY_NAME

local function createGeneralPanel(parent)
  local panel = CreateFrame("Frame", nil, parent)
  UI.PlacePanel(panel, parent)
  local W = UI.CONTENT_W

  local version = "?"
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or version
  elseif GetAddOnMetadata then
    version = GetAddOnMetadata(ADDON, "Version") or version
  end

  local band = UI.TitleBand(panel, { emblem = UI.ASSET_ROOT .. "minimap_icon", art = UI.ASSET_ROOT .. "general_banner",
    title = "About " .. DISPLAY_NAME, subtitle = "An all-in-one reference and tracker for the systems introduced or changed in WoW Forever.", fadeRight = 260 })
  local v = FLT.NewFS(band, nil, "OVERLAY", "GameFontHighlightSmall")
  v:SetPoint("RIGHT", -18, 0); v:SetText("Version " .. version .. "  |  WoW Forever beta"); v:SetTextColor(FLT.SkinC(0.75, 0.88, 1))

  -- Beta notice
  local warning = CreateFrame("Frame", nil, panel)
  warning:SetPoint("TOPLEFT", 8, -76); warning:SetSize(W, 72)
  UI.FramedPanel(warning)
  local wic = warning:CreateTexture(nil, "ARTWORK"); wic:SetSize(34, 34); wic:SetPoint("LEFT", 14, 0); FLT.SetTex(wic, "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
  local wt = UI.SmallCaps(warning, "Beta notice", 15, 11, {1, 0.72, 0.16}); wt:SetPoint("TOPLEFT", 60, -10)
  local wb = FLT.NewFS(warning, nil, "OVERLAY", "GameFontHighlightSmall")
  wb:SetPoint("TOPLEFT", 60, -30); wb:SetWidth(W - 80); wb:SetJustifyH("LEFT")
  wb:SetText("WoW Forever is still in active beta, so quests, rewards, item stats, locations, profession costs and dungeon loot can change at any time. Treat the data as a practical guide, not as a final database.")
  wb:SetTextColor(FLT.SkinC(0.92, 0.86, 0.72))

  -- Modules: one card per tab, click to open it
  local mt = UI.SectionTitle(panel, "Modules", 10, -160, -10)
  local modules = {
    {"Dungeons", key="dungeons", emblem="emblem_dungeons", "Bosses, boss-specific loot, recipe drops, dungeon quests and quest chains for all Forever dungeons, grouped by level."},
    {"Library Books", key="books", emblem="emblem_books", "All known library books with bag/bank ownership, turn-ins, map locations and the reward tiers."},
    {"Professions", key="professions", emblem="emblem_professions", "Every recipe with sources and reagents, who in your guild knows it, Merchant's Favor and camping objects."},
    {"Talent Trees", key="talents", emblem="emblem_talents", "Talent planner for every class with prerequisites and two saved presets per class."},
    {"Hunter Pets", key="pets", emblem="emblem_pets", "Pet families, abilities with every rank and where to learn them, and notable rare tames."},
    {"Quality of Life", key="qol", emblem="emblem_qol", "Optional helpers: quick loot, auto repair, junk selling, quest automation, tooltips and more."},
  }
  local y = -190
  for _, m in ipairs(modules) do
    local box = CreateFrame("Button", nil, panel); box:SetPoint("TOPLEFT", 8, y); box:SetSize(W, 48); y = y - 52
    UI.CardRow(box)
    local e = box:CreateTexture(nil, "ARTWORK"); e:SetSize(42, 42); e:SetPoint("LEFT", 8, 0); FLT.SetTex(e, UI.ASSET_ROOT .. m.emblem)
    local h = FLT.NewFS(box, nil, "OVERLAY", "GameFontNormal"); h:SetPoint("LEFT", 60, 0); h:SetText(m[1]); h:SetTextColor(FLT.SkinC(1, 0.82, 0.20))
    do local font, _, flags = h:GetFont(); if font then h:SetFont(font, 15, flags) end end
    local d = FLT.NewFS(box, nil, "OVERLAY", "GameFontHighlightSmall"); d:SetPoint("LEFT", 200, 0); d:SetWidth(W - 230); d:SetJustifyH("LEFT"); d:SetText(m[2]); d:SetTextColor(FLT.SkinC(0.84, 0.81, 0.74))
    local key = m.key
    local function go() if FLT.OpenPanel then FLT:OpenPanel(key) end end
    box:SetScript("OnClick", go)
  end
  local hint = FLT.NewFS(panel, nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 12, y - 4); hint:SetText("Choose which tabs are shown in the Settings (gear icon, top left).")

  local footer = FLT.NewFS(panel, nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", 12, 8)
  footer:SetWidth(W - 20); footer:SetJustifyH("LEFT")
  footer:SetText("If you find changed beta data, an incorrect reward or a missing item, update OneForAll to the newest build before relying on the entry.")
  footer:SetTextColor(FLT.SkinC(0.62, 0.62, 0.62))

  panel:Hide()
  return panel
end


UI.RegisterPanel({ key="general", label="General", order=1, tabWidth=118, create=createGeneralPanel })
