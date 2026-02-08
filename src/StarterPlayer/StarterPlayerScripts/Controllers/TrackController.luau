local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local PLACEHOLDER_HEADSHOT = "rbxasset://textures/ui/GuiImagePlaceholder.png"

local function SafeGetHeadshot(userId: number, size: Enum.ThumbnailSize?): string
	local thumbnailSize = size or Enum.ThumbnailSize.Size100x100
	local success, content = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, thumbnailSize)
	end)
	if success and content then
		return content
	end
	return PLACEHOLDER_HEADSHOT
end

-- ui
local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local mainUi: ScreenGui = PlayerGui:WaitForChild("RaceThroughTime_UI")
local centerHUD: Frame = mainUi:WaitForChild("CenterHUD")
local runButton: TextButton = centerHUD:WaitForChild("RunButton")

local liveMainUI: ScreenGui = PlayerGui:WaitForChild("UI_LiveDistance")
local distanceCounter: TextLabel = liveMainUI:WaitForChild("DistanceCounter")

-- live race stats ui
local RaceHUD : ScreenGui = PlayerGui:WaitForChild("RaceHUD")
local RaceHUDMainFrame: Frame = RaceHUD:WaitForChild("MainFrame")
local globalView: Frame = RaceHUDMainFrame:WaitForChild("GlobalView")
local strokeTemplate: UIStroke = globalView:WaitForChild("Templates"):WaitForChild("UIStroke")
local playerIndicatorTemplate: ImageLabel = globalView:WaitForChild("Templates"):WaitForChild("Template")
local localView: Frame = RaceHUDMainFrame:WaitForChild("LocalView")
local progressFrameFill: Frame = localView:WaitForChild("Progress"):WaitForChild("Fill")
local progressHeadshotImage: ImageLabel = progressFrameFill:WaitForChild("Frame"):WaitForChild("ImageLabel")

-- Track cancel button UI
local trackCancelUI: ScreenGui = PlayerGui:WaitForChild("UI_CancelTrackButton")
local trackCancelButton: TextButton = trackCancelUI:WaitForChild("Track_Cancel")

-- Results popup UI
local resultsPopupUI: ScreenGui = PlayerGui:WaitForChild("UI_ResultsPopup")
local resultsFrame: Frame = resultsPopupUI:WaitForChild("Frame"):WaitForChild("Frame")
local distanceFrame: Frame = resultsFrame:WaitForChild("Distance")
local distanceValueLabel: TextLabel = distanceFrame:WaitForChild("DistanceValue")
local progressFrame: Frame = resultsFrame:WaitForChild("Progress")
local greenFillFrame: Frame = progressFrame:WaitForChild("Frame"):WaitForChild("GreenFill")
local closeButton: TextButton = resultsFrame:WaitForChild("TextButton")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)

-- Reference to UIController for debounce reset
local UIController = nil
local UIFramesController = nil

-- Camera settings
local DEFAULT_FOV = 70
local TRACK_FOV = 90
local FOV_TWEEN_TIME = 0.5
local TRACK_END_LOADING_DELAY = 0.8 -- Seconds to show loading screen after track ends

-- Lighting effect settings
local LIGHTING_TWEEN_TIME = 0.5

-- Raycast parameters for ground detection
local RAYCAST_HEIGHT_OFFSET = 50
local RAYCAST_DISTANCE = 100

-- RenderStep binding name
local RENDER_STEP_BINDING = "TrackController_Movement"

-- Movement calculation constants
local TIME_EPSILON = 0.001 -- Epsilon for floating point time comparison
local SPEED_FACTOR_DIVISOR = 10 -- Divisor for speed factor calculation
local MAX_SPEED_FACTOR = 20 -- Maximum speed factor for responsiveness

-- World frame colors
local COLOR_OWNED = Color3.fromRGB(46, 204, 113) -- Green for owned worlds
local COLOR_NOT_OWNED = Color3.fromRGB(100, 100, 100) -- Gray for not owned worlds
local COLOR_CURRENT = Color3.fromRGB(52, 152, 219) -- Blue for current/latest unlocked world

local TrackController = Knit.CreateController({
	Name = "TrackController",
})

-- Private state
local IsOnTrack = false
local TrackData = nil
local CurrentWorldName = "Main"
local OriginalWalkSpeed = 16
local OriginalJumpPower = 50
local TrackLightingEffects = {} -- Store created lighting effects for cleanup
local TrackOriginalProperties = {} -- Store original track properties for restoration
local TrackFireEffects = {} -- Store fire/smoke effects

-- Movement state (client-side tracking)
local CurrentAngle = 0
local ElapsedTime = 0
local DistanceTraveled = 0
local LapCount = 0
local WorldUnlocked = false

-- Pet follow constants (same as PetController and TrackService)
local PET_FOLLOW_DISTANCE = 8
local PET_FOLLOW_HEIGHT = 2

-- Player indicators on globalView
local PlayerIndicators: { [number]: ImageLabel } = {}
local PlayerHeadshotCache: { [number]: string } = {}
local PlayerLapsFolder: Folder = nil

-- Helper function for logging
local function Log(message: string)
	--print(string.format("[TrackController]: %s", message))
end

-- Find all pet models in workspace that belong to the local player and are in track mode
local function FindLocalPlayerTrackPets(): { Model }
	local pets = {}
	local localUserId = player.UserId
	
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and child.PrimaryPart then
			local ownerUserId = child:GetAttribute("OwnerUserId")
			local trackMode = child:GetAttribute("TrackMode")
			
			-- Only include pets that belong to local player and are in track mode
			if ownerUserId == localUserId and trackMode == true then
				table.insert(pets, child)
			end
		end
	end
	
	return pets
end

-- Update pet positions during track run
-- Pets move at the same position as the player with an offset
local function UpdatePetPositionsDuringTrack(targetPosition: Vector3, targetCFrame: CFrame, physicalSpeed: number)
	local pets = FindLocalPlayerTrackPets()
	
	for _, petModel in ipairs(pets) do
		local primaryPart = petModel.PrimaryPart
		if not primaryPart then continue end
		
		local petIndex = petModel:GetAttribute("PetIndex") or 1
		local alignPos = primaryPart:FindFirstChild("PetAlignPosition")
		local alignOri = primaryPart:FindFirstChild("PetAlignOrientation")
		
		if alignPos and alignOri then
			-- Calculate offset for this pet (same formula as SetPetToFollowPlayer)
			local offset = Vector3.new(
				math.cos(petIndex * math.pi / 2) * PET_FOLLOW_DISTANCE,
				PET_FOLLOW_HEIGHT,
				math.sin(petIndex * math.pi / 2) * PET_FOLLOW_DISTANCE
			)
			
			-- Apply offset relative to player's orientation
			local petTargetCFrame = targetCFrame * CFrame.new(offset)
			
			-- Dynamically adjust responsiveness based on speed (same as player)
			local baseResponsiveness = 50
			local speedFactor = math.clamp(physicalSpeed / 10, 1, 20)
			local dynamicResponsiveness = baseResponsiveness + (speedFactor * 10)
			local dynamicMaxVelocity = math.max(500, physicalSpeed * 2)
			
			alignPos.Responsiveness = dynamicResponsiveness
			alignPos.MaxVelocity = dynamicMaxVelocity
			
			-- Update body mover targets
			alignPos.Position = petTargetCFrame.Position
			alignOri.CFrame = petTargetCFrame
		end
	end
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

-- Create raycast params for a specific world's visual track
local function CreateRaycastParamsForWorld(worldName: string): RaycastParams
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	
	local visualTrack = GetVisualTrackForWorld(worldName)
	if visualTrack then
		raycastParams.FilterDescendantsInstances = { visualTrack }
	else
		raycastParams.FilterDescendantsInstances = {}
	end
	
	return raycastParams
end

-- Update circular position using polar to cartesian conversion with ground detection
local function UpdateCircularPosition(center: Vector3, radius: number, angle: number, fallbackY: number, worldName: string): (CFrame, Vector3)
	-- Polar to Cartesian conversion
	local x = center.X + radius * math.cos(angle)
	local z = center.Z + radius * math.sin(angle)
	
	-- Raycast only hits Visual_Track part (excludes characters and other objects)
	local rayOrigin = Vector3.new(x, fallbackY + RAYCAST_HEIGHT_OFFSET, z)
	local rayDirection = Vector3.new(0, -RAYCAST_DISTANCE, 0)
	
	-- Create world-specific raycast params
	local raycastParams = CreateRaycastParamsForWorld(worldName)
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	
	local groundY = fallbackY -- Default to fallback if raycast fails
	if raycastResult then
		-- Place player at ground position
		groundY = raycastResult.Position.Y
	end
	
	local targetPosition = Vector3.new(x, groundY, z)
	
	-- Calculate orientation (tangential direction - looking forward along the path)
	local lookAtPos = targetPosition + Vector3.new(
		-math.sin(angle), -- Derivative of cos
		0,
		math.cos(angle)   -- Derivative of sin
	)
	
	local finalCFrame = CFrame.lookAt(targetPosition, lookAtPos)
	
	return finalCFrame, targetPosition
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
		local distStr = UIController and UIController:TruncateNumber(distance) or string.format("%.1f", distance)
		local totalDistStr = UIController and UIController:TruncateNumber(totalDistance) or string.format("%.1f", totalDistance)
		distanceCounter.Text = string.format("%s / %s (%.1f%%)", distStr, totalDistStr, percentage)
	end
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
local function OnTrackStarted(trackData: { 
	gateName: string, 
	totalDistance: number, 
	initialSpeed: number, 
	acceleration: number,
	maxSpeed: number,
	totalTime: number,
	startAngle: number, 
	worldName: string?,
	worldRadius: number?,
	trackCenter: Vector3?,
	maxPhysicalSpeed: number?,
	nextWorld: string?,
	unlockRequirement: number?
})
	IsOnTrack = true
	TrackData = trackData
	CurrentWorldName = trackData.worldName or "Main"
	distanceCounter.Visible = true
	
	-- Toggle view visibility: localView visible, globalView hidden during race
	localView.Visible = true
	globalView.Visible = false
	
	-- Set player headshot on progress bar with placeholder fallback
	local headshotContent = SafeGetHeadshot(player.UserId, Enum.ThumbnailSize.Size100x100)
	progressHeadshotImage.Image = headshotContent
	progressHeadshotImage.ImageTransparency = 0
	
	-- Initialize client-side movement state
	CurrentAngle = trackData.startAngle
	ElapsedTime = 0
	DistanceTraveled = 0
	LapCount = 0
	WorldUnlocked = false
	
	-- Reset progress bar
	progressFrameFill.Size = UDim2.new(1, 0, 0, 0)
	
	Log(string.format("Track started at %s, total distance: %.2f, initialSpeed: %.2f", trackData.gateName, trackData.totalDistance, trackData.initialSpeed or 0))
	
	-- Notify PetController that track run has started (pets should follow, not collect stars)
	local PetController = Knit.GetController("PetController")
	if PetController then
		PetController:SetOnTrack(true)
	end
	
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
	
	-- Initialize distance display
	UpdateDistanceDisplay(0, trackData.totalDistance)
	
	-- Disable player controls
	DisablePlayerControls()
	
	-- Show cancel button during track run
	trackCancelButton.Visible = true
	
	-- Disable all other UI frames during track run (except RaceHUD)
	if UIFramesController then
		UIFramesController:DisableFramesWithExceptions(true, {"RaceHUD"})
	end
	
	-- Show notification
	local NotificationController = Knit.GetController("NotificationController")
	if NotificationController then
		local totalDistStr = UIController and UIController:TruncateNumber(trackData.totalDistance) or string.format("%.0f", trackData.totalDistance)
		NotificationController:ShowNotification(
			"Track Run Started! Distance: " .. totalDistStr,
			NotificationController.Category.Alert,
			3
		)
	end
	
	-- Start the client-side movement loop using BindToRenderStep
	RunService:BindToRenderStep(RENDER_STEP_BINDING, Enum.RenderPriority.Character.Value + 1, function(dt)
		if not IsOnTrack or not TrackData then
			RunService:UnbindFromRenderStep(RENDER_STEP_BINDING)
			return
		end
		
		local localPlayer = Players.LocalPlayer
		local character = localPlayer.Character
		if not character then return end
		
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then return end
		
		-- Get body movers (created by server)
		local alignPosition = rootPart:FindFirstChild("TrackAlignPosition")
		local alignOrientation = rootPart:FindFirstChild("TrackAlignOrientation")
		
		if not alignPosition or not alignOrientation then return end
		
		-- Get track parameters from TrackData
		local worldName = TrackData.worldName or "Main"
		local radius = TrackData.worldRadius or Stats.WorldRadius[worldName] or Stats.WorldRadius.Main
		local center = TrackData.trackCenter
		local maxPhysicalSpeed = TrackData.maxPhysicalSpeed or Stats.MaxPhysicalSpeed
		
		if not center then return end
		
		-- Update elapsed time
		ElapsedTime = ElapsedTime + dt
		
		-- Calculate current speed using acceleration (v = v0 + a*t, capped at maxSpeed)
		local calculatedSpeed = Stats.CalculateCurrentSpeed(
			TrackData.initialSpeed,
			TrackData.acceleration,
			TrackData.maxSpeed,
			ElapsedTime
		)
		
		-- Physical speed is capped at MaxPhysicalSpeed for body movers
		local physicalSpeed = math.min(calculatedSpeed, maxPhysicalSpeed)
		
		-- Convert linear speed to angular velocity for polar coordinate movement
		local angularVelocity = Stats.LinearSpeedToAngularVelocity(physicalSpeed, radius)
		
		-- Update angle based on time delta
		CurrentAngle = CurrentAngle + (angularVelocity * dt)
		
		-- Calculate distance traveled this frame using CALCULATED speed (not physical)
		local distanceThisFrame = calculatedSpeed * dt
		DistanceTraveled = DistanceTraveled + distanceThisFrame
		
		-- Update distance display
		UpdateDistanceDisplay(DistanceTraveled, TrackData.totalDistance)
		
		-- Check for lap completion
		local startAngle = TrackData.startAngle
		local lapThreshold = startAngle + (2 * math.pi * (LapCount + 1))
		
		-- Calculate lap progress percentage (0 to 1)
		local lapStartAngle = startAngle + (2 * math.pi * LapCount)
		local angleIntoCurrentLap = CurrentAngle - lapStartAngle
		local lapPercentage = math.clamp(angleIntoCurrentLap / (2 * math.pi), 0, 1)
		progressFrameFill.Size = UDim2.new(1, 0, lapPercentage, 0)
		
		if CurrentAngle >= lapThreshold then
			LapCount = LapCount + 1
			local NotifController = Knit.GetController("NotificationController")
			if NotifController then
				NotifController:ShowNotification(
					string.format("Lap %d Complete!", LapCount),
					NotifController.Category.Success,
					2
				)
			end
			Log(string.format("Completed lap %d", LapCount))
		end
		
		-- Update distance NumberValue for server reference (if exists)
		local distanceValue = rootPart:FindFirstChild("TrackDistanceTraveled")
		if distanceValue then
			distanceValue.Value = DistanceTraveled
		end
		
		-- Check for world unlock (fire effects, etc.)
		local unlockRequirement = TrackData.unlockRequirement
		if unlockRequirement then
			local progressPercent = DistanceTraveled / unlockRequirement
			
			-- Update fire effects based on progress (activates at 50%+)
			UpdateFireEffectOnTrack(worldName, progressPercent)
			
			-- Check if reached unlock threshold
			if DistanceTraveled >= unlockRequirement and not WorldUnlocked then
				WorldUnlocked = true
				Log(string.format("World unlock threshold reached: %.2f", DistanceTraveled))
			end
		end
		
		-- Check if track run should end (time limit or distance reached)
		if ElapsedTime >= (TrackData.totalTime - TIME_EPSILON) or DistanceTraveled >= TrackData.totalDistance then
			-- Unbind immediately to prevent further updates
			RunService:UnbindFromRenderStep(RENDER_STEP_BINDING)
			
			-- Request track end from server with distance traveled
			local TrackService = Knit.GetService("TrackService")
			TrackService:RequestTrackEnd(DistanceTraveled, WorldUnlocked)
			
			return
		end
		
		-- Calculate new position using UpdateCircularPosition
		local targetCFrame, targetPosition = UpdateCircularPosition(center, radius, CurrentAngle, center.Y + 5, worldName)
		
		-- Dynamically adjust body mover responsiveness based on physical speed
		local baseResponsiveness = 50
		local speedFactor = math.clamp(physicalSpeed / SPEED_FACTOR_DIVISOR, 1, MAX_SPEED_FACTOR)
		local dynamicResponsiveness = baseResponsiveness + (speedFactor * SPEED_FACTOR_DIVISOR)
		local dynamicMaxVelocity = math.max(500, physicalSpeed * 2)
		
		alignPosition.Responsiveness = dynamicResponsiveness
		alignPosition.MaxVelocity = dynamicMaxVelocity
		
		-- Update body mover targets
		alignPosition.Position = targetPosition
		alignOrientation.CFrame = targetCFrame
		
		-- Update pet positions alongside player (using same position/orientation and speed)
		UpdatePetPositionsDuringTrack(targetPosition, targetCFrame, physicalSpeed)
	end)
end

-- Handle track ended signal from server
local function OnTrackEnded(trackData: { distanceTraveled: number, cashEarned: number, percentageToNextWorld: number?, unlockRequirement: number? })
	if not IsOnTrack then return end
	
	Log(string.format("Track ended, distance traveled: %.2f, cash earned: %.0f", trackData.distanceTraveled or 0, trackData.cashEarned or 0))
	
	IsOnTrack = false
	TrackData = nil
	
	-- Toggle view visibility: globalView visible, localView hidden when race ends
	localView.Visible = false
	globalView.Visible = true
	
	-- Notify PetController that track run has ended (pets can resume normal behavior)
	local PetController = Knit.GetController("PetController")
	if PetController then
		PetController:SetOnTrack(false)
	end
	
	-- Unbind the movement loop (in case it's still running)
	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_STEP_BINDING)
	end)
	
	-- Reset movement state
	CurrentAngle = 0
	ElapsedTime = 0
	DistanceTraveled = 0
	LapCount = 0
	WorldUnlocked = false
	
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
	
	-- Hide cancel button when track ends
	trackCancelButton.Visible = false
	
	-- Re-enable all UI frames after track run ends
	if UIFramesController then
		UIFramesController:DisableFramesWithExceptions(false, {})
	end

	print(trackData)
	
	-- Update results popup UI
	local distanceTraveled = trackData.distanceTraveled
	local percentageToNextWorld = trackData.percentageToNextWorld
	
	-- Set distance value text
	if distanceValueLabel then
		distanceValueLabel.Text = UIController and UIController:TruncateNumber(distanceTraveled) or string.format("%.0f", distanceTraveled)
	end
	
	-- Set green fill width based on percentage (scale X from 0 to 1)
	if greenFillFrame and trackData.cancelled == nil then
		local fillPercentage = math.clamp(percentageToNextWorld / 100, 0, 1)
		print("Fill percentage: ", fillPercentage)
		greenFillFrame.Size = UDim2.new(fillPercentage, 0, greenFillFrame.Size.Y.Scale, greenFillFrame.Size.Y.Offset)
	end
	
	-- Show the results popup
	if resultsPopupUI and not trackData.cancelled then
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
	
	-- Reset UIController debounce so player can request a new run
	if UIController then
		UIController:ResetTrackDebounce()
	end
	
	-- Show notification with cash earned
	local NotificationController = Knit.GetController("NotificationController")
	if NotificationController then
		local cashStr = trackData.cashEarned and (UIController and UIController:TruncateNumber(trackData.cashEarned) or string.format("%.0f", trackData.cashEarned)) or "0"
		local cashMessage = trackData.cashEarned and trackData.cashEarned > 0 
			and string.format("Track Run Complete! +$%s", cashStr)
			or "Track Run Complete!"
		NotificationController:ShowNotification(cashMessage, NotificationController.Category.Success, 3)
	end
	
	-- Note: Run button visibility is now controlled by RunButtonUIController based on gate proximity
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
	
	-- Toggle view visibility: globalView visible, localView hidden when race ends
	localView.Visible = false
	globalView.Visible = true
	
	-- Notify PetController that track run has ended
	local PetController = Knit.GetController("PetController")
	if PetController then
		PetController:SetOnTrack(false)
	end
	
	-- Unbind the movement loop
	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_STEP_BINDING)
	end)
	
	-- Reset movement state
	CurrentAngle = 0
	ElapsedTime = 0
	DistanceTraveled = 0
	LapCount = 0
	WorldUnlocked = false
	
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
	
	-- Hide cancel button
	trackCancelButton.Visible = false
	
	Log("Track stopped")
end

-- Update world frame colors in globalView based on unlocked worlds
function TrackController:UpdateWorldFrameColors()
	local data = UIController and UIController:GetData()
	if not data then return end
	
	local unlockedWorlds = data.Progression and data.Progression.UnlockedWorlds or { "Main" }
	
	-- Find the latest unlocked world based on Stats.WorldOrder
	local latestUnlockedWorld = "Main"
	for i = #Stats.WorldOrder, 1, -1 do
		local worldName = Stats.WorldOrder[i]
		for _, unlockedWorld in ipairs(unlockedWorlds) do
			if unlockedWorld == worldName then
				latestUnlockedWorld = worldName
				break
			end
		end
		if latestUnlockedWorld ~= "Main" or Stats.WorldOrder[i] == "Main" then break end
	end

	-- next world info
	local nextWorldIndex = table.find(Stats.WorldOrder, latestUnlockedWorld) + 1
	local nextworldname = Stats.WorldOrder[nextWorldIndex]
	local nextWorld = Stats.WorldOrder[nextWorldIndex] and Stats.WorldUnlockRequirements[nextworldname] or {Rebirth = 0}
	local worldProgress: Frame = globalView.Parent:FindFirstChild("WorldProgress")
	local rebirths: TextLabel = worldProgress:WaitForChild("Rebirths")
	warn(data.Stats.Rebirths, nextWorld.Rebirth)

	rebirths.Text = data.Stats.Rebirths .. "/" .. nextWorld.Rebirth
	worldProgress.WorldName.Text = nextworldname or "MAX"

	if nextWorld then
		worldProgress.Visible = true
	else
		worldProgress.Visible = false
	end
	
	-- Update each world frame in globalView
	for _, worldName in ipairs(Stats.WorldOrder) do
		local worldFrame = globalView:FindFirstChild(worldName)
		if worldFrame then
			local isOwned = false
			for _, unlockedWorld in ipairs(unlockedWorlds) do
				if unlockedWorld == worldName then
					isOwned = true
					break
				end
			end
			
			-- Determine color and stroke visibility
			if worldName == latestUnlockedWorld then
				worldFrame.BackgroundColor3 = COLOR_CURRENT
				local uiStroke = worldFrame:FindFirstChild("UIStroke")
				if uiStroke then uiStroke:Destroy() end

				local innerStroke = strokeTemplate:Clone()
				if innerStroke then
					innerStroke.Enabled = true
					innerStroke.Parent = worldFrame
				end
				
			elseif isOwned then
				worldFrame.BackgroundColor3 = COLOR_OWNED
				local uiStroke = worldFrame:FindFirstChild("UIStroke")
				if uiStroke then
					local innerStroke = uiStroke:FindFirstChild("UIStroke")
					if innerStroke then
						innerStroke:Destroy()
					end
				end
			else
				worldFrame.BackgroundColor3 = COLOR_NOT_OWNED
				local uiStroke = worldFrame:FindFirstChild("UIStroke")
				if uiStroke then
					local innerStroke = uiStroke:FindFirstChild("UIStroke")
					if innerStroke then
						innerStroke:Destroy()
					end
				end
			end
		end
	end
end

-- Get or create player indicator
local function GetOrCreatePlayerIndicator(targetPlayer: Player): ImageLabel?
	if PlayerIndicators[targetPlayer.UserId] then
		return PlayerIndicators[targetPlayer.UserId]
	end
	
	if not playerIndicatorTemplate then return nil end
	
	local indicator = playerIndicatorTemplate:Clone()
	indicator.Name = "PlayerIndicator_" .. targetPlayer.UserId
	indicator.Visible = true
	indicator.Parent = globalView
	
	PlayerIndicators[targetPlayer.UserId] = indicator
	
	task.spawn(function()
		local content = SafeGetHeadshot(targetPlayer.UserId, Enum.ThumbnailSize.Size48x48)
		indicator.Image = content
		indicator.ImageTransparency = 0
		PlayerHeadshotCache[targetPlayer.UserId] = content
	end)
	
	return indicator
end

-- Remove player indicator
local function RemovePlayerIndicator(targetPlayer: Player)
	local indicator = PlayerIndicators[targetPlayer.UserId]
	if indicator then
		indicator:Destroy()
		PlayerIndicators[targetPlayer.UserId] = nil
	end
	PlayerHeadshotCache[targetPlayer.UserId] = nil
end

-- Get world frame Y position
local function GetWorldFrameYPosition(worldName: string): number
	local worldFrame = globalView:FindFirstChild(worldName)
	if worldFrame then
		return worldFrame.Position.Y.Scale
	end
	return 0
end

-- Update all player position indicators
local function UpdatePlayerPositionIndicators()
	if not PlayerLapsFolder then
		PlayerLapsFolder = ReplicatedStorage:FindFirstChild("PlayerLaps")
		if not PlayerLapsFolder then return end
	end
	
	local currentPlayers = {}
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		currentPlayers[targetPlayer.UserId] = true
		
		local indicator = GetOrCreatePlayerIndicator(targetPlayer)
		if not indicator then continue end
		
		local lapValue = PlayerLapsFolder:FindFirstChild(tostring(targetPlayer.UserId))
		
		local launchWorld = "Main"
		local targetWorld = "Main"
		local lapPercentage = 0
		
		if lapValue then
			launchWorld = lapValue:GetAttribute("LaunchWorldName") or "Main"
			targetWorld = lapValue:GetAttribute("TargetWorldName") or "Main"
			lapPercentage = lapValue.Value or 0
		else
			local currentWorld = targetPlayer:GetAttribute("CurrentWorld")
			if currentWorld then
				launchWorld = currentWorld
				targetWorld = currentWorld
			end
		end
		
		local launchY = GetWorldFrameYPosition(launchWorld)
		local targetY = GetWorldFrameYPosition(targetWorld)
		
		local interpolatedY = launchY + (targetY - launchY) * lapPercentage
		
		indicator.Position = UDim2.new(
			indicator.Position.X.Scale,
			indicator.Position.X.Offset,
			interpolatedY,
			indicator.Position.Y.Offset
		)
	end
	
	for userId, indicator in pairs(PlayerIndicators) do
		if not currentPlayers[userId] then
			indicator:Destroy()
			PlayerIndicators[userId] = nil
			PlayerHeadshotCache[userId] = nil
		end
	end
end

-- Knit lifecycle
function TrackController:KnitInit()
	-- Controller initialization
end

function TrackController:KnitStart()
	-- Get UIController reference for debounce reset
	UIController = Knit.GetController("UIController")
	UIFramesController = Knit.GetController("UIFramesController")
	
	-- Listen for server signals
	local TrackService = Knit.GetService("TrackService")
	
	TrackService.TrackStarted:Connect(OnTrackStarted)
	TrackService.TrackEnded:Connect(OnTrackEnded)
	
	-- Listen for early world unlock during track run
	TrackService.EarlyWorldUnlock:Connect(function(unlockData)
		Log(string.format("Early world unlock! New world: %s, distance: %.2f", unlockData.newWorld or "unknown", unlockData.distanceTraveled or 0))
		
		-- Show notification
		local NotificationController = Knit.GetController("NotificationController")
		if NotificationController then
			NotificationController:ShowNotification(
				"🌍 World Unlocked!",
				NotificationController.Category.Success,
				3
			)
		end
		
		-- The TrackEnded signal will also be fired, which will handle cleanup
	end)

	closeButton.MouseButton1Click:Connect(function()
		resultsFrame.Parent.Visible = false
	end)
	
	-- Connect cancel button to cancel track run
	trackCancelButton.MouseButton1Click:Connect(function()
		if not IsOnTrack then return end
		
		-- Request cancel from server
		TrackService:CancelTrackRun():andThen(function(success, errorMsg)
			if success then
				Log("Track run cancelled successfully")
			else
				warn(string.format("[TrackController]: Failed to cancel track run - %s", errorMsg or "Unknown error"))
			end
		end)
	end)
	
	-- Ensure cancel button is hidden initially
	trackCancelButton.Visible = false
	
	-- Setup button animation for cancel button (hover/click effects)
	if UIFramesController then
		UIFramesController:SetupButtonAnimation(trackCancelButton)
	end
	
	-- Listen for data updates to refresh world frame colors
	local DataService = Knit.GetService("DataService")
	DataService.DataReady:Connect(function()
		self:UpdateWorldFrameColors()
	end)
	
	-- Update player position indicators on RenderStepped
	RunService.RenderStepped:Connect(UpdatePlayerPositionIndicators)
	
	Log("TrackController started")
end

return TrackController
