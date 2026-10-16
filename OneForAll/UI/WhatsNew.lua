local _, FLT = ...
local UI = FLT.UI
local makeTexture, makeButton = UI.makeTexture, UI.makeButton

-- "Noteworthy changes" popup. Shown once per account after logging in with a
-- new NEWS_ID (change it for the next release with news). /ofa news reopens it.
-- One popup per minor line (user 16.10.): NEWS_ID "5.6" collects the news of all 5.6.x versions and
-- is shown only to players coming from before 5.6 (whoever saw the 5.6.1 popup does not get it again).

local NEWS_ID = "5.6"

-- image (optional): picture under the lines = { tex, shown width, shown height, texcoord right, texcoord bottom }
-- (made by tools/art/proc_news.py from the user's screenshots in source_images/news)
local NEWS = {
  { icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_04", title = "New look: Modern skins", tab = "settings", button = "Open Settings",
    lines = {
      "Two new skins, Gold Modern and Dark Silver Modern, with plain frames and rounded corners. Pick your skin with the brush button in the title bar or in Settings > Skin.",
      "In the Modern skins the window can be made see-through: Settings > Window > Window opacity. Dark Silver is a little brighter.",
    },
    image = { "news_skins", 234, 147, 1, 0.6289 } },
  { icon = "Interface\\Icons\\INV_Misc_Book_11", title = "Check low spell ranks", tab = "qol", button = "Open Quality of Life",
    lines = {
      "New option in Quality of Life: finds spells on your action bars that still use an older rank than you know and updates them with one click. After a trainer visit it waits until you close the trainer.",
    },
    image = { "news_lowrank", 380, 166, 1, 0.8711 } },
  { icon = "Interface\\Icons\\INV_Misc_Map_01", title = "Map Landmarks", tab = "qol", button = "Open Quality of Life",
    lines = {
      "Icons on the world map for dungeon and raid entrances, flight masters, zeppelins and ships. Click an entrance to open that dungeon in OneForAll; the other icons show where they go.",
      "Quality of Life > World map switches it off or hides single parts.",
    } },
}

local frame

local function addonVersion()
  local v
  if C_AddOns and C_AddOns.GetAddOnMetadata then v = C_AddOns.GetAddOnMetadata("OneForAll", "Version")
  elseif GetAddOnMetadata then v = GetAddOnMetadata("OneForAll", "Version") end
  return v or NEWS_ID
end

local function create()
  local f = CreateFrame("Frame", "OneForAllWhatsNew", UIParent)
  f:SetSize(560, 200); f:SetPoint("CENTER", 0, 60); f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if UISpecialFrames then table.insert(UISpecialFrames, "OneForAllWhatsNew") end -- Esc closes it

  UI.FramedPanel(f)
  for _, t in ipairs(UI.OrnateFrame(f, f, 18, 3, "OVERLAY", 4)) do t:SetVertexColor(FLT.SkinC(1, 1, 1, 1)) end
  local band = makeTexture(f, "BORDER", 0.075, 0.062, 0.040, 0.90); band:SetPoint("TOPLEFT", 3, -3); band:SetPoint("TOPRIGHT", -3, -3); band:SetHeight(50)
  local dv = f:CreateTexture(nil, "ARTWORK"); FLT.SetTex(dv, UI.ASSET_ROOT .. "divider_ornate"); dv:SetHeight(14); dv:SetPoint("TOPLEFT", 6, -46); dv:SetPoint("TOPRIGHT", -6, -46)

  local logo = f:CreateTexture(nil, "OVERLAY"); logo:SetSize(34, 34); logo:SetPoint("TOPLEFT", 12, -8)
  FLT.SetTex(logo, "Interface\\AddOns\\OneForAll\\Assets\\minimap_icon")
  local title = UI.SmallCaps(f, "OneForAll - Noteworthy changes", 19, 15, {1, 0.82, 0.20}, "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 54, -9)
  local ver = FLT.NewFS(f, nil, "OVERLAY", "GameFontDisableSmall"); ver:SetPoint("TOPLEFT", 54, -30)
  ver:SetText("Version " .. addonVersion())

  local close = UI.CloseButton(f); close:SetPoint("TOPRIGHT", -12, -12)

  local _, class = UnitClass and UnitClass("player")
  local y = -70
  for _, entry in ipairs(NEWS) do
    do
      local ic = f:CreateTexture(nil, "ARTWORK"); ic:SetSize(36, 36); ic:SetPoint("TOPLEFT", 16, y)
      FLT.SetTex(ic, entry.icon); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      if ic.AddMaskTexture and f.CreateMaskTexture then
        local m = f:CreateMaskTexture(); FLT.SetTex(m, UI.ASSET_ROOT .. "talent_icon_mask2", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE"); m:SetAllPoints(ic); ic:AddMaskTexture(m)
      end
      local icf = f:CreateTexture(nil, "OVERLAY"); FLT.SetTex(icf, UI.ASSET_ROOT .. "talent_frame"); icf:SetPoint("TOPLEFT", ic, -3, 3); icf:SetPoint("BOTTOMRIGHT", ic, 3, -3); icf:SetVertexColor(FLT.SkinC(0.98, 0.76, 0.30, 1))
      local h = FLT.NewFS(f, nil, "OVERLAY", "GameFontNormal"); h:SetPoint("TOPLEFT", 62, y - 2)
      h:SetText(entry.title .. (entry.note and ("  |cff9d9d9d" .. entry.note .. "|r") or "")); h:SetTextColor(FLT.SkinC(1, 0.82, 0.20))
      -- the button only for characters that have that tab (Hunter Pets: hunters)
      if entry.tab and (not entry.buttonClass or entry.buttonClass == class) then
        local b = UI.GoldButton(f, entry.button, 150, 24, nil, 12); b:SetPoint("TOPRIGHT", -16, y)
        b:SetScript("OnClick", function() f:Hide(); if FLT.OpenPanel then FLT:OpenPanel(entry.tab) end end)
      end
      local ly = y - 24
      for _, line in ipairs(entry.lines) do
        local dot = FLT.NewFS(f, nil, "OVERLAY", "GameFontHighlightSmall"); dot:SetPoint("TOPLEFT", 64, ly); dot:SetText(FLT.SkinHex("d9a63a") .. "•|r")
        local t = FLT.NewFS(f, nil, "OVERLAY", "GameFontHighlightSmall"); t:SetPoint("TOPLEFT", 76, ly)
        t:SetWidth(460); t:SetJustifyH("LEFT"); t:SetText(line); t:SetTextColor(FLT.SkinC(0.90, 0.88, 0.82))
        ly = ly - math.max(16, (t:GetStringHeight() or 12) + 5)
      end
      if entry.image then
        local im = entry.image
        local pic = f:CreateTexture(nil, "ARTWORK"); pic:SetSize(im[2], im[3]); pic:SetPoint("TOPLEFT", 76, ly - 4)
        FLT.SetTex(pic, UI.ASSET_ROOT .. im[1]); pic:SetTexCoord(0, im[4], 0, im[5])
        local pf = CreateFrame("Frame", nil, f); pf:SetAllPoints(pic)
        UI.OrnateFrame(pf, pf, 10, 2, "OVERLAY", 1)
        ly = ly - im[3] - 12
      end
      y = ly - 14
    end
  end

  local foot = FLT.NewFS(f, nil, "OVERLAY", "GameFontDisableSmall"); foot:SetPoint("BOTTOMLEFT", 16, 16)
  foot:SetText("Type /ofa news to show this again.")
  local ok = UI.GoldButton(f, "Got it", 110, 26, nil, 13); ok:SetPoint("BOTTOMRIGHT", -16, 14)
  ok:SetScript("OnClick", function() f:Hide() end)

  f:SetHeight(-y + 40)
  f:Hide()
  return f
end

function FLT.ShowNews()
  if not frame then frame = create() end
  frame:Show()
  if type(OneForAllDB) == "table" then OneForAllDB.newsSeen = NEWS_ID end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  if type(OneForAllDB) ~= "table" then return end
  local seen = OneForAllDB.newsSeen
  if type(seen) == "string" and (seen == NEWS_ID or seen:sub(1, #NEWS_ID + 1) == NEWS_ID .. ".") then return end
  if C_Timer and C_Timer.After then C_Timer.After(6, FLT.ShowNews) else FLT.ShowNews() end
end)
