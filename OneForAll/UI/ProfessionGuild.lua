local _, FLT = ...

-- Recipe sharing for the "All recipes" browser.
-- OneForAll users send the recipe spell IDs they know (per profession) over a
-- hidden addon channel:
--   * GUILD: guild members (shown with a green check)
--   * a hidden custom chat channel: all other OneForAll users (blue check)
-- Stored account-wide:
--   ForeverCompanionDB.guildRecipes[guild][member]  = { t = time, [prof] = {spellID=true} }
--   ForeverCompanionDB.playerRecipes[player]        = { t = time, [prof] = {spellID=true} }
-- Own characters in the same guild are stored too, so alts show up as well.

local PREFIX = "OFAPR"
local CHANNEL = "OFAShare"
local GUILD_GAP = 0.35        -- seconds between guild messages
local CHANNEL_GAP = 1.2       -- channel messages are throttled harder by the server
local MAX_LEN = 240           -- payload size per message
local REBROADCAST = 30 * 60   -- re-send own recipes to the channel every 30 min
local PLAYER_EXPIRE = 60 * 24 * 3600 -- forget other players after 60 days
local STATUS_EVERY = 10 * 60  -- heartbeat with the current zone
local ONLINE_WINDOW = 12 * 60 -- other players count as online if heard from within this time

local scheduleStatus -- forward declaration (defined further down)

local function guildName()
  if not (IsInGuild and IsInGuild()) then return nil end
  return GetGuildInfo and GetGuildInfo("player")
end

local function shortName(n)
  if not n then return nil end
  if Ambiguate then return Ambiguate(n, "short") end
  return (n:gsub("%-.*$", ""))
end

local function now() return time and time() or 0 end

-- Identity of the current character. On Forever several characters can share
-- the first name ("Smoergi Deadheart", "Smoergi Ironfist"), and UnitName may
-- only return the first name. The full name is taken from the guild roster
-- (matched by GUID) and cached per character.
local function firstName()
  local n = UnitName and UnitName("player")
  return n and shortName(n) or nil
end
local function myName()
  if type(ForeverCompanionCharDB) == "table" and ForeverCompanionCharDB.fullName then return ForeverCompanionCharDB.fullName end
  return nil
end
local function isMe(name)
  if not name then return false end
  local n = shortName(name):lower()
  local full = myName()
  if full then return n == full:lower() end
  -- full name not known yet: only an exact match with UnitName counts
  local f = firstName()
  return f ~= nil and n == f:lower()
end

local function shareEnabled()
  return not (type(ForeverCompanionDB) == "table" and ForeverCompanionDB.recipeShareChannel == false)
end

local function guildDB(create)
  local g = guildName()
  if not g or type(ForeverCompanionDB) ~= "table" then return nil end
  ForeverCompanionDB.guildRecipes = ForeverCompanionDB.guildRecipes or {}
  local t = ForeverCompanionDB.guildRecipes[g]
  if not t and create then t = {}; ForeverCompanionDB.guildRecipes[g] = t end
  return t
end

local function playerDB()
  if type(ForeverCompanionDB) ~= "table" then return nil end
  ForeverCompanionDB.playerRecipes = ForeverCompanionDB.playerRecipes or {}
  return ForeverCompanionDB.playerRecipes
end

-- base36 encoding keeps the messages short
local DIG = "0123456789abcdefghijklmnopqrstuvwxyz"
local function enc(n)
  local s = ""
  repeat local d = n % 36; s = DIG:sub(d + 1, d + 1) .. s; n = math.floor(n / 36) until n == 0
  return s
end
local function dec(s) return tonumber(s, 36) end

-- ---------------------------------------------------------------------------
-- Guild roster (online state, members who left)
-- ---------------------------------------------------------------------------
local roster, rosterCount = {}, 0
local selfIdentified -- forward: called once the own full name is known
local function readRoster()
  if not (GetNumGuildMembers and GetGuildRosterInfo) then return end
  local n = GetNumGuildMembers() or 0
  if n == 0 then return end
  wipe(roster); rosterCount = 0
  for i = 1, n do
    local name, _, _, level, _, zone, _, _, online, _, classFile, _, _, _, _, _, guid = GetGuildRosterInfo(i)
    if name then
      local short = shortName(name)
      -- find the own full name: by GUID, else online + same first name, level and class
      local mine = guid and UnitGUID and guid == UnitGUID("player")
      if not mine and not guid and online then
        local f = firstName()
        local _, myClass = UnitClass and UnitClass("player")
        mine = f and (short == f or short:sub(1, #f + 1) == f .. " ") and level == (UnitLevel and UnitLevel("player")) and classFile == myClass
      end
      if mine and type(ForeverCompanionCharDB) == "table" and ForeverCompanionCharDB.fullName ~= short then
        ForeverCompanionCharDB.fullName = short
        selfIdentified()
      end
      roster[short:lower()] = {online = online and true or false, zone = zone, level = level, class = classFile}
      rosterCount = rosterCount + 1
    end
  end
  -- drop the old first-name-only entry of this character (older versions)
  local f, db = firstName(), guildDB(false)
  if f and db and db[f] and rosterCount > 0 and not roster[f:lower()] then db[f] = nil end
end

local function rosterInfo(name)
  if not name then return nil end
  return roster[shortName(name):lower()]
end

local function sortKnowers(out)
  table.sort(out, function(a, b) if a[2] ~= b[2] then return a[2] end return a[1] < b[1] end)
  return out
end

local lastRosterRequest = -100
function FLT.RequestGuildRoster()
  if not guildName() then return end
  local t = GetTime and GetTime() or 0
  if t - lastRosterRequest < 10 then return end
  lastRosterRequest = t
  if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
end

-- Current zone of other OneForAll users (this session only): [name] = {zone, inst, t}
local status = {}

-- Guild members that know a recipe (without the player): list of {name, online, zone}.
function FLT.GetGuildRecipeKnowers(prof, spell)
  local db = guildDB(false)
  if not db then return nil end
  local out
  for member, data in pairs(db) do
    if not isMe(member) and type(data) == "table" and data[prof] and data[prof][spell] then
      if rosterCount == 0 or rosterInfo(member) ~= nil then
        out = out or {}
        local r = rosterInfo(member)
        out[#out + 1] = {member, r and r.online or false, r and r.online and r.zone or nil, nil, level = r and r.level, class = r and r.class}
      end
    end
  end
  return out and sortKnowers(out)
end

-- Other OneForAll users (not in the guild) that know a recipe: list of
-- {name, online, zone, instanceType}. Online = heard from within ONLINE_WINDOW.
function FLT.GetOtherRecipeKnowers(prof, spell)
  if not shareEnabled() then return nil end
  local db = playerDB()
  if not db then return nil end
  local gdb = guildDB(false) or {}
  local out, t = nil, now()
  for player, data in pairs(db) do
    if not isMe(player) and type(data) == "table" and data[prof] and data[prof][spell]
       and rosterInfo(player) == nil and not gdb[player] then
      out = out or {}
      local st = status[player]
      local online = st and (t - st.t) < ONLINE_WINDOW or false
      out[#out + 1] = {player, online, online and st.zone or nil, online and st.inst or nil, level = st and st.level, class = st and st.class}
    end
  end
  return out and sortKnowers(out)
end

local function refreshBrowser()
  if FLT.RefreshRecipeBrowser then FLT.RefreshRecipeBrowser() end
end

-- ---------------------------------------------------------------------------
-- Hidden channel
-- ---------------------------------------------------------------------------
local function channelID()
  if not GetChannelName then return nil end
  local id = GetChannelName(CHANNEL)
  if id and id > 0 then return id end
  return nil
end

local function hideChannelFromChat()
  if not ChatFrame_RemoveChannel then return end
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local cf = _G["ChatFrame" .. i]
    if cf then pcall(ChatFrame_RemoveChannel, cf, CHANNEL) end
  end
end

local function joinChannel()
  if not shareEnabled() or channelID() then hideChannelFromChat(); return end
  if JoinTemporaryChannel then pcall(JoinTemporaryChannel, CHANNEL)
  elseif JoinChannelByName then pcall(JoinChannelByName, CHANNEL) end
  if C_Timer and C_Timer.After then C_Timer.After(1, hideChannelFromChat) end
end

local function leaveChannel()
  if channelID() and LeaveChannelByName then pcall(LeaveChannelByName, CHANNEL) end
end

-- Hide join/leave notices of the share channel.
if ChatFrame_AddMessageEventFilter then
  local function filter(_, _, _, _, _, chanString, _, _, _, _, chanName)
    if type(chanName) == "string" and chanName:lower() == CHANNEL:lower() then return true end
    if type(chanString) == "string" and chanString:lower():find(CHANNEL:lower(), 1, true) then return true end
    return false
  end
  ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", filter)
  ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE_USER", filter)
  ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", filter)
end

-- ---------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------
local queues = { GUILD = {}, CHANNEL = {} }
local sending = { GUILD = false, CHANNEL = false }

local function pump(dist)
  local msg = table.remove(queues[dist], 1)
  if not msg then sending[dist] = false; return end
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    if dist == "GUILD" then
      if guildName() then pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD") end
    else
      local id = channelID()
      if id and shareEnabled() then pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "CHANNEL", id) end
    end
  end
  local gap = dist == "GUILD" and GUILD_GAP or CHANNEL_GAP
  if C_Timer and C_Timer.After then C_Timer.After(gap, function() pump(dist) end) else pump(dist) end
end

local function send(dist, msg)
  local q = queues[dist]
  q[#q + 1] = msg
  if not sending[dist] then sending[dist] = true; pump(dist) end
end

-- Store own known recipes in the guild table (for alts) and return them.
local function ownRecipes()
  local out = {}
  if type(ForeverCompanionCharDB) ~= "table" or type(ForeverCompanionCharDB.professions) ~= "table" then return out end
  for prof, p in pairs(ForeverCompanionCharDB.professions) do
    if FLT.PROFESSION_RECIPES and FLT.PROFESSION_RECIPES[prof] and type(p.known) == "table" and next(p.known) then
      out[prof] = p.known
    end
  end
  local db = guildDB(true)
  local me = myName()
  if db and me then
    -- older versions stored own recipes under the first name only
    local f = firstName()
    if f and f ~= me and db[f] and db[f].own then db[f] = nil end
    local rec = {t = now(), own = true}
    for prof, known in pairs(out) do local c = {}; for s in pairs(known) do c[s] = true end; rec[prof] = c end
    db[me] = rec
  end
  return out
end

local function countKnown()
  local total = 0
  if type(ForeverCompanionCharDB) == "table" and type(ForeverCompanionCharDB.professions) == "table" then
    for _, p in pairs(ForeverCompanionCharDB.professions) do
      if type(p.known) == "table" then for _ in pairs(p.known) do total = total + 1 end end
    end
  end
  return total
end

local lastSent = { GUILD = 0, CHANNEL = 0 }
local pending = { GUILD = false, CHANNEL = false }
local lastSentCount = -1

local function broadcast(dist)
  pending[dist] = false
  if dist == "GUILD" and not guildName() then return end
  if dist == "CHANNEL" and not (shareEnabled() and channelID()) then return end
  local own = ownRecipes()
  for prof, known in pairs(own) do
    local ids = {}
    for s in pairs(known) do ids[#ids + 1] = enc(s) end
    table.sort(ids)
    send(dist, "B\t" .. prof)
    local chunk = ""
    for _, id in ipairs(ids) do
      if #chunk + #id + 1 > MAX_LEN - #prof - 3 then send(dist, "D\t" .. prof .. "\t" .. chunk); chunk = "" end
      chunk = (chunk == "" and id) or (chunk .. "," .. id)
    end
    if chunk ~= "" then send(dist, "D\t" .. prof .. "\t" .. chunk) end
  end
  lastSent[dist] = GetTime and GetTime() or 0
  lastSentCount = countKnown()
end

local function scheduleBroadcast(dist, delay)
  if pending[dist] then return end
  pending[dist] = true
  if C_Timer and C_Timer.After then C_Timer.After(delay, function() broadcast(dist) end) else broadcast(dist) end
end

-- Called after the profession window was scanned.
function FLT.OnProfessionScan()
  local total = countKnown()
  if total ~= lastSentCount then
    if lastSentCount < 0 then ownRecipes()
    else scheduleBroadcast("GUILD", 5); scheduleBroadcast("CHANNEL", 8) end
  end
end

-- Settings toggle for the channel sharing.
function FLT.IsRecipeShareEnabled() return shareEnabled() end
function FLT.SetRecipeShareEnabled(v)
  if type(ForeverCompanionDB) ~= "table" then return end
  ForeverCompanionDB.recipeShareChannel = v and true or false
  if v then joinChannel(); scheduleBroadcast("CHANNEL", 3); scheduleStatus(4) else leaveChannel() end
  refreshBrowser()
end

-- ---------------------------------------------------------------------------
-- Receiving
-- ---------------------------------------------------------------------------
local refreshPending = false
local function refreshSoon()
  if refreshPending then return end
  refreshPending = true
  if C_Timer and C_Timer.After then C_Timer.After(1, function() refreshPending = false; refreshBrowser() end)
  else refreshPending = false; refreshBrowser() end
end

selfIdentified = function()
  ownRecipes()
  refreshSoon()
end

-- Own messages come back to us. They carry this session's token, which tells
-- us the full name of the current character (also without a guild).
local SESSION = string.format("%x%x", math.random(0, 0xFFFFFF), math.floor((GetTime and GetTime() or 0) * 1000) % 0xFFFFFF)
local function learnOwnName(name)
  if type(ForeverCompanionCharDB) ~= "table" or not name then return end
  local pdb = playerDB()
  if pdb then pdb[name] = nil end
  status[name] = nil
  if ForeverCompanionCharDB.fullName ~= name then
    ForeverCompanionCharDB.fullName = name
    selfIdentified()
  else
    refreshSoon()
  end
end

local function onAddonMessage(prefix, msg, channel, sender)
  if prefix ~= PREFIX or type(msg) ~= "string" then return end
  if channel ~= "GUILD" and channel ~= "CHANNEL" then return end
  local who = shortName(sender)
  if not who then return end
  local kind, prof, data = msg:match("^(%a)\t?([^\t]*)\t?(.*)$")
  -- echo of our own hello / zone message?
  local token = (kind == "H" and prof) or (kind == "Z" and data:match("\t(%w+)$"))
  if token and token == SESSION then learnOwnName(who); return end
  if isMe(who) then return end
  if kind == "H" then
    -- only guild members ask; the channel relies on login + periodic broadcasts
    if channel == "GUILD" then
      local t = GetTime and GetTime() or 0
      if t - lastSent.GUILD > 20 then scheduleBroadcast("GUILD", 3 + math.random() * 7) end
    end
    return
  end
  if kind == "Z" then
    if channel == "CHANNEL" and shareEnabled() then
      -- data: inst [\t level \t class] \t token
      local f = {}
      for part in (data .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = part end
      local inst = f[1] or ""
      local level, class = nil, nil
      if #f >= 4 then level, class = tonumber(f[2]), (f[3] ~= "" and f[3] or nil) end
      -- 4.18.6+: map ID, so the zone shows in the reader's own language
      local zone = prof ~= "" and prof or nil
      local mapID = #f >= 5 and tonumber(f[4]) or nil
      if mapID and mapID > 0 and C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, mapID)
        if ok and info and info.name and info.name ~= "" then zone = info.name end
      end
      status[who] = {zone = zone, inst = inst ~= "" and inst ~= "none" and inst or nil, level = level, class = class, t = now()}
      refreshSoon()
    end
    return
  end
  if channel == "CHANNEL" then
    local st = status[who]
    if st then st.t = now() else status[who] = {t = now()} end
  end
  if not (prof and FLT.PROFESSION_RECIPES and FLT.PROFESSION_RECIPES[prof]) then return end
  local db
  if channel == "GUILD" then db = guildDB(true)
  elseif shareEnabled() then db = playerDB() end
  if not db then return end
  db[who] = db[who] or {}
  local rec = db[who]
  rec.t = now()
  if kind == "B" then
    rec[prof] = {}
  elseif kind == "D" then
    rec[prof] = rec[prof] or {}
    for id in data:gmatch("[^,]+") do local s = dec(id); if s then rec[prof][s] = true end end
    refreshSoon()
  end
end

local function pruneOldPlayers()
  local db = playerDB()
  if not db then return end
  local t = now()
  for name, data in pairs(db) do
    if type(data) ~= "table" or (t - (data.t or 0)) > PLAYER_EXPIRE then db[name] = nil end
  end
end

local lastStatus, statusPending = -100, false
local function sendStatus()
  statusPending = false
  if not (shareEnabled() and channelID()) then return end
  local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
  local inst = "none"
  if IsInInstance then local _, it = IsInInstance(); inst = it or "none" end
  local level = UnitLevel and UnitLevel("player") or 0
  local _, classFile = UnitClass and UnitClass("player")
  local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or 0
  send("CHANNEL", "Z\t" .. zone:gsub("\t", " ") .. "\t" .. inst .. "\t" .. tostring(level or 0) .. "\t" .. (classFile or "") .. "\t" .. tostring(mapID or 0) .. "\t" .. SESSION)
  lastStatus = GetTime and GetTime() or 0
end
scheduleStatus = function(delay)
  if statusPending then return end
  statusPending = true
  local t = GetTime and GetTime() or 0
  local wait = math.max(delay, 30 - (t - lastStatus)) -- at most one zone update per 30 s
  if C_Timer and C_Timer.After then C_Timer.After(wait, sendStatus) else sendStatus() end
end
local function heartbeat()
  scheduleStatus(0)
  if C_Timer and C_Timer.After then C_Timer.After(STATUS_EVERY, heartbeat) end
end

local function periodic()
  scheduleBroadcast("CHANNEL", 0)
  if C_Timer and C_Timer.After then C_Timer.After(REBROADCAST, periodic) end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local lastRosterRefresh = -100
local ev = CreateFrame("Frame")
for _, e in ipairs({"PLAYER_LOGIN", "CHAT_MSG_ADDON", "GUILD_ROSTER_UPDATE", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP"}) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_ADDON" then
    onAddonMessage(...)
  elseif event == "GUILD_ROSTER_UPDATE" then
    readRoster()
    local t = GetTime and GetTime() or 0
    if t - lastRosterRefresh > 30 then lastRosterRefresh = t; refreshSoon() end
  elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_LEVEL_UP" then
    if lastStatus > -100 then scheduleStatus(10) end
  elseif event == "PLAYER_LOGIN" then
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
    pruneOldPlayers()
    if C_Timer and C_Timer.After then
      -- guild info and channels are only ready a few seconds after login
      C_Timer.After(12, function()
        if guildName() then
          if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
          send("GUILD", "H\t" .. SESSION)
          broadcast("GUILD")
        end
        joinChannel()
      end)
      C_Timer.After(20, periodic)
      C_Timer.After(16, heartbeat)
    end
  end
end)
