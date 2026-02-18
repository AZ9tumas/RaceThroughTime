--[[
	EggHatchAnimation Module
	Handles egg hatching animation in ViewportFrame.
	
	This module provides functions to:
	- Set up the ViewportFrame with an egg model and camera
	- Play the shaking animation with gradual speed increase
	- Handle the final reveal animation
	
	Usage:
		local EggHatchAnimation = require(...)
		EggHatchAnimation.PlayHatch(viewportFrame, eggName, onComplete)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local EggHatchStats = require(script.Parent.EggHatchStats)

local EggHatchAnimation = {}

-- Private state
local isPlaying = false

-- Play a sound effect
local function playSound(soundId: string)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 2
	sound.Parent = workspace
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

-- Set up the camera for the ViewportFrame
local function setupCamera(viewport: ViewportFrame, targetPart: BasePart): Camera
	local camera = Instance.new("Camera")
	camera.FieldOfView = EggHatchStats.Camera.FieldOfView
	
	-- Position camera looking at the egg
	local cameraPos = Vector3.new(
		0,
		EggHatchStats.Camera.Height,
		EggHatchStats.Camera.Distance
	)
	
	camera.CFrame = CFrame.new(cameraPos, Vector3.new(0, 0, 0)) * CFrame.Angles(math.rad(-EggHatchStats.Camera.Angle), 0, 0)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	
	return camera
end

-- Clone and set up the egg model in the viewport
local function setupEggModel(viewport: ViewportFrame, eggName: string): (Model?, BasePart?)
	-- Clear existing content
	for _, child in ipairs(viewport:GetChildren()) do
		if child:IsA("Model") or child:IsA("BasePart") or child:IsA("Camera") then
			child:Destroy()
		end
	end
	
	-- Try to find the egg model in Assets/Eggs
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		warn("[EggHatchAnimation] Assets folder not found in ReplicatedStorage")
		return nil, nil
	end
	
	local eggsFolder = assets:FindFirstChild("Eggs")
	if not eggsFolder then
		warn("[EggHatchAnimation] Eggs folder not found in Assets")
		return nil, nil
	end
	
	local eggTemplate = eggsFolder:FindFirstChild(eggName)
	if not eggTemplate then
		warn("[EggHatchAnimation] Egg model not found: " .. eggName)
		-- Try to find any egg as fallback
		eggTemplate = eggsFolder:FindFirstChildOfClass("Model")
		if not eggTemplate then
			warn("[EggHatchAnimation] No egg models found in Eggs folder")
			return nil, nil
		end
	end
	
	-- Clone the egg model
	local eggModel = eggTemplate:Clone()
	eggModel.Parent = viewport
	
	-- Find the primary part or first part for positioning
	local primaryPart = eggModel.PrimaryPart or eggModel:FindFirstChildWhichIsA("BasePart", true)
	if not primaryPart then
		warn("[EggHatchAnimation] Egg model has no parts")
		eggModel:Destroy()
		return nil, nil
	end
	
	-- Anchor all parts and position at origin
	for _, part in ipairs(eggModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	
	-- Move the model to center of viewport
	if eggModel.PrimaryPart then
		eggModel:SetPrimaryPartCFrame(CFrame.new(0, 0, 0))
	else
		primaryPart.CFrame = CFrame.new(0, 0, 0)
	end
	
	return eggModel, primaryPart
end

-- Apply shake rotation to the egg model
local function applyShake(eggModel: Model, primaryPart: BasePart, rotX: number, rotZ: number)
	if eggModel.PrimaryPart then
		eggModel:SetPrimaryPartCFrame(CFrame.new(0, 0, 0) * CFrame.Angles(rotX, 0, rotZ))
	else
		primaryPart.CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(rotX, 0, rotZ)
	end
end

-- Scale the egg model
local function scaleModel(eggModel: Model, scale: number)
	for _, part in ipairs(eggModel:GetDescendants()) do
		if part:IsA("BasePart") then
			-- Store original size on first scale
			local originalSize = part:GetAttribute("OriginalSize")
			if not originalSize then
				part:SetAttribute("OriginalSize", part.Size)
				originalSize = part.Size
			end
			part.Size = originalSize * scale
		end
	end
end

--[[
	Play the shake animation
	@param eggModel - The egg model to shake
	@param primaryPart - The primary part of the egg
	@param onShakeComplete - Callback when shake is complete
]]
function EggHatchAnimation.Shake(eggModel: Model, primaryPart: BasePart, onShakeComplete: () -> ())
	local hatchTime = EggHatchStats.HatchTime
	local startTime = tick()
	local connection: RBXScriptConnection
	
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local progress = math.min(elapsed / hatchTime, 1)
		
		-- Calculate shake rotation
		local rotX, rotZ = EggHatchStats.CalculateShakeRotation(elapsed, progress)
		
		-- Apply the shake
		applyShake(eggModel, primaryPart, rotX, rotZ)
		
		-- Random crack sounds
		if math.random() < EggHatchStats.Sounds.CrackProbability then
			playSound(EggHatchStats.Sounds.Crack)
		end
		
		-- Check if shake is complete
		if progress >= 1 then
			connection:Disconnect()
			if onShakeComplete then
				onShakeComplete()
			end
		end
	end)
	
	return connection
end

--[[
	Play the full egg hatch animation
	@param viewport - The ViewportFrame to render in
	@param eggName - Name of the egg model to use from Assets/Eggs
	@param dimmer - Optional Frame for dimming effect
	@param flash - Optional Frame for flash effect
	@param onComplete - Callback when animation is complete, receives true if successful
]]
function EggHatchAnimation.PlayHatch(
	viewport: ViewportFrame,
	eggName: string,
	dimmer: Frame?,
	flash: Frame?,
	onComplete: ((success: boolean) -> ())?
)
	if isPlaying then
		if onComplete then onComplete(false) end
		return
	end
	
	isPlaying = true
	
	-- Set up the egg model
	local eggModel, primaryPart = setupEggModel(viewport, eggName)
	if not eggModel or not primaryPart then
		isPlaying = false
		if onComplete then onComplete(false) end
		return
	end
	
	-- Set up the camera
	local camera = setupCamera(viewport, primaryPart)
	
	-- Initial scale animation
	scaleModel(eggModel, EggHatchStats.Effects.SpawnScaleStart)
	
	-- Dim background
	if dimmer then
		dimmer.BackgroundTransparency = 1
		TweenService:Create(dimmer, TweenInfo.new(0.3), {BackgroundTransparency = 0.6}):Play()
	end
	
	-- Play equip sound
	playSound(EggHatchStats.Sounds.Equip)
	
	-- Animate egg scale up
	local scaleUpDuration = EggHatchStats.Effects.SpawnScaleDuration
	local scaleStart = EggHatchStats.Effects.SpawnScaleStart
	local scaleEnd = EggHatchStats.Effects.SpawnScaleEnd
	local scaleStartTime = tick()
	
	local scaleConnection
	scaleConnection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - scaleStartTime
		local progress = math.min(elapsed / scaleUpDuration, 1)
		
		-- Easing: Back ease out for bouncy effect
		local t = 1 - progress
		local overshoot = 1.70158
		local easedProgress = 1 - (t * t * ((overshoot + 1) * t + overshoot))
		
		local currentScale = scaleStart + (scaleEnd - scaleStart) * easedProgress
		scaleModel(eggModel, currentScale)
		
		if progress >= 1 then
			scaleConnection:Disconnect()
			
			-- Start the shake animation
			EggHatchAnimation.Shake(eggModel, primaryPart, function()
				-- Shake complete - play explosion
				playSound(EggHatchStats.Sounds.Explode)
				playSound(EggHatchStats.Sounds.Tada)
				
				-- Flash effect
				if flash then
					flash.BackgroundTransparency = 0
					TweenService:Create(flash, TweenInfo.new(EggHatchStats.Effects.FlashDuration), {BackgroundTransparency = 1}):Play()
				end
				
				-- Hide the egg (will be replaced by pet in the calling code)
				eggModel:Destroy()
				
				-- Wait for result display time
				task.delay(EggHatchStats.Effects.ResultDisplayTime, function()
					-- Fade out
					if dimmer then
						TweenService:Create(dimmer, TweenInfo.new(EggHatchStats.Effects.FadeOutDuration), {BackgroundTransparency = 1}):Play()
					end
					
					task.delay(EggHatchStats.Effects.FadeOutDuration, function()
						-- Clean up
						camera:Destroy()
						isPlaying = false
						
						if onComplete then
							onComplete(true)
						end
					end)
				end)
			end)
		end
	end)
end

-- Check if an animation is currently playing
function EggHatchAnimation.IsPlaying(): boolean
	return isPlaying
end

--[[
	Play the egg hatch animation on multiple viewports simultaneously.
	All viewports animate in sync with sounds played once.
	@param viewports - Array of ViewportFrames to render in
	@param eggName - Name of the egg model to use from Assets/Eggs
	@param dimmer - Optional Frame for dimming effect
	@param flash - Optional Frame for flash effect
	@param onComplete - Callback when animation is complete, receives true if successful
]]
function EggHatchAnimation.PlayMultiHatch(
	viewports: { ViewportFrame },
	eggName: string,
	dimmer: Frame?,
	flash: Frame?,
	onComplete: ((success: boolean) -> ())?
)
	if isPlaying then
		if onComplete then onComplete(false) end
		return
	end
	
	isPlaying = true
	
	local eggModels = {}
	local primaryParts = {}
	local cameras = {}
	
	-- Setup all viewports
	for i, viewport in ipairs(viewports) do
		local eggModel, primaryPart = setupEggModel(viewport, eggName)
		if not eggModel or not primaryPart then
			-- Clean up already-created models and fail
			for _, model in ipairs(eggModels) do model:Destroy() end
			for _, cam in ipairs(cameras) do cam:Destroy() end
			isPlaying = false
			if onComplete then onComplete(false) end
			return
		end
		
		local camera = setupCamera(viewport, primaryPart)
		eggModels[i] = eggModel
		primaryParts[i] = primaryPart
		cameras[i] = camera
		
		scaleModel(eggModel, EggHatchStats.Effects.SpawnScaleStart)
	end
	
	-- Dim background
	if dimmer then
		dimmer.BackgroundTransparency = 1
		TweenService:Create(dimmer, TweenInfo.new(0.3), {BackgroundTransparency = 0.6}):Play()
	end
	
	-- Play equip sound once
	playSound(EggHatchStats.Sounds.Equip)
	
	-- Animate all eggs scale up simultaneously
	local scaleUpDuration = EggHatchStats.Effects.SpawnScaleDuration
	local scaleStart = EggHatchStats.Effects.SpawnScaleStart
	local scaleEnd = EggHatchStats.Effects.SpawnScaleEnd
	local scaleStartTime = tick()
	
	local scaleConnection
	scaleConnection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - scaleStartTime
		local progress = math.min(elapsed / scaleUpDuration, 1)
		
		local t = 1 - progress
		local overshoot = 1.70158
		local easedProgress = 1 - (t * t * ((overshoot + 1) * t + overshoot))
		
		local currentScale = scaleStart + (scaleEnd - scaleStart) * easedProgress
		for _, eggModel in ipairs(eggModels) do
			scaleModel(eggModel, currentScale)
		end
		
		if progress >= 1 then
			scaleConnection:Disconnect()
			
			-- Shake all eggs in a single RenderStepped connection
			local hatchTime = EggHatchStats.HatchTime
			local shakeStart = tick()
			local shakeConnection
			
			shakeConnection = RunService.RenderStepped:Connect(function()
				local shakeElapsed = tick() - shakeStart
				local shakeProgress = math.min(shakeElapsed / hatchTime, 1)
				
				local rotX, rotZ = EggHatchStats.CalculateShakeRotation(shakeElapsed, shakeProgress)
				
				for i, eggModel in ipairs(eggModels) do
					applyShake(eggModel, primaryParts[i], rotX, rotZ)
				end
				
				-- Crack sounds (once per frame, not per egg)
				if math.random() < EggHatchStats.Sounds.CrackProbability then
					playSound(EggHatchStats.Sounds.Crack)
				end
				
				if shakeProgress >= 1 then
					shakeConnection:Disconnect()
					
					-- Explosion sounds once
					playSound(EggHatchStats.Sounds.Explode)
					playSound(EggHatchStats.Sounds.Tada)
					
					-- Flash effect
					if flash then
						flash.BackgroundTransparency = 0
						TweenService:Create(flash, TweenInfo.new(EggHatchStats.Effects.FlashDuration), {BackgroundTransparency = 1}):Play()
					end
					
					-- Destroy all egg models
					for _, model in ipairs(eggModels) do
						model:Destroy()
					end
					
					-- Wait for result display then fade out
					task.delay(EggHatchStats.Effects.ResultDisplayTime, function()
						if dimmer then
							TweenService:Create(dimmer, TweenInfo.new(EggHatchStats.Effects.FadeOutDuration), {BackgroundTransparency = 1}):Play()
						end
						
						task.delay(EggHatchStats.Effects.FadeOutDuration, function()
							for _, cam in ipairs(cameras) do
								cam:Destroy()
							end
							isPlaying = false
							
							if onComplete then
								onComplete(true)
							end
						end)
					end)
				end
			end)
		end
	end)
end

-- Force stop any playing animation
function EggHatchAnimation.Stop()
	isPlaying = false
end

return EggHatchAnimation
