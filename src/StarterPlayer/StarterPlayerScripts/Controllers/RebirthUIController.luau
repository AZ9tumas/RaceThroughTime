local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

local modules = ReplicatedStorage:WaitForChild("Modules")
local statsM = require(modules:WaitForChild("Stats"))
local rebirthStatsM = require(modules:WaitForChild("RebirthStats"))

local RebirthUIController = Knit.CreateController({
	Name = "RebirthUIController",
})

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local rebirthModalButton: TextButton
local rebirthMenu: Frame
local rebirthCloseButton: TextLabel
local progressBar: Frame
local progressText: TextLabel
local rebirthButton: TextButton
local rebirthMainLabel: TextLabel

local cashVal

local _connections = {}

local function TruncateNumber(n: number): string
	local UIController = Knit.GetController("UIController")
	if UIController then
		return UIController:TruncateNumber(n)
	end
	return tostring(n)
end

function RebirthUIController:HandleRebirthFrame()
	local UIController = Knit.GetController("UIController")
	local data = UIController:GetData()
	local cash = TruncateNumber(cashVal.Value)
	local currentRebirthLevel = data.Stats.Rebirths
	local nextLevel = rebirthStatsM.GetNextRebirth(currentRebirthLevel)
	local frames = {
		access = rebirthMenu.Frame.Access,
		bonus = rebirthMenu.Frame.Bonus,
		multiplier = rebirthMenu.Frame.Multiplier,
		status = rebirthMenu.Frame.Status,
	}
	local vals = {
		access = nextLevel.Bonus.WorldAccess or " --- ",
		bonus = "+" .. nextLevel.Bonus.Gems .. " Gems",
		multiplier = "+" .. ((nextLevel.Multiplier or 0) * 100) .. "% Multiplier",
		status = nextLevel.KeepPets and "Keep Pets" or "Lose Pets",
	}
	if nextLevel then
		local progress, remainingCash = rebirthStatsM.GetRebirthProgress(currentRebirthLevel, cashVal.Value)
		progressBar.Size = UDim2.new(progress, 0, 1, 0)
		progressText.Text = cash .. "/" .. TruncateNumber(nextLevel.CashRequired) .. " Cash"
		rebirthMainLabel.Text = "Rebirth to Level " .. tostring(nextLevel.Level)
		for key, v in pairs(frames) do
			v.Label.Text = vals[key]
		end
	else
		progressBar.Size = UDim2.new(1, 0, 1, 0)
		progressText.Text = "MAX LEVEL REACHED"
		rebirthMainLabel.Text = "MAX LEVEL REACHED"
		for _, v in pairs(frames) do
			v.Label.Text = " --- "
		end
	end
end

function RebirthUIController:ToggleRebirthMenu()
	local UIController = Knit.GetController("UIController")
	UIController:CloseAllFrames(rebirthMenu)
	local buttonPressed = not UIController:GetButtonPressed()
	UIController:SetButtonPressed(buttonPressed)
	rebirthMenu.Visible = buttonPressed
	if rebirthMenu.Visible then
		self:HandleRebirthFrame()
	end
end

function RebirthUIController:CloseRebirthMenu()
	rebirthMenu.Visible = false
end

function RebirthUIController:UpdateMenuVisibility()
	local UIController = Knit.GetController("UIController")
	rebirthMenu.Visible = UIController:GetButtonPressed() or UIController:IsPlayerNearRebirthArea()
end

function RebirthUIController:KnitInit()
	local mainUi: ScreenGui = PlayerGui:WaitForChild("RaceThroughTime_UI")
	local leftPanel: Frame = mainUi:WaitForChild("LeftPanel")
	local simulatorPopups = PlayerGui:WaitForChild("SimulatorPopups")
	rebirthModalButton = leftPanel:WaitForChild("RebirthButton")
	rebirthMenu = simulatorPopups:WaitForChild("RebirthMenu")
	rebirthCloseButton = rebirthMenu:WaitForChild("Close")
	progressBar = rebirthMenu:WaitForChild("Progress"):WaitForChild("Fill")
	progressText = rebirthMenu:WaitForChild("Progress"):WaitForChild("TextLabel")
	rebirthButton = rebirthMenu:WaitForChild("Rebirth")
	rebirthMainLabel = rebirthMenu:WaitForChild("TextLabel")
	local leaderstats = player:WaitForChild("leaderstats")
	cashVal = leaderstats:WaitForChild("Cash")
end

function RebirthUIController:KnitStart()
	local RebirthService = Knit.GetService("RebirthService")
	local UIController = Knit.GetController("UIController")
	local InventoryUIController = Knit.GetController("InventoryUIController")

	_connections["RebirthButton"] = rebirthButton.MouseButton1Click:Connect(function()
		rebirthMenu.Visible = false
		RebirthService:RequestRebirth():andThen(function(success, errorMsg, resultData)
			if success and resultData then
				local data = UIController:GetData()
				data.Stats.Rebirths = resultData.NewRebirthLevel
				if resultData.FuelReset then
					data.Stats.Fuel = statsM.StartingFuel
				end
				if resultData.KeepPets == false then
					data.Inventory.PetInventory = {}
					data.Inventory.EquippedPets = {}
				end
				if resultData.PetReward then
					table.insert(data.Inventory.PetInventory, resultData.PetReward)
				end
				if InventoryUIController:IsVisible() then
					InventoryUIController:UpdatePetsInventory()
				end
			end
		end)
	end)

	_connections["RebirthModalButton"] = rebirthModalButton.MouseButton1Click:Connect(function()
		self:ToggleRebirthMenu()
	end)

	_connections["RebirthClose"] = rebirthCloseButton.MouseButton1Click:Connect(function()
		self:CloseRebirthMenu()
	end)
end

return RebirthUIController
