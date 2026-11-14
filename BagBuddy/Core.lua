-- BagBuddy: settings, shared helpers, events and the /bud command.
local ADDON, ns = ...

ns.ADDON = ADDON
ns.VERSION = 1

local DEFAULTS = {
	tooltips = true,   -- "upgrade for ..." lines in item tooltips
	debug = false,
	peers = {},        -- [Name-Realm] = { snap = {...}, hash = "...", time = epoch, partner = bool, role = "tank"/nil }
	point = nil,       -- viewer position
}

local function CopyDefaults(defaults, db)
	for key, value in pairs(defaults) do
		if db[key] == nil then
			if type(value) == "table" then
				db[key] = {}
				CopyDefaults(value, db[key])
			else
				db[key] = value
			end
		end
	end
	return db
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local IsSecret = issecretvalue or function() return false end

-- A value an addon may read and compare: not nil and not a Midnight secret
function ns.Usable(value)
	return value ~= nil and not IsSecret(value)
end

function ns.Print(text)
	print("|cff66bbffBagBuddy|r: " .. tostring(text))
end

function ns.Debug(text)
	if ns.db and ns.db.debug then ns.Print("|cff999999" .. tostring(text) .. "|r") end
end

-- This character as "Name-Realm", the way addon messages name senders
function ns.Me()
	local name, realm = UnitFullName("player")
	if not realm or realm == "" then realm = GetNormalizedRealmName and GetNormalizedRealmName() or "" end
	if realm == "" then return name end
	return name .. "-" .. realm
end

-- "Name-Realm" from a name the game gave (an addon message's sender). Never changes letter case:
-- Forever names can have spaces ("Turtle Jerry"), and a whisper to a misspelled name fails.
function ns.FullName(name)
	if type(name) ~= "string" or IsSecret(name) or name == "" then return nil end
	name = name:gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then return nil end
	if not name:find("-", 1, true) then
		local realm = GetNormalizedRealmName and GetNormalizedRealmName()
		if realm and realm ~= "" then name = name .. "-" .. realm end
	end
	return name
end

function ns.SamePlayer(a, b)
	return a and b and a:lower() == b:lower()
end

-- The exact name of a typed player, found in the group or on the friends list; nil if neither
function ns.ResolveName(typed)
	typed = typed and typed:gsub("^%s+", ""):gsub("%s+$", "")
	if not typed or typed == "" then return nil end
	local want = typed:lower()
	local function match(name)
		if type(name) ~= "string" or IsSecret(name) then return nil end
		local full = ns.FullName(name)
		if full and (full:lower() == want or ns.Short(full):lower() == want or name:lower() == want) then return full end
	end
	local units = { "target" }
	for i = 1, 4 do table.insert(units, "party" .. i) end
	for i = 1, 40 do table.insert(units, "raid" .. i) end
	for _, unit in ipairs(units) do
		if UnitExists(unit) and UnitIsPlayer(unit) then
			local name, realm = UnitName(unit)
			if name and realm and realm ~= "" then name = name .. "-" .. realm end
			local found = match(name)
			if found then return found end
		end
	end
	if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
		for i = 1, C_FriendList.GetNumFriends() or 0 do
			local friend = C_FriendList.GetFriendInfoByIndex(i)
			local found = friend and match(friend.name)
			if found then return found end
		end
	end
	return nil
end

-- Who to whisper: just the name for someone on our realm
function ns.WhisperName(key)
	if Ambiguate then return Ambiguate(key, "none") end
	return key
end

-- "Name" for a peer on our realm, "Name-Realm" otherwise
function ns.Short(full)
	if Ambiguate then return Ambiguate(full, "short") end
	return (full:match("^[^-]+")) or full
end

-- Finds a stored peer by a typed name, with or without realm
function ns.FindPeer(name)
	if not name or name == "" then return nil end
	local full = ns.FullName(name)
	if full and ns.db.peers[full] then return full end
	local lower = name:lower()
	for key in pairs(ns.db.peers) do
		if key:lower() == lower or ns.Short(key):lower() == lower then return key end
	end
	return nil
end

-- Whether a stored name is this character. Compares the name only: the realm the game puts on
-- addon messages isn't always the one GetNormalizedRealmName gives, and isn't known early at load.
-- Forever shows names like "Glorai Magicborn" (character Glorai, realm Magicborn) while addon
-- messages come from "Glorai Magicborn-<server>". Our own group messages come back to us, marked
-- with this session's id, and the name they carry is remembered as ours (db.selfNames).
ns.session = ("%06x"):format(math.random(0, 0xFFFFFF))

function ns.IsMe(key)
	if not key then return false end
	local lower = key:lower()
	if ns.db and ns.db.selfNames and ns.db.selfNames[lower] then return true end
	local part = (key:match("^[^-]+") or key):lower()
	local name, realm = UnitFullName("player")
	if not name then return false end
	name = name:lower()
	if part == name then return true end
	local realmName = (GetRealmName and GetRealmName()) or realm
	return realmName ~= nil and part == (name .. " " .. realmName:lower())
end

function ns.RememberSelf(key)
	ns.db.selfNames = ns.db.selfNames or {}
	ns.db.selfNames[key:lower()] = true
	ns.db.peers[key] = nil
end

-- Peers with data, sorted by name
function ns.PeerList()
	local list = {}
	for key, peer in pairs(ns.db.peers) do
		if peer.snap and not ns.IsMe(key) then table.insert(list, key) end
	end
	table.sort(list)
	return list
end

function ns.Ago(time)
	if not time then return "never" end
	local seconds = math.max(0, GetServerTime() - time)
	if seconds < 60 then return "just now" end
	if seconds < 3600 then return ("%d min ago"):format(seconds / 60) end
	if seconds < 86400 then return ("%d h ago"):format(seconds / 3600) end
	return ("%d days ago"):format(seconds / 86400)
end

function ns.Money(copper)
	copper = tonumber(copper) or 0
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	return ("%d|cffffd700g|r %d|cffc7c7cfs|r %d|cffeda55fc|r"):format(g, s, c)
end

---------------------------------------------------------------------------
-- Events: each module adds handlers with ns.On(event, fn)
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		if not pcall(frame.RegisterEvent, frame, event) then
			ns.Debug("this client has no event " .. event)
		end
	end
	table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for _, fn in ipairs(list) do
		local ok, err = pcall(fn, ...)
		if not ok then ns.Debug(event .. ": " .. tostring(err)) end
	end
end)

ns.loginHooks = {}
function ns.OnLogin(fn) table.insert(ns.loginHooks, fn) end

ns.On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	BagBuddyDB = CopyDefaults(DEFAULTS, BagBuddyDB or {})
	ns.db = BagBuddyDB
	-- Never keep ourselves as a peer (an alt on the same account is fine), nor names 1.0.0 saved
	-- with the wrong letter case (they never got bags)
	for key, peer in pairs(ns.db.peers) do
		if ns.IsMe(key) or (not ns.db.fixedNames and not peer.snap) then ns.db.peers[key] = nil end
	end
	ns.db.fixedNames = true
end)

ns.On("PLAYER_LOGIN", function()
	for _, fn in ipairs(ns.loginHooks) do
		local ok, err = pcall(fn)
		if not ok then ns.Print("startup error: " .. tostring(err)) end
	end
end)

---------------------------------------------------------------------------
-- /bud
---------------------------------------------------------------------------

local function OnOff(value) return value and "|cff00ff00on|r" or "|cffff4040off|r" end

local function Help()
	ns.Print("commands:")
	print("  /bud  - open or close the BagBuddy window")
	print("  /bud sync  - ask everyone for fresh bags now")
	print("  /bud add <name>  - sync with this character even when you're not grouped (they must be on your friends list)")
	print("  /bud forget <name>  - forget a character and their bags")
	print("  /bud list  - who you have bags for")
	print("  /bud role <name> <auto|strength|agility|ranged|caster|healer|tank|bear>  - how to judge upgrades for them")
	print("  /bud tips  - upgrade lines in item tooltips on or off")
	print("  /bud debug  - extra chat output")
end

local function List()
	local list = ns.PeerList()
	if #list == 0 then
		ns.Print("no bags yet. Group up with someone who runs BagBuddy, or /bud add <name> for a friend.")
		return
	end
	ns.Print("bags you have:")
	for _, key in ipairs(list) do
		local peer = ns.db.peers[key]
		local snap = peer.snap
		print(("  %s  level %d %s (%s), updated %s%s"):format(ns.Short(key), snap.level or 0,
			ns.ClassName(snap.class), ns.RoleName(key), ns.Ago(peer.time), peer.partner and ", synced when not grouped" or ""))
	end
end

SLASH_BAGBUDDY1 = "/bud"
SLASH_BAGBUDDY2 = "/bagbuddy"
SlashCmdList.BAGBUDDY = function(msg)
	if not ns.db then return end
	local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "" or cmd == "show" then
		ns.ToggleViewer()
	elseif cmd == "help" then
		Help()
	elseif cmd == "sync" then
		ns.SyncAll(true)
		ns.Print("asking for fresh bags")
	elseif cmd == "add" then
		if arg == "" then return Help() end
		local full = ns.ResolveName(arg)
		if not full then
			return ns.Print(("can't find %s. Target them, group with them, or add them to your friends list first, then try again."):format(arg))
		end
		ns.db.peers[full] = ns.db.peers[full] or {}
		ns.db.peers[full].partner = true
		ns.Print(("%s added. You'll sync whenever you're grouped, or when they're online on your friends list."):format(ns.Short(full)))
		ns.SyncAll(true)
	elseif cmd == "forget" then
		local key = ns.FindPeer(arg)
		if not key then return ns.Print("no one called " .. tostring(arg)) end
		ns.db.peers[key] = nil
		ns.Print("forgot " .. ns.Short(key))
		ns.RefreshViewer()
	elseif cmd == "list" then
		List()
	elseif cmd == "role" then
		local name, role = arg:match("^(%S+)%s+(%S+)$")
		local key = ns.FindPeer(name)
		if not key then return ns.Print("no one called " .. tostring(name)) end
		role = role and role:lower()
		if role == "auto" then
			ns.db.peers[key].role = nil
		elseif role and ns.TEMPLATES[role] then
			ns.db.peers[key].role = role
		else
			return Help()
		end
		ns.ClearScores()
		ns.Print(("judging upgrades for %s as %s"):format(ns.Short(key), ns.RoleName(key)))
		ns.RefreshViewer()
	elseif cmd == "tips" then
		ns.db.tooltips = not ns.db.tooltips
		ns.Print("tooltip lines " .. OnOff(ns.db.tooltips))
	elseif cmd == "debug" then
		ns.db.debug = not ns.db.debug
		ns.Print("debug " .. OnOff(ns.db.debug))
	else
		Help()
	end
end
