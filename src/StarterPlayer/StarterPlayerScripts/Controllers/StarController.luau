local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local StarAnimations = require(ReplicatedStorage.Modules.StarAnimations)
local Stats = require(ReplicatedStorage.Modules.Stats)

local StarController = Knit.CreateController({
	Name = "StarController",
})

-- Private state
local SpawnedStars = {} -- [starId] = { Instance: StarInstance, Position: Vector3 }
local StarAssets = nil
local PlayerStarsFolder = nil
local ProximityCheckConnection = nil -- RenderStep connection for proximity checking
local CollectionDebounce = {} -- [starId] = true (prevents double collection)

-- Helper function for logging
local function Log(message: string)
	--print(string.format("[StarController]: %s", message))
end

-- Get or create the Stars folder in Workspace
local function GetStarsFolder(): Folder
	if PlayerStarsFolder then
		return PlayerStarsFolder
	end

	PlayerStarsFolder = Workspace:WaitForChild("Stars", 10)
	if not PlayerStarsFolder then
		warn("[StarController]: Stars folder not found in Workspace")
		return nil
	end

	return PlayerStarsFolder
end

-- Get the star assets folder from ReplicatedStorage
local function GetStarAssets(): Folder?
	if StarAssets then
		return StarAssets
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		warn("[StarController]: Assets folder not found in ReplicatedStorage")
		return nil
	end

	StarAssets = assets:FindFirstChild("Stars")
	if not StarAssets then
		warn("[StarController]: Stars folder not found in Assets")
		return nil
	end

	return StarAssets
end

-- Spawn a single star at the given position
local function SpawnStar(starInfo: { Position: Vector3, ID: string, StarName: string, FuelValue: number, Index: number })
	local starsFolder = GetStarsFolder()
	if not starsFolder then
		return
	end

	local starAssets = GetStarAssets()
	if not starAssets then
		return
	end

	local starTemplate = starAssets:FindFirstChild(starInfo.StarName)
	if not starTemplate then
		warn(string.format("[StarController]: Star template '%s' not found", starInfo.StarName))
		return
	end

	-- Clone and position the star
	local starClone = starTemplate:Clone()
	starClone.Name = starInfo.ID
	
	-- Set the position based on star type (Part or Model)
	if starClone:IsA("BasePart") then
		starClone.Position = starInfo.Position
		starClone.Anchored = true
		starClone.CanCollide = false
	elseif starClone:IsA("Model") then
		local primaryPart = starClone.PrimaryPart or starClone:FindFirstChildWhichIsA("BasePart")
		if primaryPart then
			starClone:PivotTo(CFrame.new(starInfo.Position))
		end
	end

	starClone.Parent = starsFolder

	-- Store reference with position for proximity checking
	SpawnedStars[starInfo.ID] = {
		Instance = starClone,
		Position = starInfo.Position,
	}
	
	-- Start star animations (pulsing and jumping)
	StarAnimations.StartAnimations(starClone)
end

-- Handle star spawn signal from server
local function OnSpawnStars(starInfoList: { { Position: Vector3, ID: string, StarName: string, FuelValue: number, Index: number } })
	Log(string.format("Received %d stars to spawn", #starInfoList))

	for _, starInfo in ipairs(starInfoList) do
		task.spawn(function()
			SpawnStar(starInfo)
		end)
	end
end

-- Handle star removal signal from server
local function OnRemoveStar(starId: string)
	local starData = SpawnedStars[starId]
	if starData then
		-- Stop animations before destroying
		StarAnimations.StopAnimations(starData.Instance)
		starData.Instance:Destroy()
		SpawnedStars[starId] = nil
		CollectionDebounce[starId] = nil
		Log(string.format("Removed star %s", starId))
	end
end

-- Handle remove all stars signal from server
local function OnRemoveAllStars()
	Log("Removing all stars")
	for starId, _ in pairs(SpawnedStars) do
		OnRemoveStar(starId)
	end
	table.clear(SpawnedStars)
	table.clear(CollectionDebounce)
end

-- Check proximity to stars and collect if within range
local function CheckProximityCollection()
	local character = Knit.Player.Character
	if not character then return end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	
	local playerPosition = rootPart.Position
	local collectionRadius = Stats.StarCollectionPlayerRadius
	
	-- Check each star for proximity
	for starId, starData in pairs(SpawnedStars) do
		if CollectionDebounce[starId] then continue end
		
		local distance = (playerPosition - starData.Position).Magnitude
		if distance <= collectionRadius then
			-- Mark as being collected to prevent double collection
			CollectionDebounce[starId] = true
			
			-- Request collection from server
			task.spawn(function()
				local StarService = Knit.GetService("StarService")
				local success = StarService:CollectStar(starId)
				
				if not success then
					CollectionDebounce[starId] = nil
				end
			end)
		end
	end
end

-- Knit lifecycle
function StarController:KnitInit()
	-- Pre-cache assets folder reference
	GetStarAssets()
end

function StarController:KnitStart()
	-- Listen for server signals
	local StarService = Knit.GetService("StarService")

	StarService.SpawnStars:Connect(OnSpawnStars)
	StarService.RemoveStar:Connect(OnRemoveStar)
	StarService.RemoveAllStars:Connect(OnRemoveAllStars)

	-- Start proximity checking loop using Heartbeat (runs every frame)
	ProximityCheckConnection = RunService.Heartbeat:Connect(CheckProximityCollection)

	Log("StarController started")
end

return StarController
