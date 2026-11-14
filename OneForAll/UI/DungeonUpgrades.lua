local _, FLT = ...
local L = FLT.L or setmetatable({}, { __index = function(_, k) return k end }) -- (tests without Locales)

-- Dungeon upgrades (6.2.9): per dungeon the chance that one run drops at least one upgrade for you (Gear Value of your
-- spec, UI/GearValue.lua) and those upgrades with their drop chance - shown under the name in Dungeons & Raids.
-- Boss loot only (trash drops are rare and mostly unknown); rare spawns are left out (not there every run).
-- Drop chances: Data/DungeonDropChance.lua; a boss item without one counts as one of the boss's items (one drop per
-- boss, marked "~"). Items more than 3 levels above you are left out, like the "Only dungeons for my level" filter.
-- Lean: only dungeons near your level are counted, each once until gear, level or spec change (GearValue.Gen).

local DU = {}
FLT.DungeonUpgrades = DU
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local cache = {}   -- [dungeon name] = result
local waiting = {} -- [itemID] = true while the client has no data for it
local function playerLevel() return (UnitLevel and tonumber(UnitLevel("player"))) or 1 end
local function stamp()
  local GV = FLT.GearValue
  return (GV and GV.Gen and GV.Gen() or 0) .. ":" .. playerLevel()
end

function DU.Enabled() return type(OneForAllDB) ~= "table" or OneForAllDB.dungeonUpgrades ~= false end

-- dungeons far below or above you are not counted (their items are no upgrades or not usable yet)
local function inRange(d)
  local pl = playerLevel()
  local lo = d.minLevel or 0
  local hi = d.maxLevel or lo
  return pl >= lo - 5 and pl <= hi + 5
end

local function compute(d)
  local GV = FLT.GearValue
  local r = { items = {}, chance = 0, gain = 0, pending = false }
  local pl, miss = playerLevel(), 1
  for _, b in ipairs(d.bosses or {}) do
    local loot = b.loot or {}
    if not b.rare and #loot > 0 then
      for _, it in ipairs(loot) do
        local id = it.id
        local _, _, _, loc, icon, cid, sub = GetItemInfoInstant(id)
        if loc and FLT.GEAR_LOC_SLOTS and FLT.GEAR_LOC_SLOTS[loc] and FLT.GearCanUse(loc, cid, sub) then
          local name, _, q, _, req = GetItemInfo(id)
          if not name then
            r.pending = true; waiting[id] = true
          elseif (req or 0) <= pl + 3 then
            local kind, pct = GV.Change(id)
            if (kind == "up" or kind == "new") and pct and pct > 0 then
              local p = FLT.GetDropChance and FLT.GetDropChance(d.name, b.name, id)
              local est = not p
              p = math.min((p or 100 / #loot) / 100, 1)
              r.items[#r.items + 1] = { id = id, name = name, q = q, icon = icon, boss = b.name, p = p, est = est, pct = pct, req = req }
              miss = miss * (1 - p)
              r.gain = r.gain + p * pct
            end
          end
        end
      end
    end
  end
  r.chance = 1 - miss
  table.sort(r.items, function(a, b) if a.pct ~= b.pct then return a.pct > b.pct end return a.id < b.id end)
  r.stamp = stamp() -- after counting: the first Value of a session builds the weights and moves the generation on
  return r
end

-- the result for a dungeon, nil when it is not counted (switched off, a raid without loot, far from your level)
function DU.Get(d)
  if not (d and DU.Enabled() and FLT.GearValue and FLT.GearCanUse and GetItemInfoInstant) then return nil end
  if not inRange(d) then return nil end
  local r = cache[d.name]
  if r and r.stamp == stamp() then return r end -- a pending one is dropped when its items arrive (flush)
  r = compute(d)
  cache[d.name] = r
  return r
end

-- "38%", one decimal below 10 %
local function pctText(p) return FLT.GearValue.Pct(p) .. "%" end
function DU.ChanceText(r) return pctText(r.chance * 100) end

local function qualityHex(q)
  local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  return c and c.hex or "|cffffffff"
end
function DU.Tooltip(tt, d, r)
  local NM = FLT.Name or function(s) return s end
  tt:AddLine(L["Upgrades for you"], 1, 0.82, 0)
  if #r.items == 0 then
    tt:AddLine(r.pending and L["Loading item data..."] or L["No boss item here is an upgrade for you right now."], 1, 1, 1, true)
  else
    tt:AddLine(string.format(L["Chance of at least one upgrade per run: %s"], DU.ChanceText(r)), 0.25, 1, 0.25)
    tt:AddLine(string.format(L["On average +%s Gear Value per run."], pctText(r.gain)), 0.85, 0.85, 0.85)
    tt:AddLine(" ")
    local shown = math.min(#r.items, 10)
    for i = 1, shown do
      local e = r.items[i]
      local left = (e.icon and ("|T" .. e.icon .. ":14:14:0:0|t ") or "") .. qualityHex(e.q) .. e.name .. "|r  |cff9d9d9d" .. NM(e.boss) .. "|r"
      local drop = (e.est and "~" or "") .. pctText(e.p * 100)
      tt:AddDoubleLine(left, "|cff40ff40+" .. pctText(e.pct) .. "|r  |cffb0b0b0" .. string.format(L["%s drop"], drop) .. "|r")
    end
    if #r.items > shown then tt:AddLine(string.format(L["and %d more"], #r.items - shown), 0.65, 0.65, 0.65) end
  end
  tt:AddLine(" ")
  tt:AddLine(L["Gear Value of your spec (Armory > Gear Planner). Boss loot only, without rare spawns; ~ = drop chance not known, one item per boss assumed."], 0.6, 0.6, 0.6, true)
end

-- item data arrives later: count the dungeons that waited for it again (throttled)
local ev = CreateFrame("Frame")
local queued = false
local function flush()
  queued = false
  for name, r in pairs(cache) do if r.pending then cache[name] = nil end end
  if FLT.UI and FLT.UI.RefreshDungeonUpgrades then FLT.UI.RefreshDungeonUpgrades() end
end
for _, e in ipairs({ "GET_ITEM_INFO_RECEIVED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event, id)
  if event == "GET_ITEM_INFO_RECEIVED" then
    if not (id and waiting[id]) then return end
    waiting[id] = nil
  end
  -- gear / level: the stamp no longer matches, the list only has to be painted again
  if queued then return end
  queued = true
  if C_Timer and C_Timer.After then C_Timer.After(0.5, flush) else flush() end
end)
DU._reset = function() wipe(cache); wipe(waiting) end -- tests
