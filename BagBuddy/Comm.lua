-- BagBuddy: talking to other BagBuddy players with addon messages.
--
--   H:<hash>               "here are my bags at version <hash>": sent to the group and to online
--                          friends you sync with, whenever your bags or gear change
--   R                      "send me your bags": the answer to an H whose hash you don't have
--   D:<hash>:<i>:<n>:<..>  part i of n of a snapshot, by whisper to whoever asked
local _, ns = ...

local PREFIX = "BagBuddy"
local CHUNK = 220
local SEND_GAP = 0.35    -- seconds between messages we send
local QUIET = 6          -- seconds of no bag changes before telling others
local MIN_ANNOUNCE = 15  -- seconds between announcements

-- Results of SendAddonMessage that won't get better by trying again
local PERMANENT = { [1] = true, [2] = true, [4] = true, [5] = true, [6] = true, [7] = true, [10] = true, [12] = true }

local mine = { text = nil, hash = nil }
local greeted = {}       -- peers we said hello to this session
local announced = {}     -- peers told about mine.hash already
local inbox = {}         -- partial snapshots by sender
local told = {}          -- peers whose first snapshot we printed about

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

local queue = {}
local sending = false

local function Pump()
	local item = queue[1]
	if not item then sending = false; return end
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.msg, item.channel, item.target)
	local delay = SEND_GAP
	if not ok then
		ns.Debug("send error: " .. tostring(result))
		table.remove(queue, 1)
	elseif result == nil or result == true or result == 0 then
		table.remove(queue, 1)
	elseif type(result) == "number" and PERMANENT[result] then
		ns.Debug(("dropped a message to %s (%s)"):format(tostring(item.target or item.channel), result))
		table.remove(queue, 1)
	else
		-- Throttled, or addon messages are locked (combat in an instance): try again later
		item.tries = (item.tries or 0) + 1
		if item.tries > 60 then table.remove(queue, 1) end
		delay = 2
	end
	C_Timer.After(delay, Pump)
end

local function Send(msg, channel, target)
	if channel == "WHISPER" then target = ns.WhisperName(target) end
	table.insert(queue, { msg = msg, channel = channel, target = target })
	if not sending then
		sending = true
		C_Timer.After(0, Pump)
	end
end

local function GroupChannel()
	if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
	return nil
end

local function InGroup(key)
	local short = ns.Short(key)
	return UnitInParty(short) or UnitInRaid(short)
end

-- A partner we can whisper while not grouped: on the friends list and online. Whispering
-- someone offline prints "No player named ..." in chat, so never guess.
local function FriendOnline(key)
	if not (C_FriendList and C_FriendList.GetFriendInfo) then return false end
	for _, name in ipairs({ ns.Short(key), key }) do
		local ok, info = pcall(C_FriendList.GetFriendInfo, name)
		if ok and type(info) == "table" and info.connected then return true end
	end
	return false
end

local function Reachable(key)
	return InGroup(key) or FriendOnline(key)
end

---------------------------------------------------------------------------
-- My snapshot
---------------------------------------------------------------------------

local function Refresh()
	local ok, snap = pcall(ns.ReadSelf)
	if not ok then ns.Debug("reading bags: " .. tostring(snap)); return false end
	local text = ns.Encode(snap)
	local hash = ns.Hash(text)
	mine.snap = snap
	if hash == mine.hash then return false end
	mine.text, mine.hash = text, hash
	wipe(announced)
	return true
end

function ns.MySnapshot()
	if not mine.snap then Refresh() end
	return mine.snap
end

local function Packed()
	local text = mine.text
	local E = C_EncodingUtil
	if E and E.CompressString and E.EncodeBase64 and E.DecompressString and E.DecodeBase64
		and Enum and Enum.CompressionMethod then
		local ok, packed = pcall(function()
			local z = E.EncodeBase64(E.CompressString(text, Enum.CompressionMethod.Deflate))
			if E.DecompressString(E.DecodeBase64(z), Enum.CompressionMethod.Deflate) ~= text then return nil end
			return z
		end)
		if ok and type(packed) == "string" and #packed < #text then return "Z" .. packed end
	end
	return "P" .. text
end

local function SendSnapshot(target)
	Refresh()
	if not mine.text then return end
	-- Don't queue a second copy for someone still waiting on the first
	for _, item in ipairs(queue) do
		if item.target == ns.WhisperName(target) and item.msg:sub(1, 2) == "D:" then return end
	end
	local data = Packed()
	local n = math.ceil(#data / CHUNK)
	for i = 1, n do
		Send(("D:%s:%d:%d:%s"):format(mine.hash, i, n, data:sub((i - 1) * CHUNK + 1, i * CHUNK)), "WHISPER", target)
	end
	ns.Debug(("sent my bags to %s in %d parts (%d bytes)"):format(ns.Short(target), n, #data))
end

-- Tell the group and online partners what version of my bags there is
local lastAnnounce = 0
local function Announce(force)
	Refresh()
	if not mine.hash then return end
	lastAnnounce = GetTime()
	local channel = GroupChannel()
	if channel then Send("H:" .. mine.hash .. ":" .. ns.session, channel) end
	for key, peer in pairs(ns.db.peers) do
		if peer.partner and not InGroup(key) and (force or not announced[key]) and FriendOnline(key) then
			Send("H:" .. mine.hash .. ":" .. ns.session, "WHISPER", key)
			announced[key] = true
			greeted[key] = true
		end
	end
end

local announceTimer
local function AnnounceSoon()
	if announceTimer then announceTimer:Cancel() end
	local wait = math.max(QUIET, MIN_ANNOUNCE - (GetTime() - lastAnnounce))
	announceTimer = C_Timer.NewTimer(wait, function()
		announceTimer = nil
		if Refresh() then Announce() end
	end)
end

function ns.SyncAll(force)
	Refresh()
	for key in pairs(ns.db.peers) do
		if Reachable(key) then Send("R", "WHISPER", key) end
	end
	Announce(force)
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local function Unpack(data)
	local kind, body = data:sub(1, 1), data:sub(2)
	if kind == "P" then return body end
	if kind == "Z" then
		local E = C_EncodingUtil
		local ok, text = pcall(function()
			return E.DecompressString(E.DecodeBase64(body), Enum.CompressionMethod.Deflate)
		end)
		if ok and type(text) == "string" then return text end
	end
	return nil
end

local function Store(sender, hash, text)
	if ns.Hash(text) ~= hash then ns.Debug("snapshot from " .. sender .. " didn't add up"); return end
	local snap = ns.Decode(text)
	if not snap then ns.Debug("couldn't read the snapshot from " .. sender); return end
	local peer = ns.db.peers[sender] or {}
	for key, other in pairs(ns.db.peers) do
		if key ~= sender and ns.SamePlayer(key, sender) then
			peer.role, peer.partner = peer.role or other.role, peer.partner or other.partner
			ns.db.peers[key] = nil
		end
	end
	ns.db.peers[sender] = peer
	peer.snap, peer.hash, peer.time = snap, hash, GetServerTime()
	peer.partner = true
	if not told[sender] then
		told[sender] = true
		ns.Print(("got %s's bags. Type /bud to look."):format(ns.Short(sender)))
	end
	ns.RefreshViewer()
end

local function OnHello(sender, hash)
	local peer = ns.db.peers[sender]
	if not peer or peer.hash ~= hash then
		Send("R", "WHISPER", sender)
	elseif peer then
		peer.time = GetServerTime()
	end
	-- Answer a hello once, so a player who just logged in learns about us too
	if not greeted[sender] then
		greeted[sender] = true
		Refresh()
		if mine.hash then Send("H:" .. mine.hash .. ":" .. ns.session, "WHISPER", sender) end
	end
end

local function OnData(sender, hash, i, n, chunk)
	local box = inbox[sender]
	if not box or box.hash ~= hash or box.n ~= n then
		box = { hash = hash, n = n, parts = {}, got = 0 }
		inbox[sender] = box
	end
	if not box.parts[i] then
		box.parts[i] = chunk
		box.got = box.got + 1
	end
	if box.got == n then
		inbox[sender] = nil
		local text = Unpack(table.concat(box.parts))
		if text then Store(sender, hash, text) else ns.Debug("couldn't unpack data from " .. sender) end
	end
end

ns.On("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
	if prefix ~= PREFIX or not ns.Usable(msg) or not ns.Usable(sender) then return end
	sender = ns.FullName(sender)
	if not sender or ns.SamePlayer(sender, ns.Me()) or ns.IsMe(sender) then return end
	local kind = msg:sub(1, 1)
	if kind == "H" then
		local hash, session = msg:match("^H:(%x+):?(%x*)")
		if session == ns.session then
			-- Our own group message, come back to us
			if ns.db.peers[sender] or not (ns.db.selfNames and ns.db.selfNames[sender:lower()]) then
				ns.RememberSelf(sender)
				ns.RefreshViewer()
			end
			return
		end
		if hash then OnHello(sender, hash) end
	elseif kind == "R" then
		SendSnapshot(sender)
	elseif kind == "D" then
		local hash, i, n, chunk = msg:match("^D:(%x+):(%d+):(%d+):(.*)$")
		i, n = tonumber(i), tonumber(n)
		if hash and i and n and n < 200 and i >= 1 and i <= n then OnData(sender, hash, i, n, chunk) end
	end
end)

---------------------------------------------------------------------------
-- When to tell others
---------------------------------------------------------------------------

ns.OnLogin(function()
	if C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
	C_Timer.After(6, function() Announce() end)
	-- Partners who come online later
	C_Timer.NewTicker(60, function()
		for key, peer in pairs(ns.db.peers) do
			if peer.partner and not greeted[key] and not InGroup(key) and FriendOnline(key) then
				Announce()
				return
			end
		end
	end)
end)

for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
	"PLAYER_MONEY", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
	"QUEST_REMOVED", "QUEST_LOG_UPDATE" }) do
	ns.On(event, AnnounceSoon)
end

local rosterTimer
ns.On("GROUP_ROSTER_UPDATE", function()
	if rosterTimer then return end
	rosterTimer = C_Timer.NewTimer(3, function()
		rosterTimer = nil
		Announce()
	end)
end)
