-- BagBuddy: reading this character's bags and gear, and the text a snapshot travels as.
local _, ns = ...

---------------------------------------------------------------------------
-- Talent tree with the most points (Forever's talents are Classic trees on the trait system:
-- one config, one tree, its display groups are the tabs). Approach from Forever++'s
-- Lib/Talents.lua (MIT, Cameron Weaver).
---------------------------------------------------------------------------

local function TraitTab()
	if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo
		and C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetGroupCurrencyInfo) then
		return nil
	end
	local configID = C_ClassTalents.GetActiveConfigID()
	local config = configID and C_Traits.GetConfigInfo(configID)
	local treeID = config and type(config.treeIDs) == "table" and config.treeIDs[1]
	if not treeID then return nil end
	local tabs = {}
	for _, group in ipairs(C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}) do
		if type(group) == "table" and ns.Usable(group.groupID) then
			local ok, result = pcall(C_Traits.GetGroupCurrencyInfo, configID, { group.groupID })
			local entry = ok and type(result) == "table" and result[1]
			local currency = entry and type(entry.currencyInfos) == "table" and entry.currencyInfos[1]
			local spent = currency and tonumber(currency.spent) or 0
			table.insert(tabs, { order = tonumber(group.orderIndex) or 0, spent = spent })
		end
	end
	table.sort(tabs, function(a, b) return a.order < b.order end)
	local best, bestSpent, total = 0, 0, 0
	for i, tab in ipairs(tabs) do
		total = total + tab.spent
		if tab.spent > bestSpent then best, bestSpent = i, tab.spent end
	end
	-- Points left to spend: the tree's own currency, when it says
	local unspent
	if C_Traits.GetTreeCurrencyInfo then
		local ok, currencies = pcall(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
		local first = ok and type(currencies) == "table" and currencies[1]
		if first and type(first.quantity) == "number" and ns.Usable(first.quantity) then unspent = first.quantity end
	end
	return best, total, unspent
end

local function ClassicTab()
	if not GetTalentTabInfo then return nil end
	local best, bestSpent, total = 0, 0, 0
	for i = 1, 3 do
		local ok, a, b, c, d, e = pcall(GetTalentTabInfo, i)
		if not ok then return nil end
		-- Classic: name, icon, pointsSpent; later clients: id, name, description, icon, pointsSpent
		local spent = type(c) == "number" and c or (type(e) == "number" and e) or 0
		total = total + spent
		if spent > bestSpent then best, bestSpent = i, spent end
	end
	return best, total
end

-- The talent tree with the most points, and how many points are waiting to be spent (Classic:
-- one point a level from 10, when the game doesn't say)
function ns.TalentTab()
	local ok, tab, total, unspent = pcall(TraitTab)
	if not (ok and tab) then
		ok, tab, total = pcall(ClassicTab)
		unspent = nil
	end
	if not (ok and tab) then return 0, nil end
	if not unspent and total then
		local level = UnitLevel("player") or 0
		unspent = math.max(0, level - 9 - total)
	end
	return tab, unspent
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------

local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

-- This character's snapshot: { class, level, tab, money, free, total, equip = { [slot] = item },
-- containers = { { bag, item (the bag itself), slots, contents = { [slot] = { item, count, bound } } } },
-- bags = { { item, count, bound }, ... } }. `bags` adds up the same item across stacks.
local function Merge(snap)
	local seen = {}
	snap.bags = {}
	for _, container in ipairs(snap.containers) do
		for slot = 1, container.slots do
			local entry = container.contents[slot]
			if entry then
				local key = entry[1] .. (entry[3] and "!" or "")
				local merged = seen[key]
				if merged then
					merged[2] = merged[2] + entry[2]
				else
					merged = { entry[1], entry[2], entry[3] }
					seen[key] = merged
					table.insert(snap.bags, merged)
				end
			end
		end
	end
end

local function BagItem(bag)
	if bag == 0 or not C_Container.ContainerIDToInventoryID then return nil end
	local ok, invSlot = pcall(C_Container.ContainerIDToInventoryID, bag)
	if not ok or not invSlot then return nil end
	return ns.ItemString(GetInventoryItemLink("player", invSlot))
end

function ns.ReadSelf()
	local _, class = UnitClass("player")
	local snap = {
		class = class, level = UnitLevel("player"), money = GetMoney(),
		free = 0, total = 0, equip = {}, containers = {}, dura = {},
	}
	snap.tab, snap.unspent = ns.TalentTab()
	for slot = 1, 19 do
		local item = ns.ItemString(GetInventoryItemLink("player", slot))
		if item then
			snap.equip[slot] = item
			local ok, cur, max = pcall(GetInventoryItemDurability, slot)
			if ok and type(cur) == "number" and type(max) == "number" and ns.Usable(cur) and ns.Usable(max) and max > 0 then
				snap.dura[slot] = math.floor(cur / max * 100)
			end
		end
	end
	snap.skills = ns.ReadSkills()
	for bag = 0, LAST_BAG do
		local slots = C_Container.GetContainerNumSlots(bag) or 0
		if slots > 0 then
			snap.total = snap.total + slots
			snap.free = snap.free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
			local container = { bag = bag, item = BagItem(bag), slots = slots, contents = {} }
			for slot = 1, slots do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				local item = info and ns.ItemString(info.hyperlink)
				if item then
					container.contents[slot] = { item, info.stackCount or 1, info.isBound and true or false }
				end
			end
			table.insert(snap.containers, container)
		end
	end
	Merge(snap)
	ns.ReadQuests(snap)
	snap.unplaced = ns.ReadUnplacedSpells()
	return snap
end

---------------------------------------------------------------------------
-- Text
-- 4^CLASS^level^tab^money^free^total^slot=item,slot=item^containers^race^quest log^finished quests
--   ^slot=durability%,...^unspent talent points^profession=rank=max~...
--   ^spell IDs not on an action bar ("-" when unknown)
-- containers: bag/bagitem/slots/slot=item*count!+slot=item;bag/...
-- Items drop their "item:" prefix; "*n" is a count above 1, "!" marks soulbound.
---------------------------------------------------------------------------

local function EntryText(entry)
	local text = entry[1]:sub(6)
	if entry[2] > 1 then text = text .. "*" .. entry[2] end
	if entry[3] then text = text .. "!" end
	return text
end

local function ParseEntry(text)
	local item, rest = text:match("^([^*!]+)(.*)$")
	item = item and ns.ItemString("item:" .. item)
	if not item then return nil end
	return { item, tonumber(rest:match("%*(%d+)")) or 1, rest:find("!", 1, true) and true or false }
end

function ns.Encode(snap)
	local equip = {}
	for slot = 1, 19 do
		if snap.equip[slot] then
			table.insert(equip, slot .. "=" .. snap.equip[slot]:sub(6))
		end
	end
	local containers = {}
	for _, c in ipairs(snap.containers) do
		local contents = {}
		for slot = 1, c.slots do
			if c.contents[slot] then table.insert(contents, slot .. "=" .. EntryText(c.contents[slot])) end
		end
		table.insert(containers, ("%d/%s/%d/%s"):format(c.bag, c.item and c.item:sub(6) or "", c.slots,
			table.concat(contents, "+")))
	end
	local log, completed = ns.EncodeQuests(snap)
	local dura = {}
	for slot = 1, 19 do
		if snap.dura and snap.dura[slot] then table.insert(dura, slot .. "=" .. snap.dura[slot]) end
	end
	local skills = {}
	for _, skill in ipairs(snap.skills or {}) do
		table.insert(skills, ("%s=%d=%d"):format((skill[1]:gsub("[%^~=]", "")), skill[2] or 0, skill[3] or 0))
	end
	return table.concat({ "4", snap.class or "", snap.level or 0, snap.tab or 0, snap.money or 0,
		snap.free or 0, snap.total or 0, table.concat(equip, ","), table.concat(containers, ";"),
		snap.race or 0, log, completed, table.concat(dura, ","), snap.unspent or "", table.concat(skills, "~"),
		snap.unplaced and table.concat(snap.unplaced, ",") or "-" }, "^")
end

function ns.Decode(text)
	local parts = {}
	for part in (text .. "^"):gmatch("([^^]*)^") do table.insert(parts, part) end
	local version = parts[1]
	if not (version == "1" or version == "2" or version == "3" or version == "4") or #parts < 9 then return nil end
	local snap = {
		class = parts[2], level = tonumber(parts[3]) or 0, tab = tonumber(parts[4]) or 0,
		money = tonumber(parts[5]) or 0, free = tonumber(parts[6]) or 0, total = tonumber(parts[7]) or 0,
		equip = {}, containers = {},
	}
	for slot, item in parts[8]:gmatch("(%d+)=([^,]+)") do
		snap.equip[tonumber(slot)] = ns.ItemString("item:" .. item)
	end
	if version == "1" then
		-- An older BagBuddy: one list, no bags
		local container = { bag = 0, slots = 0, contents = {}, merged = true }
		local n = 0
		for entry in parts[9]:gmatch("[^,]+") do
			local parsed = ParseEntry(entry)
			if parsed then
				n = n + 1
				container.contents[n] = parsed
			end
		end
		container.slots = math.max(n, snap.total)
		table.insert(snap.containers, container)
	else
		for text in parts[9]:gmatch("[^;]+") do
			local bag, bagItem, slots, contents = text:match("^(%-?%d+)/([^/]*)/(%d+)/(.*)$")
			if bag then
				local container = { bag = tonumber(bag), item = bagItem ~= "" and ns.ItemString("item:" .. bagItem) or nil,
					slots = tonumber(slots), contents = {} }
				for slot, entry in contents:gmatch("(%d+)=([^+]+)") do
					container.contents[tonumber(slot)] = ParseEntry(entry)
				end
				table.insert(snap.containers, container)
			end
		end
	end
	Merge(snap)
	if #parts >= 12 then
		snap.race = tonumber(parts[10]) or 0
		ns.DecodeQuests(snap, parts[11], parts[12])
	end
	if #parts >= 15 then
		snap.dura = {}
		for slot, pct in parts[13]:gmatch("(%d+)=(%d+)") do snap.dura[tonumber(slot)] = tonumber(pct) end
		snap.unspent = tonumber(parts[14])
		snap.skills = {}
		for name, rank, max in parts[15]:gmatch("([^~=]+)=(%d+)=(%d+)") do
			table.insert(snap.skills, { name, tonumber(rank), tonumber(max) })
		end
	end
	if #parts >= 16 and parts[16] ~= "-" then
		snap.unplaced = {}
		for id in parts[16]:gmatch("%d+") do table.insert(snap.unplaced, tonumber(id)) end
	end
	return snap
end

-- A short fingerprint of a text, to tell whether a peer's bags changed
function ns.Hash(text)
	local h = 5381
	for i = 1, #text do
		h = (h * 33 + text:byte(i)) % 2147483647
	end
	return ("%x"):format(h)
end
