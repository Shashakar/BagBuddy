-- BagBuddy: "upgrade for ..." lines in item tooltips.
local _, ns = ...

function ns.ClassColor(class)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class or ""]
	if c and c.colorStr then return "|c" .. c.colorStr end
	return "|cff66bbff"
end

-- How many of an item a snapshot holds in its bags
function ns.CountIn(snap, itemString)
	local count = 0
	for _, entry in ipairs(snap.bags or {}) do
		if ns.SameItem(entry[1], itemString) then count = count + entry[2] end
	end
	return count
end

-- The text for one peer about one item, or nil when there's nothing to say
function ns.VerdictText(key, itemString, withCount)
	local peer = ns.db.peers[key]
	local snap = peer and peer.snap
	if not snap then return nil end
	local parts = {}
	local result = ns.Compare(itemString, key)
	if result then
		local s = result.status
		if s == "upgrade" then
			local text = "|cff20ff20Upgrade"
			if result.percent then text = text .. (" +%d%%"):format(math.floor(result.percent + 0.5)) end
			if not result.rival then text = text .. " (empty slot)" end
			text = text .. "|r"
			if result.level then text = text .. (" |cffff9933at level %d|r"):format(result.level) end
			table.insert(parts, text)
		elseif s == "downgrade" then
			local text = "|cff999999Not an upgrade"
			if result.percent then text = text .. (" (%d%%)"):format(math.floor(result.percent + 0.5)) end
			table.insert(parts, text .. "|r")
		elseif s == "same" then
			table.insert(parts, "|cffcccc66About the same|r")
		elseif s == "equipped" then
			table.insert(parts, "|cffccccccWearing this|r")
		elseif s == "pending" then
			table.insert(parts, "|cff999999checking...|r")
		end
	end
	if withCount then
		local count = ns.CountIn(snap, itemString)
		if count > 0 then table.insert(parts, ("|cffccccffhas %d|r"):format(count)) end
	end
	if #parts == 0 then return nil end
	return ns.ClassColor(snap.class) .. ns.Short(key) .. "|r: " .. table.concat(parts, ", "), result
end

local MAX_AGE = 30 * 86400

-- The item a tooltip shows: from the tooltip, else from the data the game built it from
local function TooltipItem(tooltip, data)
	if tooltip.GetItem then
		local ok, _, link = pcall(tooltip.GetItem, tooltip)
		local itemString = ok and ns.ItemString(link)
		if itemString then return itemString end
	end
	if type(data) == "table" then
		local itemString = ns.ItemString(data.hyperlink)
		if itemString then return itemString end
		if type(data.id) == "number" and ns.Usable(data.id) then return "item:" .. data.id end
	end
	return nil
end

local function AddLines(tooltip, data)
	if not ns.db or not ns.db.tooltips then return end
	if tooltip == ShoppingTooltip1 or tooltip == ShoppingTooltip2 then return end
	local itemString = TooltipItem(tooltip, data)
	if not itemString then return end
	local now = GetServerTime()
	for _, key in ipairs(ns.PeerList()) do
		local peer = ns.db.peers[key]
		if now - (peer.time or 0) < MAX_AGE then
			local text, result = ns.VerdictText(key, itemString, true)
			if text then
				tooltip:AddLine(text)
				if result and result.status == "upgrade" and result.rival then
					local rival = ns.ItemInfo(result.rival)
					if rival then tooltip:AddLine("    |cff999999instead of " .. rival.name .. "|r") end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Quest givers: "Turtle Jerry needs: ..." on an NPC's tooltip
---------------------------------------------------------------------------

local function NpcID(tooltip, data)
	local guid = type(data) == "table" and data.guid or nil
	if not (guid and ns.Usable(guid)) and tooltip.GetUnit then
		local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
		if ok and unit and ns.Usable(unit) then guid = UnitGUID(unit) end
	end
	if type(guid) ~= "string" or not ns.Usable(guid) then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind ~= "Creature" then return nil end
	return tonumber(id)
end

local MAX_QUEST_LINES = 3

local function AddQuestLines(tooltip, data)
	if not ns.db or not ns.db.tooltips or not LibQuestieDB then return end
	local npcID = NpcID(tooltip, data)
	if not npcID then return end
	for _, key in ipairs(ns.PeerList()) do
		local quests = ns.NpcQuestsFor(npcID, key)
		if quests then
			local snap = ns.db.peers[key].snap
			local who = ns.ClassColor(snap.class) .. ns.Short(key) .. "|r"
			local needs = {}
			for _, q in ipairs(quests.needs) do
				if not ns.db.ignoredQuests[q.id] then table.insert(needs, q) end
			end
			for i, q in ipairs(needs) do
				if i > MAX_QUEST_LINES then
					tooltip:AddLine(("    |cff999999and %d more|r"):format(#needs - MAX_QUEST_LINES))
					break
				end
				local text = ("%s needs: |cffffd100%s|r"):format(who, q.title)
				if q.tooLow then text = text .. (" |cffff9933at level %d|r"):format(q.minLevel) end
				tooltip:AddLine(text)
			end
			for _, q in ipairs(quests.turnIn) do
				tooltip:AddLine(("%s can turn in: |cff20ff20%s|r"):format(who, q.title))
			end
		end
	end
end

ns.OnLogin(function()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
			local ok, err = pcall(AddQuestLines, tooltip, data)
			if not ok then ns.Debug("unit tooltip: " .. tostring(err)) end
		end)
	end
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
			local ok, err = pcall(AddLines, tooltip, data)
			if not ok then ns.Debug("tooltip: " .. tostring(err)) end
		end)
	else
		ns.Print("this client has no tooltip hook; upgrade lines are off")
	end
end)
