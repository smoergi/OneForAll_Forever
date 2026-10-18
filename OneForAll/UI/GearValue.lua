local _, FLT = ...

-- Gear Planner "Value" (5.6.3): sum of the item's stats x the stat weights of the active spec (the talent tree
-- with the most points; user 16.10.: standard specs only, no choice yet). Weights: Data/GearWeights.lua (Sharpie's
-- Gear Judge, MIT): level 60 = the raid profile, below 60 = the spec's leveling curve at the player's level,
-- no talents = the class's general leveling curve. Ratings are turned into % first (GEAR_RATING).
-- Compared with what is worn: rings / trinkets with the weaker one, two-handers with main + off hand.
-- Lean: weights are built once per spec / level / talent change, item values are cached per item and slot,
-- worn values per slot until the gear changes. Nothing runs until a tooltip or the planner asks.

local GV = {}
FLT.GearValue = GV
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local KEYS, RATING = FLT.GEAR_STAT_KEYS or {}, FLT.GEAR_RATING or {}
local W, specName, autoTree -- current weights; the talent tree with the most points
local values = {}  -- [slot][itemID] = value
local worn = {}    -- [slot] = value of the worn item (false = empty)
local speeds = {}  -- [itemID] = weapon speed (tooltip data)

local function curveAt(curve, level)
  local n = #curve
  local a, b = curve[1], curve[n]
  if level <= a[1] then b = a
  elseif level >= b[1] then a = b
  else
    for i = 1, n - 1 do
      if level >= curve[i][1] and level <= curve[i + 1][1] then a, b = curve[i], curve[i + 1]; break end
    end
  end
  local t = (b[1] > a[1]) and ((level - a[1]) / (b[1] - a[1])) or 0
  local out = {}
  for k, v in pairs(a[2]) do out[k] = v end
  for k in pairs(b[2]) do out[k] = out[k] or 0 end
  for k, va in pairs(out) do
    local v = va + ((b[2][k] or 0) - va) * t
    out[k] = (v > 0 and v < 0.02) and 0 or v
  end
  return out
end

local function buildWeights()
  local _, cls = UnitClass("player")
  local data = FLT.GEAR_WEIGHTS and FLT.GEAR_WEIGHTS[cls]
  if not data then return end
  local ok, pts = pcall(FLT.TalentPointsPerTree or function() end)
  if not ok then pts = nil end
  local tree, best = nil, 0
  for i = 1, 3 do if pts and (pts[i] or 0) > best then tree, best = i, pts[i] end end
  autoTree = tree
  -- chosen in the Gear Planner (per character, user 18.10.); nil = the active spec
  local pick = type(OneForAllCharDB) == "table" and OneForAllCharDB.gearSpec
  if pick and data.specs[pick] then tree = pick end
  local spec = tree and data.specs[tree]
  local level = UnitLevel("player") or 1
  local w
  if spec and level >= 60 then
    w = {}; for k, v in pairs(spec.raid) do w[k] = v end
  else
    w = curveAt(data.curves[spec and spec.curve or "Leveling"] or data.curves.Leveling, level)
  end
  -- Forever has one hit and one crit rating for melee and spells (as Gear Judge does)
  w.hit = math.max(w.hit or 0, w.shit or 0); w.crit = math.max(w.crit or 0, w.scrit or 0)
  W, specName = w, spec and spec.name or "Leveling"
  wipe(values); wipe(worn)
end
function GV.SpecName() if not W then buildWeights() end return specName end
-- the planner's spec drop-down: the class's three specs, the one in use (nil = active spec) and the active one
function GV.Specs()
  if not W then buildWeights() end
  local _, cls = UnitClass("player")
  local data = FLT.GEAR_WEIGHTS and FLT.GEAR_WEIGHTS[cls]
  local pick = type(OneForAllCharDB) == "table" and OneForAllCharDB.gearSpec or nil
  return data and data.specs or {}, pick, autoTree
end
function GV.SetSpec(i)
  if type(OneForAllCharDB) ~= "table" then return end
  OneForAllCharDB.gearSpec = i
  W = nil; wipe(values); wipe(worn)
  if FLT.GearMarks and FLT.GearMarks.Refresh then FLT.GearMarks.Refresh() end
end

-- weapon speed is not in GetItemStats: read it once from the item's tooltip data
local function weaponSpeed(id)
  local s = speeds[id]
  if s ~= nil then return s or nil end
  s = false
  local data = C_TooltipInfo and C_TooltipInfo.GetItemByID and C_TooltipInfo.GetItemByID(id)
  for _, line in ipairs(data and data.lines or {}) do
    local v = (line.rightText or ""):match("(%d+[%.,]%d+)")
    if v and (line.rightText or ""):find(SPEED or "Speed", 1, true) then s = tonumber((v:gsub(",", "."))); break end
  end
  speeds[id] = s
  return s or nil
end

local function score(stats, slot, id, isWand)
  local total = 0
  for k, v in pairs(stats) do
    local s = KEYS[k]
    if s and type(v) == "number" then
      local wk = s
      if s == "dps" then
        if slot == 17 and W.dpsoh then wk = "dpsoh"
        elseif (slot == 16 or slot == 17) and W.dpsmelee then wk = "dpsmelee"
        elseif isWand and W.dpswand then wk = "dpswand" end
      end
      local w = W[wk] or 0
      if w > 0 then
        local val = RATING[s] and v / RATING[s] or v
        if slot == 17 and s == "dps" and wk ~= "dpsoh" then val = val * 0.5 end
        total = total + val * w
      end
      -- spell power also heals
      if k == "ITEM_MOD_SPELL_POWER_SHORT" and (W.heal or 0) > 0 then total = total + v * W.heal end
    end
  end
  if (slot == 16 or slot == 17) and (W.speed or 0) > 0 and stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT then
    local sp = weaponSpeed(id)
    if sp then total = total + sp * W.speed end
  end
  return total
end

local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
-- value of an item in a slot; nil while the client has no data for it yet
local function itemValue(id, slot, link)
  if not W then buildWeights() end
  if not W or not getStats then return nil end
  local cache = values[slot]
  if not cache then cache = {}; values[slot] = cache end
  local v = cache[id]
  if v then return v end
  if not (GetItemInfo and GetItemInfo(id)) then return nil end
  local stats = getStats(link or ("item:" .. id))
  if not stats then return nil end
  local _, _, _, _, _, cid, sub = GetItemInfoInstant(id)
  v = score(stats, slot, id, cid == 2 and sub == 19)
  cache[id] = v
  return v
end

local function wornValue(slot)
  local v = worn[slot]
  if v ~= nil then return v end
  local link = GetInventoryItemLink("player", slot)
  if not link then worn[slot] = 0; return 0 end
  local id = tonumber(link:match("item:(%d+)"))
  v = id and itemValue(id, slot, link)
  if v then worn[slot] = v end
  return v
end

local function slotFor(loc, slots)
  if loc == "INVTYPE_WEAPONOFFHAND" then return 17 end
  return slots[1]
end

-- Value of an item and the change against what is worn: value, delta (nil = no data yet / not gear)
function GV.Upgrade(id)
  local _, _, _, loc, _, cid, sub = GetItemInfoInstant(id)
  local slots = loc and FLT.GEAR_LOC_SLOTS and FLT.GEAR_LOC_SLOTS[loc]
  if not slots then return nil end
  local slot = slotFor(loc, slots)
  local v = itemValue(id, slot)
  if not v then return nil end
  for _, s in ipairs(slots) do
    if GetInventoryItemID and GetInventoryItemID("player", s) == id then return v, 0, true end
  end
  local base, replaced
  if loc == "INVTYPE_2HWEAPON" then
    local a, b = wornValue(16), wornValue(17)
    base = a and b and (a + b)
  elseif #slots == 2 and (loc ~= "INVTYPE_WEAPON" or (FLT.CanDualWield() and select(6, GetItemInfoInstant(GetInventoryItemID("player", 17) or 0)) == 2)) then
    local a, b = wornValue(slots[1]), wornValue(slots[2])
    base = a and b and math.min(a, b)
    if base then replaced = (a <= b) and slots[1] or slots[2] end -- the weaker one, named in the tooltip
  else
    base = wornValue(slot)
  end
  if not base then return v end
  return v, v - base, false, base, replaced
end

-- What players see is the change in % against the worn item (user 16.10.): kind, pct
-- kind: "up" / "down" / "same" / "new" (nothing worn there, or it has no value) / "worn"; nil = no data yet;
-- third value: the slot compared with when there are two (rings, trinkets, dual wield)
function GV.Change(id)
  local v, d, equipped, base, replaced = GV.Upgrade(id)
  if not v then return nil end
  if equipped then return "worn" end
  if not d then return nil end
  if not base or base <= 0 then return v > 0 and "new" or "same" end
  local pct = d / base * 100
  if pct >= 0.5 then return "up", pct, replaced elseif pct <= -0.5 then return "down", -pct, replaced end
  return "same"
end

-- own arrows (tools/art/arrows.py); the client's Arrow-Up-Up was tiny and odd in the tooltip (beta10)
local ASSET = (FLT.UI and FLT.UI.ASSET_ROOT) or FLT.ASSET_ROOT or "Interface\\AddOns\\OneForAll\\Assets\\"
local OFA = "|cffc8961eOFA|r "  -- dark yellow (user 16.10.)
local UP = OFA .. "|T" .. ASSET .. "icon_arrow_up:16:16:0:0|t "
local DOWN = OFA .. "|T" .. ASSET .. "icon_arrow_down:16:16:0:0|t "
GV.UP, GV.DOWN = UP, DOWN
-- tooltip: green "Upgrade: 30%" with an arrow up, red "Downgrade: 12%" with an arrow down (like the user's example);
-- Quality of Life switch "gearValue", on by default (user 16.10.)
function GV.TooltipLine(tt, id)
  local _, _, _, loc, _, cid, sub = GetItemInfoInstant(id)
  if not (loc and FLT.GEAR_LOC_SLOTS and FLT.GEAR_LOC_SLOTS[loc]) or not FLT.GearCanUse(loc, cid, sub) then return end
  local kind, pct, slot = GV.Change(id)
  -- with two slots (rings, trinkets, dual wield): which worn item it is compared with (user 17.10.)
  local link = slot and GetInventoryItemLink("player", slot)
  local which = link and link:match("%[(.-)%]")
  which = which and ("  |cffb0b0b0(replaces " .. which .. ")|r") or ""
  if kind == "up" then tt:AddLine(UP .. string.format("Upgrade: %d%%", math.floor(pct + 0.5)) .. which, 0.25, 1, 0.25)
  elseif kind == "new" then tt:AddLine(UP .. "Upgrade (slot empty)", 0.25, 1, 0.25)
  elseif kind == "down" then tt:AddLine(DOWN .. string.format("Downgrade: %d%%", math.floor(pct + 0.5)) .. which, 1, 0.3, 0.3) end
end

-- refresh: talents / level change the weights, gear changes the worn values
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED",
  "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_EQUIPMENT_CHANGED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_EQUIPMENT_CHANGED" then wipe(worn) else W = nil end
end)
GV._reset = function() W = nil; wipe(values); wipe(worn); wipe(speeds) end -- tests
