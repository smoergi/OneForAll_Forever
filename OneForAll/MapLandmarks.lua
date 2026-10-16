local ADDON, FLT = ...

-- Map Landmarks (Quality of Life, on by default with all parts, user 16.10.): icons on the world map for dungeon and raid
-- entrances, flight masters, zeppelin towers and ship docks. Entrances come from DungeonData.lua,
-- the rest from Data/MapLandmarks.lua. Click an entrance to open that dungeon in OneForAll, Shift-click
-- it for the map pin of Map.lua; the other icons only have a tooltip (user 16.10.). Flight masters: own
-- faction + neutral; ships and zeppelins: all, the other faction's marked "(Alliance only)" / "(Horde only)".
-- Lean: nothing runs while the switch is off; with it on, pins are only placed when the world map
-- shows or changes map (no OnUpdate), reused from a pool, and the per-map index is built once.

local LM = {}
FLT.MapLandmarks = LM

local ASSET = FLT.ASSET_ROOT or ("Interface\\AddOns\\" .. ADDON .. "\\Assets\\")
-- icons: client atlases (dungeon/raid) and our assets made from client art (tools note in DESIGN.md)
local KINDS = {
  dungeon = { atlas = "dungeon", w = 28, h = 28, key = "lmDungeons" },
  raid = { atlas = "raid", w = 30, h = 30, key = "lmDungeons" },
  flight = { file = ASSET .. "landmark_flight", w = 20, h = 20, key = "lmFlight" },
  shipA = { file = ASSET .. "landmark_ship_a", w = 34, h = 34, key = "lmTransport" },
  shipH = { file = ASSET .. "landmark_ship_h", w = 34, h = 34, key = "lmTransport" },
  zeppelin = { file = ASSET .. "landmark_zeppelin", w = 40, h = 20, key = "lmTransport" },
}
local SIDE_NAME = { A = "Alliance", H = "Horde" }

local function Q(key) return FLT.QoL and FLT.QoL.Get(key) end

-- mapID -> list of { kind=, x=, y=, ... }; built on first use
local byMap
local function add(mapID, e)
  local l = byMap[mapID]
  if not l then l = {}; byMap[mapID] = l end
  l[#l + 1] = e
end

local function buildIndex()
  byMap = {}
  local faction = UnitFactionGroup and UnitFactionGroup("player")
  local letter = faction == "Horde" and "H" or faction == "Alliance" and "A" or nil
  local function mine(sides) return not letter or sides:find(letter, 1, true) ~= nil end
  -- entrances: dungeons that share an entrance (Scarlet Monastery, Dire Maul ...) get one icon
  local seen = {}
  for _, d in ipairs(FLT.DUNGEONS or {}) do
    local mapID = d.mapZone and d.mapX and d.mapY and FLT:FindMapID(d.mapZone)
    if mapID then
      local id = mapID .. ":" .. math.floor(d.mapX + 0.5) .. ":" .. math.floor(d.mapY + 0.5)
      local e = seen[id]
      if not e then
        e = { kind = "dungeon", x = d.mapX, y = d.mapY, mapID = mapID, list = {} }
        seen[id] = e; add(mapID, e)
      end
      e.list[#e.list + 1] = d
      if d.raid then e.kind = "raid" end
    end
  end
  local data = FLT.MAP_LANDMARKS or {}
  for _, f in ipairs(data.flight or {}) do
    if mine(f[4]) then add(f[1], { kind = "flight", x = f[2], y = f[3], mapID = f[1], name = f[5] }) end
  end
  for _, z in ipairs(data.zeppelin or {}) do
    add(z[1], { kind = "zeppelin", x = z[2], y = z[3], dest = { select(4, unpack(z)) }, only = letter == "A" and "Horde" or nil })
  end
  for _, s in ipairs(data.ship or {}) do
    add(s[1], { kind = s[4] == "A" and "shipA" or "shipH", x = s[2], y = s[3], dest = { s[5] },
      only = not mine(s[4]) and SIDE_NAME[s[4]] or nil })
  end
end

-- Pins ------------------------------------------------------------------------
local pool, used = {}, 0

local function openDungeon(d)
  if WorldMapFrame and WorldMapFrame:IsShown() and HideUIPanel then pcall(HideUIPanel, WorldMapFrame) end
  FLT:OpenPanel("dungeons")
  if FLT.UI and FLT.UI.OpenDungeon then FLT.UI.OpenDungeon(d) end
end

local function onClick(pin)
  local e = pin.entry
  if not (e and e.list) then return end
  if IsShiftKeyDown and IsShiftKeyDown() then
    if FLT.ShowOnMap then FLT:ShowOnMap({ mapID = e.mapID, x = e.x, y = e.y, name = e.list[1].name .. " entrance" }) end
    return
  end
  do
    if #e.list == 1 then openDungeon(e.list[1]); return end
    local options = {}
    for i, d in ipairs(e.list) do options[i] = { key = i, label = d.name } end
    FLT.UI.OpenDropDown(pin, options, nil, function(i) openDungeon(e.list[i]) end, 230)
  end
end

local KIND_LABEL = { flight = "Flight master", zeppelin = "Zeppelin", shipA = "Ship", shipH = "Ship" }
local function onEnter(pin)
  local e = pin.entry
  if not e or not GameTooltip then return end
  GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
  if e.list then
    for _, d in ipairs(e.list) do
      local lvl = d.level and d.level ~= "?" and ("  |cffb0b0b0" .. d.level .. "|r") or ""
      GameTooltip:AddLine(d.name .. lvl, 1, 0.82, 0.2)
    end
    GameTooltip:AddLine(e.kind == "raid" and "Raid entrance" or "Dungeon entrance", 0.8, 0.8, 0.8)
    GameTooltip:AddLine(#e.list > 1 and "Click: choose one to open in OneForAll" or "Click: open in OneForAll", 0.4, 0.8, 1)
    GameTooltip:AddLine("Shift-click: set a map pin", 0.4, 0.8, 1)
  else
    local title = e.name or KIND_LABEL[e.kind]
    if e.only then title = title .. "  |cffff6060(" .. e.only .. " only)|r" end
    GameTooltip:AddLine(title, 1, 0.82, 0.2)
    if e.name then GameTooltip:AddLine(KIND_LABEL[e.kind], 0.8, 0.8, 0.8) end
    for _, d in ipairs(e.dest or {}) do GameTooltip:AddLine("To " .. d, 1, 1, 1) end
  end
  GameTooltip:Show()
end
local function onLeave() if GameTooltip then GameTooltip:Hide() end end

local function acquire(parent)
  used = used + 1
  local pin = pool[used]
  if not pin then
    pin = CreateFrame("Button", nil, parent)
    pin.tex = pin:CreateTexture(nil, "OVERLAY"); pin.tex:SetAllPoints()
    pin:RegisterForClicks("LeftButtonUp")
    pin:SetScript("OnClick", onClick); pin:SetScript("OnEnter", onEnter); pin:SetScript("OnLeave", onLeave)
    pool[used] = pin
  end
  return pin
end

local function setIcon(pin, kind)
  if pin.kind == kind then return end
  pin.kind = kind
  local k = KINDS[kind]
  if k.atlas and pin.tex.SetAtlas and pcall(pin.tex.SetAtlas, pin.tex, k.atlas) then return end
  pin.tex:SetTexture(k.file or "Interface\\Minimap\\POIIcons"); pin.tex:SetTexCoord(0, 1, 0, 1)
end

local function hideAll()
  for i = 1, used do pool[i]:Hide(); pool[i].entry = nil end
  used = 0
end

function LM.Refresh()
  if not WorldMapFrame then return end
  hideAll()
  if not Q("mapLandmarks") or not WorldMapFrame:IsShown() then return end
  local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
  if not mapID then return end
  if not byMap then buildIndex() end
  local list = byMap[mapID]
  if not list then return end
  local child = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
  if not child then return end
  local w, h = child:GetWidth(), child:GetHeight()
  if not (w and h and w > 0 and h > 0) then return end
  local scale = 1
  local sc = WorldMapFrame.ScrollContainer
  if sc.GetCanvasScale then scale = 1 / math.max(0.1, sc:GetCanvasScale() or 1) end
  -- frame level: the map's own top pin level when the client has the manager, at least child + 500; in the
  -- Barrens the icons were hidden under the map's area highlight although they got the mouse (5.6.3)
  local level = child:GetFrameLevel() + 500
  local mgr = WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
  if mgr and mgr.GetValidFrameLevel then
    local ok, l = pcall(mgr.GetValidFrameLevel, mgr, "PIN_FRAME_LEVEL_TOPMOST")
    if ok and type(l) == "number" and l > level then level = l end
  end
  for _, e in ipairs(list) do
    local k = KINDS[e.kind]
    if Q(k.key) ~= false then
      local pin = acquire(child)
      setIcon(pin, e.kind)
      pin.entry = e
      pin:SetSize(k.w, k.h); pin:SetScale(scale)
      pin:SetFrameLevel(level)
      pin:ClearAllPoints()
      pin:SetPoint("CENTER", child, "TOPLEFT", (e.x / 100) * w / scale, -(e.y / 100) * h / scale)
      pin:Show()
    end
  end
end

-- the switch in the QoL tab: hooks go in once, the first time it is on
local hooked
local function hook()
  if hooked or not WorldMapFrame then return end
  hooked = true
  WorldMapFrame:HookScript("OnShow", LM.Refresh)
  WorldMapFrame:HookScript("OnHide", hideAll)
  if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", LM.Refresh) end
  if WorldMapFrame.OnCanvasScaleChanged then hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", LM.Refresh) end
end

function LM.Apply()
  if Q("mapLandmarks") then hook() end
  LM.Refresh()
end

LM._pool = pool -- for tools/tests/t_landmarks.lua
function LM._reset() byMap = nil end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self)
  self:UnregisterAllEvents()
  local Qo = FLT.QoL
  if Qo and Qo.On then
    Qo.On("mapLandmarks", LM.Apply)
    Qo.On("lmDungeons", LM.Refresh); Qo.On("lmFlight", LM.Refresh); Qo.On("lmTransport", LM.Refresh)
  end
  if FLT.SafeCall then FLT.SafeCall("MapLandmarks", LM.Apply) else pcall(LM.Apply) end
end)
