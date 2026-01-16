local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

-- ui
local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local mainUi: ScreenGui = PlayerGui:WaitForChild("RaceThroughTime_UI")
local centerHUD: Frame = mainUi:WaitForChild("CenterHUD")
local runButton: TextButton = centerHUD:WaitForChild("RunButton")

local liveMainUI: ScreenGui = PlayerGui:WaitForChild("UI_LiveDistance")
local distanceCounter: TextLabel = liveMainUI:WaitForChild("DistanceCounter")

-- Results popup UI
local resultsPopupUI: ScreenGui = PlayerGui:WaitForChild("UI_ResultsPopup")
local resultsFrame: Frame = resultsPopupUI:WaitForChild("Frame"):WaitForChild("Frame")
local distanceFrame: Frame = resultsFrame:WaitForChild("Distance")
local distanceValueLabel: TextLabel = distanceFrame:WaitForChild("DistanceValue")
local progressFrame: Frame = resultsFrame:WaitForChild("Progress")
local greenFillFrame: Frame = progressFrame:WaitForChild("Frame"):WaitForChild("GreenFill")
local closeButton: TextButton = resultsFrame:WaitForChild("TextButton")

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
local CurrentWorldName = "Main"
local OriginalWalkSpeed = 16
local OriginalJumpPower = 50
local DistanceUpdateConnection = nil
local DistanceValueInstance = nil
local TrackLightingEffects = {} -- Store created lighting effects for cleanup
local TrackOriginalProperties = {} -- Store original track properties for restoration
local TrackFireEffects = {} -- Store fire/smoke effects

-- Helper function for logging
local function Log(message: string)
	--print(string.format("[TrackController]: %s", message))
end

-- Get the world folder from workspace
local function GetWorldFolder(worldName: string): Folder?
	local worldFolder = Workspace:FindFirstChild(worldName)
	if worldFolder then
		return worldFolder
	end
	return Workspace:FindFirstChild("Main")
end

-- Get VisualTrack from the current world
local function GetVisualTrackForWorld(worldName: string): BasePart?
	local worldFolder = GetWorldFolder(worldName)
	if worldFolder then
		local trackSystem = worldFolder:FindFirstChild("Track_System")
		if trackSystem then
			return trackSystem:FindFirstChild("Visual_Track")
		end
	end
	return nil
end

-- Apply neon effect to track when player starts running
local function ApplyNeonEffectToTrack(worldName: string)
	local visualTrack = GetVisualTrackForWorld(worldName)
	if not visualTrack then return end
	
	-- Store original properties if not already stored
	if not TrackOriginalProperties[worldName] then
		TrackOriginalProperties[worldName] = {
			Material = visualTrack.Material,
			Transparency = visualTrack.Transparency,
		}
	end
	
	-- Apply neon effect
	visualTrack.Material = Enum.Material.Neon
	visualTrack.Transparency = 0
	
	-- Add PointLight for glow effect if it doesn't exist
	local pointLight = visualTrack:FindFirstChild("TrackGlow")
	if not pointLight then
		pointLight = Instance.new("PointLight")
		pointLight.Name = "TrackGlow"
		pointLight.Color = visualTrack.Color
		pointLight.Brightness = 2
		pointLight.Range = 30
		pointLight.Parent = visualTrack
	end
	pointLight.Enabled = true
	
	Log(string.format("Applied neon effect to track in world %s", worldName))
end

-- Remove neon effect from track when player stops running
local function RemoveNeonEffectFromTrack(worldName: string)
	local visualTrack = GetVisualTrackForWorld(worldName)
	if not visualTrack then return end
	
	-- Restore original properties
	local originalProps = TrackOriginalProperties[worldName]
	if originalProps then
		visualTrack.Material = originalProps.Material
		visualTrack.Transparency = originalProps.Transparency
	end
	
	-- Disable PointLight
	local pointLight = visualTrack:FindFirstChild("TrackGlow")
	if pointLight then
		pointLight.Enabled = false
	end
	
	Log(string.format("Removed neon effect from track in world %s", worldName))
end

-- Apply or update fire and smoke effects on track based on progress percentage
local function UpdateFireEffectOnTrack(worldName: string, progressPercent: number)
	local visualTrack = GetVisualTrackForWorld(worldName)
	if not visualTrack then return end
	
	-- Fire only activates at 50% or above progress
	if progressPercent < 0.5 then
		-- Remove fire if exists and progress dropped below 50%
		local effects = TrackFireEffects[worldName]
		if effects then
			if effects.Fire then effects.Fire:Destroy() end
			if effects.Smoke then effects.Smoke:Destroy() end
			TrackFireEffects[worldName] = nil
		end
		return
	end
	
	-- Calculate intensity based on progress (50% to 100% maps to 0 to 1)
	local intensityFactor = math.clamp((progressPercent - 0.5) / 0.5, 0, 1)
	
	-- Check if fire already exists
	local effects = TrackFireEffects[worldName]
	if not effects then
		-- Create Fire effect
		local fire = Instance.new("Fire")
		fire.Name = "TrackFire"
		fire.Heat = 5 + (intensityFactor * 10)
		fire.Size = 5 + (intensityFactor * 10)
		fire.Parent = visualTrack
		
		-- Create Smoke effect
		local smoke = Instance.new("Smoke")
		smoke.Name = "TrackSmoke"
		smoke.Size = 2 + (intensityFactor * 5)
		smoke.Opacity = 0.3 + (intensityFactor * 0.4)
		smoke.RiseVelocity = 5 + (intensityFactor * 10)
		smoke.Parent = visualTrack
		
		TrackFireEffects[worldName] = {
			Fire = fire,
			Smoke = smoke,
		}
		effects = TrackFireEffects[worldName]
		
		Log(string.format("Created fire effect on track in world %s at %.0f%% progress", worldName, progressPercent * 100))
	end
	
	-- Update fire properties based on progress
	if effects.Fire then
		effects.Fire.Heat = 5 + (intensityFactor * 10)
		effects.Fire.Size = 5 + (intensityFactor * 10)
		
		-- Color changes to purple at >90% progress
		if progressPercent >= 0.9 then
			effects.Fire.Color = Color3.fromRGB(128, 0, 255) -- Purple
			effects.Fire.SecondaryColor = Color3.fromRGB(75, 0, 130) -- Indigo
		else
			effects.Fire.Color = Color3.fromRGB(255, 165, 0) -- Orange
			effects.Fire.SecondaryColor = Color3.fromRGB(255, 69, 0) -- Orange-Red
		end
	end
	
	-- Update smoke properties
	if effects.Smoke then
		effects.Smoke.Size = 2 + (intensityFactor * 5)
		effects.Smoke.Opacity = 0.3 + (intensityFactor * 0.4)
		effects.Smoke.RiseVelocity = 5 + (intensityFactor * 10)
		
		-- Smoke color matches fire
		if progressPercent >= 0.9 then
			effects.Smoke.Color = Color3.fromRGB(75, 0, 130) -- Dark purple
		else
			effects.Smoke.Color = Color3.fromRGB(50, 50, 50) -- Dark gray
		end
	end
end

-- Remove fire and smoke effects from track
local function RemoveFireEffectFromTrack(worldName: string)
	local effects = TrackFireEffects[worldName]
	if effects then
		if effects.Fire then effects.Fire:Destroy() end
		if effects.Smoke then effects.Smoke:Destroy() end
		TrackFireEffects[worldName] = nil
		Log(string.format("Removed fire effect from track in world %s", worldName))
	end
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
local function OnTrackStarted(trackData: { gateName: string, totalDistance: number, speed: number, startAngle: number, worldName: string? })
	IsOnTrack = true
	TrackData = trackData
	CurrentWorldName = trackData.worldName or "Main"
	distanceCounter.Visible = true
	
	Log(string.format("Track started at %s, total distance: %.2f, speed: %.2f", trackData.gateName, trackData.totalDistance, trackData.speed or 0))
	
	-- Fade out the loading screen now that server has acknowledged the request
	local LoadingScreenController = Knit.GetController("LoadingScreenController")
	if LoadingScreenController then
		LoadingScreenController:HideLoadingScreen()
	end
	
	-- Increase camera FOV for speed effect
	TweenCameraFOV(TRACK_FOV, FOV_TWEEN_TIME)
	
	-- Apply neon effect to track
	ApplyNeonEffectToTrack(CurrentWorldName)
	
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
			"Track Run Started! Distance: " .. math.floor(trackData.totalDistance),
			NotificationController.Category.Alert,
			3
		)
	end
end

-- Handle track ended signal from server
local function OnTrackEnded(trackData: { distanceTraveled: number, cashEarned: number, percentageToNextWorld: number?, unlockRequirement: number? })
	if not IsOnTrack then return end
	
	Log(string.format("Track ended, distance traveled: %.2f, cash earned: %.0f", trackData.distanceTraveled or 0, trackData.cashEarned or 0))
	
	IsOnTrack = false
	TrackData = nil
	
	-- Cleanup distance feedback
	CleanupDistanceFeedback()
	
	-- Reset camera FOV to default
	TweenCameraFOV(DEFAULT_FOV, FOV_TWEEN_TIME)
	
	-- Remove neon effect from track
	RemoveNeonEffectFromTrack(CurrentWorldName)
	
	-- Remove fire effect from track
	RemoveFireEffectFromTrack(CurrentWorldName)
	
	-- Remove lighting effects (blur, color correction, bloom)
	RemoveTrackLightingEffects()
	
	-- Re-enable player controls
	EnablePlayerControls()
	
	-- Update results popup UI
	local distanceTraveled = trackData.distanceTraveled
	local percentageToNextWorld = trackData.percentageToNextWorld
	
	-- Set distance value text
	if distanceValueLabel then
		distanceValueLabel.Text = string.format("%.0f", distanceTraveled)
	end
	
	-- Set green fill width based on percentage (scale X from 0 to 1)
	if greenFillFrame then
		local fillPercentage = math.clamp(percentageToNextWorld / 100, 0, 1)
		print("Fill percentage: ", fillPercentage)
		greenFillFrame.Size = UDim2.new(fillPercentage, 0, greenFillFrame.Size.Y.Scale, greenFillFrame.Size.Y.Offset)
	end
	
	-- Show the results popup
	if resultsPopupUI then
		resultsPopupUI.Enabled = true
		resultsFrame.Parent.Visible = true
	end
	
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
	
	-- Remove neon effect from track
	RemoveNeonEffectFromTrack(CurrentWorldName)
	
	-- Remove fire effect from track
	RemoveFireEffectFromTrack(CurrentWorldName)
	
	-- Remove lighting effects
	RemoveTrackLightingEffects()
	
	-- Re-enable player controls
	EnablePlayerControls()
	
	Log("Track stopped")
end

-- Handle track progress update from server for fire effects
local function OnTrackProgressUpdate(progressData: { worldName: string, progressPercent: number, distanceTraveled: number, unlockRequirement: number })
	if not IsOnTrack then return end
	
	-- Update fire effects based on progress (activates at 50%+)
	UpdateFireEffectOnTrack(progressData.worldName, progressData.progressPercent)
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
	TrackService.TrackProgressUpdate:Connect(OnTrackProgressUpdate)

	closeButton.MouseButton1Click:Connect(function()
		resultsFrame.Parent.Visible = false
	end)
	
	Log("TrackController started")
end

return TrackController
