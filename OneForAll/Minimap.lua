local _, FLT = ...

local button

local function getAngle(y, x)
  if math.atan2 then return math.atan2(y, x) end
  if atan2 then return atan2(y, x) end
  if x == 0 then
    if y >= 0 then return math.pi / 2 else return -math.pi / 2 end
  end
  local a = math.atan(y / x)
  if x < 0 then a = a + math.pi end
  return a
end

local function positionButton(angle)
  if not button or not Minimap then return end
  angle = angle or 225
  local radius = 80
  local r = math.rad(angle)
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(r) * radius, math.sin(r) * radius)
end

local function stopDragging(self)
  self:SetScript("OnUpdate", nil)
  self.dragging = nil
end

local function updateDragging(self)
  local mx, my = Minimap:GetCenter()
  if not mx or not my then return end

  local scale = UIParent:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  cx, cy = cx / scale, cy / scale

  local angle = math.deg(getAngle(cy - my, cx - mx))
  if angle < 0 then angle = angle + 360 end

  ForeverCompanionDB.minimapAngle = angle
  positionButton(angle)
end

function FLT:CreateMinimapButton()
  if button or not Minimap then return end

  button = CreateFrame("Button", "OneForAllMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 8)
  button:RegisterForClicks("LeftButtonUp")
  button:RegisterForDrag("LeftButton")

  -- Same geometry as LibDBIcon (used by most addons), so the button matches
  -- other minimap buttons and button-collector bars.
  -- MiniMap-TrackingBorder contains transparent padding, so it must be
  -- anchored to the button's TOPLEFT without a manual offset.
  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  background:SetSize(24, 24)
  background:SetPoint("CENTER", 0, 0)

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\AddOns\\OneForAll\\Assets\\minimap_icon")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", 0, 0)
  icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
  button.icon = icon

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(50, 50)
  border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  highlight:SetBlendMode("ADD")
  highlight:SetSize(31, 31)
  highlight:SetPoint("CENTER", 0, 0)

  button:SetScript("OnClick", function()
    if FLT.ToggleUI then FLT:ToggleUI() end
  end)

  button:SetScript("OnDragStart", function(self)
    self.dragging = true
    self:SetScript("OnUpdate", updateDragging)
  end)

  button:SetScript("OnDragStop", stopDragging)
  button:SetScript("OnHide", stopDragging)

  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(FLT.DISPLAY_NAME or "OneForAll", 1, 0.82, 0)
    GameTooltip:AddLine("Left-click: Open / close", 1, 1, 1)
    GameTooltip:AddLine("Drag: Move around the minimap", 0.75, 0.75, 0.75)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)

  positionButton((ForeverCompanionDB and ForeverCompanionDB.minimapAngle) or 225)
  button:Show()
end
