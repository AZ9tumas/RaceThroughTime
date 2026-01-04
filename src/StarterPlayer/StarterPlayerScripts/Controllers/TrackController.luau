--[[
	TrackController
	Handles track running on the client side.
	Receives acknowledgment from server and disables player controls while on track.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local TrackController = Knit.CreateController({
	Name = "TrackController",
})

-- Private state
local IsOnTrack = false
local TrackData = nil
local OriginalWalkSpeed = 16
local OriginalJumpPower = 50

-- Helper function for logging
local function Log(message: string)
	print(string.format("[TrackController]: %s", message))
end

-- Disable player movement controls
local function DisablePlayerControls()
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Store original values
		OriginalWalkSpeed = humanoid.WalkSpeed
		OriginalJumpPower = humanoid.JumpPower
		
		-- Disable movement
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end
	
	-- Unbind existing action first to prevent conflicts
	pcall(function()
		ContextActionService:UnbindAction("TrackController_DisableMovement")
	end)
	
	-- Sink all movement inputs
	local success, err = pcall(function()
		ContextActionService:BindAction("TrackController_DisableMovement", function()
			return Enum.ContextActionResult.Sink
		end, false, 
			Enum.PlayerActions.CharacterForward,
			Enum.PlayerActions.CharacterBackward,
			Enum.PlayerActions.CharacterLeft,
			Enum.PlayerActions.CharacterRight,
			Enum.PlayerActions.CharacterJump
		)
	end)
	
	if not success then
		warn(string.format("[TrackController]: Failed to bind movement disable action - %s", tostring(err)))
	end
	
	Log("Player controls disabled")
end

-- Enable player movement controls
local function EnablePlayerControls()
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Restore original values
		humanoid.WalkSpeed = OriginalWalkSpeed
		humanoid.JumpPower = OriginalJumpPower
	end
	
	-- Unbind movement sink
	ContextActionService:UnbindAction("TrackController_DisableMovement")
	
	Log("Player controls enabled")
end

-- Handle track started signal from server
local function OnTrackStarted(trackData: { gateName: string, totalDistance: number, speed: number })
	IsOnTrack = true
	TrackData = trackData
	
	Log(string.format("Track started at %s, total distance: %.2f, speed: %.2f", trackData.gateName, trackData.totalDistance, trackData.speed or 0))
	
	-- Fade out the loading screen now that server has acknowledged the request
	local LoadingScreenController = Knit.GetController("LoadingScreenController")
	if LoadingScreenController then
		LoadingScreenController:HideLoadingScreen()
	end
	
	-- Disable player controls
	DisablePlayerControls()
	
	-- Show notification
	local NotificationController = Knit.GetController("NotificationController")
	if NotificationController then
		NotificationController:ShowNotification("🏁 Track Run Started!", 3, nil, {
			icon = "🏁"
		})
	end
end

-- Handle track ended signal from server
local function OnTrackEnded(trackData: { distanceTraveled: number })
	if not IsOnTrack then return end
	
	Log(string.format("Track ended, distance traveled: %.2f", trackData.distanceTraveled or 0))
	
	IsOnTrack = false
	TrackData = nil
	
	-- Re-enable player controls
	EnablePlayerControls()
	
	-- Show notification
	local NotificationController = Knit.GetController("NotificationController")
	if NotificationController then
		NotificationController:ShowNotification("🏁 Track Run Complete!", 3, nil, {
			icon = "✅"
		})
	end
end

-- Check if player is currently on track
function TrackController:IsOnTrack(): boolean
	return IsOnTrack
end

-- Get current track data
function TrackController:GetTrackData()
	return TrackData
end

-- Stop track running (for future use)
function TrackController:StopTrack()
	if not IsOnTrack then return end
	
	IsOnTrack = false
	TrackData = nil
	
	-- Re-enable player controls
	EnablePlayerControls()
	
	Log("Track stopped")
end

-- Knit lifecycle
function TrackController:KnitInit()
	-- Controller initialization
end

function TrackController:KnitStart()
	-- Listen for server signals
	local TrackService = Knit.GetService("TrackService")
	
	TrackService.TrackStarted:Connect(OnTrackStarted)
	TrackService.TrackEnded:Connect(OnTrackEnded)
	
	Log("TrackController started")
end

return TrackController
