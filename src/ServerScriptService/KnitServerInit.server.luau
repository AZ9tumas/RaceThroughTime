--[[
	KnitServerInit
	Initializes Knit on the server side.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Knit = require(ReplicatedStorage.Packages.Knit)

-- main Module
local main = require(ServerScriptService.main)

-- Add all services from the Services folder
Knit.AddServices(ServerScriptService.Services)

-- Start Knit
Knit.Start():andThen(function()
	print("[Knit]: Server started successfully")
	main()
end):catch(function(err)
	warn("[Knit]: Server failed to start -", err)
end)
