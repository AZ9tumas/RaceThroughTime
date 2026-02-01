local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)

local BossService = Knit.CreateService({
	Name = "BossService",
	Client = {},
})

local CurrentBossIndex = 0
local SpawnedBosses = {}

function BossService:SpawnBoss()
	CurrentBossIndex = CurrentBossIndex + 1
	if CurrentBossIndex > #Stats.Bosses then
		CurrentBossIndex = 1
	end
	
	local bossName = Stats.Bosses[CurrentBossIndex]
	local bossAssets = ServerStorage:FindFirstChild("Assets")
	if not bossAssets then
		warn("[BossService] ServerStorage.Assets not found")
		return
	end
	
	local bossesFolder = bossAssets:FindFirstChild("Bosses")
	if not bossesFolder then
		warn("[BossService] ServerStorage.Assets.Bosses not found")
		return
	end
	
	local bossModel = bossesFolder:FindFirstChild(bossName)
	if not bossModel then
		warn("[BossService] Boss model not found:", bossName)
		return
	end
	
	for _, existingBoss in ipairs(SpawnedBosses) do
		if existingBoss and existingBoss.Parent then
			existingBoss:Destroy()
		end
	end
	SpawnedBosses = {}
	
	for _, world in ipairs(workspace:GetChildren()) do
		local spawnLocation = world:FindFirstChild("SpawnLocation")
		if spawnLocation and spawnLocation:IsA("BasePart") then
			local bossClone = bossModel:Clone()
			bossClone.Name = bossName
			
			if bossClone.PrimaryPart then
				bossClone:SetPrimaryPartCFrame(spawnLocation.CFrame + Vector3.new(0, 5, 0))
			elseif bossClone:FindFirstChild("HumanoidRootPart") then
				bossClone.HumanoidRootPart.CFrame = spawnLocation.CFrame + Vector3.new(0, 5, 0)
			else
				local firstPart = bossClone:FindFirstChildWhichIsA("BasePart")
				if firstPart then
					firstPart.CFrame = spawnLocation.CFrame + Vector3.new(0, 5, 0)
				end
			end
			
			bossClone.Parent = world
			table.insert(SpawnedBosses, bossClone)
		end
	end
	
	local statsFolder = ReplicatedStorage:FindFirstChild("Stats")
	if statsFolder then
		local bossFight = statsFolder:FindFirstChild("BossFight")
		if bossFight and bossFight:IsA("BoolValue") then
			bossFight.Value = true
		end
		
		local bossHealth = statsFolder:FindFirstChild("BossHealth")
		if bossHealth and bossHealth:IsA("NumberValue") then
			bossHealth.Value = Stats.BossMaxHealth
		end
	end
	
	return bossName
end

function BossService:GetCurrentBossName()
	if CurrentBossIndex > 0 and CurrentBossIndex <= #Stats.Bosses then
		return Stats.Bosses[CurrentBossIndex]
	end
	return nil
end

function BossService:IsBossFightActive()
	local statsFolder = ReplicatedStorage:FindFirstChild("Stats")
	if statsFolder then
		local bossFight = statsFolder:FindFirstChild("BossFight")
		if bossFight and bossFight:IsA("BoolValue") then
			return bossFight.Value
		end
	end
	return false
end

function BossService:EndBossFight()
	for _, existingBoss in ipairs(SpawnedBosses) do
		if existingBoss and existingBoss.Parent then
			existingBoss:Destroy()
		end
	end
	SpawnedBosses = {}
	
	local statsFolder = ReplicatedStorage:FindFirstChild("Stats")
	if statsFolder then
		local bossFight = statsFolder:FindFirstChild("BossFight")
		if bossFight and bossFight:IsA("BoolValue") then
			bossFight.Value = false
		end
		
		local bossHealth = statsFolder:FindFirstChild("BossHealth")
		if bossHealth and bossHealth:IsA("NumberValue") then
			bossHealth.Value = 0
		end
	end
end

function BossService:KnitStart()
end

function BossService:KnitInit()
	local statsFolder = ReplicatedStorage:FindFirstChild("Stats")
	if not statsFolder then
		statsFolder = Instance.new("Folder")
		statsFolder.Name = "Stats"
		statsFolder.Parent = ReplicatedStorage
	end
	
	local bossFight = statsFolder:FindFirstChild("BossFight")
	if not bossFight then
		bossFight = Instance.new("BoolValue")
		bossFight.Name = "BossFight"
		bossFight.Value = false
		bossFight.Parent = statsFolder
	end
	
	local bossHealth = statsFolder:FindFirstChild("BossHealth")
	if not bossHealth then
		bossHealth = Instance.new("NumberValue")
		bossHealth.Name = "BossHealth"
		bossHealth.Value = 0
		bossHealth.Parent = statsFolder
	end
end

return BossService
