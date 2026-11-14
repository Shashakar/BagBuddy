-- BagBuddy: profession skills, and the recipes each character knows. The game only lists recipes
-- while a profession window is open, so they're read then, saved, and shared separately from the
-- bags (they change rarely and are the biggest part). What a buddy can make is worked out from
-- the reagents and their bags, so it stays current as their bags change.
local _, ns = ...

---------------------------------------------------------------------------
-- Skills (always readable)
---------------------------------------------------------------------------

-- { { name, rank, max }, ... }
function ns.ReadSkills()
	local skills = {}
	if not (GetProfessions and GetProfessionInfo) then return skills end
	local result = { pcall(GetProfessions) }
	if not result[1] then return skills end
	-- Fixed slots (primary, primary, archaeology, fishing, cooking, first aid); any can be nil
	for i = 2, 7 do
		local index = result[i]
		if index then
			local okInfo, name, _, rank, max = pcall(GetProfessionInfo, index)
			if okInfo and type(name) == "string" and ns.Usable(name) then
				table.insert(skills, { name, tonumber(rank) or 0, tonumber(max) or 0 })
			end
		end
	end
	return skills
end

---------------------------------------------------------------------------
-- Recipes, read while a profession window is open
---------------------------------------------------------------------------

local function Mine()
	ns.db.myRecipes = ns.db.myRecipes or {}
	local me = ns.Me()
	ns.db.myRecipes[me] = ns.db.myRecipes[me] or {}
	return ns.db.myRecipes[me]
end

local function ProfessionName(T, firstRecipe)
	if T.GetBaseProfessionInfo then
		local ok, info = pcall(T.GetBaseProfessionInfo)
		if ok and type(info) == "table" and type(info.professionName) == "string" and info.professionName ~= "" then
			return info.professionName
		end
	end
	if firstRecipe and T.GetTradeSkillLineForRecipe then
		local ok, _, name, _, parentName = pcall(T.GetTradeSkillLineForRecipe, firstRecipe)
		if ok then
			if type(parentName) == "string" and parentName ~= "" then return parentName end
			if type(name) == "string" and name ~= "" then return name end
		end
	end
	return nil
end

-- The reagents every craft of a recipe uses: { { itemID, count }, ... }, and what it makes
local function Schematic(T, recipeID)
	if not T.GetRecipeSchematic then return {}, nil end
	local ok, schematic = pcall(T.GetRecipeSchematic, recipeID, false)
	if not ok or type(schematic) ~= "table" then return {}, nil end
	local reagents = {}
	local basic = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
	for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
		local isBasic
		if basic and slot.reagentType ~= nil then isBasic = slot.reagentType == basic else isBasic = slot.required end
		local reagent = slot.reagents and slot.reagents[1]
		if isBasic and reagent and reagent.itemID and (slot.quantityRequired or 0) > 0 then
			table.insert(reagents, { reagent.itemID, slot.quantityRequired })
		end
	end
	local output = type(schematic.outputItemID) == "number" and schematic.outputItemID or nil
	return reagents, output
end

local function Capture()
	local T = C_TradeSkillUI
	if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) then return end
	-- Only our own professions, not one someone linked in chat or an NPC's
	if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return end
	if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then return end
	if T.IsNPCCrafting and T.IsNPCCrafting() then return end
	local ids = T.GetAllRecipeIDs()
	if type(ids) ~= "table" or #ids == 0 then return end
	local list, first = {}, nil
	for _, id in ipairs(ids) do
		local ok, info = pcall(T.GetRecipeInfo, id)
		if ok and type(info) == "table" and info.learned and not info.isDummyRecipe then
			first = first or id
			local reagents, output = Schematic(T, id)
			table.insert(list, { id = id, name = info.name or ("Recipe " .. id), diff = tonumber(info.relativeDifficulty) or 3,
				out = output, reagents = reagents })
		end
	end
	if #list == 0 then return end
	local name = ProfessionName(T, first)
	if not name then return end
	local mine = Mine()
	local old = mine[name]
	-- Only when something a buddy would see changed (also skill-ups that change colors)
	if old and ns.EncodeRecipes({ [name] = { time = 0, list = old.list } }) == ns.EncodeRecipes({ [name] = { time = 0, list = list } }) then
		return
	end
	mine[name] = { time = GetServerTime(), list = list }
	ns.RecipesChanged()
end

local captureTimer
local function CaptureSoon()
	if captureTimer then captureTimer:Cancel() end
	captureTimer = C_Timer.NewTimer(1, function()
		captureTimer = nil
		local ok, err = pcall(Capture)
		if not ok then ns.Debug("reading recipes: " .. tostring(err)) end
	end)
end
ns.On("TRADE_SKILL_SHOW", CaptureSoon)
ns.On("TRADE_SKILL_LIST_UPDATE", CaptureSoon)

---------------------------------------------------------------------------
-- Text: professions joined by "#": name|time|recipe~recipe
-- recipe: id;difficulty;output item;name;item*count,item*count
---------------------------------------------------------------------------

local function Clean(text)
	return (tostring(text or ""):gsub("[#|~;,%*%^]", ""))
end

function ns.EncodeRecipes(profs)
	local names = {}
	for name in pairs(profs or {}) do table.insert(names, name) end
	table.sort(names)
	local blocks = {}
	for _, name in ipairs(names) do
		local prof = profs[name]
		local recipes = {}
		for _, r in ipairs(prof.list or {}) do
			local reagents = {}
			for _, reagent in ipairs(r.reagents or {}) do table.insert(reagents, reagent[1] .. "*" .. reagent[2]) end
			table.insert(recipes, ("%d;%d;%s;%s;%s"):format(r.id, r.diff or 3, r.out or "", Clean(r.name), table.concat(reagents, ",")))
		end
		table.insert(blocks, ("%s|%d|%s"):format(Clean(name), prof.time or 0, table.concat(recipes, "~")))
	end
	return table.concat(blocks, "#")
end

function ns.DecodeRecipes(text)
	local profs = {}
	for block in (text or ""):gmatch("[^#]+") do
		local name, time, recipes = block:match("^([^|]*)|(%d+)|(.*)$")
		if name then
			local list = {}
			for entry in recipes:gmatch("[^~]+") do
				local id, diff, out, rname, reagents = entry:match("^(%d+);(%d+);(%d*);([^;]*);(.*)$")
				if id then
					local r = { id = tonumber(id), diff = tonumber(diff), out = tonumber(out), name = rname, reagents = {} }
					for item, count in reagents:gmatch("(%d+)%*(%d+)") do
						table.insert(r.reagents, { tonumber(item), tonumber(count) })
					end
					table.insert(list, r)
				end
			end
			profs[name] = { time = tonumber(time), list = list }
		end
	end
	return profs
end

-- My recipes as text, for sending
function ns.MyRecipesText()
	local mine = ns.db and ns.db.myRecipes and ns.db.myRecipes[ns.Me()]
	if not mine or next(mine) == nil then return nil end
	return ns.EncodeRecipes(mine)
end

---------------------------------------------------------------------------
-- What a buddy can make
---------------------------------------------------------------------------

-- How many of each item a snapshot carries, by item ID
function ns.ItemCounts(snap)
	local counts = {}
	for _, entry in ipairs(snap.bags or {}) do
		local id = ns.ItemID(entry[1])
		if id then counts[id] = (counts[id] or 0) + entry[2] end
	end
	return counts
end

-- How many times a recipe can be made from these counts, and what's short: { { itemID, missing } }
function ns.CanMake(recipe, counts)
	if #recipe.reagents == 0 then return 0, {} end
	local times, missing = math.huge, {}
	for _, reagent in ipairs(recipe.reagents) do
		local have = counts[reagent[1]] or 0
		times = math.min(times, math.floor(have / reagent[2]))
		if have < reagent[2] then table.insert(missing, { reagent[1], reagent[2] - have }) end
	end
	return times, missing
end

-- Blizzard's difficulty colors: orange, yellow, green, gray
local DIFF_COLORS = { [0] = "|cffff8040", [1] = "|cffffff00", [2] = "|cff40c040", [3] = "|cff808080" }
function ns.RecipeColor(diff)
	return DIFF_COLORS[diff or 3] or "|cffffffff"
end
