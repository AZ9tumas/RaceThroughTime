--[[
	KnitServerInit
	Initializes Knit on the server side.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Knit = require(ReplicatedStorage.Packages.Knit)

-- Add all services from the Services folder
Knit.AddServices(ServerScriptService.Services)

-- Start Knit
Knit.Start():andThen(function()
	print("[Knit]: Server started successfully")
end):catch(function(err)
	warn("[Knit]: Server failed to start -", err)
end)
