local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

-- ui
local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local mainUi: ScreenGui = PlayerGui:WaitForChild("RaceThroughTime_UI")
local centerHUD: Frame = mainUi:WaitForChild("CenterHUD")
local runButton: TextButton = centerHUD:WaitForChild("RunButton")

local liveMainUI: ScreenGui = PlayerGui:WaitForChild("UI_LiveDistance")
local distanceCounter: TextLabel = liveMainUI:WaitForChild("DistanceCounter")

local Knit = require(ReplicatedStorage.Packages.Knit)

-- Reference to InitUI module for debounce reset
local InitUI = nil

-- Camera settings
local DEFAULT_FOV = 70
local TRACK_FOV = 90
local FOV_TWEEN_TIME = 0.5
local TRACK_END_LOADING_DELAY = 0.8 -- Seconds to show loading screen after track ends

-- Lighting effect settings
local LIGHTING_TWEEN_TIME = 0.5

local TrackController = Knit.CreateController({
	Name = "TrackController",
})

-- Private state
local IsOnTrack = false
local TrackData = nil
local OriginalWalkSpeed = 16
local OriginalJumpPower = 50
local DistanceUpdateConnection = nil
local DistanceValueInstance = nil
local TrackLightingEffects = {} -- Store created lighting effects for cleanup

-- Helper function for logging
local function Log(message: string)
	print(string.format("[TrackController]: %s", message))
end

-- Apply lighting effects when player starts running on track
local function ApplyTrackLightingEffects()
	-- Create BlurEffect for speed sensation
	local blur = Instance.new("BlurEffect")
	blur.Name = "TrackBlur"
	blur.Size = 0
	blur.Parent = Lighting
	TrackLightingEffects.blur = blur
	
	-- Tween blur in
	local blurTween = TweenService:Create(blur, TweenInfo.new(LIGHTING_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = 6
	})
	blurTween:Play()
	
	-- Create ColorCorrectionEffect for vivid colors during track run
	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "TrackColorCorrection"
	colorCorrection.Saturation = 0
	colorCorrection.Contrast = 0
	colorCorrection.Brightness = 0
	colorCorrection.Parent = Lighting
	TrackLightingEffects.colorCorrection = colorCorrection
	
	-- Tween color correction in
	local colorTween = TweenService:Create(colorCorrection, TweenInfo.new(LIGHTING_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Saturation = 0.15,
		Contrast = 0.1,
		Brightness = 0.03
	})
	colorTween:Play()
	
	-- Create Bloom effect for glowing track
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "TrackBloom"
	bloom.Intensity = 0
	bloom.Size = 24
	bloom.Threshold = 1
	bloom.Parent = Lighting
	TrackLightingEffects.bloom = bloom
	
	-- Tween bloom in
	local bloomTween = TweenService:Create(bloom, TweenInfo.new(LIGHTING_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Intensity = 0.8,
		Threshold = 0.9
	})
	bloomTween:Play()
	
	Log("Applied track lighting effects")
end

-- Remove lighting effects when player stops running on track
local function RemoveTrackLightingEffects()
	-- Tween out and destroy blur
	if TrackLightingEffects.blur then
		local blur = TrackLightingEffects.blur
		local blurTween = TweenService:Create(blur, TweenInfo.new(LIGHTING_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = 0
		})
		blurTween:Play()
		blurTween.Completed:Connect(function()
			blur:Destroy()
		end)
	end
	
	-- Tween out and destroy color correction
	if TrackLightingEffects.colorCorrection then
		local colorCorrection = TrackLightingEffects.colorCorrection
		local colorTween = TweenService:Create(colorCorrection, TweenInfo.new(LIGHTING_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Saturation = 0,
			Contrast = 0,
			Brightness = 0
		})
		colorTween:Play()
		colorTween.Completed:Connect(function()
			colorCorrection:Destroy()
		end)
	end
	
	-- Tween out and destroy bloom
	if TrackLightingEffects.bloom then
		local bloom = TrackLightingEffects.bloom
		local bloomTween = TweenService:Create(bloom, TweenInfo.new(LIGHTING_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Intensity = 0
		})
		bloomTween:Play()
		bloomTween.Completed:Connect(function()
			bloom:Destroy()
		end)
	end
	
	TrackLightingEffects = {}
	Log("Removed track lighting effects")
end

-- Tween camera FOV
local function TweenCameraFOV(targetFOV: number, duration: number)
	local camera = workspace.CurrentCamera
	if not camera then return end
	
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(camera, tweenInfo, { FieldOfView = targetFOV })
	tween:Play()
end

-- Update distance counter display
local function UpdateDistanceDisplay(distance: number, totalDistance: number)
	if distanceCounter then
		local percentage = math.clamp((distance / totalDistance) * 100, 0, 100)
		distanceCounter.Text = string.format("%.0f / %.0f (%.1f%%)", distance, totalDistance, percentage)
	end
end

-- Setup distance feedback loop from server NumberValue
local function SetupDistanceFeedback(player: Player)
	-- Find the distance value in player's character
	local character = player.Character
	if not character then return end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	
	-- Wait for the distance value created by server
	DistanceValueInstance = rootPart:WaitForChild("TrackDistanceTraveled", 5)
	if not DistanceValueInstance then
		Log("Could not find TrackDistanceTraveled value")
		return
	end
	
	-- Connect to value changes
	DistanceUpdateConnection = DistanceValueInstance.Changed:Connect(function(newValue)
		if TrackData and TrackData.totalDistance then
			UpdateDistanceDisplay(newValue, TrackData.totalDistance)
		end
	end)
	
	Log("Distance feedback loop setup complete")
end

-- Cleanup distance feedback
local function CleanupDistanceFeedback()
	if DistanceUpdateConnection then
		DistanceUpdateConnection:Disconnect()
		DistanceUpdateConnection = nil
	end
	DistanceValueInstance = nil
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
local function OnTrackStarted(trackData: { gateName: string, totalDistance: number, speed: number, startAngle: number })
	IsOnTrack = true
	TrackData = trackData
	distanceCounter.Visible = true
	
	Log(string.format("Track started at %s, total distance: %.2f, speed: %.2f", trackData.gateName, trackData.totalDistance, trackData.speed or 0))
	
	-- Fade out the loading screen now that server has acknowledged the request
	local LoadingScreenController = Knit.GetController("LoadingScreenController")
	if LoadingScreenController then
		LoadingScreenController:HideLoadingScreen()
	end
	
	-- Increase camera FOV for speed effect
	TweenCameraFOV(TRACK_FOV, FOV_TWEEN_TIME)
	
	-- Apply lighting effects (blur, color correction, bloom)
	ApplyTrackLightingEffects()
	
	-- Setup distance feedback from server
	SetupDistanceFeedback(Players.LocalPlayer)
	
	-- Initialize distance display
	UpdateDistanceDisplay(0, trackData.totalDistance)
	
	-- Disable player controls
	DisablePlayerControls()
	
	-- Show notification
	local NotificationController = Knit.GetController("NotificationController")
	if NotificationController then
		NotificationController:ShowNotification(
			"Track Run Started! Distance: " .. trackData.totalDistance,
			NotificationController.Category.Alert,
			3
		)
	end
end

-- Handle track ended signal from server
local function OnTrackEnded(trackData: { distanceTraveled: number, cashEarned: number })
	if not IsOnTrack then return end
	
	Log(string.format("Track ended, distance traveled: %.2f, cash earned: %.0f", trackData.distanceTraveled or 0, trackData.cashEarned or 0))
	
	IsOnTrack = false
	TrackData = nil
	
	-- Cleanup distance feedback
	CleanupDistanceFeedback()
	
	-- Reset camera FOV to default
	TweenCameraFOV(DEFAULT_FOV, FOV_TWEEN_TIME)
	
	-- Remove lighting effects (blur, color correction, bloom)
	RemoveTrackLightingEffects()
	
	-- Re-enable player controls
	EnablePlayerControls()
	
	-- Show WhiteFrame loading screen briefly then fade out
	local LoadingScreenController = Knit.GetController("LoadingScreenController")
	if LoadingScreenController then
		LoadingScreenController:ShowLoadingScreen()
		-- Wait a bit then fade out
		task.delay(TRACK_END_LOADING_DELAY, function()
			LoadingScreenController:HideLoadingScreen()
			distanceCounter.Visible = false
		end)
	else
		distanceCounter.Visible = false
	end
	
	-- Reset InitUI debounce so player can request a new run
	if InitUI and InitUI.ResetTrackDebounce then
		InitUI.ResetTrackDebounce()
	end
	
	-- Show notification with cash earned
	local NotificationController = Knit.GetController("NotificationController")
	if NotificationController then
		local cashMessage = trackData.cashEarned and trackData.cashEarned > 0 
			and string.format("Track Run Complete! +$%.0f", trackData.cashEarned)
			or "Track Run Complete!"
		NotificationController:ShowNotification(cashMessage, NotificationController.Category.Success, 3)
	end
	
	-- Note: Run button visibility is now controlled by InitUI based on gate proximity
end

-- Handle lap completed signal from server
local function OnLapCompleted(lapData: { lapNumber: number })
	if not IsOnTrack then return end
	
	Log(string.format("Lap %d completed!", lapData.lapNumber or 1))
	
	local NotificationController = Knit.GetController("NotificationController")
	if NotificationController then
		NotificationController:ShowNotification(
			string.format("Lap %d Complete!", lapData.lapNumber or 1),
			NotificationController.Category.Success,
			2
		)
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
	
	-- Cleanup distance feedback
	CleanupDistanceFeedback()
	
	-- Reset camera FOV
	TweenCameraFOV(DEFAULT_FOV, FOV_TWEEN_TIME)
	
	-- Remove lighting effects
	RemoveTrackLightingEffects()
	
	-- Re-enable player controls
	EnablePlayerControls()
	
	Log("Track stopped")
end

-- Knit lifecycle
function TrackController:KnitInit()
	-- Controller initialization
end

function TrackController:KnitStart()
	-- Get InitUI reference for debounce reset
	local StarterPlayerScripts = Knit.Player:WaitForChild("PlayerScripts")
	local initUIModule = StarterPlayerScripts:FindFirstChild("InitUI")
	if initUIModule then
		InitUI = require(initUIModule)
	end
	
	-- Listen for server signals
	local TrackService = Knit.GetService("TrackService")
	
	TrackService.TrackStarted:Connect(OnTrackStarted)
	TrackService.TrackEnded:Connect(OnTrackEnded)
	TrackService.LapCompleted:Connect(OnLapCompleted)
	
	Log("TrackController started")
end

return TrackController
