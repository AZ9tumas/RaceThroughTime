local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

local WorldUIController = Knit.CreateController({
	Name = "WorldUIController",
})

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local worldMenu: Frame
local worldClose: TextButton
local worldScrollFrame: ScrollingFrame
local worldButtonTemplate: TextButton

local _connections = {}

local function ClearWorlds()
	for _, v in pairs(worldScrollFrame:GetChildren()) do
		if v:IsA("TextButton") then
			v:Destroy()
		end
	end
end

function WorldUIController:UpdateWorlds()
	local UIController = Knit.GetController("UIController")
	local NotificationController = Knit.GetController("NotificationController")
	local data = UIController:GetData()
	local worlds = data.Progression.UnlockedWorlds
	local currworld = data.Progression.CurrentWorld
	ClearWorlds()
	for _, world in pairs(worlds) do
		local temp = worldButtonTemplate:Clone()
		temp.Parent = worldScrollFrame
		temp.Name = world
		temp.TextLabel.Text = world
		temp.Visible = true
		temp.UIStroke.Enabled = world == currworld
		temp.MouseButton1Click:Connect(function()
			local worldService = Knit.GetService("WorldService")
			worldService:RequestTeleportToWorld(world):andThen(function(success, errorMsg, updatedData)
				if success then
					UIController:SetData(updatedData)
					if NotificationController then
						NotificationController:ShowNotification(
							errorMsg,
							NotificationController.Category.Success,
							5
						)
					end
				end
			end)
		end)
	end
end

function WorldUIController:UpdateMenuVisibility()
	local UIController = Knit.GetController("UIController")
	local UIFramesController = Knit.GetController("UIFramesController")
	local shouldShow = UIController:IsPlayerNearWorldPad()
	
	if shouldShow and not UIFramesController:IsFrameOpen("World") then
		UIFramesController:OpenFrame("World")
		self:UpdateWorlds()
	elseif not shouldShow and UIFramesController:IsFrameOpen("World") then
		UIFramesController:CloseFrame("World")
	end
end

function WorldUIController:CloseWorldMenu()
	local UIFramesController = Knit.GetController("UIFramesController")
	UIFramesController:CloseFrame("World")
end

function WorldUIController:KnitInit()
	local simulatorPopups = PlayerGui:WaitForChild("SimulatorPopups")
	worldMenu = simulatorPopups:WaitForChild("WorldMenu")
	worldClose = worldMenu:WaitForChild("Close")
	worldScrollFrame = worldMenu:WaitForChild("ScrollingFrame")
	worldButtonTemplate = worldScrollFrame:WaitForChild("UIListLayout"):WaitForChild("Template")
end

function WorldUIController:KnitStart()
	_connections["WorldClose"] = worldClose.MouseButton1Click:Connect(function()
		self:CloseWorldMenu()
	end)
end

return WorldUIController
