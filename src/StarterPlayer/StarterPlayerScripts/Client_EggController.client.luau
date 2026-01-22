--[[
	Client_EggController
	Handles egg hatching UI and animations on the client side.
	
	Uses the EggHatchAnimation module for the shaking animation and
	EggHatchStats for configuration.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local ScreenGui = PlayerGui:WaitForChild("EggHatchScreen")
local Viewport = ScreenGui:WaitForChild("Dimmer"):WaitForChild("Viewport")
local Dimmer = ScreenGui:WaitForChild("Dimmer")
local Flash = ScreenGui:FindFirstChild("Flash")

-- Wait for modules to load
local Modules = ReplicatedStorage:WaitForChild("Modules")
local EggHatchStats = require(Modules:WaitForChild("EggHatchStats"))
local EggHatchAnimation = require(Modules:WaitForChild("EggHatchAnimation"))

-- Wait for Knit
local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

local isHatching = false
local currentClosestStand = nil
local EggService = nil

-- Sound configuration
local SOUNDS = {
	Click   = "rbxassetid://6042054019",
	Equip   = "rbxassetid://244655616",
	Crack   = "rbxassetid://4819098925",
	Explode = "rbxassetid://2801263161",
	Tada    = "rbxassetid://6042054019",
}

-- Rarity colors for pet reveal
local RARITY = {
	Common    = { Color = Color3.fromRGB(200, 200, 200), Chance = 0.50 },
	Uncommon  = { Color = Color3.fromRGB(50, 255, 100),  Chance = 0.30 },
	Rare      = { Color = Color3.fromRGB(0, 150, 255),   Chance = 0.15 },
	Epic      = { Color = Color3.fromRGB(170, 0, 255),   Chance = 0.04 },
	Legendary = { Color = Color3.fromRGB(255, 170, 0),   Chance = 0.01 }
}

local function playSound(id)
	local s = Instance.new("Sound", workspace)
	s.SoundId = id
	s.Volume = 2
	s.PlayOnRemove = true
	s:Destroy()
end

--[[
	Set up the camera in the viewport to look at the egg
]]
local function setupViewportCamera(viewport: ViewportFrame, targetPosition: Vector3): Camera
	local camera = viewport:FindFirstChildOfClass("Camera")
	if not camera then
		camera = Instance.new("Camera")
		camera.Parent = viewport
	end
	
	camera.FieldOfView = EggHatchStats.Camera.FieldOfView
	
	local cameraPos = targetPosition + Vector3.new(
		0,
		EggHatchStats.Camera.Height,
		EggHatchStats.Camera.Distance
	)
	
	camera.CFrame = CFrame.new(cameraPos, targetPosition) * CFrame.Angles(math.rad(-EggHatchStats.Camera.Angle), 0, 0)
	viewport.CurrentCamera = camera
	
	return camera
end

--[[
	Clone the egg model from Assets/Eggs and place it in the viewport
]]
local function setupEggInViewport(viewport: ViewportFrame, eggName: string): (Model?, BasePart?)
	-- Clear existing content
	for _, child in ipairs(viewport:GetChildren()) do
		if child:IsA("Model") or child:IsA("BasePart") then
			child:Destroy()
		end
	end
	
	-- Find the egg model
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		warn("[EggController] Assets folder not found")
		return nil, nil
	end
	
	local eggsFolder = assets:FindFirstChild("Eggs")
	if not eggsFolder then
		warn("[EggController] Eggs folder not found in Assets")
		return nil, nil
	end
	
	local eggTemplate = eggsFolder:FindFirstChild(eggName)
	if not eggTemplate then
		-- Try any egg as fallback
		eggTemplate = eggsFolder:FindFirstChildOfClass("Model")
		if not eggTemplate then
			warn("[EggController] No egg model found: " .. eggName)
			return nil, nil
		end
	end
	
	-- Clone and setup
	local eggModel = eggTemplate:Clone()
	eggModel.Parent = viewport
	
	local primaryPart = eggModel.PrimaryPart or eggModel:FindFirstChildWhichIsA("BasePart", true)
	if not primaryPart then
		eggModel:Destroy()
		return nil, nil
	end
	
	-- Anchor all parts
	for _, part in ipairs(eggModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	
	-- Position at origin
	if eggModel.PrimaryPart then
		eggModel:SetPrimaryPartCFrame(CFrame.new(0, 0, 0))
	else
		primaryPart.CFrame = CFrame.new(0, 0, 0)
	end
	
	return eggModel, primaryPart
end

--[[
	Apply shake animation to the egg based on progress (0 to 1)
]]
local function applyEggShake(eggModel: Model, primaryPart: BasePart, time: number, progress: number)
	local rotX, rotZ = EggHatchStats.CalculateShakeRotation(time, progress)
	
	if eggModel.PrimaryPart then
		eggModel:SetPrimaryPartCFrame(CFrame.new(0, 0, 0) * CFrame.Angles(rotX, 0, rotZ))
	else
		primaryPart.CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(rotX, 0, rotZ)
	end
end

--[[
	Scale the egg model for spawn animation
]]
local function scaleEggModel(eggModel: Model, scale: number)
	for _, part in ipairs(eggModel:GetDescendants()) do
		if part:IsA("BasePart") then
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
	Build a simple pet model for the reveal animation
]]
local function buildPetModel(color: Color3): Model
	local model = Instance.new("Model")
	local body = Instance.new("Part", model)
	body.Name = "Body"
	body.Size = Vector3.new(2, 2, 2)
	body.Color = color
	body.Material = Enum.Material.Neon
	body.Anchored = true
	
	local face = Instance.new("Decal", body)
	face.Texture = "rbxassetid://14407565945"
	face.Face = Enum.NormalId.Front
	
	local ear1 = Instance.new("Part", model)
	ear1.Name = "Ear"
	ear1.Size = Vector3.new(0.6, 0.8, 0.5)
	ear1.Color = color
	ear1.Material = Enum.Material.Plastic
	ear1.Anchored = true
	
	local ear2 = ear1:Clone()
	ear2.Parent = model
	
	body.Position = Vector3.new(0, 0, 0)
	ear1.Position = Vector3.new(-0.8, 1.2, 0)
	ear2.Position = Vector3.new(0.8, 1.2, 0)
	
	return model
end

--[[
	Play the full egg hatch animation
	@param eggName - Name of the egg to hatch (matches model in Assets/Eggs)
	@param onComplete - Called when animation finishes with the success status
]]
local function PlayEggHatchAnimation(eggName: string, onComplete: ((success: boolean) -> ())?)
	if isHatching then
		if onComplete then onComplete(false) end
		return
	end
	
	isHatching = true
	ScreenGui.Enabled = true
	
	-- Reset UI state
	if Flash then Flash.BackgroundTransparency = 1 end
	Dimmer.BackgroundTransparency = 1
	
	-- Set up the egg
	local eggModel, primaryPart = setupEggInViewport(Viewport, eggName)
	if not eggModel or not primaryPart then
		isHatching = false
		ScreenGui.Enabled = false
		if onComplete then onComplete(false) end
		return
	end
	
	-- Set up camera
	local camera = setupViewportCamera(Viewport, Vector3.new(0, 0, 0))
	
	-- Start with small scale
	scaleEggModel(eggModel, EggHatchStats.Effects.SpawnScaleStart)
	
	-- Fade in dimmer
	TweenService:Create(Dimmer, TweenInfo.new(0.3), {BackgroundTransparency = 0.6}):Play()
	playSound(SOUNDS.Equip)
	
	-- Phase 1: Scale up animation
	local scaleUpDuration = EggHatchStats.Effects.SpawnScaleDuration
	local scaleStartTime = tick()
	
	local scaleConnection
	scaleConnection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - scaleStartTime
		local progress = math.min(elapsed / scaleUpDuration, 1)
		
		-- Back ease out for bouncy effect
		local t = 1 - progress
		local overshoot = 1.70158
		local easedProgress = 1 - (t * t * ((overshoot + 1) * t + overshoot))
		
		local currentScale = EggHatchStats.Effects.SpawnScaleStart + 
			(EggHatchStats.Effects.SpawnScaleEnd - EggHatchStats.Effects.SpawnScaleStart) * easedProgress
		scaleEggModel(eggModel, currentScale)
		
		if progress >= 1 then
			scaleConnection:Disconnect()
			
			-- Phase 2: Shake animation
			local hatchTime = EggHatchStats.HatchTime
			local shakeStartTime = tick()
			
			local shakeConnection
			shakeConnection = RunService.RenderStepped:Connect(function()
				local shakeElapsed = tick() - shakeStartTime
				local shakeProgress = math.min(shakeElapsed / hatchTime, 1)
				
				-- Apply shake
				applyEggShake(eggModel, primaryPart, shakeElapsed, shakeProgress)
				
				-- Random crack sounds
				if math.random() < EggHatchStats.Sounds.CrackProbability then
					playSound(SOUNDS.Crack)
				end
				
				if shakeProgress >= 1 then
					shakeConnection:Disconnect()
					
					-- Phase 3: Hatch complete - explosion and reveal
					playSound(SOUNDS.Explode)
					playSound(SOUNDS.Tada)
					
					-- Flash
					if Flash then
						Flash.BackgroundTransparency = 0
						TweenService:Create(Flash, TweenInfo.new(EggHatchStats.Effects.FlashDuration), {BackgroundTransparency = 1}):Play()
					end
					
					-- Remove egg
					eggModel:Destroy()
					
					-- Now the server request happens - the pet reveal will be handled separately
					-- For now, we'll just fade out after the flash
					task.delay(EggHatchStats.Effects.ResultDisplayTime, function()
						-- Fade out
						TweenService:Create(Dimmer, TweenInfo.new(EggHatchStats.Effects.FadeOutDuration), {BackgroundTransparency = 1}):Play()
						
						task.delay(EggHatchStats.Effects.FadeOutDuration, function()
							ScreenGui.Enabled = false
							isHatching = false
							
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

--[[
	Request egg purchase from server after animation completes
]]
local function requestEggPurchase(eggType: string)
	if not EggService then
		warn("[EggController] EggService not available")
		return
	end
	
	local success, errorMsg, petInfo = EggService:RequestPurchaseEgg(eggType)
	if success and petInfo then
		print("[EggController] Successfully obtained: " .. petInfo.Name)
	else
		warn("[EggController] Failed to purchase egg: " .. (errorMsg or "Unknown error"))
	end
end

--[[
	Start the egg hatching process
	This plays the animation first, then requests the purchase from the server
]]
local function StartEggHatch(eggName: string, eggType: string)
	PlayEggHatchAnimation(eggName, function(animationSuccess)
		if animationSuccess then
			-- Request the actual egg purchase from the server
			requestEggPurchase(eggType)
		end
	end)
end

-- Scan for nearby egg stands and show UI
local function scan()
	local char = player.Character
	if not char then return end
	
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	
	local closest, closestDist = nil, 15
	local allStands = {}
	
	for _, f in pairs(workspace:GetChildren()) do
		if f.Name:find("EggShop_Stands") then
			for _, s in pairs(f:GetChildren()) do
				table.insert(allStands, s)
			end
		end
	end
	
	for _, stand in ipairs(allStands) do
		local rootPart = stand:FindFirstChild("EggRoot")
		if rootPart then
			local dist = (rootPart.Position - root.Position).Magnitude
			local ui = rootPart:FindFirstChild("UI_HatchBoard")
			if ui then
				if dist <= 15 then
					ui.Enabled = true
					if dist < closestDist then
						closestDist = dist
						closest = stand
					end
					
					local btn = ui.Container.MainBoard.ActionButtons.Btn_Hatch
					if not btn:GetAttribute("Linked") then
						btn:SetAttribute("Linked", true)
						btn.MouseButton1Click:Connect(function()
							if not isHatching then
								-- Get egg type from stand name or attribute
								local eggType = stand:GetAttribute("EggType") or "StandardEgg"
								StartEggHatch(eggType, eggType)
							end
						end)
					end
				else
					ui.Enabled = false
				end
			end
		end
	end
	
	currentClosestStand = closest
end

-- Initialize
task.spawn(function()
	-- Wait for Knit to start
	Knit.OnStart():andThen(function()
		EggService = Knit.GetService("EggService")
		print("[EggController] Connected to EggService")
	end):catch(function(err)
		warn("[EggController] Failed to connect to EggService: " .. tostring(err))
	end)
end)

-- Continuous scan for egg stands
RunService.RenderStepped:Connect(scan)

-- E key to hatch at closest stand
UserInputService.InputBegan:Connect(function(inp, gpe)
	if gpe then return end
	if inp.KeyCode == Enum.KeyCode.E and currentClosestStand and not isHatching then
		local eggType = currentClosestStand:GetAttribute("EggType") or "StandardEgg"
		StartEggHatch(eggType, eggType)
	end
end)

