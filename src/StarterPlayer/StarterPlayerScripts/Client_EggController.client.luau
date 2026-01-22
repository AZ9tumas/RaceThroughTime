local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local ScreenGui = PlayerGui:WaitForChild("EggHatchScreen")
local Viewport = ScreenGui.Viewport
local Rays = ScreenGui.Sunburst
local Flash = ScreenGui.Flash
local RarityText = ScreenGui.RarityText
local Dimmer = ScreenGui.Dimmer

local isHatching = false
local currentClosestStand = nil

local SOUNDS = {
	Click   = "rbxassetid://6042054019",
	Equip   = "rbxassetid://244655616",
	Crack   = "rbxassetid://4819098925",
	Explode = "rbxassetid://2801263161",
	Tada    = "rbxassetid://6042054019",
}

local RARITY = {
	Common    = { Color = Color3.fromRGB(200, 200, 200), Chance = 0.50 },
	Uncommon  = { Color = Color3.fromRGB(50, 255, 100),  Chance = 0.30 },
	Rare      = { Color = Color3.fromRGB(0, 150, 255),   Chance = 0.15 },
	Epic      = { Color = Color3.fromRGB(170, 0, 255),   Chance = 0.04 },
	Legendary = { Color = Color3.fromRGB(255, 170, 0),   Chance = 0.01 }
}

local function playSound(id)
	local s = Instance.new("Sound", workspace)
	s.SoundId = id; s.Volume = 2; s.PlayOnRemove = true; s:Destroy()
end

local function buildPetModel(color)
	local model = Instance.new("Model")
	local body = Instance.new("Part", model)
	body.Name = "Body"
	body.Size = Vector3.new(2,2,2); body.Color = color; body.Material = Enum.Material.Neon; body.Anchored = true
	local face = Instance.new("Decal", body); face.Texture = "rbxassetid://14407565945"; face.Face = Enum.NormalId.Front
	local ear1 = Instance.new("Part", model); ear1.Name="Ear"; ear1.Size = Vector3.new(0.6,0.8,0.5); ear1.Color = color; ear1.Material = Enum.Material.Plastic; ear1.Anchored=true
	local ear2 = ear1:Clone(); ear2.Parent = model
	
	body.Position = Vector3.new(0,0,0)
	ear1.Position = Vector3.new(-0.8, 1.2, 0)
	ear2.Position = Vector3.new(0.8, 1.2, 0)
	
	return model
end

local function PlayScreenHatch(eggColor)
	if isHatching then return end
	isHatching = true
	
	Viewport:ClearAllChildren()
	ScreenGui.Enabled = true
	Flash.BackgroundTransparency = 1
	RarityText.TextTransparency = 1
	Rays.ImageTransparency = 1
	Dimmer.BackgroundTransparency = 1
	
	local egg = Instance.new("Part", Viewport)
	egg.Shape = Enum.PartType.Ball; egg.Material = Enum.Material.Plastic; egg.Color = eggColor
	egg.Size = Vector3.new(0,0,0); egg.Position = Vector3.new(0,0,0); egg.Anchored = true
	
	playSound(SOUNDS.Equip)
	TweenService:Create(Dimmer, TweenInfo.new(0.5), {BackgroundTransparency = 0.6}):Play()
	TweenService:Create(egg, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = Vector3.new(4,5,4)}):Play()
	wait(0.6)
	
	local start = tick()
	local shakeDur = 1.8
	local baseSize = Vector3.new(4,5,4)
	
	while tick() - start < shakeDur do
		local elapsed = tick() - start
		local intensity = 0.5 + (elapsed * 3)
		local rx = math.sin(tick() * 30) * intensity
		local rz = math.cos(tick() * 25) * intensity
		local sy = 1 + (math.sin(tick() * 20) * (0.1 * elapsed))
		local sxz = 1 / math.sqrt(sy)
		
		egg.Size = baseSize * Vector3.new(sxz, sy, sxz)
		egg.CFrame = CFrame.new(0,0,0) * CFrame.Angles(math.rad(rx), 0, math.rad(rz))
		
		if math.random() > 0.9 then playSound(SOUNDS.Crack) end
		RunService.RenderStepped:Wait()
	end
	
	local rng = math.random(); local result = RARITY.Common; local name = "Common"
	if rng < RARITY.Legendary.Chance then result = RARITY.Legendary; name="LEGENDARY!"
	elseif rng < RARITY.Epic.Chance then result = RARITY.Epic; name="EPIC!"
	elseif rng < RARITY.Rare.Chance then result = RARITY.Rare; name="Rare"
	elseif rng < RARITY.Uncommon.Chance then result = RARITY.Uncommon; name="Uncommon" end
	
	playSound(SOUNDS.Explode); playSound(SOUNDS.Tada)
	
	TweenService:Create(Flash, TweenInfo.new(0.1), {BackgroundTransparency = 0}):Play()
	egg:Destroy()
	wait(0.1)
	TweenService:Create(Flash, TweenInfo.new(0.5), {BackgroundTransparency = 1}):Play()
	
	local pet = buildPetModel(result.Color)
	pet.Parent = Viewport
	local primary = pet:WaitForChild("Body")
	
	for _, p in pairs(pet:GetChildren()) do p.Transparency = 0; p.Size = p.Size * 0.1 end
	
	for _, p in pairs(pet:GetChildren()) do
		local tSize = (p.Name == "Body" and Vector3.new(2,2,2) or Vector3.new(0.6,0.8,0.5))
		local tPos = (p.Name == "Body" and Vector3.new(0,0,0) or (p.Position.X < 0 and Vector3.new(-0.8,1.2,0) or Vector3.new(0.8,1.2,0)))
		TweenService:Create(p, TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {Size=tSize, Position=tPos}):Play()
	end
	
	Rays.ImageColor3 = result.Color
	RarityText.Text = name
	RarityText.TextColor3 = result.Color
	
	TweenService:Create(Rays, TweenInfo.new(0.5), {ImageTransparency = 0.2}):Play()
	TweenService:Create(RarityText, TweenInfo.new(0.5, Enum.EasingStyle.Bounce), {TextTransparency = 0}):Play()
	
	local spin = true
	task.spawn(function()
		while spin do
			Rays.Rotation = Rays.Rotation + 0.5
			if primary then primary.CFrame = primary.CFrame * CFrame.Angles(0, math.rad(1), 0) end
			RunService.RenderStepped:Wait()
		end
	end)
	
	wait(2.5)
	
	spin = false
	TweenService:Create(Dimmer, TweenInfo.new(0.5), {BackgroundTransparency = 1}):Play()
	TweenService:Create(Rays, TweenInfo.new(0.5), {ImageTransparency = 1}):Play()
	TweenService:Create(RarityText, TweenInfo.new(0.5), {TextTransparency = 1}):Play()
	
	for _, p in pairs(pet:GetChildren()) do TweenService:Create(p, TweenInfo.new(0.3), {Size = Vector3.new(0,0,0)}):Play() end
	wait(0.3)
	
	ScreenGui.Enabled = false
	isHatching = false
end

local function scan()
	local char = player.Character; if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart"); if not root then return end
	
	local closest, closestDist = nil, 15
	local allStands = {}
	for _, f in pairs(workspace:GetChildren()) do
		if f.Name:find("EggShop_Stands") then
			for _, s in pairs(f:GetChildren()) do table.insert(allStands, s) end
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
					if dist < closestDist then closestDist = dist; closest = stand end
					
					local btn = ui.Container.MainBoard.ActionButtons.Btn_Hatch
					if not btn:GetAttribute("Linked") then
						btn:SetAttribute("Linked", true)
						btn.MouseButton1Click:Connect(function() PlayScreenHatch(rootPart.Color) end)
					end
				else
					ui.Enabled = false
				end
			end
		end
	end
	currentClosestStand = closest
end

RunService.RenderStepped:Connect(scan)

UserInputService.InputBegan:Connect(function(inp, gpe)
	if gpe then return end
	if inp.KeyCode == Enum.KeyCode.E and currentClosestStand and not isHatching then
		local root = currentClosestStand:FindFirstChild("EggRoot")
		if root then PlayScreenHatch(root.Color) end
	end
end)
