local ADDON, FLT = ...

-- OneForAllAPI: the public door for plugins.
--
-- A plugin is a separate addon with "## Dependencies: OneForAll" in its .toc. It loads after OneForAll and reaches
-- OneForAll only through the global OneForAllAPI, never through OneForAll's own (private) tables. So OneForAll can be
-- updated without touching the plugins, and a plugin without touching OneForAll.
--
--   local API = OneForAllAPI
--   if not (API and API.VERSION >= 1) then return end
--
-- A plugin can READ everything OneForAll knows, and DO what this file offers. It can never change OneForAll:
--   * API.Data: all of OneForAll's data (dungeons, quests, items, sets, professions, books, pets, talents, maps...),
--     read only. Writing into it raises an error. Iterate with API.pairs / API.ipairs / API.Count (Lua 5.1's own
--     pairs, ipairs and # don't see through a read-only table), or take a plain copy with API.Copy.
--   * Every table the API returns is read only the same way (a dungeon, a boss, a book, saved data...).
--   * Options: a plugin reads OneForAll's options and writes only its own (API.NewOptions), kept apart from them.
--   * Its part of the Plugins page, slash commands, callbacks: a plugin adds its own; it can't replace or remove
--     anything.
--   * OneForAllAPI itself is read only: a plugin can't replace a function another plugin or OneForAll relies on.
-- (In WoW all addons share one Lua space, so nothing stops an addon that edits OneForAll's saved variables or frames on
--  its own. What this API guarantees is that it never hands out a way to change OneForAll.)
--
-- Rules:
--   * VERSION goes up when something is added. What is here stays as it is (a change would break the plugins).
--   * Name your own saved variables after your plugin, so they never meet OneForAll's.
--   * Register settings and slash commands while your addon loads (before the player opens the window).
--
-- Proposed for OneForAll 6.2.13; first user: the Dungeon Tracker plugin (OneForAll_DungeonTracker).

local api = { VERSION = 1 }
local plugins = {}            -- [name] = { name, version, title }
local callbacks = {}          -- [event] = { fn, ... }
local pluginSettings = {}     -- [plugin name] = { section defs, in order }: the Plugins page
FLT.PluginSlash = {}          -- [word] = { fn, help }, read by the /ofa command in Core.lua ("plugin_<x>", "plugins")

local function safe(tag, fn, ...) if FLT.SafeCall then return FLT.SafeCall(tag, fn, ...) end return pcall(fn, ...) end

-- Read-only views -----------------------------------------------------------------------------------------------------
-- A view is an empty table whose metatable reads the original: values come out as views too, functions and game
-- objects (frames) don't come out at all, and any write raises an error. One view per table (same table, same view),
-- so comparing two of them (d == found) works.
local views = setmetatable({}, { __mode = "k" })    -- original -> view
local origins = setmetatable({}, { __mode = "k" })  -- view -> original
local view
local function isObject(t) return type(rawget(t, 0)) == "userdata" end -- a frame, texture, font string...
local function out(v)
  local tv = type(v)
  if tv == "table" then
    if origins[v] then return v end
    if isObject(v) then return nil end
    return view(v)
  end
  if tv == "function" or tv == "userdata" or tv == "thread" then return nil end
  return v
end
local function readOnly() error("OneForAll: this table is read only (plugins can't change OneForAll)", 2) end
view = function(t)
  local p = views[t]
  if p then return p end
  p = setmetatable({}, { __index = function(_, k) return out(t[k]) end, __newindex = readOnly,
    __metatable = "OneForAll read-only" })
  views[t], origins[p] = p, t
  return p
end
-- the original behind a view (for OneForAll's own functions), anything else as it is
local function unwrap(v) return type(v) == "table" and origins[v] or v end

-- pairs / ipairs / # / a plain copy, for views and for plain tables alike
local root, fillRoot -- API.Data (below)
function api.pairs(t)
  local o = origins[t]
  if not o then return pairs(t) end
  if o == root then fillRoot() end
  local k
  return function()
    while true do
      local v
      k, v = next(o, k)
      if k == nil then return nil end
      local ov = out(v)
      if ov ~= nil then return out(k), ov end
    end
  end
end
function api.ipairs(t)
  local o = origins[t] or t
  local i = 0
  return function()
    i = i + 1
    local v = o[i]
    if v == nil then return nil end
    return i, out(v)
  end
end
function api.Count(t) return #(origins[t] or t) end
function api.IsReadOnly(t) return origins[t] ~= nil end
-- a plain, writable copy (yours: changing it changes nothing in OneForAll); functions and frames are left out
function api.Copy(t, seen)
  local o = origins[t] or t
  if type(o) ~= "table" then return o end
  seen = seen or {}
  if seen[o] then return seen[o] end
  local c = {}
  seen[o] = c
  for k, v in next, o do
    local tv = type(v)
    if tv == "table" then
      if not isObject(v) then c[api.Copy(k, seen)] = api.Copy(v, seen) end
    elseif tv ~= "function" and tv ~= "userdata" and tv ~= "thread" then
      c[api.Copy(k, seen)] = v
    end
  end
  return c
end

-- API.Data: OneForAll's data tables by name (FLT.DUNGEONS -> API.Data.DUNGEONS ...): the names in capitals, which
-- are data, never code. API.DataKeys() lists them.
local function isDataKey(k) return type(k) == "string" and k:match("^%u[%u%d_]*$") ~= nil and k ~= "UI" end
root = setmetatable({}, { __index = function(t, k)
  if not isDataKey(k) then return nil end
  local v = FLT[k]
  if v ~= nil and type(v) ~= "function" then rawset(t, k, v) end
  return v
end })
fillRoot = function() for k in pairs(FLT) do if isDataKey(k) then local _ = root[k] end end end
api.Data = view(root)
function api.DataKeys()
  fillRoot()
  local list = {}
  for k in pairs(root) do list[#list + 1] = k end
  table.sort(list)
  return list
end

-- About OneForAll ---------------------------------------------------------------------------------------------------

-- OneForAll's version, as in its .toc ("6.2.11")
function api.GetVersion()
  return (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
    or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "?"
end
-- the language chosen in OneForAll's settings: "enUS", "deDE", "frFR", "esES" or "ptBR". Changing it reloads the
-- interface, so reading it once while your addon loads is enough.
function api.GetLanguage() return FLT.Language and FLT.Language() or "enUS" end
-- one of OneForAll's own texts in the chosen language (the English text when it has none)
function api.Translate(text) return FLT.L and FLT.L[text] or text end
-- an English name from OneForAll's data (boss, NPC, item, quest, zone) in the chosen language when it is known
function api.Name(englishName) return FLT.Name and FLT.Name(englishName) or englishName end
-- a line in the chat with OneForAll's prefix
function api.Print(text) if FLT.Msg then FLT.Msg(text) end end
-- true when one of the values is a "secret" the client hides in combat (it can't be compared or shown)
function api.IsSecret(...) return FLT.IsSecret and FLT.IsSecret(...) or false end
-- runs fn(...) and keeps an error in OneForAll's error list (/ofa errors) instead of a Lua error popup; true when it ran
function api.SafeCall(tag, fn, ...) return safe(tag, fn, ...) end

-- Plugins -----------------------------------------------------------------------------------------------------------

-- tells OneForAll a plugin is there: name = its addon folder, info = { version = "1.0.0", title = "Dungeon Tracker" }.
-- Shown with /ofa plugins. A name already taken stays with its first plugin.
-- A plugin's command word: "plugin_" + its name without the "OneForAll_" prefix, in lower case
-- (OneForAll_DungeonTracker -> plugin_dungeontracker). Addon folder names are unique, so the words are too.
local function commandWord(name)
  local short = name:gsub("^[Oo]ne[Ff]or[Aa]ll[_%-]?", "")
  if short == "" then short = name end
  return "plugin_" .. (short:lower():gsub("[^%w_]", ""))
end
function api.RegisterPlugin(name, info)
  if type(name) ~= "string" or name == "" or plugins[name] then return false end
  info = type(info) == "table" and info or {}
  plugins[name] = { name = name, version = tostring(info.version or "?"), title = tostring(info.title or name) }
  return true
end
function api.GetPlugins()
  local list = {}
  for _, p in pairs(plugins) do
    list[#list + 1] = { name = p.name, version = p.version, title = p.title, command = p.command, alias = p.alias }
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

-- Callbacks ---------------------------------------------------------------------------------------------------------
-- fn(...) after something happened in OneForAll:
--   "OPTION_CHANGED" (key, value)   an option was changed (OneForAll's, or a plugin's: "plugin.<name>.<key>")
--   "TAB_SHOWN" (key)               a page of the window was shown ("dungeons", "professions", "plugins"...)
--   "WINDOW_SHOWN" / "WINDOW_HIDDEN" OneForAll's window opened / closed
--   "DATA_REFRESHED"                OneForAll read the bags / bank again (book and item states may have changed)
local EVENTS = { OPTION_CHANGED = true, TAB_SHOWN = true, WINDOW_SHOWN = true, WINDOW_HIDDEN = true, DATA_REFRESHED = true }
function api.RegisterCallback(event, fn)
  if not EVENTS[event] or type(fn) ~= "function" then return false end
  callbacks[event] = callbacks[event] or {}
  table.insert(callbacks[event], fn)
  return true
end
function api.UnregisterCallback(event, fn)
  for i, f in ipairs(callbacks[event] or {}) do
    if f == fn then table.remove(callbacks[event], i) return true end
  end
  return false
end
local function fire(event, ...)
  for _, fn in ipairs(callbacks[event] or {}) do safe("Plugin callback " .. event, fn, ...) end
end

-- Window and tabs ---------------------------------------------------------------------------------------------------

-- opens OneForAll's window on a page ("dungeons", "professions", "qol", "talents", "books", "pets", "settings",
-- "plugins"); nil: the window as it was
-- since 6.2.12 OneForAll builds its window and a page one frame after the other the first time (the game stops a
-- script that runs too long in combat): the same here, then fn
local function prepared(key, fn)
  local UI = FLT.UI
  if UI and UI.PrepareWindow then
    UI.PrepareWindow(key, function() FLT.SafeCall("Plugin API", fn) end)
  else
    fn()
  end
end
function api.OpenTab(key)
  if FLT.OpenPanel then prepared(key, function() FLT:OpenPanel(key) end) end
end
function api.ToggleWindow() if FLT.ToggleUI then FLT:ToggleUI() end end
function api.IsWindowShown() return FLT.UI and FLT.UI.IsWindowShown and FLT.UI.IsWindowShown() or false end
function api.GetActiveTab() return FLT.UI and FLT.UI.ActiveTab and FLT.UI.ActiveTab() or nil end
-- the tabs in their order: { { key = "dungeons", label = "Dungeons & Raids" (translated), shown = true }, ... }
function api.GetTabs()
  local list = {}
  local UI = FLT.UI
  local panels = UI and (UI.OrderedPanels and UI.OrderedPanels() or UI.panels) or {}
  for _, spec in ipairs(panels) do
    list[#list + 1] = { key = spec.key, label = api.Translate(spec.label or spec.key),
      shown = not (UI.IsTabVisible and not UI.IsTabVisible(spec.key)) }
  end
  return list
end

-- Dungeons ----------------------------------------------------------------------------------------------------------
-- A dungeon (read only): d.name (English, the key), d.bosses = { { name, npcID, rare, aliases }, ... } in the order of
-- the dungeon, d.instanceID (when known), d.minLevel / d.maxLevel, d.quests ...

-- every dungeon and raid OneForAll knows
function api.GetDungeons() return view(FLT.DUNGEONS or {}) end
-- the dungeon by its English name ("Ragefire Chasm")
function api.GetDungeon(name)
  for _, d in ipairs(FLT.DUNGEONS or {}) do if d.name == name then return view(d) end end
end
-- the dungeons that use this instance ID (GetInstanceInfo's 8th value), as a plain list. More than one where wings
-- share an instance: Scarlet Monastery, Dire Maul, Blackrock Spire. The WoW Forever dungeons have their ID in the
-- dungeon maps only.
local byID
function api.GetDungeonsByInstanceID(id)
  if not byID then
    byID = {}
    for _, d in ipairs(FLT.DUNGEONS or {}) do
      local m = FLT.DUNGEON_MAPS and FLT.DUNGEON_MAPS[d.name]
      local iid = d.instanceID or (type(m) == "table" and m.map)
      if iid then byID[iid] = byID[iid] or {}; table.insert(byID[iid], d) end
    end
  end
  local list = {}
  for i, d in ipairs(byID[id] or {}) do list[i] = view(d) end
  return list
end
-- the dungeon the player is in: d, sure (sure = false when OneForAll only guesses the wing, e.g. in a Scarlet
-- Monastery corridor without a known place name). nil outside a dungeon or in one OneForAll doesn't know.
function api.FindCurrentDungeon()
  if not FLT.FindCurrentDungeon then return nil end
  local d, sure = FLT.FindCurrentDungeon()
  return out(d), sure
end
-- a dungeon's name in the chosen language
function api.DungeonName(name) return FLT.DungeonName and FLT.DungeonName(name) or name end
-- true for a boss that only comes when summoned (Maraudon's Veng and Maraudos ...)
function api.IsSummonedBoss(npcID)
  return npcID ~= nil and FLT.BOSS_SUMMONED ~= nil and FLT.BOSS_SUMMONED[npcID] and true or false
end
-- opens OneForAll on a dungeon (a dungeon or its English name), on a boss when bossName (English) is given.
-- mode: "bosses" (default), "loot", "quests"; questID: a quest to show (mode "quests")
function api.OpenDungeon(d, bossName, mode, questID)
  if type(d) == "string" then d = api.GetDungeon(d) end
  d = unwrap(d)
  if type(d) ~= "table" then return false end
  if not FLT.OpenPanel then return false end
  prepared("dungeons", function()
    FLT:OpenPanel("dungeons") -- the tab builds UI.OpenDungeon when it is first opened
    if FLT.UI and FLT.UI.OpenDungeon then FLT.UI.OpenDungeon(d, bossName, mode, questID) end
  end)
  return true
end

-- Quests, books, items, recipes, map --------------------------------------------------------------------------------

function api.IsQuestDone(questID) return FLT.IsQuestDone and FLT:IsQuestDone(tonumber(questID)) or false end
-- true when a quest gives no more experience at the player's level
function api.IsQuestGrey(questID, level) return FLT.IsQuestGrey and FLT.IsQuestGrey(tonumber(questID), level) or false end
-- a quest's details: { id, name, lvl, req, side, cls, races, giver, loc = { mapID, x, y }, ... } (read only) or nil
function api.GetQuestInfo(questID) return FLT.QuestInfo and out(FLT.QuestInfo(tonumber(questID))) or nil end
-- true when a quest is for the player's faction, class and race (6.2.12: of a step's variants, only the player's)
function api.IsQuestForMe(questID)
  local q = FLT.QuestInfo and FLT.QuestInfo(tonumber(questID))
  if not (q and FLT.QuestForMe) then return false end
  return FLT.QuestForMe(q) and true or false
end
-- true once a raid is open on the server (6.2.12: Onyxia's Lair, Hyjal Summit and Barrow Deeps open later); a dungeon
-- (from GetDungeon) or its English name
function api.IsRaidOpen(d)
  if type(d) == "table" then d = unwrap(d).name end
  if type(d) ~= "string" or not FLT.RaidOpen then return true end
  return FLT.RaidOpen(d) and true or false
end
-- where a quest starts / is turned in: { mapID, x, y, ... } (read only) or nil
function api.GetQuestStart(questID) return FLT.QuestLoc and out(FLT:QuestLoc(tonumber(questID))) or nil end
function api.GetQuestEnd(questID) return FLT.QuestEndLoc and out(FLT:QuestEndLoc(tonumber(questID))) or nil end
-- puts a quest's start on the world map (quest: from API.Data, or { id = questID })
function api.ShowQuestStartOnMap(quest)
  if FLT.ShowQuestStartOnMap and type(quest) == "table" then FLT:ShowQuestStartOnMap(api.Copy(quest)) end
end

-- the library book a quest belongs to (read only) or nil
function api.FindBookByQuestID(questID) return FLT.FindBookByQuestID and out(FLT:FindBookByQuestID(questID)) or nil end
-- a book's state for this character: "done", "manual", "bag", "bank", "questflag" or "missing"
function api.GetBookState(book)
  book = unwrap(book)
  if not (FLT.GetBookState and type(book) == "table" and type(OneForAllCharDB) == "table") then return nil end
  return FLT:GetBookState(book)
end
-- books turned in, books owned (turned in + in the bags or bank)
function api.GetBookCounts() if FLT.GetCounts and type(OneForAllCharDB) == "table" then return FLT:GetCounts() end return 0, 0 end
-- opens the Library Books tab on a book
function api.ShowBook(book)
  book = unwrap(book)
  if type(book) ~= "table" then return false end
  if not FLT.OpenPanel then return false end
  prepared("books", function()
    FLT:OpenPanel("books")
    if FLT.UI and FLT.UI.ShowBook then FLT.UI.ShowBook(book) end
  end)
  return true
end
-- puts a book on the world map
function api.ShowBookOnMap(book)
  book = unwrap(book)
  if FLT.ShowOnMap and type(book) == "table" then FLT:ShowOnMap(book) end
end

-- where an item is for this character, as OneForAll last saw it: "bag", "bank", "missing" or "unknown"
function api.GetItemStorageState(itemID) return FLT.GetItemStorageState and FLT:GetItemStorageState(tonumber(itemID)) or "unknown" end

-- a recipe's full name ("Recipe: ..."), and its item link (recipe: from API.Data.PROFESSION_RECIPES ...)
function api.GetRecipeFullName(recipe) return FLT.GetRecipeFullName and FLT:GetRecipeFullName(unwrap(recipe)) or nil end
function api.GetRecipeItemLink(recipe) return FLT.GetRecipeItemLink and FLT:GetRecipeItemLink(unwrap(recipe)) or nil end

-- a zone's map ID (English zone name) or nil
function api.FindMapID(zone) return FLT.FindMapID and FLT:FindMapID(zone) or nil end

-- Saved data (read only) --------------------------------------------------------------------------------------------
-- What OneForAll saved for this character (books turned in, bank contents, tabs...) and for the account (options,
-- profiles...). Read only, as it is now: read it again when you need it.
function api.GetCharacterKey() return FLT.CharKey and FLT.CharKey() or nil end
function api.GetCharacterData() return type(OneForAllCharDB) == "table" and view(OneForAllCharDB) or nil end
function api.GetAccountData() return type(OneForAllDB) == "table" and view(OneForAllDB) or nil end

-- Options -----------------------------------------------------------------------------------------------------------

-- one of OneForAll's own options, read only (a table comes out read only)
function api.GetOption(key) return out(FLT.QoL and FLT.QoL.Get(key)) end
-- fn(value) after one of OneForAll's options changed; as many as you like
function api.OnOptionChanged(key, fn)
  if type(fn) ~= "function" then return false end
  return api.RegisterCallback("OPTION_CHANGED", function(k, v) if k == key then fn(v) end end)
end

-- A plugin's own options. Stored with OneForAll's options, in the profile the character uses (exported and imported
-- with it), under "plugin.<name>.<key>": OneForAll's keys never have a dot, so a plugin's options can never meet
-- OneForAll's or another plugin's.
--   local opts = API.NewOptions("OneForAll_DungeonTracker", { solo = true, hideTime = false })
--   opts:Get("solo")  opts:Set("solo", false)  opts:OnChanged("solo", function(value) ... end)
-- name: the name given to RegisterPlugin (one options object per plugin). defaults: their types are checked when a
-- profile is imported; an option may also have no default (a window position).
local optionSets = {}
function api.NewOptions(name, defaults)
  if not plugins[name] or optionSets[name] then return nil end
  local prefix = "plugin." .. name .. "."
  local d = FLT.QoL and FLT.QoL.DEFAULTS
  if type(d) == "table" and type(defaults) == "table" then
    for k, v in pairs(defaults) do
      if type(k) == "string" and type(v) ~= "function" and type(v) ~= "table" then d[prefix .. k] = v end
    end
  end
  local o = {}
  function o:Get(key) return FLT.QoL and FLT.QoL.Get(prefix .. tostring(key)) end
  function o:Set(key, value)
    if type(value) == "function" or type(value) == "userdata" then return false end
    if FLT.QoL then FLT.QoL.Set(prefix .. tostring(key), value) end
    return true
  end
  function o:OnChanged(key, fn)
    if type(fn) ~= "function" then return false end
    local full = prefix .. tostring(key)
    return api.RegisterCallback("OPTION_CHANGED", function(k, v) if k == full then fn(v) end end)
  end
  optionSets[name] = o
  return setmetatable({}, { __index = o, __newindex = readOnly, __metatable = "OneForAll read-only" })
end

-- Plugins page: the settings of each plugin --------------------------------------------------------------------------

-- a section of settings of your plugin, on its own part of the Plugins page (several sections stack in their order):
--   API.AddSettingsSection("OneForAll_DungeonTracker", { title = "Dungeon Tracker", icon = "Interface\\Icons\\...",
--     build = function(s)
--       s:check(label, hint, get, set[, x, compact, width])  -- a switch; get() -> boolean, set(boolean)
--       s:button(text, width, onClick[, x])                  -- a gold button
--       s:text(str)                                          -- a grey line of text
--       s:nextRow()                                          -- the next row
--       s.width                                              -- the section's width
--     end })
-- name: the name given to RegisterPlugin. The section takes the whole width of the page's right side (at least 488):
-- s.width tells it, to place two switches side by side (x = 0 and s.width / 2). Labels that don't fit wrap onto a
-- second line. Built the first time the plugin's page is shown.
function api.AddSettingsSection(name, def)
  if not plugins[name] or type(def) ~= "table" or type(def.build) ~= "function" then return false end
  pluginSettings[name] = pluginSettings[name] or {}
  table.insert(pluginSettings[name], { title = tostring(def.title or plugins[name].title), icon = def.icon, build = def.build })
  return true
end

-- a block of your own on your part of the Plugins page, under your settings sections, for anything they can't show
-- (a list, a summary, a preview...):
--   API.AddPluginContent("MyPlugin", { title = "Statistics", icon = "Interface\\Icons\\...", height = 200,
--     build = function(frame, width) ... end })  -- frame: yours, width x height, built once
function api.AddPluginContent(name, def)
  if not plugins[name] or type(def) ~= "table" or type(def.build) ~= "function" then return false end
  pluginSettings[name] = pluginSettings[name] or {}
  table.insert(pluginSettings[name], { content = true, title = tostring(def.title or plugins[name].title), icon = def.icon,
    height = math.max(20, math.min(2000, tonumber(def.height) or 120)), build = def.build })
  return true
end

-- Slash commands ----------------------------------------------------------------------------------------------------

-- /ofa plugin_<name> [rest]: a plugin's own command, one per plugin. Every /ofa word starting with "plugin_" is the
-- plugins', and every other one stays OneForAll's, so a new OneForAll command never takes a plugin's.
-- * The word comes from the plugin's folder name, in lower case: MyBosses -> plugin_mybosses. A leading "OneForAll_"
--   (or "OneForAll-") is dropped, so OneForAll_DungeonTracker -> plugin_dungeontracker. Folder names are unique, so
--   two plugins never share one.
-- * alias (optional): a short name as well (alias "dt" -> plugin_dt), for the first plugin that asks for it.
-- fn(rest) gets what follows the word ("" when nothing does; in lower case: the plugin reads its own sub-commands
-- from it). help: one line, shown by /ofa plugins and on the plugin's page.
-- Returns the command ("/ofa plugin_dungeontracker") and the alias's ("/ofa plugin_dt", or nil when not given or
-- taken), or false (plugin not registered, or already has a command).
local function plainWord(s) return (tostring(s):lower():gsub("[^%w_]", "")) end
function api.RegisterSlashCommand(name, fn, help, alias)
  local p = type(name) == "string" and plugins[name]
  if not p or type(fn) ~= "function" or p.command then return false end
  local word = commandWord(name)
  if FLT.PluginSlash[word] then return false end
  local entry = { fn = fn, help = type(help) == "string" and help or nil, plugin = name }
  FLT.PluginSlash[word] = entry
  p.command = "/ofa " .. word
  if type(alias) == "string" then
    local short = plainWord(alias)
    local aw = short ~= "" and ("plugin_" .. short) or nil
    if aw and not FLT.PluginSlash[aw] then
      FLT.PluginSlash[aw] = entry
      p.alias = "/ofa " .. aw
    end
  end
  return p.command, p.alias
end

-- /ofa plugin_<something> that no plugin has (called by Core.lua): say so, rather than opening the window
function FLT.PluginSlashUnknown(word)
  api.Print(string.format(api.Translate("No plugin answers to /ofa %s. /ofa plugins lists the plugins' commands."), word))
end

-- Widgets: OneForAll's look, on frames of your own -------------------------------------------------------------------
local W = {}
api.Widgets = W
-- OneForAll's dark panel with the gold frame
function W.FramedPanel(frame) if FLT.UI and FLT.UI.FramedPanel then return FLT.UI.FramedPanel(frame) end end
-- the square close button (X); onClick() when clicked
function W.CloseButton(parent, onClick) if FLT.UI and FLT.UI.CloseButton then return FLT.UI.CloseButton(parent, onClick) end end
-- a gold button
function W.GoldButton(parent, text, width, height)
  if FLT.UI and FLT.UI.GoldButton then return FLT.UI.GoldButton(parent, text, width or 120, height or 24, nil, 12) end
end
-- a Yes / No question; onYes() on Yes
function W.Confirm(text, onYes) if FLT.UI and FLT.UI.Confirm then FLT.UI.Confirm(text, onYes) else onYes() end end
-- a font string in OneForAll's font
function W.FontString(parent, layer, template)
  if FLT.NewFS then return FLT.NewFS(parent, nil, layer or "OVERLAY", template or "GameFontNormal") end
  return parent:CreateFontString(nil, layer or "OVERLAY", template or "GameFontNormal")
end
-- sets a texture by path (works with the game's own and with addon files)
function W.SetTexture(tex, path, ...) if FLT.SetTex then return FLT.SetTex(tex, path, ...) end return tex:SetTexture(path, ...) end
-- a color in the chosen skin (r, g, b in, r, g, b out)
function W.SkinColor(r, g, b) if FLT.SkinC then return FLT.SkinC(r, g, b) end return r, g, b end

-- Where the callbacks come from (OneForAll's own functions, watched from here) -----------------------------------------
-- an option changed: after QoL.Set (OneForAll's own handler for it runs as before)
if FLT.QoL and FLT.QoL.Set then
  local set = FLT.QoL.Set
  FLT.QoL.Set = function(key, value, ...)
    local r = set(key, value, ...)
    fire("OPTION_CHANGED", key, out(value))
    return r
  end
end
-- bags / bank read again
if FLT.Refresh then
  local refresh = FLT.Refresh
  FLT.Refresh = function(self, ...)
    local r = refresh(self, ...)
    fire("DATA_REFRESHED")
    return r
  end
end
-- tabs shown, window shown / hidden: every page (OneForAll's and the plugins') tells when it shows; the window is
-- hooked when its first page is built
local windowHooked
local function watchPanel(spec)
  if spec.ofaWatched then return end
  spec.ofaWatched = true
  local create = spec.create
  spec.create = function(parent, ...)
    local panel = create(parent, ...)
    if panel and panel.HookScript then panel:HookScript("OnShow", function() fire("TAB_SHOWN", spec.key) end) end
    if not windowHooked and parent and parent.HookScript then
      windowHooked = true
      parent:HookScript("OnShow", function() fire("WINDOW_SHOWN") end)
      parent:HookScript("OnHide", function() fire("WINDOW_HIDDEN") end)
    end
    return panel
  end
end
if FLT.UI and FLT.UI.RegisterPanel and FLT.UI.panels then
  for _, spec in ipairs(FLT.UI.panels) do watchPanel(spec) end
  local register = FLT.UI.RegisterPanel
  FLT.UI.RegisterPanel = function(spec, ...)
    if type(spec) == "table" and type(spec.create) == "function" then watchPanel(spec) end
    return register(spec, ...)
  end
end

-- The Plugins page --------------------------------------------------------------------------------------------------
-- Left: the plugins (addons with "## Dependencies: OneForAll"), loaded or not, each with a switch to turn it on or off
-- (as in the game's AddOns list: after a reload). Right: the chosen plugin's description and its settings sections.
-- It opens from a button in the window's title bar, there only when a plugin is installed.
local L = FLT.L or setmetatable({}, { __index = function(_, k) return k end })
local function N(s) return s end -- (an English text translated where it is shown)

local function meta(name, field)
  return (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(name, field))
    or (GetAddOnMetadata and GetAddOnMetadata(name, field)) or nil
end
-- the installed plugins: { name, title, version, notes, author, loaded, enabled }
local function installedPlugins()
  local list, seen = {}, {}
  local num = (C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns()) or (GetNumAddOns and GetNumAddOns()) or 0
  local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
  local getDeps = (C_AddOns and C_AddOns.GetAddOnDependencies) or GetAddOnDependencies
  local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  for i = 1, num do
    local name, _, _, loadable, reason
    if getInfo then name, _, _, loadable, reason = getInfo(i) end
    local deps = getDeps and { getDeps(i) } or {}
    local ours = false
    for _, d in ipairs(deps) do if d == ADDON then ours = true end end
    if type(name) == "string" and ours then
      seen[name] = true
      local loaded = isLoaded and isLoaded(name) and true or false
      -- on or off for the next load, as the game's AddOns list shows it: GetAddOnInfo's reason is "DISABLED" for an
      -- addon turned off (GetAddOnEnableState isn't reliable here: its arguments differ between clients)
      local enabled
      if reason == "DISABLED" then enabled = false
      elseif loadable ~= nil or reason ~= nil then enabled = true
      else enabled = loaded end
      list[#list + 1] = { name = name, title = plugins[name] and plugins[name].title or (meta(name, "Title") or name),
        version = plugins[name] and plugins[name].version or meta(name, "Version") or "?",
        notes = meta(name, "Notes"), author = meta(name, "Author"),
        loaded = loaded, enabled = enabled }
    end
  end
  -- registered without a dependency line (should not happen): listed too
  for name, p in pairs(plugins) do
    if not seen[name] then
      list[#list + 1] = { name = name, title = p.title, version = p.version, notes = meta(name, "Notes"),
        author = meta(name, "Author"), loaded = true, enabled = true }
    end
  end
  table.sort(list, function(a, b) return a.title:lower() < b.title:lower() end)
  return list
end
api.GetInstalledPlugins = function() return api.Copy(installedPlugins()) end

local function setEnabled(name, on)
  local f = on and ((C_AddOns and C_AddOns.EnableAddOn) or EnableAddOn) or ((C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn)
  if f then pcall(f, name) end
end

local SEC_W = 488 -- the narrowest a section gets; it takes the whole width of the page's right side
-- a scroll area without a visible bar: the mouse wheel scrolls it (both columns of the Plugins page)
local function wheelScroll(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(10, 10)
  sf:SetScrollChild(child)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange() or 0
    local y = (self:GetVerticalScroll() or 0) - (tonumber(delta) or 0) * 40
    self:SetVerticalScroll(math.max(0, math.min(range, y)))
  end)
  -- back inside the range when the content got shorter
  sf:SetScript("OnScrollRangeChanged", function(self, _, yrange)
    local range = tonumber(yrange) or self:GetVerticalScrollRange() or 0
    if (self:GetVerticalScroll() or 0) > range then self:SetVerticalScroll(math.max(0, range)) end
  end)
  return sf, child
end

local function createPluginsPanel(parent)
  local UI = FLT.UI
  local panel = CreateFrame("Frame", nil, parent)
  UI.PlacePanel(panel, parent)
  UI.TitleBand(panel, { emblem = UI.ASSET_ROOT .. "emblem_settings", art = UI.ASSET_ROOT .. "settings_banner",
    title = L["Plugins"], subtitle = L["Addons that plug into OneForAll. Their options are saved in the profile this character uses."], fadeRight = 200 })

  -- left: the list
  local listBox = CreateFrame("Frame", nil, panel)
  listBox:SetPoint("TOPLEFT", 8, -78); listBox:SetPoint("BOTTOMLEFT", 8, 8); listBox:SetWidth(250)
  UI.FramedPanel(listBox)
  -- the plugins one under the other; the mouse wheel scrolls them once they don't fit (no visible bar)
  local listScroll, listChild = wheelScroll(listBox)
  listScroll:SetPoint("TOPLEFT", 4, -4); listScroll:SetPoint("BOTTOMRIGHT", -4, 4)
  listChild:SetWidth(250 - 8)
  local rows, selected, current = {}, nil, {}
  local pages = {}

  -- right: the chosen plugin's page; the mouse wheel scrolls it (no visible bar)
  local sf = wheelScroll(panel)
  sf:SetPoint("TOPLEFT", 270, -74); sf:SetPoint("BOTTOMRIGHT", -8, 4)
  local empty = FLT.NewFS(panel, nil, "OVERLAY", "GameFontDisable")
  empty:SetPoint("TOPLEFT", 290, -100); empty:SetText(L["No plugins."])

  -- a settings section on a page, as on OneForAll's Settings page
  local function section(page, state, label, icon)
    local box = CreateFrame("Frame", nil, page)
    local W = state.w or SEC_W
    box:SetPoint("TOPLEFT", 4, state.y); box:SetWidth(W)
    UI.FramedPanel(box)
    local band = UI.makeTexture(box, "BORDER", 0.09, 0.075, 0.05, 0.85); band:SetPoint("TOPLEFT", 3, -3); band:SetPoint("TOPRIGHT", -3, -3); band:SetHeight(28)
    local ic = box:CreateTexture(nil, "OVERLAY"); ic:SetSize(20, 20); ic:SetPoint("TOPLEFT", 10, -6)
    FLT.SetTex(ic, icon or "Interface\\Icons\\INV_Misc_Gear_08"); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local t = FLT.NewFS(box, nil, "OVERLAY", "GameFontNormal"); t:SetPoint("LEFT", ic, "RIGHT", 8, 0); t:SetText(label)
    t:SetTextColor(FLT.SkinC(1, 0.82, 0.20))
    local s = { y = -40, rowMax = -40, box = box, width = W }
    function s:check(text, hint, get, set, x, compact, w)
      local cx = 12 + (tonumber(x) or 0)
      local cb = FLT.SkinBlizz(CreateFrame("CheckButton", nil, box, "UICheckButtonTemplate"))
      cb:SetSize(24, 24); cb:SetPoint("TOPLEFT", cx, self.y)
      local l = FLT.NewFS(box, nil, "OVERLAY", "GameFontHighlight")
      l:SetPoint("TOPLEFT", cb, "TOPRIGHT", 4, -5)
      l:SetWidth(tonumber(w) or (W - cx - 38)); l:SetJustifyH("LEFT"); l:SetWordWrap(true); l:SetText(tostring(text))
      local lh = math.max(14, l:GetStringHeight() or 14)
      cb:SetScript("OnClick", function(btn) safe("Plugin setting", set, btn:GetChecked() and true or false) end)
      local h = math.max(30, lh + 16)
      if hint and not compact then
        local d = FLT.NewFS(box, nil, "OVERLAY", "GameFontDisableSmall")
        d:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -3); d:SetWidth(tonumber(w) or (W - cx - 44)); d:SetJustifyH("LEFT"); d:SetText(hint)
        h = lh + 12 + math.max(12, d:GetStringHeight() or 12) + 4
      end
      if hint then
        cb:SetScript("OnEnter", function(btn)
          GameTooltip:SetOwner(btn, "ANCHOR_RIGHT"); GameTooltip:AddLine(text, 1, 0.82, 0)
          GameTooltip:AddLine(hint, 1, 1, 1, true); GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
      end
      state.refreshers[#state.refreshers + 1] = function() local ok, v = pcall(get); cb:SetChecked(ok and v and true or false) end
      self.rowMax = math.min(self.rowMax, self.y - h)
      return cb
    end
    function s:nextRow() self.y = self.rowMax end
    function s:button(text, bw, onClick, x)
      local b = UI.GoldButton(box, text, bw or 160, 24, nil, 12); b:SetPoint("TOPLEFT", 12 + (tonumber(x) or 0), self.y - 2)
      b:SetScript("OnClick", function() safe("Plugin button", onClick) end)
      self.rowMax = math.min(self.rowMax, self.y - 34)
      return b
    end
    function s:text(str)
      local d = FLT.NewFS(box, nil, "OVERLAY", "GameFontDisableSmall")
      d:SetPoint("TOPLEFT", 14, self.y - 2); d:SetWidth(W - 28); d:SetJustifyH("LEFT"); d:SetText(str)
      self.rowMax = math.min(self.rowMax, self.y - math.max(14, d:GetStringHeight() or 14) - 10)
      self:nextRow()
    end
    function s:finish()
      self:nextRow()
      local height = -self.y + 6
      box:SetHeight(height)
      state.y = state.y - height - 12
    end
    return s
  end

  -- a plugin's page: what it is, its switch, its settings
  local function buildPage(p)
    local page = CreateFrame("Frame", nil, sf)
    -- the sections as wide as the right side (the page is built when first shown, so the width is known)
    local W = math.max(SEC_W, math.floor((tonumber(sf:GetWidth() or 0) or 0) - 10))
    page:SetSize(W + 8, 10)
    local state = { y = -4, refreshers = {}, w = W }
    local head = section(page, state, p.title .. "  |cff9d9d9d" .. p.version .. "|r", "Interface\\Icons\\INV_Misc_Gear_08")
    if p.notes and p.notes ~= "" then head:text(p.notes) end
    if p.author and p.author ~= "" then head:text(string.format(L["By %s"], p.author)) end
    local reg = plugins[p.name]
    if reg and reg.command then
      head:text(string.format(L["Command: %s"], reg.command .. (reg.alias and ("  |cff9d9d9d(" .. reg.alias .. ")|r") or "")))
    end
    -- the switch, and right of it the Reload button once there is something to apply
    local reload
    local rowY = head.y
    head:check(L["Enabled"], L["Turns the plugin on or off, as in the game's AddOns list. The change applies after a reload."],
      function() return p.wanted == nil and p.enabled or p.wanted end,
      function(v) p.wanted = v; setEnabled(p.name, v); if reload then reload:SetShown(v ~= p.loaded) end end,
      0, false, W - 200)
    reload = UI.GoldButton(head.box, L["Reload"], 120, 24, nil, 12)
    reload:SetPoint("TOPRIGHT", head.box, "TOPRIGHT", -14, rowY - 2)
    reload:SetScript("OnClick", function() if ReloadUI then ReloadUI() end end)
    reload:SetShown(p.wanted ~= nil and p.wanted ~= p.loaded)
    head:nextRow()
    head:finish()
    if p.loaded then
      local defs = pluginSettings[p.name] or {}
      if #defs == 0 then
        local s = section(page, state, L["Options"], "Interface\\Icons\\INV_Misc_Note_01"); s:text(L["This plugin has no options."]); s:finish()
      end
      for _, def in ipairs(defs) do
        local s = section(page, state, def.title, def.icon)
        if def.content then
          local f = CreateFrame("Frame", nil, s.box)
          f:SetPoint("TOPLEFT", 12, s.y); f:SetSize(W - 24, def.height)
          safe("Plugin content " .. p.name, def.build, f, W - 24)
          s.rowMax = s.y - def.height - 6
        else
          safe("Plugin settings " .. p.name, def.build, s)
        end
        s:finish()
      end
    else
      local s = section(page, state, L["Options"], "Interface\\Icons\\INV_Misc_Note_01")
      s:text(L["This plugin is turned off. Turn it on and reload to see its options."]); s:finish()
    end
    page:SetHeight(-state.y + 8)
    page.refresh = function() for _, f in ipairs(state.refreshers) do f() end end
    return page
  end

  local function show(name)
    selected = name
    for key, page in pairs(pages) do page:Hide() end
    for _, r in ipairs(rows) do r.hi:SetShown(r.name == name) end
    for _, p in ipairs(current) do
      if p.name == name then
        pages[name] = pages[name] or buildPage(p)
        sf:SetScrollChild(pages[name]); pages[name]:Show(); pages[name].refresh()
        sf:SetVerticalScroll(0)
      end
    end
  end

  function panel:Refresh()
    local list = installedPlugins()
    -- keep what was switched in this session (the game applies it after the reload)
    for _, p in ipairs(list) do for _, old in ipairs(current) do if old.name == p.name then p.wanted = old.wanted end end end
    current = list
    empty:SetShown(#list == 0)
    for i, p in ipairs(list) do
      local r = rows[i]
      if not r then
        r = CreateFrame("Button", nil, listChild)
        r:SetHeight(36); r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 38); r:SetPoint("TOPRIGHT", -2, -2 - (i - 1) * 38)
        r.hi = UI.makeTexture(r, "BACKGROUND", 0.90, 0.66, 0.22, 0.16); r.hi:SetAllPoints(); r.hi:Hide()
        r.hover = UI.makeTexture(r, "BACKGROUND", 1, 1, 1, 0.05); r.hover:SetAllPoints(); r.hover:Hide()
        r.title = FLT.NewFS(r, nil, "OVERLAY", "GameFontNormal"); r.title:SetPoint("TOPLEFT", 8, -4); r.title:SetPoint("RIGHT", -8, 0)
        r.title:SetJustifyH("LEFT"); r.title:SetWordWrap(false)
        r.sub = FLT.NewFS(r, nil, "OVERLAY", "GameFontDisableSmall"); r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -3)
        r:SetScript("OnEnter", function(self) self.hover:Show() end)
        r:SetScript("OnLeave", function(self) self.hover:Hide() end)
        r:SetScript("OnClick", function(self) show(self.name) end)
        rows[i] = r
      end
      r.name = p.name
      r.title:SetText(p.title)
      r.sub:SetText(p.version .. "  -  " .. (p.loaded and L["On"] or L["Off"]))
      r:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    listChild:SetHeight(math.max(10, #list * 38 + 4))
    local keep
    for _, p in ipairs(list) do if p.name == selected then keep = selected end end
    if keep or list[1] then show(keep or list[1].name) end
  end
  panel:SetScript("OnShow", function(self) self:Refresh() end)
  return panel
end

-- the tab, once the plugins have loaded (they load after OneForAll, before the player can open the window)
do
  local boot = CreateFrame("Frame")
  boot:RegisterEvent("PLAYER_LOGIN")
  boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if #installedPlugins() == 0 or not (FLT.UI and FLT.UI.RegisterPanel) or _G.OneForAllFrame then return end
    -- no tab (the tab bar is full): a button in the title bar, left of the Discord button (UI/MainFrame.lua: noTab)
    FLT.UI.RegisterPanel({ key = "plugins", label = N"Plugins", noTab = true, icon = "Interface\\Icons\\Trade_Engineering",
      tooltip = N"Plugins installed for OneForAll, their options, on or off.", create = createPluginsPanel, combatLock = true })
  end)
end

-- OneForAllAPI: read only, so no plugin can replace a function OneForAll or another plugin relies on
local function lock(t)
  for k, v in pairs(t) do if type(v) == "table" and k ~= "Data" then t[k] = lock(v) end end
  return setmetatable({}, { __index = t, __newindex = readOnly, __metatable = "OneForAll read-only" })
end
OneForAllAPI = lock(api)

-- /ofa plugins: the plugins that registered, with their command (OneForAll's own word, not a plugin's)
FLT.PluginSlash.plugins = { fn = function()
  local list = api.GetPlugins()
  if #list == 0 then api.Print(api.Translate("No plugins.")) return end
  for _, p in ipairs(list) do
    api.Print(p.title .. " " .. p.version .. (p.command and ("  -  " .. p.command) or "")
      .. (p.alias and (" (" .. p.alias .. ")") or ""))
    local h = p.command and FLT.PluginSlash[p.command:sub(6)]
    if h and h.help then api.Print("    " .. h.help) end
  end
end }
