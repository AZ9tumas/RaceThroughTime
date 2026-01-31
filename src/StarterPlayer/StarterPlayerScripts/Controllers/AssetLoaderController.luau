--[[
	AssetLoaderController
	Handles preloading of critical game assets and synchronizes with server.
	Waits for both assets to be preloaded AND Knit services to be ready before signaling completion.
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
local IsKnitServicesReady = false
local IsAssetPreloadComplete = false

--[[
	Collects all critical game assets for preloading.
	Critical assets include:
	- Worlds: All visual elements (parts, decals, textures, meshes) from the Worlds folder
	- Stars: All visual elements from the Stars folder
	- UI: All images from PlayerGui and StarterGui
	- Assets: All visual and audio elements from ReplicatedStorage/Assets folder
	Returns an array of Instances to pass to ContentProvider:PreloadAsync
]]
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

	-- Collect UI elements from PlayerGui (may not exist immediately)
	local playerGui = Knit.Player:FindFirstChild("PlayerGui")
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
		IsAssetPreloadComplete = true
		return
	end

	LoadedAssets = 0
	LoadingProgress = 0

	-- Use ContentProvider:PreloadAsync with callback for progress tracking
	-- Callback receives (contentId: string, assetFetchStatus: Enum.AssetFetchStatus)
	ContentProvider:PreloadAsync(assets, function(contentId, assetFetchStatus)
		-- Track progress regardless of fetch status (success or failure)
		-- This ensures the progress bar reflects overall completion
		LoadedAssets = LoadedAssets + 1
		LoadingProgress = LoadedAssets / TotalAssets

		-- Log failures for debugging purposes
		if assetFetchStatus ~= Enum.AssetFetchStatus.Success then
			warn(string.format("[AssetLoader]: Failed to load asset %s - Status: %s", tostring(contentId), tostring(assetFetchStatus)))
		end
	end)

	LoadingProgress = 1
	IsAssetPreloadComplete = true
end

-- Try to complete loading if both assets and Knit services are ready
local function TryCompleteLoading()
	if IsAssetPreloadComplete and IsKnitServicesReady then
		IsLoadingComplete = true
		local LoadingScreenController = Knit.GetController("LoadingScreenController")
		if LoadingScreenController then
			LoadingScreenController:SetAssetsReady()
		end
	end
end

-- Get current loading status (0.0 to 1.0)
function AssetLoaderController:GetLoadingStatus(): number
	return LoadingProgress
end

-- Check if loading is complete
function AssetLoaderController:IsComplete(): boolean
	return IsLoadingComplete
end

-- Called by KnitClientInit when all Knit services are ready
function AssetLoaderController:OnKnitServicesReady()
	IsKnitServicesReady = true
	TryCompleteLoading()
end

-- Knit lifecycle
function AssetLoaderController:KnitInit()
	
end

function AssetLoaderController:KnitStart()
	-- Start preloading assets
	task.spawn(function()
		PreloadAssets()
		TryCompleteLoading()
	end)
end

return AssetLoaderController
