--[[
	PetController
	Handles client-side pet position updates for ALL players in the same world.
	
	For all players in the same world as the local player:
	- Pets follow their owner in formation
	- Pets face the same direction as their owner
	
	For the local player ONLY (when in arena):
	- Pets target nearby stars and move to collect them
	- Each pet targets one star at a time
	
	Pet Object Structure:
	petObj = {
		Player: Player,        -- Owner player
		PetParams: {...},      -- Pet data (ID, Name, Multiplier, RoamRange, etc.)
		PetModel: Model,       -- The pet model in workspace
	}
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
local ARENA_CHECK_INTERVAL = 0.2

-- Private state
local Player = Players.LocalPlayer
local PetService = nil
local IsInArena = false
local LastArenaCheck = 0

-- Pet objects: [PetModel] = petObj
local PetObjects = {}

-- Pet targets for local player's pets: [PetModel] = targetStarID or nil
local PetTargets = {}

-- Debug beams: [PetModel] = { Beam, Attachment0, Attachment1, CurrentStarPart }
local DebugBeams = {}

-- Connection
local UpdateConnection = nil

-- Get player's root part
local function GetPlayerRoot(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

-- Get current world name for a player
local function GetCurrentWorld(player: Player): string
	repeat
		task.wait()
	until player:GetAttribute("CurrentWorld") ~= nil
	return player:GetAttribute("CurrentWorld")
end

-- Check if local player is inside arena
local function CheckInArena(): boolean
	local root = GetPlayerRoot(Player)
	if not root then return false end
	
	local world = GetCurrentWorld(Player)
	local worldFolder = Workspace:FindFirstChild(world)
	if not worldFolder then return false end
	
	local arena = worldFolder:FindFirstChild("1_Central_Arena")
	if not arena then return false end
	
	local radius = Stats.ArenaRadius[world] or 200
	local dist = math.sqrt((root.Position.X - arena.Position.X)^2 + (root.Position.Z - arena.Position.Z)^2)
	
	return dist <= radius
end

-- Get Stars folder
local function GetStarsFolder(): Folder?
	return Workspace:FindFirstChild("Stars")
end

-- Find all pet models in workspace
local function FindAllPetModels(): {Model}
	local pets = {}
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and child.PrimaryPart then
			if child.PrimaryPart:FindFirstChild("PetAlignPosition") and child:GetAttribute("OwnerUserId") then
				table.insert(pets, child)
			end
		end
	end
	return pets
end

-- Build or update pet objects from workspace
local function RefreshPetObjects()
	local localWorld = GetCurrentWorld(Player)
	local petModels = FindAllPetModels()
	
	-- Build set of current models
	local currentModels = {}
	for _, model in ipairs(petModels) do
		currentModels[model] = true
	end
	
	-- Remove pet objects for models that no longer exist
	for model, _ in pairs(PetObjects) do
		if not currentModels[model] or not model.Parent then
			PetObjects[model] = nil
			PetTargets[model] = nil
			-- Clean up debug beam
			if DebugBeams[model] then
				if DebugBeams[model].Beam then DebugBeams[model].Beam:Destroy() end
				if DebugBeams[model].Attachment0 then DebugBeams[model].Attachment0:Destroy() end
				if DebugBeams[model].Attachment1 then DebugBeams[model].Attachment1:Destroy() end
				DebugBeams[model] = nil
			end
		end
	end
	
	-- Add/update pet objects for current models
	for _, model in ipairs(petModels) do
		local ownerUserId = model:GetAttribute("OwnerUserId")
		local owner = Players:GetPlayerByUserId(ownerUserId)
		
		if owner then
			local ownerWorld = GetCurrentWorld(owner)
			
			-- Only track pets from players in the same world
			if ownerWorld == localWorld then
				if not PetObjects[model] then
					-- Create new pet object
					print(model)
					PetObjects[model] = {
						Player = owner,
						PetParams = {
							ID = model:GetAttribute("PetID") or "",
							Name = model:GetAttribute("PetName") or "Pet",
							PetType = model:GetAttribute("PetType") or "StandardPet",
							Multiplier = model:GetAttribute("Multiplier") or 1.0,
							RoamRange = model:GetAttribute("RoamRange"),
							StarCollectionRadius = model:GetAttribute("StarCollectionRadius") or 5,
							PetIndex = model:GetAttribute("PetIndex") or 1,
						},
						PetModel = model,
					}
				end
			else
				-- Remove pets from different worlds
				PetObjects[model] = nil
				PetTargets[model] = nil
			end
		end
	end
end

-- Find nearest untargeted star within range for local player's pet
local function FindNearestStar(petPos: Vector3, playerPos: Vector3, roamRange: number): (string?, Vector3?)
	local starsFolder = GetStarsFolder()
	if not starsFolder then return nil, nil end
	
	-- Get already targeted stars
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

-- Update debug beam between pet and targeted star
local function UpdateDebugBeam(petModel: Model, starPart: BasePart?)
	local primaryPart = petModel.PrimaryPart
	if not primaryPart then return end
	
	-- If no star target, remove existing beam
	if not starPart then
		local beamData = DebugBeams[petModel]
		if beamData then
			if beamData.Beam then beamData.Beam:Destroy() end
			if beamData.Attachment0 then beamData.Attachment0:Destroy() end
			if beamData.Attachment1 then beamData.Attachment1:Destroy() end
			DebugBeams[petModel] = nil
		end
		return
	end
	
	local beamData = DebugBeams[petModel]
	
	if not beamData then
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
		
		DebugBeams[petModel] = {
			Beam = beam,
			Attachment0 = attachment0,
			Attachment1 = attachment1,
			CurrentStarPart = starPart,
		}
	else
		-- Update attachment1 if star changed
		if beamData.CurrentStarPart ~= starPart then
			if beamData.Attachment1 then
				beamData.Attachment1:Destroy()
			end
			local newAttachment1 = Instance.new("Attachment")
			newAttachment1.Name = "DebugBeamAttachment1"
			newAttachment1.Parent = starPart
			beamData.Attachment1 = newAttachment1
			beamData.Beam.Attachment1 = newAttachment1
			beamData.CurrentStarPart = starPart
		end
	end
end

-- Clear debug beam for a pet
local function ClearDebugBeam(petModel: Model)
	UpdateDebugBeam(petModel, nil)
end

-- Set pet to follow player in formation
local function SetPetToFollowPlayer(petModel: Model, petIndex: number, ownerRoot: BasePart, isLocalPlayer: boolean)
	local primaryPart = petModel.PrimaryPart
	if not primaryPart then return end
	
	local alignPos = primaryPart:FindFirstChild("PetAlignPosition")
	local alignOri = primaryPart:FindFirstChild("PetAlignOrientation")
	if not alignPos then return end
	
	local offset = Vector3.new(
		math.cos(petIndex * math.pi / 2) * PET_FOLLOW_DISTANCE,
		2,
		math.sin(petIndex * math.pi / 2) * PET_FOLLOW_DISTANCE
	)
	alignPos.Position = ownerRoot.Position + offset
	
	-- Face same direction as owner
	if alignOri then
		alignOri.CFrame = ownerRoot.CFrame
	end
	
	-- Update debug beam to target player's HumanoidRootPart (only for local player's pets)
	if isLocalPlayer then
		UpdateDebugBeam(petModel, ownerRoot)
	end
end

-- Update a single pet
local function UpdatePet(petObj: {Player: Player, PetParams: any, PetModel: Model})
	local owner = petObj.Player
	local petModel = petObj.PetModel
	local petParams = petObj.PetParams
	
	if not petModel or not petModel.PrimaryPart or not petModel.Parent then
		return
	end
	
	local ownerRoot = GetPlayerRoot(owner)
	if not ownerRoot then return end
	
	local primaryPart = petModel.PrimaryPart
	local alignPos = primaryPart:FindFirstChild("PetAlignPosition")
	local alignOri = primaryPart:FindFirstChild("PetAlignOrientation")
	if not alignPos then return end
	
	local isLocalPlayer = owner == Player
	local petIndex = petParams.PetIndex or 1
	
	-- For non-local players: always follow owner
	if not isLocalPlayer then
		SetPetToFollowPlayer(petModel, petIndex, ownerRoot, false)
		return
	end
	
	-- For local player: handle star collection when in arena
	local petPos = primaryPart.Position
	local playerPos = ownerRoot.Position
	local roamRange = petParams.RoamRange or 150
	
	if IsInArena then
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
				
				-- Update debug beam
				local starsFolder = GetStarsFolder()
				if starsFolder then
					local star = starsFolder:FindFirstChild(targetId)
					if star then
						local starPart = star:IsA("BasePart") and star or star:FindFirstChildWhichIsA("BasePart")
						if starPart then
							UpdateDebugBeam(petModel, starPart)
						end
					end
				end
				
				-- Check if close enough to collect (use per-pet StarCollectionRadius)
				local dist = (petPos - targetPos).Magnitude
				local starCollectionRadius = petParams.StarCollectionRadius or 5
				if dist <= starCollectionRadius then
					CollectStar(targetId, petPos)
					PetTargets[petModel] = nil
					ClearDebugBeam(petModel)
				end
			else
				-- Star no longer exists
				PetTargets[petModel] = nil
				ClearDebugBeam(petModel)
			end
		else
			-- Find a new star to target
			local newId, _ = FindNearestStar(petPos, playerPos, roamRange)
			
			if newId then
				PetTargets[petModel] = newId
			else
				-- No stars available, follow player (beam targets player)
				SetPetToFollowPlayer(petModel, petIndex, ownerRoot, true)
			end
		end
	else
		-- Not in arena - follow player (beam targets player)
		PetTargets[petModel] = nil
		SetPetToFollowPlayer(petModel, petIndex, ownerRoot, true)
	end
end

-- Main update loop
local function Update()
	-- Refresh pet objects periodically
	RefreshPetObjects()
	
	-- Check arena status (throttled)
	local now = tick()
	if now - LastArenaCheck >= ARENA_CHECK_INTERVAL then
		LastArenaCheck = now
		local wasInArena = IsInArena
		IsInArena = CheckInArena()
		
		-- Clear targets when leaving arena
		if wasInArena and not IsInArena then
			PetTargets = {}
			-- Clear all debug beams
			for petModel, _ in pairs(DebugBeams) do
				ClearDebugBeam(petModel)
			end
		end
	end
	
	-- Update all pets
	for _, petObj in pairs(PetObjects) do
		UpdatePet(petObj)
	end
end

-- Handle player added (to track world changes)
local function OnPlayerAdded(player: Player)
	-- Listen for world changes
	player:GetAttributeChangedSignal("CurrentWorld"):Connect(function()
		-- Refresh pet objects when any player changes world
		RefreshPetObjects()
	end)
end

-- Handle player removing
local function OnPlayerRemoving(player: Player)
	-- Clean up pets for this player
	for model, petObj in pairs(PetObjects) do
		if petObj.Player == player then
			PetObjects[model] = nil
			PetTargets[model] = nil
			ClearDebugBeam(model)
		end
	end
end

-- Knit lifecycle
function PetController:KnitInit()
	-- Nothing needed
end

function PetController:KnitStart()
	PetService = Knit.GetService("PetService")
	
	-- Initial pet refresh
	RefreshPetObjects()
	
	-- Start update loop (RenderStepped for smooth visual updates)
	RunService:BindToRenderStep("PetControllerUpdate", Enum.RenderPriority.Character.Value + 1, Update)
	
	-- Listen for player events
	for _, player in ipairs(Players:GetPlayers()) do
		OnPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(OnPlayerAdded)
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
	
	-- Listen for pet events (to refresh pet objects)
	PetService.PetEquipped:Connect(function()
		RefreshPetObjects()
		PetTargets = {} -- Reset targets when pets change
	end)
	
	PetService.PetUnequipped:Connect(function()
		RefreshPetObjects()
		PetTargets = {}
		-- Clear all debug beams
		for petModel, _ in pairs(DebugBeams) do
			ClearDebugBeam(petModel)
		end
	end)
end

return PetController
