local _, FLT = ...

-- Gear marks (5.6.5, user 18.10.): small signs from the Gear Planner on the game's own frames.
-- - Loot roll window (Need / Greed): a gold star on the item when it is on the wishlist, a green arrow up when it
--   is an upgrade (no % - the tooltip has it; one star / arrow only, so the window does not look crowded).
-- - Bags: a green arrow up on items that are an upgrade you can wear now (the game's bags and Baganator).
-- Both follow the Quality of Life switch "Gear Value" (on by default, user 16.10.).
-- /ofa rolltest opens the real roll window with an example item (the roll functions are faked for that one
-- window and restored when it closes; its buttons do not roll).
-- Lean: bags are only marked when a bag frame updates or is shown (no polling), values come from the Gear Value
-- caches; nothing runs while the switch is off.

local GM = {}
FLT.GearMarks = GM

local ASSET = (FLT.UI and FLT.UI.ASSET_ROOT) or "Interface\\AddOns\\OneForAll\\Assets\\"
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local function on() return FLT.QoL and FLT.QoL.Get("gearValue") and FLT.GearValue end

local function itemID(link) return link and tonumber(link:match("item:(%d+)")) end

-- an upgrade the player can use (and, for the bags, wear at his level now)
local function isUpgrade(id, nowOnly)
  if not id or not on() then return false end
  local _, _, _, loc, _, cid, sub = GetItemInfoInstant(id)
  if not (loc and FLT.GEAR_LOC_SLOTS and FLT.GEAR_LOC_SLOTS[loc]) or not FLT.GearCanUse(loc, cid, sub) then return false end
  if nowOnly then
    local minLevel = select(5, GetItemInfo(id))
    if minLevel and UnitLevel and minLevel > UnitLevel("player") then return false end
  end
  local kind = FLT.GearValue.Change(id)
  return kind == "up" or kind == "new"
end

local function mark(parent, key, file, size, point, x, y, gold)
  local t = parent[key]
  if not t then
    t = parent:CreateTexture(nil, "OVERLAY", nil, 7); t:SetSize(size, size); t:SetPoint(point, x, y)
    FLT.SetTex(t, ASSET .. file)
    if gold then t:SetVertexColor(1, 0.82, 0.25) end
    parent[key] = t
  end
  return t
end

-- Loot roll window --------------------------------------------------------------
local function iconOf(frame)
  return frame.IconFrame or (frame.GetName and frame:GetName() and _G[frame:GetName() .. "IconFrame"])
end
local function decorateRoll(frame)
  local icon = frame and iconOf(frame)
  if not icon then return end
  local id = frame.rollID and GetLootRollItemLink and itemID(GetLootRollItemLink(frame.rollID))
  local wish = on() and id and FLT.IsOnWishlist and FLT.IsOnWishlist(id)
  local up = isUpgrade(id)
  mark(icon, "ofaStar", "icon_star", 18, "TOPLEFT", -6, 6, true):SetShown(wish and true or false)
  mark(icon, "ofaUp", "icon_arrow_up", 18, "BOTTOMRIGHT", 5, -5):SetShown(up)
end

local function rollFrames()
  local list = {}
  for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
    local f = _G["GroupLootFrame" .. i]
    if f then list[#list + 1] = f end
  end
  return list
end

-- Bags ---------------------------------------------------------------------------
local getContainerItemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
local function buttonsOf(frame)
  if frame.EnumerateValidItems then
    local list = {}
    for _, b in frame:EnumerateValidItems() do list[#list + 1] = b end
    return list
  end
  if frame.Items then return frame.Items end
  local list, name = {}, frame:GetName()
  for i = 1, (frame.size or 36) do local b = name and _G[name .. "Item" .. i]; if b then list[#list + 1] = b end end
  return list
end
local function markBag(frame)
  if not (frame and frame:IsShown()) then return end
  local active = on()
  for _, b in ipairs(buttonsOf(frame)) do
    local up = false
    if active and b:IsShown() then
      local bag = b.GetBagID and b:GetBagID() or frame:GetID()
      up = isUpgrade(getContainerItemID and getContainerItemID(bag, b:GetID()), true)
    end
    if up or b.ofaUp then mark(b, "ofaUp", "icon_arrow_up", 15, "TOPLEFT", 1, -1):SetShown(up) end
  end
end
local function bagFrames()
  local list = {}
  for i = 1, (NUM_CONTAINER_FRAMES or 13) do local f = _G["ContainerFrame" .. i]; if f then list[#list + 1] = f end end
  if ContainerFrameCombinedBags then list[#list + 1] = ContainerFrameCombinedBags end
  return list
end
function GM.RefreshBags() for _, f in ipairs(bagFrames()) do markBag(f) end end

-- Baganator (user 18.10.): its own API for icons in the corners of item buttons; the user can move or switch the
-- arrow off in Baganator's icon settings. onUpdate: true = show, false = not, nil = item data not there yet (asks
-- again later)
local baganator
local function hookBaganator()
  local api = Baganator and Baganator.API
  if baganator or not (api and api.RegisterCornerWidget) then return end
  baganator = api
  pcall(api.RegisterCornerWidget, "OneForAll: upgrade", "oneforall_upgrade", function(_, details)
    if not on() then return false end
    local id = details and (details.itemID or itemID(details.itemLink))
    if not id then return false end
    if not GetItemInfo(id) then return nil end
    return isUpgrade(id, true)
  end, function(button)
    local t = button:CreateTexture(nil, "OVERLAY"); t:SetSize(15, 15); FLT.SetTex(t, ASSET .. "icon_arrow_up")
    return t
  end, { corner = "top_left", priority = 1 })
end

-- the game re-uses item buttons for other bags: mark again whenever a bag frame updates
local pending
local function later()
  if pending then return end
  pending = true
  C_Timer.After(0.3, function() pending = false; GM.RefreshBags() end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    self:UnregisterEvent("PLAYER_LOGIN")
    for _, f in ipairs(rollFrames()) do f:HookScript("OnShow", decorateRoll) end
    if ContainerFrame_Update then hooksecurefunc("ContainerFrame_Update", markBag) end
    for _, f in ipairs(bagFrames()) do
      if f.UpdateItems then hooksecurefunc(f, "UpdateItems", markBag) end
      f:HookScript("OnShow", markBag)
    end
    hookBaganator()
    -- worn gear or item data changed: the visible bags again (debounced)
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED"); self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    return
  end
  if event == "PLAYER_EQUIPMENT_CHANGED" and baganator and baganator.RequestItemButtonsRefresh then
    pcall(baganator.RequestItemButtonsRefresh)
  end
  for _, f in ipairs(bagFrames()) do if f:IsShown() then later(); return end end
end)

-- other weights (spec picked in the Gear Planner): bags and Baganator again
function GM.Refresh()
  GM.RefreshBags()
  if baganator and baganator.RequestItemButtonsRefresh then pcall(baganator.RequestItemButtonsRefresh) end
end

-- /ofa rolltest ---------------------------------------------------------------------
local TEST_ID = 999999
-- an example: a wishlist item, else an upgrade from the planner's data, else the worn chest
local function exampleItem()
  if type(OneForAllCharDB) == "table" and OneForAllCharDB.wishlist then
    for id in pairs(OneForAllCharDB.wishlist) do return id end
  end
  local idx = FLT.GearIndex and FLT.GearIndex() or {}
  for i = 1, math.min(#idx, 3000) do
    local e = idx[i]
    if GetItemInfo(e.id) and isUpgrade(e.id, true) then return e.id end
  end
  return GetInventoryItemID and GetInventoryItemID("player", 5)
end

function GM.RollTest()
  -- Forever has the modern container (GroupLootContainer_OpenNewFrame, checked in game 18.10.), Classic the old one
  local open = GroupLootContainer_OpenNewFrame or GroupLootFrame_OpenNewFrame
  if not open then FLT.Msg("This client has no loot roll window to test."); return end
  local id = exampleItem()
  local name, link, quality, _, _, _, _, _, _, texture = GetItemInfo(id or 0)
  if not name then FLT.Msg("No example item yet - try again in a moment."); return end
  local saved = { GetLootRollItemInfo, GetLootRollItemLink, GetLootRollTimeLeft, RollOnLoot, GetActiveLootRollIDs }
  local function restore()
    GetLootRollItemInfo, GetLootRollItemLink, GetLootRollTimeLeft, RollOnLoot = saved[1], saved[2], saved[3], saved[4]
    GetActiveLootRollIDs = saved[5]
  end
  GetLootRollItemInfo = function(r, ...)
    if r == TEST_ID then return texture, name, 1, quality, true, true, true, false end
    return saved[1](r, ...)
  end
  GetLootRollItemLink = function(r, ...) if r == TEST_ID then return link end return saved[2](r, ...) end
  GetLootRollTimeLeft = function(r, ...) if r == TEST_ID then return 60000 end return saved[3](r, ...) end
  -- the container drops rolls the game does not list as active
  if saved[5] then
    GetActiveLootRollIDs = function(...) local t = saved[5](...) or {}; t[#t + 1] = TEST_ID; return t end
  end
  RollOnLoot = function(r, ...)
    if r == TEST_ID then for _, f in ipairs(rollFrames()) do if f.rollID == TEST_ID then f:Hide() end end return end
    return saved[4](r, ...)
  end
  local ok = pcall(open, TEST_ID, 60000)
  local shown
  for _, f in ipairs(rollFrames()) do
    if f.rollID == TEST_ID and f:IsShown() then
      shown = f
      f:HookScript("OnHide", function(self) if self.rollID == TEST_ID then self.rollID = nil; restore() end end)
      -- the game's own item tooltip asks the server for the roll and stays empty for a test roll: show the item
      local icon = iconOf(f)
      if icon and not icon.ofaTestTip then
        icon.ofaTestTip = true
        icon:HookScript("OnEnter", function(self)
          if f.rollID == TEST_ID and f.ofaTestLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(f.ofaTestLink); GameTooltip:Show()
          end
        end)
      end
      f.ofaTestLink = link
    end
  end
  if not (ok and shown) then restore(); FLT.Msg("The test roll window could not be opened."); return end
  FLT.Msg("Test roll window with " .. link .. " - the buttons only close it.")
end
