local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

local RunButtonUIController = Knit.CreateController({
	Name = "RunButtonUIController",
})

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local runButton: TextButton

local _connections = {}

function RunButtonUIController:UpdateVisibility()
	local UIController = Knit.GetController("UIController")
	local TrackController = Knit.GetController("TrackController")
	if TrackController and TrackController:IsOnTrack() then
		runButton.Visible = false
		return
	end
	if UIController:IsRequestingTrack() then
		runButton.Visible = false
		return
	end
	runButton.Visible = UIController:IsPlayerNearGate()
end

function RunButtonUIController:KnitInit()
	local mainUi: ScreenGui = PlayerGui:WaitForChild("RaceThroughTime_UI")
	local centerHUD: Frame = mainUi:WaitForChild("CenterHUD")
	runButton = centerHUD:WaitForChild("RunButton")
end

function RunButtonUIController:KnitStart()
	local TrackService = Knit.GetService("TrackService")
	local UIController = Knit.GetController("UIController")
	local TrackController = Knit.GetController("TrackController")
	local LoadingScreenController = Knit.GetController("LoadingScreenController")
	local NotificationController = Knit.GetController("NotificationController")

	_connections["RunButton"] = runButton.MouseButton1Click:Connect(function()
		if UIController:IsRequestingTrack() then return end
		if TrackController and TrackController:IsOnTrack() then return end
		UIController:SetRequestingTrack(true)
		if LoadingScreenController then
			LoadingScreenController:ShowLoadingScreen()
		end
		TrackService:RequestTrackStart():andThen(function(success: boolean, gateName: string?)
			if success then
				runButton.Visible = false
			else
				if NotificationController then
					NotificationController:ShowNotification(
						(gateName or "Unknown error"),
						NotificationController.Category.Error,
						5
					)
				end
				if LoadingScreenController then
					LoadingScreenController:HideLoadingScreen()
				end
				UIController:SetRequestingTrack(false)
			end
		end)
	end)
end

return RunButtonUIController
