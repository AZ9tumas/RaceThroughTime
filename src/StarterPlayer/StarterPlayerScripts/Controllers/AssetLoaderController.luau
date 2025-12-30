--[[
	AssetLoaderController
	Handles preloading of critical game assets and synchronizes with server.
]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)

local AssetLoaderController = Knit.CreateController({
	Name = "AssetLoaderController",
})

-- Private state
local LoadingProgress = 0 -- 0.0 to 1.0
local IsLoadingComplete = false
local TotalAssets = 0
local LoadedAssets = 0

-- Collect all critical assets for preloading
local function CollectCriticalAssets(): { Instance }
	local assets = {}

	-- Collect Worlds (if they exist in Workspace or ReplicatedStorage)
	local worldsFolder = Workspace:FindFirstChild("Worlds") or ReplicatedStorage:FindFirstChild("Worlds")
	if worldsFolder then
		for _, world in worldsFolder:GetDescendants() do
			if world:IsA("BasePart") or world:IsA("Decal") or world:IsA("Texture") or world:IsA("MeshPart") then
				table.insert(assets, world)
			end
		end
	end

	-- Collect Stars (if they exist)
	local starsFolder = Workspace:FindFirstChild("Stars") or ReplicatedStorage:FindFirstChild("Stars")
	if starsFolder then
		for _, star in starsFolder:GetDescendants() do
			if star:IsA("BasePart") or star:IsA("Decal") or star:IsA("Texture") or star:IsA("MeshPart") then
				table.insert(assets, star)
			end
		end
	end

	-- Collect UI elements
	local playerGui = Knit.Player:WaitForChild("PlayerGui", 5)
	if playerGui then
		for _, gui in playerGui:GetDescendants() do
			if gui:IsA("ImageLabel") or gui:IsA("ImageButton") then
				table.insert(assets, gui)
			end
		end
	end

	-- Collect from StarterGui
	local starterGui = game:GetService("StarterGui")
	for _, gui in starterGui:GetDescendants() do
		if gui:IsA("ImageLabel") or gui:IsA("ImageButton") then
			table.insert(assets, gui)
		end
	end

	-- Collect any game assets in ReplicatedStorage
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if assetsFolder then
		for _, asset in assetsFolder:GetDescendants() do
			if asset:IsA("BasePart") or asset:IsA("Decal") or asset:IsA("Texture") or 
			   asset:IsA("MeshPart") or asset:IsA("Sound") or asset:IsA("Animation") then
				table.insert(assets, asset)
			end
		end
	end

	return assets
end

-- Preload assets with progress tracking
local function PreloadAssets()
	local assets = CollectCriticalAssets()
	TotalAssets = #assets

	if TotalAssets == 0 then
		-- No assets to preload
		LoadingProgress = 1
		IsLoadingComplete = true
		return
	end

	LoadedAssets = 0
	LoadingProgress = 0

	-- Use ContentProvider:PreloadAsync with callback for progress
	ContentProvider:PreloadAsync(assets, function(assetId, assetFetchStatus)
		LoadedAssets = LoadedAssets + 1
		LoadingProgress = LoadedAssets / TotalAssets
	end)

	LoadingProgress = 1
	IsLoadingComplete = true
end

-- Get current loading status (0.0 to 1.0)
function AssetLoaderController:GetLoadingStatus(): number
	return LoadingProgress
end

-- Check if loading is complete
function AssetLoaderController:IsComplete(): boolean
	return IsLoadingComplete
end

-- Knit lifecycle
function AssetLoaderController:KnitInit()
	-- Nothing to initialize
end

function AssetLoaderController:KnitStart()
	-- Start preloading assets
	task.spawn(function()
		PreloadAssets()

		-- Signal the server that we're ready
		local DataService = Knit.GetService("DataService")
		DataService:SignalReady()
	end)
end

return AssetLoaderController
