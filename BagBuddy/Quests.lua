-- BagBuddy: quest logs and finished quests, and comparing them between buddies. Names, levels and
-- where a quest starts come from QuestieDB when it's installed (read only, at run time).
local _, ns = ...

---------------------------------------------------------------------------
-- Reading this character's quests
---------------------------------------------------------------------------

-- { { id, level, done, title }, ... } from the quest log
local function ReadLog()
	local log = {}
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		local n = C_QuestLog.GetNumQuestLogEntries() or 0
		for i = 1, n do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and not info.isHidden and ns.Usable(info.questID) and (info.questID or 0) > 0 then
				local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
				table.insert(log, { info.questID, info.level or 0, done and true or false, info.title or "" })
			end
		end
	elseif GetNumQuestLogEntries and GetQuestLogTitle then
		local n = GetNumQuestLogEntries() or 0
		for i = 1, n do
			local title, level, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
			if title and not isHeader and questID and questID > 0 then
				table.insert(log, { questID, level or 0, isComplete == 1 or isComplete == true, title })
			end
		end
	end
	return log
end

-- A sorted list of every quest this character has turned in
local function ReadCompleted()
	local list = {}
	if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
		local ok, ids = pcall(C_QuestLog.GetAllCompletedQuestIDs)
		if ok and type(ids) == "table" then
			for _, id in ipairs(ids) do table.insert(list, id) end
		end
	end
	if #list == 0 and GetQuestsCompleted then
		local ok, set = pcall(GetQuestsCompleted)
		if ok and type(set) == "table" then
			for id in pairs(set) do table.insert(list, id) end
		end
	end
	table.sort(list)
	return list
end

function ns.ReadQuests(snap)
	local ok, log = pcall(ReadLog)
	snap.log = ok and log or {}
	local okC, completed = pcall(ReadCompleted)
	snap.completed = okC and completed or {}
	local okR, _, _, race = pcall(UnitRace, "player")
	snap.race = okR and tonumber(race) or 0
end

---------------------------------------------------------------------------
-- Text: log entries "id=level=done=title" joined by "~"; finished quests as base 36 gaps
-- from the one before, joined by "."
---------------------------------------------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function Base36(n)
	if n == 0 then return "0" end
	local s = ""
	while n > 0 do
		local d = n % 36
		s = DIGITS:sub(d + 1, d + 1) .. s
		n = (n - d) / 36
	end
	return s
end

function ns.EncodeQuests(snap)
	local log = {}
	for _, q in ipairs(snap.log or {}) do
		local title = (q[4] or ""):gsub("[%^~=;/,+]", "")
		table.insert(log, ("%d=%d=%d=%s"):format(q[1], q[2] or 0, q[3] and 1 or 0, title))
	end
	local gaps, last = {}, 0
	for _, id in ipairs(snap.completed or {}) do
		table.insert(gaps, Base36(id - last))
		last = id
	end
	return table.concat(log, "~"), table.concat(gaps, ".")
end

function ns.DecodeQuests(snap, logText, completedText)
	snap.log, snap.completed = {}, {}
	for entry in (logText or ""):gmatch("[^~]+") do
		local id, level, done, title = entry:match("^(%d+)=(%d+)=(%d)=(.*)$")
		if id then table.insert(snap.log, { tonumber(id), tonumber(level), done == "1", title }) end
	end
	local last = 0
	for gap in (completedText or ""):gmatch("[^.]+") do
		local n = tonumber(gap, 36)
		if n then
			last = last + n
			table.insert(snap.completed, last)
		end
	end
	snap.hasQuests = logText ~= nil
end

---------------------------------------------------------------------------
-- QuestieDB, when it's there
---------------------------------------------------------------------------

local function QuestField(id, field)
	local lib = LibQuestieDB
	if type(lib) ~= "table" or type(lib.Quest) ~= "table" or type(lib.Quest.Get) ~= "function" then return nil end
	local ok, value = pcall(lib.Quest.Get, id, field)
	if ok then return value end
	return nil
end

local function NpcName(id)
	local lib = LibQuestieDB
	if type(lib) ~= "table" or type(lib.Npc) ~= "table" or type(lib.Npc.Get) ~= "function" then return nil end
	local ok, value = pcall(lib.Npc.Get, id, "name")
	if ok and type(value) == "string" then return value end
	return nil
end

local function ObjectName(id)
	local lib = LibQuestieDB
	if type(lib) ~= "table" or type(lib.Object) ~= "table" or type(lib.Object.Get) ~= "function" then return nil end
	local ok, value = pcall(lib.Object.Get, id, "name")
	if ok and type(value) == "string" then return value end
	return nil
end

local function AreaName(areaID)
	if type(areaID) ~= "number" or areaID <= 0 or not (C_Map and C_Map.GetAreaInfo) then return nil end
	local ok, name = pcall(C_Map.GetAreaInfo, areaID)
	if ok and type(name) == "string" and name ~= "" then return name end
	return nil
end

-- Class bits as Classic's ChrClasses IDs: warrior 1, paladin 2, hunter 3, rogue 4, priest 5,
-- shaman 7, mage 8, warlock 9, druid 11
local CLASS_ID = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8,
	WARLOCK = 9, DRUID = 11 }

local function HasBit(mask, bit)
	if type(mask) ~= "number" or mask <= 0 or not bit or bit < 1 then return true end
	local value = 2 ^ (bit - 1)
	return math.floor(mask / value) % 2 == 1
end

-- Whether QuestieDB says a snapshot's character can take this quest (true when it doesn't know)
local function CanTake(id, snap)
	if not HasBit(QuestField(id, "requiredClasses"), CLASS_ID[snap.class or ""]) then return false end
	if not HasBit(QuestField(id, "requiredRaces"), snap.race) then return false end
	return true
end

-- What to say about a quest: { id, title, level, minLevel, where }
function ns.QuestDetails(id, fallbackTitle, fallbackLevel)
	local title = QuestField(id, "name")
	if type(title) ~= "string" or title == "" then
		title = fallbackTitle
		if (not title or title == "") and C_QuestLog and C_QuestLog.GetTitleForQuestID then
			local ok, t = pcall(C_QuestLog.GetTitleForQuestID, id)
			if ok then title = t end
		end
	end
	local level = QuestField(id, "questLevel")
	if type(level) ~= "number" or level <= 0 then level = fallbackLevel end
	local minLevel = QuestField(id, "requiredLevel")
	if type(minLevel) ~= "number" or minLevel <= 0 then minLevel = nil end
	local where
	local starters = QuestField(id, "startedBy")
	if type(starters) == "table" then
		local npc = type(starters[1]) == "table" and starters[1][1]
		local object = type(starters[2]) == "table" and starters[2][1]
		where = (npc and NpcName(npc)) or (object and ObjectName(object))
	end
	local zone = AreaName(QuestField(id, "zoneOrSort"))
	if zone then where = where and (where .. ", " .. zone) or zone end
	return { id = id, title = title or ("Quest " .. id), level = level, minLevel = minLevel, where = where }
end

-- Who takes a quest in (QuestieDB), e.g. "Eleanor Shackleton"; nil without QuestieDB
function ns.QuestTurnIn(id)
	local enders = QuestField(id, "finishedBy")
	if type(enders) ~= "table" then return nil end
	local npc = type(enders[1]) == "table" and enders[1][1]
	local object = type(enders[2]) == "table" and enders[2][1]
	return (npc and NpcName(npc)) or (object and ObjectName(object)) or nil
end

---------------------------------------------------------------------------
-- Comparing
---------------------------------------------------------------------------

local function Set(list, field)
	local set = {}
	for _, v in ipairs(list or {}) do set[field and v[field] or v] = v end
	return set
end

-- Two lists of quests:
--   theirs: in their log, not in mine, and I haven't done it (I could go get it)
--   mine:   in my log, not in theirs, they haven't done it, and their class and race can take it
function ns.CompareQuests(key)
	local peer = ns.db.peers[key]
	local snap = peer and peer.snap
	if not snap or not snap.hasQuests then return nil end
	local me = {}
	ns.ReadQuests(me)
	local myLog, myDone = Set(me.log, 1), Set(me.completed)
	local theirLog, theirDone = Set(snap.log, 1), Set(snap.completed)
	local theirs, mine = {}, {}
	for _, q in ipairs(snap.log) do
		if not myLog[q[1]] and not myDone[q[1]] then
			table.insert(theirs, ns.QuestDetails(q[1], q[4], q[2]))
		end
	end
	for _, q in ipairs(me.log) do
		if not theirLog[q[1]] and not theirDone[q[1]] and CanTake(q[1], snap) then
			local details = ns.QuestDetails(q[1], q[4], q[2])
			details.tooLow = details.minLevel and details.minLevel > (snap.level or 0)
			table.insert(mine, details)
		end
	end
	local function byLevel(a, b)
		if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
		return a.title < b.title
	end
	table.sort(theirs, byLevel)
	table.sort(mine, byLevel)
	return theirs, mine
end

-- Quests in a buddy's log whose objectives are done, waiting to be turned in, that we've
-- already turned in ourselves (ones we both still have to hand in aren't worth a reminder)
function ns.ReadyToTurnIn(key)
	local peer = ns.db.peers[key]
	local snap = peer and peer.snap
	if not snap or not snap.hasQuests then return nil end
	local me = {}
	ns.ReadQuests(me)
	local myDone = Set(me.completed)
	local list = {}
	for _, q in ipairs(snap.log or {}) do
		if q[3] and myDone[q[1]] then
			local details = ns.QuestDetails(q[1], q[4], q[2])
			local turnIn = ns.QuestTurnIn(q[1])
			details.where = turnIn and ("turn in to " .. turnIn) or nil
			table.insert(list, details)
		end
	end
	table.sort(list, function(a, b)
		if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
		return a.title < b.title
	end)
	return list
end


---------------------------------------------------------------------------
-- Quest givers: what an NPC has for a buddy (QuestieDB only)
---------------------------------------------------------------------------

local setCache = {}
local function PeerSets(key)
	local peer = ns.db.peers[key]
	local cached = setCache[key]
	if cached and cached.hash == peer.hash then return cached.log, cached.done end
	local log = {}
	for _, q in ipairs(peer.snap.log or {}) do log[q[1]] = q end
	cached = { hash = peer.hash, log = log, done = Set(peer.snap.completed) }
	setCache[key] = cached
	return cached.log, cached.done
end

local function AllDone(list, done)
	if type(list) ~= "table" then return true end
	for _, id in ipairs(list) do
		if type(id) == "number" and id > 0 and not done[id] then return false end
	end
	return true
end

local function AnyDone(list, done)
	if type(list) ~= "table" or #list == 0 then return true end
	for _, id in ipairs(list) do
		if type(id) == "number" and done[id] then return true end
	end
	return false
end

local function NoneDone(list, done, log)
	if type(list) ~= "table" then return true end
	for _, id in ipairs(list) do
		if type(id) == "number" and (done[id] or log[id]) then return false end
	end
	return true
end

-- Quests an NPC has for a buddy: { needs = { details... }, turnIn = { details... } }, or nil
function ns.NpcQuestsFor(npcID, key)
	local peer = ns.db.peers[key]
	local snap = peer and peer.snap
	if not snap or not snap.hasQuests or not LibQuestieDB then return nil end
	local lib = LibQuestieDB
	if type(lib.Npc) ~= "table" or type(lib.Npc.Get) ~= "function" then return nil end
	local okS, starts = pcall(lib.Npc.Get, npcID, "questStarts")
	local okE, ends = pcall(lib.Npc.Get, npcID, "questEnds")
	starts = okS and type(starts) == "table" and starts or {}
	ends = okE and type(ends) == "table" and ends or {}
	if #starts == 0 and #ends == 0 then return nil end
	local log, done = PeerSets(key)
	local needs, turnIn = {}, {}
	for _, id in ipairs(starts) do
		if type(id) == "number" and not done[id] and not log[id] and CanTake(id, snap)
			and AllDone(QuestField(id, "preQuestGroup"), done) and AnyDone(QuestField(id, "preQuestSingle"), done)
			and NoneDone(QuestField(id, "exclusiveTo"), done, log) then
			local details = ns.QuestDetails(id)
			details.tooLow = details.minLevel and details.minLevel > (snap.level or 0)
			table.insert(needs, details)
		end
	end
	for _, id in ipairs(ends) do
		local q = type(id) == "number" and log[id]
		if q and q[3] then table.insert(turnIn, ns.QuestDetails(id, q[4], q[2])) end
	end
	if #needs == 0 and #turnIn == 0 then return nil end
	table.sort(needs, function(a, b) return (a.level or 0) < (b.level or 0) end)
	return { needs = needs, turnIn = turnIn }
end
