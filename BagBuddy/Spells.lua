-- BagBuddy: spells this character knows but hasn't put on an action bar (what the spellbook's
-- "not on your bars" glow shows), read here so it can travel with the snapshot.
local _, ns = ...

-- Only the game's own C functions here: calling Blizzard's Lua helpers (ActionButtonUtil) from
-- an addon can taint the action bars
local function Missing(spellID)
	if C_ActionBar and C_ActionBar.FindSpellActionButtons then
		local ok, slots = pcall(C_ActionBar.FindSpellActionButtons, spellID)
		if ok then return not (type(slots) == "table" and #slots > 0) end
	end
	return false
end

-- Spell IDs, in spellbook order; nil when this client can't tell
function ns.ReadUnplacedSpells()
	local book = C_SpellBook
	if not (book and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo and book.GetSpellBookItemInfo
		and Enum.SpellBookSpellBank and Enum.SpellBookItemType) then
		return nil
	end
	local bank = Enum.SpellBookSpellBank.Player
	local list, seen = {}, {}
	for line = 1, book.GetNumSpellBookSkillLines() or 0 do
		local lineInfo = book.GetSpellBookSkillLineInfo(line)
		if type(lineInfo) == "table" and not lineInfo.shouldHide and not lineInfo.isGuild and not lineInfo.offSpecID then
			local first = lineInfo.itemIndexOffset or 0
			for index = first + 1, first + (lineInfo.numSpellBookItems or 0) do
				local ok, item = pcall(book.GetSpellBookItemInfo, index, bank)
				if ok and type(item) == "table" and item.itemType == Enum.SpellBookItemType.Spell
					and not item.isPassive and not item.isOffSpec then
					local id = item.actionID or item.spellID
					local auto = C_Spell and ((C_Spell.IsAutoAttackSpell and C_Spell.IsAutoAttackSpell(id))
						or (C_Spell.IsRangedAutoAttackSpell and C_Spell.IsRangedAutoAttackSpell(id)))
					if type(id) == "number" and ns.Usable(id) and not auto and not seen[id] and Missing(id) then
						seen[id] = true
						table.insert(list, id)
					end
				end
			end
		end
	end
	return list
end

function ns.SpellName(id)
	local name, icon
	if C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(id) end
	if C_Spell and C_Spell.GetSpellTexture then icon = C_Spell.GetSpellTexture(id) end
	if not name and GetSpellInfo then
		local n, _, i = GetSpellInfo(id)
		name, icon = n, icon or i
	end
	return name or ("spell " .. id), icon
end
