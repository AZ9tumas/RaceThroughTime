local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local StarAnimations = require(ReplicatedStorage.Modules.StarAnimations)
local Stats = require(ReplicatedStorage.Modules.Stats)

-- Collection effect constants
local COLLECTION_EFFECT_DURATION = 0.25 -- seconds for star to fly to player
local COLLECTION_EFFECT_TWEEN_INFO = TweenInfo.new(
	COLLECTION_EFFECT_DURATION,
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.In
)

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
		-- Still track the star for collection even without visual
		SpawnedStars[starInfo.ID] = {
			Instance = nil,
			Position = starInfo.Position,
		}
		return
	end

	local starAssets = GetStarAssets()
	if not starAssets then
		-- Still track the star for collection even without visual
		SpawnedStars[starInfo.ID] = {
			Instance = nil,
			Position = starInfo.Position,
		}
		return
	end

	local starTemplate = starAssets:FindFirstChild(starInfo.StarName)
	if not starTemplate then
		warn(string.format("[StarController]: Star template '%s' not found", starInfo.StarName))
		-- Still track the star for collection even without visual
		SpawnedStars[starInfo.ID] = {
			Instance = nil,
			Position = starInfo.Position,
		}
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

-- Play collection effect: star flies towards player
-- This is fail-proof - if instance doesn't exist or player moves, it still works
local function PlayCollectionEffect(starId: string)
	local starData = SpawnedStars[starId]
	if not starData or not starData.Instance then
		return -- No visual to animate
	end
	
	local character = Knit.Player.Character
	if not character then return end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	
	local starInstance = starData.Instance
	
	-- Stop the normal animations so they don't interfere
	StarAnimations.StopAnimations(starInstance)
	
	-- Get target position (slightly in front of player chest)
	local targetPosition = rootPart.Position + Vector3.new(0, 1, 0)
	
	-- Create the tween based on instance type
	local tween
	if starInstance:IsA("BasePart") then
		-- Scale down and move to player
		tween = TweenService:Create(starInstance, COLLECTION_EFFECT_TWEEN_INFO, {
			Position = targetPosition,
			Size = starInstance.Size * 0.3, -- Shrink as it approaches
			Transparency = 0.5
		})
	elseif starInstance:IsA("Model") then
		-- For models, we need to move the primary part or use PivotTo in a loop
		local primaryPart = starInstance.PrimaryPart or starInstance:FindFirstChildWhichIsA("BasePart")
		if primaryPart then
			tween = TweenService:Create(primaryPart, COLLECTION_EFFECT_TWEEN_INFO, {
				Position = targetPosition,
				Size = primaryPart.Size * 0.3,
				Transparency = 0.5
			})
		end
	end
	
	if tween then
		-- Play tween in protected call to handle if instance gets destroyed mid-tween
		pcall(function()
			tween:Play()
		end)
	end
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
		-- Stop animations and destroy if instance exists
		if starData.Instance then
			StarAnimations.StopAnimations(starData.Instance)
			starData.Instance:Destroy()
		end
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
	local collectionRadius = Stats.MinStarCollectionPlayerRadius
	
	-- Check each star for proximity
	for starId, starData in pairs(SpawnedStars) do
		if CollectionDebounce[starId] then continue end
		
		local distance = (playerPosition - starData.Position).Magnitude
		if distance <= collectionRadius then
			-- Mark as being collected to prevent double collection
			CollectionDebounce[starId] = true
			
			-- Play collection effect immediately (star flies to player)
			PlayCollectionEffect(starId)
			
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
