local mq = require('mq')
local ImGui = require('ImGui')
local Actors = require('actors')

local mailboxName = "ItemTracker"
local actor
local trackedItems = {}
local itemData = {}
local showUI = true
local saveFileName = mq.configDir .. "/itemtracker.lua"
local mainWindowFlags = bit32.bor(ImGuiWindowFlags.None)
local removedItems = {}
local myName = mq.TLO.Me.CleanName()

-- variables for UI
local tmpTxt = ""
local needSave = false

local function saveTrackedItems()
	mq.pickle(saveFileName, { trackedItems = trackedItems, })
end

local function loadTrackedItems()
	local loadedData = dofile(saveFileName) or {}
	if type(loadedData) == "table" and type(loadedData.trackedItems) == "table" then
		for _, item in ipairs(loadedData.trackedItems) do
			table.insert(trackedItems, item)
		end
	end
end

-- Register Actor
local function RegisterActors()
	actor = Actors.register(mailboxName, function(message)
		if not message() then return end
		local received_message = message()
		local who = received_message.Sender or "Unknown"
		local items = received_message.Items or {}
		local tracking = received_message.Tracking or {}
		local remItem = received_message.Remove or nil
		if remItem ~= nil then
			printf("\ayRemoving\ax Item:\at %s", remItem)
			itemData[remItem] = nil
			for _, itemname in ipairs(trackedItems) do
				if itemname == remItem then
					table.remove(trackedItems, _)
					break
				end
			end
			saveTrackedItems()
			goto end_message
		end
		for _, itemName in ipairs(tracking) do
			if itemData[itemName] == nil then itemData[itemName] = {} end
			if itemData[itemName][who] == nil then itemData[itemName][who] = {} end
			if items[itemName] then
				itemData[itemName][who].inventory = items[itemName].inventory
				itemData[itemName][who].bank = items[itemName].bank
			end
		end
		for itemName, v in pairs(itemData) do
			if not TableContains(tracking, itemName) then
				itemData[itemName] = nil
			end
		end
		trackedItems = tracking
		::end_message::
	end)
end

-- Function to Check Item Counts
local function checkItems()
	local items = {}

	for _, itemName in ipairs(trackedItems) do
		local invCount = mq.TLO.FindItemCount(itemName)() or 0
		local bankCount = mq.TLO.FindItemBankCount(itemName)() or 0
		items[itemName] = { inventory = invCount, bank = bankCount, }
	end

	actor:send({ mailbox = mailboxName, }, { Items = items, Sender = myName, Tracking = trackedItems, })
end

-- GUI Rendering
local needRemove = false

-- New variable to track selected item
local selectedItem = nil
local colGreen = ImVec4(0.409, 1.000, 0.409, 1.000)
local colWhite = ImVec4(1, 1, 1, 1)
local colYellow = ImVec4(1, 1, 0, 1)
local function renderUI()
	if not showUI then return end
	ImGui.SetNextWindowSize(ImVec2(600, 400), ImGuiCond.FirstUseEver)
	local open, show = ImGui.Begin("Item Tracker##1", true, mainWindowFlags)
	if not open then show = false end
	if show then
		-- Add Item UI
		ImGui.Text("Items to Track")
		tmpTxt = ImGui.InputTextWithHint("##ItemInput", "Enter Item Name...", tmpTxt)
		ImGui.SameLine()
		if ImGui.Button("Add") and tmpTxt ~= "" then
			needSave = true
		end
		ImGui.Separator()

		-- Begin Split Pane
		-- local contentWidth, sizeY = ImGui.GetContentRegionAvail()
		local leftWidth = 150
		ImGui.BeginChild("ItemList", ImVec2(leftWidth, 0), bit32.bor(ImGuiChildFlags.ResizeX, ImGuiChildFlags.Border))
		for _, item in ipairs(trackedItems) do
			if ImGui.Selectable(item, selectedItem == item) then
				selectedItem = item
			end
			if ImGui.BeginPopupContextItem() then
				if ImGui.MenuItem("Remove") then
					removedItems[item] = true
					needRemove = true
					if selectedItem == item then selectedItem = nil end
				end
				ImGui.EndPopup()
			end
		end
		ImGui.EndChild()

		-- Right Side: Item Data Table
		ImGui.SameLine()
		ImGui.BeginChild("ItemDataView", ImVec2(0, 0), ImGuiChildFlags.Border)
		if selectedItem and itemData[selectedItem] then
			ImGui.Text("Item: " .. selectedItem)
			if ImGui.BeginTable("ItemTable", 3, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable)) then
				ImGui.TableSetupColumn("Character")
				ImGui.TableSetupColumn("Inventory")
				ImGui.TableSetupColumn("Bank")
				ImGui.TableHeadersRow()
				for char, data in pairs(itemData[selectedItem]) do
					local colInv = (data.inventory or 0) > 0 and colYellow or colWhite
					local colBank = (data.bank or 0) > 0 and colGreen or colWhite
					ImGui.TableNextRow()
					ImGui.TableSetColumnIndex(0)
					ImGui.Text(char)
					ImGui.TableSetColumnIndex(1)
					ImGui.TextColored(colInv, tostring(data.inventory or 0))
					ImGui.TableSetColumnIndex(2)
					ImGui.TextColored(colBank, tostring(data.bank or 0))
				end
				ImGui.EndTable()
			end
		elseif selectedItem then
			ImGui.Text("No data for: " .. selectedItem)
		else
			ImGui.Text("Select an item to view details.")
		end
		ImGui.EndChild()
	end
	ImGui.End()
	if not open then showUI = false end
end


-- Helper function to check if a table contains a value
function TableContains(table, element)
	for _, value in pairs(table) do
		if value == element then
			return true
		end
	end
	return false
end

-- Load tracked items from previous session
local function init()
	loadTrackedItems()
	RegisterActors()
	mq.imgui.init("itemTracker", renderUI)
end


init()
local refreshTimer = os.clock()
-- Main Script Loop
while showUI do
	if needRemove then
		for item, _ in pairs(removedItems) do
			for i, trackedItem in ipairs(trackedItems) do
				if trackedItem == item then
					table.remove(trackedItems, i)
					actor:send({ mailbox = mailboxName, }, { Items = {}, Sender = myName, Tracking = {}, Remove = item, })
					break
				end
			end
		end
		removedItems = {}
		needRemove = false
		saveTrackedItems()
	end
	if needSave then
		if tmpTxt ~= "" then
			if not TableContains(trackedItems, tmpTxt) then
				table.insert(trackedItems, tmpTxt)
			end
			tmpTxt = ""
		end
		checkItems()
		needSave = false
		saveTrackedItems()
	end

	mq.doevents()
	if os.difftime(os.clock(), refreshTimer) > 3 then
		checkItems()
		refreshTimer = os.clock()
	end
	mq.delay(10) -- Refresh every 3 seconds
end
