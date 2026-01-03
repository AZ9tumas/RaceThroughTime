local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local uiInit = require(script.Parent:WaitForChild("InitUI"))

-- Wait for Knit to be started before accessing controllers
Knit.OnStart():andThen(function()
	print("client is ready")
end):catch(function(err)
	warn("[Test]: Failed to get AssetLoaderController -", err)
end)