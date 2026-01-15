--[[
	PetController
	Handles client-side pet behavior for star collection.
	
	When player is in arena:
	- Pets target nearby stars and move to collect them
	- Each pet targets one star at a time
	
	When player is outside arena or no stars available:
	- Pets return to follow the player
	- Pets face the same direction as the player
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)

local PetController = Knit.CreateController({
	Name = "PetController",
})

-- Constants
local PET_FOLLOW_DISTANCE = 8
local STAR_COLLECTION_DISTANCE = 5
local ARENA_CHECK_INTERVAL = 0.2
local DEFAULT_ROAM_RANGE = 30

-- Private state
local Player = Players.LocalPlayer
local PetService = nil
local IsInArena = false
local LastArenaCheck = 0
local CachedRoamRange = DEFAULT_ROAM_RANGE

-- Pet targets: [petModel] = targetStarID or nil
local PetTargets = {}

-- Debug beams: [petModel] = { Beam, Attachment0, Attachment1 }
local DebugTrails = {}

-- Connection
local UpdateConnection = nil

-- Refresh cached roam range from equipped pets
local function RefreshRoamRange()
	CachedRoamRange = DEFAULT_ROAM_RANGE
	if PetService then
		local pets = PetService:GetPets()
		for _, pet in ipairs(pets) do
			if pet.Equipped and pet.RoamRange then
				CachedRoamRange = math.max(CachedRoamRange, pet.RoamRange)
			end
		end
	end
end

-- Get player's root part
local function GetPlayerRoot(): BasePart?
	local char = Player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

-- Get current world name based on player position
local function GetCurrentWorld(): string
	return Player:GetAttribute("CurrentWorld") or "Main"
end

-- Check if player is inside arena
local function CheckInArena(): boolean
	local root = GetPlayerRoot()
	if not root then return false end
	
	local world = GetCurrentWorld()
	local worldFolder = Workspace:FindFirstChild(world)
	if not worldFolder then return false end
	
	local arena = worldFolder:FindFirstChild("1_Central_Arena")
	if not arena then return false end
	
	local radius = Stats.ArenaRadius[world] or 200
	local dist = math.sqrt((root.Position.X - arena.Position.X)^2 + (root.Position.Z - arena.Position.Z)^2)
	
	return dist <= radius
end

-- Get all pet models from workspace (have PetAlignPosition)
local function GetPetModels(): {Model}
	local pets = {}
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and child.PrimaryPart then
			if child.PrimaryPart:FindFirstChild("PetAlignPosition") then
				table.insert(pets, child)
			end
		end
	end
	return pets
end

-- Get Stars folder
local function GetStarsFolder(): Folder?
	return Workspace:FindFirstChild("Stars")
end

-- Find nearest untargeted star within range
local function FindNearestStar(petPos: Vector3, playerPos: Vector3, roamRange: number): (string?, Vector3?)
	local starsFolder = GetStarsFolder()
	if not starsFolder then return nil, nil end
	
	-- Get already targeted stars (PetTargets maps petModel -> targetStarId)
	local targeted = {}
	for _, targetId in pairs(PetTargets) do
		if targetId and type(targetId) == "string" then
			targeted[targetId] = true
		end
	end
	
	local nearestId, nearestPos = nil, nil
	local nearestDist = math.huge
	
	for _, star in ipairs(starsFolder:GetChildren()) do
		local starPart = star:IsA("BasePart") and star or star:FindFirstChildWhichIsA("BasePart")
		if not starPart then continue end
		
		local starId = star.Name
		if targeted[starId] then continue end
		
		-- Check if within roam range from player
		local distFromPlayer = (starPart.Position - playerPos).Magnitude
		if distFromPlayer > roamRange then continue end
		
		-- Find nearest to pet
		local distFromPet = (starPart.Position - petPos).Magnitude
		if distFromPet < nearestDist then
			nearestDist = distFromPet
			nearestId = starId
			nearestPos = starPart.Position
		end
	end
	
	return nearestId, nearestPos
end

-- Get star position by ID
local function GetStarPosition(starId: string): Vector3?
	local starsFolder = GetStarsFolder()
	if not starsFolder then return nil end
	
	local star = starsFolder:FindFirstChild(starId)
	if not star then return nil end
	
	local starPart = star:IsA("BasePart") and star or star:FindFirstChildWhichIsA("BasePart")
	return starPart and starPart.Position
end

-- Request server to collect star
local function CollectStar(starId: string, petPos: Vector3)
	if PetService then
		PetService:RequestPetCollectStar(starId, petPos)
	end
end

-- Helper to make pet follow player in formation
local function SetPetToFollowPlayer(alignPos: AlignPosition, alignOri: AlignOrientation?, petIndex: number, playerRoot: BasePart)
	local playerPos = playerRoot.Position
	local offset = Vector3.new(
		math.cos(petIndex * math.pi / 2) * PET_FOLLOW_DISTANCE,
		2,
		math.sin(petIndex * math.pi / 2) * PET_FOLLOW_DISTANCE
	)
	alignPos.Position = playerPos + offset
	
	-- Face same direction as player
	if alignOri then
		alignOri.CFrame = playerRoot.CFrame
	end
end

-- Create or update debug beam between pet and targeted star
local function UpdateDebugTrail(petModel: Model, starPart: BasePart?)
	local primaryPart = petModel.PrimaryPart
	if not primaryPart then return end
	
	-- If no star target, remove existing beam
	if not starPart then
		local trailData = DebugTrails[petModel]
		if trailData then
			if trailData.Beam then trailData.Beam:Destroy() end
			if trailData.Attachment0 then trailData.Attachment0:Destroy() end
			if trailData.Attachment1 then trailData.Attachment1:Destroy() end
			DebugTrails[petModel] = nil
		end
		return
	end
	
	-- Create or get beam data
	local trailData = DebugTrails[petModel]
	
	if not trailData then
		-- Create attachment on pet's primary part
		local attachment0 = Instance.new("Attachment")
		attachment0.Name = "DebugBeamAttachment0"
		attachment0.Parent = primaryPart
		
		-- Create attachment on star
		local attachment1 = Instance.new("Attachment")
		attachment1.Name = "DebugBeamAttachment1"
		attachment1.Parent = starPart
		
		-- Create beam between attachments
		local beam = Instance.new("Beam")
		beam.Name = "DebugPetBeam"
		beam.Attachment0 = attachment0
		beam.Attachment1 = attachment1
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 0)) -- Yellow beam
		beam.Transparency = NumberSequence.new(0.3)
		beam.Width0 = 0.5
		beam.Width1 = 0.5
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Parent = primaryPart
		
		trailData = {
			Beam = beam,
			Attachment0 = attachment0,
			Attachment1 = attachment1,
			CurrentStarPart = starPart,
		}
		DebugTrails[petModel] = trailData
	else
		-- Update attachment1 if star changed
		if trailData.CurrentStarPart ~= starPart then
			-- Create new attachment on new star (old one gets destroyed with cleanup)
			if trailData.Attachment1 then
				trailData.Attachment1:Destroy()
			end
			local newAttachment1 = Instance.new("Attachment")
			newAttachment1.Name = "DebugBeamAttachment1"
			newAttachment1.Parent = starPart
			trailData.Attachment1 = newAttachment1
			trailData.Beam.Attachment1 = newAttachment1
			trailData.CurrentStarPart = starPart
		end
	end
end

-- Clear all debug beams for a pet
local function ClearDebugTrail(petModel: Model)
	UpdateDebugTrail(petModel, nil)
end

-- Update single pet
local function UpdatePet(petModel: Model, petIndex: number, playerRoot: BasePart, roamRange: number)
	local primaryPart = petModel.PrimaryPart
	if not primaryPart then return end
	
	local alignPos = primaryPart:FindFirstChild("PetAlignPosition")
	local alignOri = primaryPart:FindFirstChild("PetAlignOrientation")
	if not alignPos then return end
	
	local petPos = primaryPart.Position
	local playerPos = playerRoot.Position
	
	if IsInArena then
		-- Check if we have a target
		local targetId = PetTargets[petModel]
		
		if targetId then
			-- Check if target still exists
			local targetPos = GetStarPosition(targetId)
			
			if targetPos then
				-- Move towards star
				alignPos.Position = targetPos
				
				-- Face the star
				if alignOri then
					local diff = targetPos - petPos
					if diff.Magnitude > 0.1 then
						alignOri.CFrame = CFrame.lookAt(petPos, targetPos)
					end
				end

				-- Update debug trail to star
				local starsFolder = GetStarsFolder()
				if starsFolder then
					local star = starsFolder:FindFirstChild(targetId)
					if star then
						local starPart = star:IsA("BasePart") and star or star:FindFirstChildWhichIsA("BasePart")
						if starPart then
							UpdateDebugTrail(petModel, starPart)
						end
					end
				end
				
				-- Check if close enough to collect
				local dist = (petPos - targetPos).Magnitude
				if dist <= STAR_COLLECTION_DISTANCE then
					CollectStar(targetId, petPos)
					PetTargets[petModel] = nil
					ClearDebugTrail(petModel) -- Clear trail when star collected
				end
			else
				-- Star no longer exists
				PetTargets[petModel] = nil
				ClearDebugTrail(petModel)
			end
		else
			-- Find a new star to target
			local newId, _ = FindNearestStar(petPos, playerPos, roamRange)
			
			if newId then
				PetTargets[petModel] = newId
			else
				-- No stars, follow player
				SetPetToFollowPlayer(alignPos, alignOri, petIndex, playerRoot)
				ClearDebugTrail(petModel)
			end
		end
	else
		-- Not in arena - follow player and face player's direction
		PetTargets[petModel] = nil
		SetPetToFollowPlayer(alignPos, alignOri, petIndex, playerRoot)
		ClearDebugTrail(petModel)
	end
end

-- Main update loop
local function Update()
	-- Check arena status (throttled)
	local now = tick()
	if now - LastArenaCheck >= ARENA_CHECK_INTERVAL then
		LastArenaCheck = now
		local wasInArena = IsInArena
		IsInArena = CheckInArena()
		
		-- Clear targets when leaving arena
		if wasInArena and not IsInArena then
			PetTargets = {}
		end
	end
	
	local playerRoot = GetPlayerRoot()
	if not playerRoot then return end
	
	-- Update each pet using cached roam range
	local petModels = GetPetModels()
	for i, petModel in ipairs(petModels) do
		UpdatePet(petModel, i, playerRoot, CachedRoamRange)
	end
end

-- Knit lifecycle
function PetController:KnitInit()
	-- Nothing needed
end

function PetController:KnitStart()
	PetService = Knit.GetService("PetService")
	
	-- Initialize cached roam range
	RefreshRoamRange()
	
	-- Start update loop (RenderStepped for smoother visual updates)
	UpdateConnection = RunService.RenderStepped:Connect(Update)
	
	-- Listen for pet events
	PetService.PetEquipped:Connect(function()
		-- Clear all debug trails when pets change
		for petModel, _ in pairs(DebugTrails) do
			ClearDebugTrail(petModel)
		end
		PetTargets = {} -- Reset targets when pets change
		RefreshRoamRange() -- Update cached roam range
	end)
	
	PetService.PetUnequipped:Connect(function()
		-- Clear all debug trails when pets change
		for petModel, _ in pairs(DebugTrails) do
			ClearDebugTrail(petModel)
		end
		PetTargets = {}
		RefreshRoamRange()
	end)
end

return PetController
