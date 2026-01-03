local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Knit = require(ReplicatedStorage.Packages.Knit)

-- Wait for Knit to be started before accessing controllers
Knit.OnStart():andThen(function()
	local assetLoader = Knit.GetController("AssetLoaderController")
	print("client is ready")
end):catch(function(err)
	warn("[Test]: Failed to get AssetLoaderController -", err)
end)