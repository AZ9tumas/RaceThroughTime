--[[
	LeaderboardController
	Client-side controller that displays leaderboard data on SurfaceGuis
	attached to parts in each world's Leaderboards_Zone folder.
	
	Each world folder has a "Leaderboards_Zone" folder with three parts:
	- Cash
	- Distance
	- Rebirth
	
	On DataReady or world change, this controller:
	1. Finds the current world's Leaderboards_Zone folder
	2. Clears existing children on each part
	3. Clones the LeaderboardUI SurfaceGui from PlayerGui onto each part
	4. Fetches leaderboard data from LeaderboardService
	5. Populates the ScrollingFrame with cloned Template labels
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

local LeaderboardController = Knit.CreateController({
	Name = "LeaderboardController",
})

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local LeaderboardService = nil
local DataService = nil

-- Map of part name to server fetch method and display title
local LeaderboardConfig = {
	Cash = {
		FetchMethod = "GetTopCash",
		Title = "Top Cash",
	},
	Distance = {
		FetchMethod = "GetTopDistance",
		Title = "Top Distance",
	},
	Rebirth = {
		FetchMethod = "GetTopRebirths",
		Title = "Top Rebirths",
	},
}

--[[
	Clear all children of a part (removes existing SurfaceGuis).
	
	@param part BasePart - The part to clear
]]
local function ClearPartChildren(part: BasePart)
	part:ClearAllChildren()
end

--[[
	Populate a leaderboard SurfaceGui with entries from the server.
	
	@param surfaceGui SurfaceGui - The cloned SurfaceGui to populate
	@param entries { { UserId: number, Name: string, Value: number } } - Leaderboard entries
]]
local function PopulateLeaderboard(surfaceGui: SurfaceGui, entries: { { UserId: number, Name: string, Value: number } })
	local frame = surfaceGui:FindFirstChild("Frame")
	if not frame then return end
	
	local scrollingFrame = frame:FindFirstChild("ScrollingFrame")
	if not scrollingFrame then return end
	
	local template = scrollingFrame.UIListLayout:FindFirstChild("Template")
	if not template then return end
	
	-- Clear existing cloned entries (keep Template and UIListLayout)
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("TextLabel") and child.Name ~= "Template" then
			child:Destroy()
		end
	end
	
	-- Hide the template
	template.Visible = false
	
	-- Create entries
	local UIController = Knit.GetController("UIController")
	for rank, entry in ipairs(entries) do
		local clone = template:Clone()
		clone.Name = "Entry_" .. rank
		local valueStr = UIController and UIController:TruncateNumber(entry.Value) or tostring(entry.Value)
		clone.Text = string.format("#%d %s %s", rank, entry.Name, valueStr)
		clone.Visible = true
		clone.Parent = scrollingFrame
	end
end

--[[
	Setup a single leaderboard SurfaceGui on a part.
	
	@param part BasePart - The part in Leaderboards_Zone
	@param config table - Config with FetchMethod and Title
]]
local function SetupLeaderboardOnPart(part: BasePart, config: { FetchMethod: string, Title: string })
	--print(config, "fetch method") --- IGNORE ---
	-- Clear existing SurfaceGuis
	ClearPartChildren(part)
	
	-- Find the LeaderboardUI template in PlayerGui
	local leaderboardUITemplate = PlayerGui:FindFirstChild("LeaderboardUI")
	if not leaderboardUITemplate then
		warn("[LeaderboardController]: LeaderboardUI not found in PlayerGui")
		return
	end
	
	-- Clone the SurfaceGui
	local surfaceGui = leaderboardUITemplate:Clone() :: SurfaceGui
	surfaceGui.Adornee = part
	surfaceGui.Parent = part
	
	-- Set the title
	local titleLabel = surfaceGui.Frame:FindFirstChild("TextLabel")
	titleLabel.Text = config.Title
	
	-- Fetch data from server and populate
	LeaderboardService[config.FetchMethod](LeaderboardService):andThen(function(entries)
		--warn("Entries", entries)
		if entries then
			PopulateLeaderboard(surfaceGui, entries)
		end
	end):catch(function(err)
		warn(string.format("[LeaderboardController]: Failed to fetch %s: %s", config.FetchMethod, tostring(err)))
	end)
end

--[[
	Setup all leaderboards for the current world.
	Finds the Leaderboards_Zone folder and sets up SurfaceGuis on each part.
]]
function LeaderboardController:SetupLeaderboards()
	local currentWorld = Player:GetAttribute("CurrentWorld") or "Main"
	local worldFolder = Workspace:FindFirstChild(currentWorld)
	if not worldFolder then
		return
	end
	
	local leaderboardsZone = worldFolder:FindFirstChild("Leaderboards_Zone")
	if not leaderboardsZone then
		return
	end
	
	-- Setup each leaderboard part
	for partName, config in pairs(LeaderboardConfig) do
		local part = leaderboardsZone:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			SetupLeaderboardOnPart(part, config)
		end
	end
end

function LeaderboardController:KnitInit()
	-- Nothing to initialize
end

function LeaderboardController:KnitStart()
	LeaderboardService = Knit.GetService("LeaderboardService")
	DataService = Knit.GetService("DataService")
	
	-- Setup leaderboards when data is ready
	DataService.DataReady:Connect(function(_newData)
		self:SetupLeaderboards()
	end)
	
	-- Update leaderboards when world changes
	Player:GetAttributeChangedSignal("CurrentWorld"):Connect(function()
		self:SetupLeaderboards()
	end)
end

return LeaderboardController
