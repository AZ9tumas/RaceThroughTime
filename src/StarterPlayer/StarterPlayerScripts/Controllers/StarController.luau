--[[
	StarController
	Handles star spawning and collection on the client side.
	Listens to server signals and manages star instances.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)

local StarController = Knit.CreateController({
	Name = "StarController",
})

-- Private state
local SpawnedStars = {} -- [starId] = StarInstance
local StarAssets = nil
local PlayerStarsFolder = nil

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

	-- Store reference
	SpawnedStars[starInfo.ID] = starClone

	-- Set up touch detection
	local touchParts = {}
	if starClone:IsA("BasePart") then
		table.insert(touchParts, starClone)
	else
		for _, child in starClone:GetDescendants() do
			if child:IsA("BasePart") then
				table.insert(touchParts, child)
			end
		end
	end

	local debounce = false
	for _, part in touchParts do
		part.Touched:Connect(function(hit)
			if debounce then return end

			local character = Knit.Player.Character
			if not character then return end

			-- Check if the hit part belongs to the player's character
			if hit:IsDescendantOf(character) then
				debounce = true

				-- Request collection from server
				local StarService = Knit.GetService("StarService")
				local success = StarService:CollectStar(starInfo.ID)

				if not success then debounce = false end
			end
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
	local star = SpawnedStars[starId]
	if star then
		star:Destroy()
		SpawnedStars[starId] = nil
		Log(string.format("Removed star %s", starId))
		
		-- Show notification for star collection
		local NotificationController = Knit.GetController("NotificationController")
		NotificationController:ShowNotification("Star collected! ⭐ +Fuel", {
			icon = "⭐", sound = "CollectStar", name = "Custom"
		}, 2)
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

	Log("StarController started")
end

return StarController
