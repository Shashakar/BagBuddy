-- BagBuddy: the window. Pick a buddy, see what they wear and carry, or which of your own items
-- would be upgrades for them.
local _, ns = ...

local WIDTH, HEIGHT = 560, 620
local SIZE, GAP, PER_ROW = 34, 4, 11

local SLOT_NAMES = { "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands",
	"Ring", "Ring", "Trinket", "Trinket", "Back", "Main Hand", "Off Hand", "Ranged", "Tabard" }
local SLOT_ORDER = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18, 4, 19 }

local frame, scroll, content, title, info, search, modeButtons, emptyText
local peerButtons, itemButtons, rows, labels, recipeRows, questRows = {}, {}, {}, {}, {}, {}
local selected, mode = nil, "theirs"

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------

local function InsertLink(link)
	if not link then return end
	if ChatEdit_InsertLink then
		pcall(ChatEdit_InsertLink, link)
	elseif ChatFrameUtil and ChatFrameUtil.InsertLink then
		pcall(ChatFrameUtil.InsertLink, link)
	end
end

local function SetArrow(button)
	local arrow = button:CreateTexture(nil, "OVERLAY", nil, 2)
	arrow:SetSize(14, 14)
	arrow:SetPoint("TOPLEFT", -2, 2)
	local ok, set = pcall(arrow.SetAtlas, arrow, "bags-greenarrow")
	if not ok or set == false then
		arrow:Hide()
		arrow = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		arrow:SetPoint("TOPLEFT", 1, -1)
		arrow:SetText("|cff20ff20+|r")
	end
	button.arrow = arrow
end

local function ItemButton(i)
	local button = itemButtons[i]
	if button then return button end
	button = CreateFrame("Button", nil, content)
	button:SetFrameLevel(content:GetFrameLevel() + 3)
	button:SetSize(SIZE, SIZE)
	button.bg = button:CreateTexture(nil, "BACKGROUND")
	button.bg:SetAllPoints()
	button.bg:SetColorTexture(0, 0, 0, 0.5)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", 2, -2)
	button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button.border = button:CreateTexture(nil, "OVERLAY")
	button.border:SetAllPoints()
	button.border:SetTexture("Interface\\Buttons\\WHITE8x8")
	button.border:SetDrawLayer("BORDER")
	button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.count:SetPoint("BOTTOMRIGHT", -2, 2)
	SetArrow(button)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.item then
			GameTooltip:SetHyperlink(self.item)
			if self.bound then GameTooltip:AddLine("|cffff8080Soulbound to " .. (self.boundTo or "them") .. "|r") end
			if self.wear then
				local color = self.wear == 0 and "|cffff2020" or (self.wear < 25 and "|cffff8c00" or "|cffffffff")
				GameTooltip:AddLine(("Their durability: %s%d%%|r"):format(color, self.wear))
			end
		elseif self.slotName then
			GameTooltip:SetText(self.slotName)
			GameTooltip:AddLine("Empty", 0.6, 0.6, 0.6)
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnClick", function(self)
		if self.item and IsModifiedClick and IsModifiedClick("CHATLINK") then
			local itemInfo = ns.ItemInfo(self.item)
			InsertLink(itemInfo and itemInfo.link)
		end
	end)
	itemButtons[i] = button
	return button
end

-- Fills a button with an item (or an empty slot) and dims it when it doesn't match the search
local function ShowItem(button, item, count, opts)
	opts = opts or {}
	button.item, button.slotName, button.bound, button.boundTo = item, opts.slotName, opts.bound, opts.boundTo
	if item then
		button.icon:SetTexture(ns.ItemIcon(item))
		local itemInfo = ns.ItemInfo(item)
		local r, g, b = 0.3, 0.3, 0.3
		if itemInfo and itemInfo.quality and itemInfo.quality > 1 and C_Item.GetItemQualityColor then
			r, g, b = C_Item.GetItemQualityColor(itemInfo.quality)
		end
		button.border:SetVertexColor(r, g, b, 1)
		button.border:Show()
	else
		button.icon:SetTexture(opts.emptyTexture)
		button.icon:SetDesaturated(not opts.emptyBag)
		button.border:SetVertexColor(0.45, 0.45, 0.45, 1)
		button.border:SetShown(opts.emptyBag and true or false)
	end
	if item then button.icon:SetDesaturated(false) end
	button:SetSize(opts.size or SIZE, opts.size or SIZE)
	button.wear = opts.wear
	if opts.wear and opts.wear < 25 then
		-- Broken or nearly: red or orange, like the game's armor figure
		if opts.wear == 0 then button.border:SetVertexColor(1, 0.1, 0.1, 1) else button.border:SetVertexColor(1, 0.55, 0, 1) end
		button.border:Show()
	end
	button.count:SetText(count and count > 1 and count or "")
	button.arrow:SetShown(opts.upgrade and true or false)
	button:SetAlpha(opts.dim and 0.25 or 1)
	button:Show()
end

local function Label(i, text, y, x, font)
	local label = labels[i]
	if not label then
		if not content.labelLayer then
			-- Above the bag panel and the item buttons
			content.labelLayer = CreateFrame("Frame", nil, content)
			content.labelLayer:SetAllPoints()
			content.labelLayer:SetFrameLevel(content:GetFrameLevel() + 5)
		end
		label = content.labelLayer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		labels[i] = label
	end
	label:SetFontObject(font or "GameFontNormal")
	label:SetWidth(0)
	label:SetWordWrap(true)
	label:ClearAllPoints()
	label:SetPoint("TOPLEFT", x or 4, y)
	label:SetJustifyH("LEFT")
	label:SetText(text)
	label:Show()
	return y - 18, label
end

local function Row(i)
	local row = rows[i]
	if row then return row end
	row = CreateFrame("Frame", nil, content)
	row:SetSize(WIDTH - 60, SIZE)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.text:SetPoint("LEFT", SIZE + 8, 0)
	row.text:SetPoint("RIGHT", 0, 0)
	row.text:SetJustifyH("LEFT")
	rows[i] = row
	return row
end

local function Matches(item)
	local text = search and search:GetText() or ""
	if text == "" then return true end
	local itemInfo = ns.ItemInfo(item)
	if not itemInfo then return true end
	return itemInfo.name:lower():find(text:lower(), 1, true) ~= nil
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function HideAll()
	for _, r in ipairs(recipeRows) do r:Hide() end
	for _, r in ipairs(questRows) do r:Hide() end
	if content.bagPanel then content.bagPanel:Hide() end
	for _, b in ipairs(itemButtons) do b:Hide() end
	for _, r in ipairs(rows) do r:Hide() end
	for _, l in ipairs(labels) do l:Hide() end
end

local function Grid(startIndex, y, count, place)
	for n = 1, count do
		local button = ItemButton(startIndex + n - 1)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", 4 + ((n - 1) % PER_ROW) * (SIZE + GAP), y - math.floor((n - 1) / PER_ROW) * (SIZE + GAP))
		place(button, n)
	end
	return y - math.ceil(count / PER_ROW) * (SIZE + GAP) - 6
end

-- The character window's layout: slot, column (1 left, 2 right, 3 bottom row), row
local PAPERDOLL = {
	{ 1, 1, 1, "HeadSlot" }, { 2, 1, 2, "NeckSlot" }, { 3, 1, 3, "ShoulderSlot" }, { 15, 1, 4, "BackSlot" },
	{ 5, 1, 5, "ChestSlot" }, { 4, 1, 6, "ShirtSlot" }, { 19, 1, 7, "TabardSlot" }, { 9, 1, 8, "WristSlot" },
	{ 10, 2, 1, "HandsSlot" }, { 6, 2, 2, "WaistSlot" }, { 7, 2, 3, "LegsSlot" }, { 8, 2, 4, "FeetSlot" },
	{ 11, 2, 5, "Finger0Slot" }, { 12, 2, 6, "Finger1Slot" }, { 13, 2, 7, "Trinket0Slot" }, { 14, 2, 8, "Trinket1Slot" },
	{ 16, 3, 1, "MainHandSlot" }, { 17, 3, 2, "SecondaryHandSlot" }, { 18, 3, 3, "RangedSlot" },
}

local slotTextures = {}
local function SlotTexture(slotName)
	if slotTextures[slotName] == nil then
		local ok, _, texture = pcall(GetInventorySlotInfo, slotName)
		slotTextures[slotName] = ok and texture or false
	end
	return slotTextures[slotName] or nil
end

local function BagName(container)
	if container.merged then return "All bags |cffff9933(they need BagBuddy 1.1 to show each bag)|r" end
	if container.bag == 0 then return "Backpack" end
	local bagInfo = container.item and ns.ItemInfo(container.item)
	if bagInfo then return bagInfo.name end
	if container.bag == 5 then return "Reagent Bag" end
	return "Bag " .. container.bag
end

local function AverageItemLevel(snap)
	local total, count = 0, 0
	for slot, item in pairs(snap.equip) do
		if slot ~= 4 and slot ~= 19 then
			local itemInfo = ns.ItemInfo(item)
			if itemInfo then total, count = total + itemInfo.ilvl, count + 1 end
		end
	end
	return count > 0 and total / count or nil
end

local function DrawTheirs(key)
	local snap = ns.db.peers[key].snap
	local name = ns.Short(key)
	local width = content:GetWidth()
	local step = SIZE + GAP
	local nButton, nLabel = 0, 0
	local function NextButton() nButton = nButton + 1; return ItemButton(nButton) end
	local function NextLabel(...) nLabel = nLabel + 1; return Label(nLabel, ...) end

	-- Character window: two columns of slots, weapons along the bottom, who they are between
	for _, place in ipairs(PAPERDOLL) do
		local slot, column, row, slotName = place[1], place[2], place[3], place[4]
		local x, y
		if column == 1 then
			x, y = 4, -4 - (row - 1) * step
		elseif column == 2 then
			x, y = width - SIZE - 4, -4 - (row - 1) * step
		else
			x, y = width / 2 - (3 * step - GAP) / 2 + (row - 1) * step, -4 - 8 * step - 4
		end
		local button = NextButton()
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", x, y)
		local item = snap.equip[slot]
		local wear = item and snap.dura and snap.dura[slot]
		ShowItem(button, item, 1, { slotName = SLOT_NAMES[slot], emptyTexture = SlotTexture(slotName),
			dim = item and not Matches(item), wear = wear })
	end
	local cx = SIZE + 20
	local y = -24
	local _, label = NextLabel(ns.ClassColor(snap.class) .. name .. "|r", y, cx, "GameFontNormalHuge")
	y = y - 30
	y = NextLabel(("Level %d %s"):format(snap.level or 0, ns.ClassName(snap.class)), y, cx, "GameFontHighlight")
	y = NextLabel("|cff999999" .. ns.RoleName(key) .. "|r", y, cx, "GameFontHighlightSmall")
	y = y - 10
	local ilvl = AverageItemLevel(snap)
	if ilvl then y = NextLabel(("Average item level |cffffffff%.1f|r"):format(ilvl), y, cx, "GameFontNormalSmall") end
	y = NextLabel("Gold " .. ns.Money(snap.money), y, cx, "GameFontNormalSmall")
	y = NextLabel(("Bag space |cffffffff%d of %d free|r"):format(snap.free or 0, snap.total or 0), y, cx, "GameFontNormalSmall")
	y = NextLabel("|cff999999Updated " .. ns.Ago(ns.db.peers[key].time) .. "|r", y, cx, "GameFontHighlightSmall")

	-- Gear checkup: what needs fixing, in a few words
	y = y - 10
	local function Wrapped(text)
		local _, l = NextLabel(text, y, cx, "GameFontHighlightSmall")
		l:SetWidth(width - 2 * cx)
		y = y - math.max(14, l:GetStringHeight() + 4)
	end
	local issues = 0
	if snap.dura then
		local broken, low = {}, {}
		for _, place in ipairs(PAPERDOLL) do
			local pct = snap.dura[place[1]]
			if pct == 0 then table.insert(broken, SLOT_NAMES[place[1]])
			elseif pct and pct < 25 then table.insert(low, ("%s %d%%"):format(SLOT_NAMES[place[1]], pct)) end
		end
		if #broken > 0 then Wrapped("|cffff2020Broken:|r " .. table.concat(broken, ", ")); issues = issues + 1 end
		if #low > 0 then Wrapped("|cffff8c00Needs repair:|r " .. table.concat(low, ", ")); issues = issues + 1 end
		local empty = {}
		for _, place in ipairs(PAPERDOLL) do
			local slot = place[1]
			if slot ~= 4 and slot ~= 19 and not snap.equip[slot] then
				if not (slot == 17 and snap.equip[16] and ns.ItemInfo(snap.equip[16])
					and ns.ItemInfo(snap.equip[16]).equipLoc == "INVTYPE_2HWEAPON") then
					table.insert(empty, SLOT_NAMES[slot])
				end
			end
		end
		if #empty > 0 then Wrapped("|cffffd100Empty:|r " .. table.concat(empty, ", ")); issues = issues + 1 end
		if (snap.unspent or 0) > 0 then
			Wrapped(("|cffffd100%d unspent talent point%s|r"):format(snap.unspent, snap.unspent == 1 and "" or "s"))
			issues = issues + 1
		end
		if snap.unplaced and #snap.unplaced > 0 then
			local names = {}
			for _, id in ipairs(snap.unplaced) do
				local name, icon = ns.SpellName(id)
				table.insert(names, icon and ("|T%s:14|t %s"):format(icon, name) or name)
			end
			Wrapped("|cffffd100Not on action bars:|r " .. table.concat(names, ", "))
			issues = issues + 1
		end
		if issues == 0 then Wrapped("|cff20ff20Gear checkup: all good|r") end
	end
	local centerBottom = y

	-- Each bag with its slots, empty ones too, on a panel of their own
	y = math.min(-4 - 9 * step - 16, centerBottom - 12)
	local panelTop = y + 8
	local containers = snap.containers
	if not containers then
		local bags = snap.bags or {}
		containers = { { bag = 0, slots = math.max(#bags, snap.total or 0), contents = bags, merged = true } }
	end
	local perRow = math.floor((width - 4) / step)
	for _, container in ipairs(containers) do
		local free = 0
		for slot = 1, container.slots do
			if not container.contents[slot] then free = free + 1 end
		end
		if container.item then
			local bagButton = NextButton()
			bagButton:ClearAllPoints()
			bagButton:SetPoint("TOPLEFT", 4, y + 2)
			ShowItem(bagButton, container.item, 1, { size = 20 })
		end
		local tx = container.item and 30 or 4
		NextLabel(("%s  |cff999999%d slots, %d free|r"):format(BagName(container), container.slots, free), y - 2, tx)
		y = y - 24
		for slot = 1, container.slots do
			local button = NextButton()
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", 4 + ((slot - 1) % perRow) * step, y - math.floor((slot - 1) / perRow) * step)
			local entry = container.contents[slot]
			if entry then
				local result = ns.Compare(entry[1], key)
				ShowItem(button, entry[1], entry[2], {
					bound = entry[3], boundTo = name, dim = not Matches(entry[1]),
					upgrade = result and result.status == "upgrade" and not result.level,
				})
			else
				ShowItem(button, nil, nil, { emptyTexture = "Interface\\PaperDoll\\UI-Backpack-EmptySlot", emptyBag = true,
					dim = (search and search:GetText() or "") ~= "" })
			end
		end
		y = y - math.ceil(container.slots / perRow) * step - 10
	end
	if not content.bagPanel then
		local panel = CreateFrame("Frame", nil, content, BackdropTemplateMixin and "BackdropTemplate" or nil)
		panel:SetFrameLevel(content:GetFrameLevel() + 1)
		if panel.SetBackdrop then
			panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
			panel:SetBackdropColor(0.12, 0.09, 0.05, 0.9)
			panel:SetBackdropBorderColor(0.6, 0.5, 0.35, 1)
		else
			local bg = panel:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints()
			bg:SetColorTexture(0.12, 0.09, 0.05, 0.9)
		end
		content.bagPanel = panel
	end
	local panel = content.bagPanel
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", -2, panelTop)
	panel:SetPoint("RIGHT", content, "RIGHT", 2, 0)
	panel:SetHeight(panelTop - y)
	panel:Show()
	content:SetHeight(-y + 10)
end

local function DrawMine(key)
	local mine = ns.ReadSelf()
	local list = {}
	for _, entry in ipairs(mine.bags) do
		local result = ns.Compare(entry[1], key)
		-- Soulbound items can't be handed over, so they're no use to anyone else
		if not entry[3] and result and (result.status == "upgrade" or result.status == "pending") and Matches(entry[1]) then
			table.insert(list, { entry = entry, result = result })
		end
	end
	table.sort(list, function(a, b)
		return (a.result.percent or 1000) > (b.result.percent or 1000)
	end)
	local y = Label(1, ("Items in your bags that would be upgrades for %s"):format(ns.Short(key)), -4)
	if #list == 0 then
		y = Label(2, "|cff999999None right now. Gear you pick up shows here when it would help.|r", y)
	end
	for n, row in ipairs(list) do
		local frameRow = Row(n)
		frameRow:ClearAllPoints()
		frameRow:SetPoint("TOPLEFT", 4, y)
		local button = ItemButton(n)
		button:ClearAllPoints()
		button:SetPoint("LEFT", frameRow, "LEFT", 0, 0)
		ShowItem(button, row.entry[1], row.entry[2], { bound = row.entry[3], boundTo = "you", upgrade = true })
		local itemInfo = ns.ItemInfo(row.entry[1])
		local text = ns.VerdictText(key, row.entry[1]) or ""
		text = text:gsub("^.-|r: ", "")
		frameRow.text:SetText((itemInfo and itemInfo.link or "...") .. "\n" .. text)
		frameRow:Show()
		y = y - SIZE - GAP
	end
	content:SetHeight(-y + 10)
end

local function QuestColor(level)
	if GetQuestDifficultyColor and level and level > 0 then
		local ok, c = pcall(GetQuestDifficultyColor, level)
		if ok and type(c) == "table" and c.r then
			return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
		end
	end
	return "|cffffd100"
end

local function QuestMatches(q)
	local text = search and search:GetText() or ""
	return text == "" or q.title:lower():find(text:lower(), 1, true) ~= nil
end

-- Addons can't open a browser, so show the Wowhead link in a box ready to copy (Ctrl+C)
local WOWHEAD = "https://www.wowhead.com/classic/quest=%d"
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["BAGBUDDY_LINK"] = {
	text = "%s\n|cff999999Press Ctrl+C to copy, then paste it in your browser.|r",
	button1 = OKAY or "OK",
	hasEditBox = true,
	editBoxWidth = 320,
	OnShow = function(self, data)
		local box = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
		if box then
			box:SetText(data or "")
			box:SetFocus()
			box:HighlightText()
		end
	end,
	EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
	EditBoxOnEnterPressed = function(box) box:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function ShowQuestLink(id, title)
	local url = WOWHEAD:format(id)
	StaticPopup_Show("BAGBUDDY_LINK", title or ("Quest " .. id), nil, url)
end

-- One quest line, with an Ignore (or Unignore) button on the right. Click the line for its
-- Wowhead link.
local function QuestRow(i)
	local row = questRows[i]
	if row then return row end
	row = CreateFrame("Button", nil, content)
	row:SetFrameLevel(content:GetFrameLevel() + 3)
	row:SetHeight(18)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row:SetScript("OnClick", function(self)
		if self.questID then ShowQuestLink(self.questID, self.title) end
	end)
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.title or "")
		GameTooltip:AddLine("Click for its Wowhead link", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row.toggle = CreateFrame("Button", nil, row)
	row.toggle:SetSize(64, 16)
	row.toggle:SetPoint("RIGHT", -2, 0)
	row.toggle:SetNormalFontObject("GameFontDisableSmall")
	row.toggle:SetHighlightFontObject("GameFontHighlightSmall")
	row.toggle:SetText("ignore")
	row.toggle:GetFontString():SetJustifyH("RIGHT")
	row.toggle:GetFontString():SetPoint("RIGHT")
	row.toggle:SetScript("OnClick", function(self)
		local id = self:GetParent().questID
		if not id then return end
		ns.db.ignoredQuests[id] = not ns.db.ignoredQuests[id] or nil
		ns.RefreshViewer(true)
	end)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.text:SetPoint("LEFT", 0, 0)
	row.text:SetPoint("RIGHT", row.toggle, "LEFT", -6, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	questRows[i] = row
	return row
end

local function DrawQuests(key)
	local snap = ns.db.peers[key].snap
	local name = ns.Short(key)
	local width = content:GetWidth() - 16
	local n, r = 0, 0
	local ignored = ns.db.ignoredQuests
	local function Line(text, y, x, font)
		n = n + 1
		local nextY, label = Label(n, text, y, x, font)
		label:SetWidth(width - (x or 4) + 4)
		label:SetWordWrap(false)
		return nextY
	end
	local function Quest(q, y, extra, toggleText)
		local text = ("%s[%s]|r %s"):format(QuestColor(q.level), q.level and q.level > 0 and q.level or "?", q.title)
		if extra then text = text .. "  " .. extra end
		if q.where then text = text .. "  |cff999999" .. q.where .. "|r" end
		r = r + 1
		local row = QuestRow(r)
		row.questID, row.title = q.id, q.title
		row.text:SetText(text)
		row.toggle:SetText(toggleText or "ignore")
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 14, y + 2)
		row:SetWidth(width - 10)
		row:Show()
		return y - 18
	end
	local y = -4
	local theirs, mine = ns.CompareQuests(key)
	if not theirs then
		y = Line(("|cff999999%s's BagBuddy is too old to share quests. Send them version 1.2 or newer.|r"):format(name), y)
		content:SetHeight(-y + 10)
		return
	end
	local hidden = {}
	local function Section(header, list, extraFor)
		local visible = {}
		for _, q in ipairs(list) do
			if ignored[q.id] then table.insert(hidden, q) else table.insert(visible, q) end
		end
		y = Line(("%s  |cff999999(%d)|r"):format(header, #visible), y, 4, "GameFontNormalLarge") - 4
		local shown = 0
		for _, q in ipairs(visible) do
			if QuestMatches(q) then y = Quest(q, y, extraFor and extraFor(q)); shown = shown + 1 end
		end
		if shown == 0 then y = Line("|cff999999None.|r", y, 14) end
		y = y - 14
	end
	-- Quests done and waiting to be turned in come first, and only once
	local ready = ns.ReadyToTurnIn(key) or {}
	local isReady = {}
	for _, q in ipairs(ready) do isReady[q.id] = true end
	local rest = {}
	for _, q in ipairs(theirs) do
		if not isReady[q.id] then table.insert(rest, q) end
	end
	if #ready > 0 then
		Section(("|cff20ff20%s can turn in (you already did)|r"):format(name), ready)
	end
	Section(("Quests %s has that you don't"):format(name), rest)
	Section(("Your quests %s still needs"):format(name), mine, function(q)
		return q.tooLow and ("|cffff9933at level %d|r"):format(q.minLevel) or nil
	end)
	if #hidden > 0 then
		y = Line(("Ignored  |cff999999(%d)|r"):format(#hidden), y, 4, "GameFontNormal") - 2
		for _, q in ipairs(hidden) do
			if QuestMatches(q) then y = Quest(q, y, nil, "unignore") end
		end
		y = y - 10
	end
	if not LibQuestieDB then
		y = Line("|cff999999Install QuestieDB to see where each quest starts.|r", y, 4, "GameFontHighlightSmall")
	end
	content:SetHeight(-y + 10)
end

---------------------------------------------------------------------------
-- Professions
---------------------------------------------------------------------------

local function ItemName(id)
	local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
	if not name and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
	return name or ("item " .. id)
end

local function RecipeRow(i)
	local row = recipeRows[i]
	if row then return row end
	row = CreateFrame("Button", nil, content)
	row:SetFrameLevel(content:GetFrameLevel() + 3)
	row:SetHeight(16)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", 4, 0)
	row.name:SetJustifyH("LEFT")
	row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.status:SetPoint("RIGHT", -4, 0)
	row.status:SetJustifyH("RIGHT")
	row.name:SetPoint("RIGHT", row.status, "LEFT", -8, 0)
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local r = self.recipe
		if r.out then GameTooltip:SetHyperlink("item:" .. r.out) else GameTooltip:SetText(r.name) end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Reagents in " .. (self.who or "their") .. " bags:")
		for _, reagent in ipairs(r.reagents) do
			local have = self.counts[reagent[1]] or 0
			local color = have >= reagent[2] and "|cff20ff20" or "|cffff4040"
			GameTooltip:AddDoubleLine(ItemName(reagent[1]), ("%s%d / %d|r"):format(color, have, reagent[2]), 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	recipeRows[i] = row
	return row
end

local GATHERING = { Herbalism = true, Skinning = true, Fishing = true }

local function DrawProfessions(key)
	local peer = ns.db.peers[key]
	local snap = peer.snap
	local name = ns.Short(key)
	local width = content:GetWidth()
	local counts = ns.ItemCounts(snap)
	local text = search and search:GetText() or ""
	local n, nRow = 0, 0
	local function Line(t, y, x, font)
		n = n + 1
		return (Label(n, t, y, x, font))
	end
	local y = -4
	local recipes = peer.recipes or {}
	local order, seen = {}, {}
	for _, skill in ipairs(snap.skills or {}) do
		table.insert(order, { skill[1], skill[2], skill[3] })
		seen[skill[1]] = true
	end
	for profName in pairs(recipes) do
		if not seen[profName] then table.insert(order, { profName }) end
	end
	if #order == 0 then
		y = Line(("|cff999999No professions from %s yet. They need BagBuddy 1.3 or newer.|r"):format(name), y)
	end
	for _, prof in ipairs(order) do
		local profName, rank, max = prof[1], prof[2], prof[3]
		local header = profName
		if rank then header = ("%s  |cffffffff%d / %d|r"):format(profName, rank, max or 0) end
		y = Line(header, y, 4, "GameFontNormalLarge") - 2
		local data = recipes[profName]
		if data and #data.list > 0 then
			local list, makeable = {}, 0
			for _, r in ipairs(data.list) do
				local times, missing = ns.CanMake(r, counts)
				if times > 0 then makeable = makeable + 1 end
				if text == "" or r.name:lower():find(text:lower(), 1, true) then
					table.insert(list, { r = r, times = times, missing = missing })
				end
			end
			table.sort(list, function(a, b)
				if (a.r.diff or 3) ~= (b.r.diff or 3) then return (a.r.diff or 3) < (b.r.diff or 3) end
				return a.r.name < b.r.name
			end)
			y = Line(("|cff999999%d recipes, %d %s can make now. Recipes updated %s.|r"):format(#data.list, makeable, name,
				ns.Ago(data.time)), y, 8, "GameFontHighlightSmall") - 2
			for _, entry in ipairs(list) do
				nRow = nRow + 1
				local row = RecipeRow(nRow)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", 4, y)
				row:SetWidth(width - 8)
				row.recipe, row.counts, row.who = entry.r, counts, name .. "'s"
				row.name:SetText(ns.RecipeColor(entry.r.diff) .. entry.r.name .. "|r")
				if entry.times > 0 then
					row.status:SetText(("|cff20ff20can make %d|r"):format(entry.times))
				elseif #entry.r.reagents == 0 then
					row.status:SetText("")
				else
					local first = entry.missing[1]
					local more = #entry.missing > 1 and (" +%d more"):format(#entry.missing - 1) or ""
					row.status:SetText(("|cff999999needs %d %s%s|r"):format(first[2], ItemName(first[1]), more))
				end
				row:Show()
				y = y - 16
			end
		elseif not GATHERING[profName] then
			y = Line(("|cff999999Recipes show up here once %s opens their %s window.|r"):format(name, profName), y, 8,
				"GameFontHighlightSmall")
		end
		y = y - 10
	end
	content:SetHeight(-y + 10)
end

local function DrawPeers()
	local list = ns.PeerList()
	if not selected or not ns.db.peers[selected] or not ns.db.peers[selected].snap then selected = list[1] end
	local x = 12
	for i, key in ipairs(list) do
		local button = peerButtons[i]
		if not button then
			button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
			button:SetHeight(22)
			button:SetScript("OnClick", function(self)
				selected = self.key
				ns.RefreshViewer(true)
			end)
			peerButtons[i] = button
		end
		button.key = key
		button:SetText(ns.Short(key))
		button:SetWidth(math.max(70, button:GetFontString():GetStringWidth() + 24))
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", x, -30)
		button:SetEnabled(key ~= selected)
		button:Show()
		x = x + button:GetWidth() + 4
	end
	for i = #list + 1, #peerButtons do peerButtons[i]:Hide() end
	return #list
end

local function Draw()
	if not frame or not frame:IsShown() then return end
	HideAll()
	local count = DrawPeers()
	if count == 0 then
		info:SetText("")
		emptyText:Show()
		for _, b in pairs(modeButtons) do b:Hide() end
		search:Hide()
		content:SetHeight(10)
		return
	end
	emptyText:Hide()
	search:Show()
	for m, b in pairs(modeButtons) do
		b:Show()
		b:SetEnabled(m ~= mode)
	end
	local peer = ns.db.peers[selected]
	local snap = peer.snap
	info:SetText(("%sLevel %d %s|r, %s  |cff999999updated %s|r  %s"):format(ns.ClassColor(snap.class), snap.level or 0,
		ns.ClassName(snap.class), ns.RoleName(selected), ns.Ago(peer.time), ns.Money(snap.money)))
	if mode == "mine" then
		DrawMine(selected)
	elseif mode == "quests" then
		DrawQuests(selected)
	elseif mode == "professions" then
		DrawProfessions(selected)
	else
		DrawTheirs(selected)
	end
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------

local function Create()
	local ok, f = pcall(CreateFrame, "Frame", "BagBuddyFrame", UIParent, "BasicFrameTemplateWithInset")
	if not ok then
		f = CreateFrame("Frame", "BagBuddyFrame", UIParent, "BackdropTemplate")
		f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
		local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -4, -4)
	end
	frame = f
	f:SetSize(WIDTH, HEIGHT)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		ns.db.point = { point, relPoint, x, y }
	end)
	local p = ns.db.point
	if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("CENTER") end
	table.insert(UISpecialFrames, "BagBuddyFrame")

	title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", 0, -5)
	title:SetText("BagBuddy")

	info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	info:SetPoint("TOPLEFT", 14, -58)
	info:SetPoint("RIGHT", -14, 0)
	info:SetJustifyH("LEFT")

	modeButtons = {}
	local theirs = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	theirs:SetSize(118, 22)
	theirs:SetPoint("TOPLEFT", 12, -76)
	theirs:SetText("Their gear & bags")
	theirs:SetScript("OnClick", function() mode = "theirs"; ns.RefreshViewer(true) end)
	modeButtons.theirs = theirs
	local mine = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	mine:SetSize(140, 22)
	mine:SetPoint("LEFT", theirs, "RIGHT", 4, 0)
	mine:SetText("Upgrades in my bags")
	mine:SetScript("OnClick", function() mode = "mine"; ns.RefreshViewer(true) end)
	modeButtons.mine = mine
	local quests = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	quests:SetSize(70, 22)
	quests:SetPoint("LEFT", mine, "RIGHT", 4, 0)
	quests:SetText("Quests")
	quests:SetScript("OnClick", function() mode = "quests"; ns.RefreshViewer(true) end)
	modeButtons.quests = quests
	local profs = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	profs:SetSize(90, 22)
	profs:SetPoint("LEFT", quests, "RIGHT", 4, 0)
	profs:SetText("Professions")
	profs:SetScript("OnClick", function() mode = "professions"; ns.RefreshViewer(true) end)
	modeButtons.professions = profs

	search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	search:SetSize(90, 20)
	search:SetPoint("TOPRIGHT", -18, -77)
	search:SetAutoFocus(false)
	search:SetScript("OnTextChanged", function() ns.RefreshViewer(true) end)
	search:SetScript("OnEscapePressed", search.ClearFocus)
	local hint = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", 2, 0)
	hint:SetText("Search")
	search:HookScript("OnEditFocusGained", function() hint:Hide() end)
	search:HookScript("OnEditFocusLost", function(self) hint:SetShown(self:GetText() == "") end)

	local okScroll, s = pcall(CreateFrame, "ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	if not okScroll then
		-- No scroll bar template: scroll with the mouse wheel
		s = CreateFrame("ScrollFrame", nil, f)
		s:EnableMouseWheel(true)
		s:SetScript("OnMouseWheel", function(self, delta)
			local max = math.max(0, content:GetHeight() - self:GetHeight())
			self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 40)))
		end)
	end
	scroll = s
	scroll:SetPoint("TOPLEFT", 10, -104)
	scroll:SetPoint("BOTTOMRIGHT", -30, 10)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(WIDTH - 44, 10)
	scroll:SetScrollChild(content)

	emptyText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	emptyText:SetPoint("TOPLEFT", 20, -70)
	emptyText:SetPoint("RIGHT", -20, 0)
	emptyText:SetJustifyH("LEFT")
	emptyText:SetSpacing(4)
	emptyText:SetText("No one's bags yet.\n\nBagBuddy shares bags with anyone in your group who also has it installed. "
		.. "Join a group with them and their bags show up here within a few seconds.\n\n"
		.. "To sync when you're not grouped, add each other to your friends lists and type\n|cffffd100/bud add Name|r")

	f:SetScript("OnShow", Draw)
end

local redraw = false
function ns.RefreshViewer(now)
	if not frame or not frame:IsShown() then return end
	if now then return Draw() end
	if redraw then return end
	redraw = true
	C_Timer.After(0.2, function()
		redraw = false
		Draw()
	end)
end

function ns.ToggleViewer()
	if not frame then
		Create()
		frame:Hide()
		frame:Show()
		return
	end
	frame:SetShown(not frame:IsShown())
end
