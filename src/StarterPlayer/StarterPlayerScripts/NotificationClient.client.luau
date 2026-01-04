--// SERVICES \\--
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--// VARIABLES \\--
-- UI;
local Sample = script:WaitForChild("Sample")

-- Essentials;
local Player = Players.LocalPlayer
local ClientEssentials = ReplicatedStorage:WaitForChild("ClientEssentials")
local Binds = ClientEssentials:WaitForChild("Binds")
local CustomNotification = Binds:WaitForChild("CustomNotification")

local Modules = ClientEssentials:WaitForChild("Modules")
local UITweening = require(Modules:WaitForChild("UITweening"))
local UISounds = require(Modules:WaitForChild("UISounds"))

-- Settings;
local fadeGoal = {["GroupTransparency"] = 1}
local fadeTime = 0.5

--// FUNCTIONS \\--
local function createNotification(params) -- params[1] = text, params[2] = duration, params[3] = sound, params[4] = properties
 	local removeTime
	if params[2] == nil then removeTime = 4 else removeTime = params[2] end
	local notification = Sample:Clone()
	local TextLabel = notification.TextLabel
	TextLabel.Text = UITweening:RichStroke( params[1] )
	--notification.Actual.Text = params[1]

	Debris:AddItem(notification,removeTime)
	notification.Parent = script.Parent
	UITweening:OpenOutwards(notification, 0.03)
	if params[3] == nil then
		UISounds:Play("NotificationSound")
	else
		UISounds:Play(params[3], params[4])
	end
	coroutine.wrap(function()
		wait(removeTime-fadeTime) -- wait until it's time to fade out the gui
		TweenService:Create(notification,TweenInfo.new(fadeTime),fadeGoal):Play()
		--TweenService:Create(notification.UIStroke,TweenInfo.new(fadeTime),fadeGoal):Play()
	end)()
end

CustomNotification.Event:Connect(createNotification)