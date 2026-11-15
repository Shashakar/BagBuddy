-- BagBuddy: what a peer can wear, stat weights per class and talent tree, and whether an item is
-- an upgrade for them.
--
-- The role templates and per-tree nudges are adapted from Forever++'s Upgrade Arrows
-- (github.com/xIGBClutchIx/ForeverPlusPlus, Modules/Items/UpgradeArrows/Weights.lua and
-- Lib/ItemStats.lua, MIT License, Copyright (c) 2026 Cameron Weaver). Simplified here: the
-- attributes use the templates' fixed values, and ratings use Forever's level 60 table.
local _, ns = ...

---------------------------------------------------------------------------
-- Item strings
---------------------------------------------------------------------------

-- "item:..." from a link or item string, with empty and zero fields at the end dropped,
-- so the same item reads the same wherever it came from.
function ns.ItemString(link)
	if type(link) ~= "string" or not ns.Usable(link) then return nil end
	local s = link:match("|H(item:[^|]+)|h") or link:match("^(item:[^|%s,;+/%^~=*!]+)")
	if not s then return nil end
	-- Keep only numeric fields: crafted items can carry the crafter (a "Player-..." GUID)
	-- or other text, which would break the snapshot text
	local fields = {}
	for field in (s:sub(6) .. ":"):gmatch("([^:]*):") do
		table.insert(fields, field:match("^%-?%d+$") and field or "")
	end
	if not fields[1] or fields[1] == "" then return nil end
	s = "item:" .. table.concat(fields, ":")
	local trimmed
	repeat
		trimmed = s
		s = s:gsub(":0?$", "")
	until s == trimmed
	return s
end

-- Two item strings for the same item: same ID, enchant and random suffix. The rest (such as
-- the level of whoever made the link) can differ between players.
local function Fields(itemString)
	local f = {}
	for value in (itemString:sub(6) .. ":"):gmatch("([^:]*):") do f[#f + 1] = value end
	return f
end
function ns.SameItem(a, b)
	if a == b then return true end
	if not a or not b then return false end
	local fa, fb = Fields(a), Fields(b)
	for _, i in ipairs({ 1, 2, 7 }) do
		local x, y = fa[i] or "", fb[i] or ""
		if x == "0" then x = "" end
		if y == "0" then y = "" end
		if x ~= y then return false end
	end
	return true
end

function ns.ItemID(itemString)
	return tonumber(itemString and itemString:match("^item:(%d+)"))
end

---------------------------------------------------------------------------
-- Stats
---------------------------------------------------------------------------

-- The game's stat keys and ours. On Forever "Hit" and "Critical Strike" count for spells too,
-- and Spell Power is damage and healing.
local KEYS = {
	ITEM_MOD_STRENGTH_SHORT = "STR",
	ITEM_MOD_AGILITY_SHORT = "AGI",
	ITEM_MOD_STAMINA_SHORT = "STA",
	ITEM_MOD_INTELLECT_SHORT = "INT",
	ITEM_MOD_SPIRIT_SHORT = "SPI",
	ITEM_MOD_HEALTH_SHORT = "HEALTH",
	ITEM_MOD_MANA_SHORT = "MANA",
	ITEM_MOD_ATTACK_POWER_SHORT = "AP",
	ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP",
	ITEM_MOD_SPELL_POWER_SHORT = { "SP", "HEAL" },
	ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SP",
	ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HEAL",
	ITEM_MOD_MANA_REGENERATION_SHORT = "MP5",
	ITEM_MOD_POWER_REGEN0_SHORT = "MP5",
	ITEM_MOD_HEALTH_REGEN_SHORT = "HP5",
	ITEM_MOD_HEALTH_REGENERATION_SHORT = "HP5",
	ITEM_MOD_HIT_RATING_SHORT = { "HIT", "SPELLHIT" },
	ITEM_MOD_HIT_MELEE_RATING_SHORT = "HIT",
	ITEM_MOD_HIT_RANGED_RATING_SHORT = "HIT",
	ITEM_MOD_HIT_SPELL_RATING_SHORT = "SPELLHIT",
	ITEM_MOD_CRIT_RATING_SHORT = { "CRIT", "SPELLCRIT" },
	ITEM_MOD_CRIT_MELEE_RATING_SHORT = "CRIT",
	ITEM_MOD_CRIT_RANGED_RATING_SHORT = "CRIT",
	ITEM_MOD_CRIT_SPELL_RATING_SHORT = "SPELLCRIT",
	ITEM_MOD_HASTE_RATING_SHORT = "HASTE",
	ITEM_MOD_HASTE_MELEE_RATING_SHORT = "HASTE",
	ITEM_MOD_HASTE_RANGED_RATING_SHORT = "HASTE",
	ITEM_MOD_HASTE_SPELL_RATING_SHORT = "HASTE",
	ITEM_MOD_EXPERTISE_RATING_SHORT = "EXPERTISE",
	ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DEF",
	ITEM_MOD_DODGE_RATING_SHORT = "DODGE",
	ITEM_MOD_PARRY_RATING_SHORT = "PARRY",
	ITEM_MOD_BLOCK_RATING_SHORT = "BLOCK",
	ITEM_MOD_BLOCK_VALUE_SHORT = "BLOCKVALUE",
	ITEM_MOD_EXTRA_ARMOR_SHORT = "ARMOR",
	RESISTANCE0_NAME = "ARMOR",
	ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
}

-- Gear carries hit, crit and the like as ratings; these many points make 1% (Forever, level 60).
local RATING = { HIT = 10, SPELLHIT = 10, CRIT = 14, SPELLCRIT = 14, HASTE = 10, EXPERTISE = 10,
	DODGE = 12, PARRY = 15, BLOCK = 5 }

local function Normalize(raw)
	local stats = {}
	if type(raw) ~= "table" then return stats end
	local function add(ours, value)
		stats[ours] = (stats[ours] or 0) + value / (RATING[ours] or 1)
	end
	for key, value in pairs(raw) do
		if ns.Usable(key) and type(value) == "number" and ns.Usable(value) then
			local ours = KEYS[key]
			if type(ours) == "table" then
				for _, each in ipairs(ours) do add(each, value) end
			elseif ours then
				add(ours, value)
			end
		end
	end
	return stats
end

-- What an item is: { id, equipLoc, classID, subclassID, minLevel, ilvl, quality, name, link,
-- icon, stats }, or nil while the game hasn't loaded it (it's asked for, and
-- GET_ITEM_INFO_RECEIVED fires when it arrives).
local infoCache = {}
function ns.ItemInfo(itemString)
	if not itemString then return nil end
	local info = infoCache[itemString]
	if info then return info end
	local name, link, quality, ilvl, minLevel = C_Item.GetItemInfo(itemString)
	if not name then
		local id = ns.ItemID(itemString)
		if id and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
		return nil
	end
	local id, _, _, equipLoc, icon, classID, subclassID = C_Item.GetItemInfoInstant(itemString)
	local raw = C_Item.GetItemStats and C_Item.GetItemStats(itemString)
	info = {
		id = id, equipLoc = equipLoc or "", classID = classID, subclassID = subclassID,
		minLevel = minLevel or 0, ilvl = ilvl or 0, quality = quality or 1,
		name = name, link = link, icon = icon, stats = Normalize(raw),
	}
	infoCache[itemString] = info
	return info
end

-- Icon right away (the client knows every item's icon without loading it)
function ns.ItemIcon(itemString)
	local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemString)
	return icon or 134400
end

---------------------------------------------------------------------------
-- Weights
---------------------------------------------------------------------------

-- 1 Strength is 1 for a class that gets 2 attack power from it; 1 spell damage is 1 for casters,
-- 1 healing for healers, 1 Stamina for tanks. Chance stats are per 1%.
ns.TEMPLATES = {
	strength = { STR = 1, AGI = 0.6, AP = 0.5, HIT = 10, CRIT = 10, HASTE = 7, EXPERTISE = 8, STA = 0.3,
		HEALTH = 0.03, ARMOR = 0.01, DPS = 7, DPS_OFF = 3.5 },
	agility = { AGI = 1, STR = 0.5, AP = 0.5, HIT = 10, CRIT = 10, HASTE = 7, EXPERTISE = 8, STA = 0.3,
		HEALTH = 0.03, ARMOR = 0.01, DPS = 7, DPS_OFF = 3.5 },
	ranged = { AGI = 1, RAP = 0.5, AP = 0.1, HIT = 12, CRIT = 12, HASTE = 7, INT = 0.3, MANA = 0.02, MP5 = 0.3,
		STA = 0.3, HEALTH = 0.03, ARMOR = 0.01, DPS_RANGED = 7.5, DPS = 0.2 },
	caster = { SP = 1, SPELLHIT = 10, SPELLCRIT = 7, HASTE = 6, INT = 0.35, MANA = 0.02, STA = 0.3,
		HEALTH = 0.03, MP5 = 0.6, SPI = 0.15, DPS_RANGED = 1.2 },
	healer = { HEAL = 1, SP = 0.1, MP5 = 1.5, INT = 0.6, MANA = 0.04, SPI = 0.5, SPELLCRIT = 3, HASTE = 3,
		STA = 0.2, HEALTH = 0.02, DPS_RANGED = 0.5 },
	tank = { STA = 1, HEALTH = 0.1, DEF = 1.5, DODGE = 8, PARRY = 7, BLOCK = 3, BLOCKVALUE = 0.3, ARMOR = 0.04,
		STR = 0.5, AGI = 0.7, AP = 0.25, HIT = 6, CRIT = 3, EXPERTISE = 4, DPS = 2 },
	bear = { STA = 1, HEALTH = 0.1, AGI = 0.8, ARMOR = 0.1, STR = 0.4, AP = 0.2, DEF = 1, DODGE = 8, HIT = 5,
		CRIT = 3 },
	fallback = { STR = 1, AGI = 1, STA = 0.5, HEALTH = 0.05, INT = 1, MANA = 0.03, SPI = 0.5, AP = 0.3, SP = 0.8,
		HEAL = 0.6, HIT = 5, CRIT = 5, SPELLHIT = 5, SPELLCRIT = 5, DPS = 2 },
}

local ROLE_NAMES = { strength = "Strength melee", agility = "Agility melee", ranged = "Ranged",
	caster = "Caster", healer = "Healer", tank = "Tank", bear = "Bear tank", fallback = "General" }

-- Each class's talent trees in Classic order, and the template each uses
local CLASS_TABS = {
	WARRIOR = { "strength", "strength", "tank" },  -- Arms, Fury, Protection
	PALADIN = { "healer", "tank", "strength" },    -- Holy, Protection, Retribution
	HUNTER = { "ranged", "ranged", "ranged" },
	ROGUE = { "agility", "agility", "agility" },
	PRIEST = { "healer", "healer", "caster" },     -- Discipline, Holy, Shadow
	SHAMAN = { "caster", "strength", "healer" },   -- Elemental, Enhancement, Restoration
	MAGE = { "caster", "caster", "caster" },
	WARLOCK = { "caster", "caster", "caster" },
	DRUID = { "caster", "agility", "healer" },     -- Balance, Feral, Restoration
}

local TAB_NAMES = {
	WARRIOR = { "Arms", "Fury", "Protection" }, PALADIN = { "Holy", "Protection", "Retribution" },
	HUNTER = { "Beast Mastery", "Marksmanship", "Survival" }, ROGUE = { "Assassination", "Combat", "Subtlety" },
	PRIEST = { "Discipline", "Holy", "Shadow" }, SHAMAN = { "Elemental", "Enhancement", "Restoration" },
	MAGE = { "Arcane", "Fire", "Frost" }, WARLOCK = { "Affliction", "Demonology", "Destruction" },
	DRUID = { "Balance", "Feral", "Restoration" },
}

-- The tree to assume before any talent points are spent: the usual leveling tree
local LEVELING_TAB = { PALADIN = 3, PRIEST = 3, SHAMAN = 2, DRUID = 2 }

local NUDGES = {
	WARRIOR = { { CRIT = 11, DPS = 8, DPS_OFF = 0 }, { HIT = 11, DPS_OFF = 4.5 }, {} },
	PALADIN = {
		{ SPELLCRIT = 8, MP5 = 2, SPI = 0.15, INT = 0.8 },
		{ SP = 0.5, SPELLHIT = 2, INT = 0.5, MANA = 0.03, MP5 = 1, BLOCK = 3.5, BLOCKVALUE = 0.35, DPS = 1 },
		{ CRIT = 11, DPS = 8, DPS_OFF = 0, SP = 0.25, SPELLCRIT = 1, SPELLHIT = 1, INT = 0.25, MANA = 0.015, MP5 = 0.5 },
	},
	HUNTER = { { STA = 0.35, INT = 0.35, MANA = 0.025 }, { RAP = 0.55, CRIT = 13, DPS_RANGED = 8 }, { AGI = 1.1 } },
	ROGUE = { { CRIT = 11 }, { HIT = 11, DPS_OFF = 4.5 }, { DPS = 7.5, AGI = 1.1 } },
	PRIEST = { { SPI = 0.9, INT = 0.7, SP = 0.2 }, { SPI = 0.9, SPELLCRIT = 4, SP = 0.2 }, { SPELLHIT = 11, SPI = 0.4 } },
	SHAMAN = { { SPELLCRIT = 9 }, { DPS = 8, DPS_OFF = 0.5, CRIT = 11, SP = 0.15, INT = 0.25, MANA = 0.01 },
		{ MP5 = 1.7, SPELLCRIT = 4 } },
	MAGE = { { INT = 0.5, MANA = 0.03, SPELLCRIT = 6 }, { SPELLCRIT = 9 }, { SPELLCRIT = 8, SPI = 0.3 } },
	WARLOCK = { { MP5 = 0.2, SPI = 0.25 }, { MP5 = 0.2, STA = 0.4, HEALTH = 0.04 }, { MP5 = 0.2, SPELLCRIT = 9 } },
	DRUID = { { SPELLCRIT = 8, SPI = 0.3 }, { STR = 1, CRIT = 11, DPS = 0, DPS_OFF = 0 }, { SPI = 0.9 } },
}

function ns.ClassName(class)
	return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class or ""]) or class or "?"
end

-- The tree a snapshot plays: its tab, or the leveling default with no points spent
local function Tab(snap)
	local tab = tonumber(snap.tab) or 0
	if tab < 1 or tab > 3 then tab = LEVELING_TAB[snap.class] or 1 end
	return tab
end

-- The weights for a peer: { role, weights }
local weightCache = {}
function ns.PeerWeights(key)
	local peer = ns.db.peers[key]
	local snap = peer and peer.snap
	if not snap then return nil end
	local cacheKey = ("%s:%s:%s"):format(snap.class or "?", peer.role or "", tostring(snap.tab))
	local cached = weightCache[cacheKey]
	if cached then return cached end
	local class, tab = snap.class, Tab(snap)
	local role = peer.role or (CLASS_TABS[class] and CLASS_TABS[class][tab]) or "fallback"
	local weights = {}
	for stat, weight in pairs(ns.TEMPLATES[role]) do weights[stat] = weight end
	if not peer.role and NUDGES[class] and NUDGES[class][tab] then
		for stat, weight in pairs(NUDGES[class][tab]) do weights[stat] = weight end
	end
	cached = { role = role, weights = weights }
	weightCache[cacheKey] = cached
	return cached
end

function ns.RoleName(key)
	local peer = ns.db.peers[key]
	local snap = peer and peer.snap
	if not snap then return "?" end
	local w = ns.PeerWeights(key)
	local text = ROLE_NAMES[w.role] or w.role
	if peer.role then return text .. ", set by you" end
	local tabs = TAB_NAMES[snap.class]
	local tab = tonumber(snap.tab) or 0
	if tabs and tab >= 1 and tab <= 3 then return tabs[tab] .. ", " .. text end
	return text
end

---------------------------------------------------------------------------
-- What a class can wear (Classic rules)
---------------------------------------------------------------------------

local ARMOR, WEAPON = 4, 2
-- Armor subclasses: 0 misc, 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield, 7 libram, 8 idol, 9 totem
local ARMOR_OK = {
	WARRIOR = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
	PALADIN = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1, [7] = 1 },
	HUNTER = { [1] = 1, [2] = 1, [3] = 40 },
	SHAMAN = { [1] = 1, [2] = 1, [3] = 40, [6] = 1, [9] = 1 },
	ROGUE = { [1] = 1, [2] = 1 },
	DRUID = { [1] = 1, [2] = 1, [8] = 1 },
	PRIEST = { [1] = 1 }, MAGE = { [1] = 1 }, WARLOCK = { [1] = 1 },
}
-- Weapon subclasses: 0 1h axe, 1 2h axe, 2 bow, 3 gun, 4 1h mace, 5 2h mace, 6 polearm, 7 1h sword,
-- 8 2h sword, 10 staff, 13 fist, 15 dagger, 16 thrown, 18 crossbow, 19 wand
local function Set(...)
	local t = {}
	for i = 1, select("#", ...) do t[select(i, ...)] = true end
	return t
end
local WEAPON_OK = {
	WARRIOR = Set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18),
	PALADIN = Set(0, 1, 4, 5, 6, 7, 8),
	HUNTER = Set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18),
	ROGUE = Set(2, 3, 4, 7, 13, 15, 16, 18),
	PRIEST = Set(4, 10, 15, 19),
	SHAMAN = Set(0, 1, 4, 5, 10, 13, 15),
	MAGE = Set(7, 10, 15, 19),
	WARLOCK = Set(7, 10, 15, 19),
	DRUID = Set(4, 5, 10, 13, 15),
}
local DUAL_WIELD = { WARRIOR = true, ROGUE = true, HUNTER = true }

-- true, or false and the reason, or true with the level they can wear it from
local function CanWear(info, class, level)
	if info.classID == ARMOR then
		local ok = ARMOR_OK[class]
		if not ok or info.subclassID == 0 then return true end
		local from = ok[info.subclassID]
		if not from then return false end
		if from > 1 and level < from then return true, from end
		return true
	elseif info.classID == WEAPON then
		local ok = WEAPON_OK[class]
		if not ok then return true end
		return ok[info.subclassID] or false
	end
	return true
end

---------------------------------------------------------------------------
-- Comparing
---------------------------------------------------------------------------

-- Which equipment slots an item can go in
local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
ns.SLOTS = SLOTS

local function Score(info, weights, slot)
	local total = 0
	for stat, value in pairs(info.stats) do
		local key = stat
		if stat == "DPS" and slot == 17 then key = "DPS_OFF" end
		if stat == "DPS" and slot == 18 then key = "DPS_RANGED" end
		local weight = weights[key]
		if weight then total = total + value * weight end
	end
	return total
end

local resultCache = {}
function ns.ClearScores()
	wipe(resultCache)
	wipe(weightCache)
end

-- Whether itemString would be an upgrade for the peer. Returns nil for something they can't
-- wear, else a table:
--   status   "upgrade", "downgrade", "same", "equipped" or "pending" (item data not loaded yet)
--   percent  how much better or worse (nil against an empty slot or when only item level was compared)
--   rival    the item string it would replace (nil for an empty slot)
--   level    the level they can wear it from, when that's above their level
function ns.Compare(itemString, key)
	local peer = ns.db.peers[key]
	local snap = peer and peer.snap
	if not snap or not itemString then return nil end
	local cacheKey = key .. "|" .. (peer.hash or "") .. "|" .. itemString
	local cached = resultCache[cacheKey]
	if cached ~= nil then return cached or nil end

	local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemString)
	local slots = SLOTS[equipLoc or ""]
	if not slots then resultCache[cacheKey] = false; return nil end
	local info = ns.ItemInfo(itemString)
	if not info then return { status = "pending" } end
	local wear, from = CanWear(info, snap.class, snap.level or 1)
	if not wear then resultCache[cacheKey] = false; return nil end
	local level = math.max(from or 0, info.minLevel or 0)
	if level <= (snap.level or 0) then level = nil end

	local equip = snap.equip or {}
	for _, slot in ipairs(slots) do
		local worn = equip[slot]
		if worn and ns.SameItem(worn, itemString) then
			local result = { status = "equipped" }
			resultCache[cacheKey] = result
			return result
		end
	end

	local weights = ns.PeerWeights(key).weights
	local mainHand = equip[16] and ns.ItemInfo(equip[16])
	if equip[16] and not mainHand then return { status = "pending" } end
	local wearsTwoHander = mainHand and mainHand.equipLoc == "INVTYPE_2HWEAPON"

	local best
	for _, slot in ipairs(slots) do
		local usable = true
		if equipLoc == "INVTYPE_WEAPON" and slot == 17 and (not DUAL_WIELD[snap.class] or wearsTwoHander) then
			usable = false
		end
		if usable then
			local rival, rivalScore, rivalIlvl = equip[slot], 0, 0
			local rivalInfo = rival and ns.ItemInfo(rival)
			if rival and not rivalInfo then return { status = "pending" } end
			if rivalInfo then
				rivalScore, rivalIlvl = Score(rivalInfo, weights, slot), rivalInfo.ilvl
			end
			if equipLoc == "INVTYPE_2HWEAPON" and equip[17] then
				-- A two-hander replaces both hands
				local offInfo = ns.ItemInfo(equip[17])
				if not offInfo then return { status = "pending" } end
				rivalScore = rivalScore + Score(offInfo, weights, 17)
			elseif slot == 17 and wearsTwoHander then
				-- An off hand means giving up the two-hander
				rival, rivalScore, rivalIlvl = equip[16], Score(mainHand, weights, 16), mainHand.ilvl
			end
			local score = Score(info, weights, slot)
			local gain, percent
			if score == 0 and rivalScore == 0 then
				gain = (info.ilvl or 0) - (rivalIlvl or 0)
			else
				gain = score - rivalScore
				if rivalScore > 0 then percent = gain / rivalScore * 100 end
			end
			if not rival then gain = math.max(gain, 0.001); percent = nil end
			if not best or gain > best.gain then
				best = { gain = gain, percent = percent, rival = rival, slot = slot }
			end
		end
	end
	if not best then resultCache[cacheKey] = false; return nil end

	local status
	if not best.rival then
		status = "upgrade"
	elseif best.percent then
		status = best.percent > 1 and "upgrade" or (best.percent < -1 and "downgrade" or "same")
	else
		status = best.gain > 0 and "upgrade" or (best.gain < 0 and "downgrade" or "same")
	end
	local result = { status = status, percent = best.percent, rival = best.rival, level = level, slot = best.slot }
	resultCache[cacheKey] = result
	return result
end

-- Results that waited on item data are worked out again once it arrives
ns.On("GET_ITEM_INFO_RECEIVED", function()
	ns.ItemDataArrived()
end)

local pendingRefresh = false
function ns.ItemDataArrived()
	if pendingRefresh then return end
	pendingRefresh = true
	C_Timer.After(0.3, function()
		pendingRefresh = false
		ns.RefreshViewer()
	end)
end
