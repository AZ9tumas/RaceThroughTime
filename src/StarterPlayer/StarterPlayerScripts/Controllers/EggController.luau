local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))
local Stats = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Stats"))
local EggHatchAnimation = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EggHatchAnimation"))

local EggController = Knit.CreateController({
	Name = "EggController",
})

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local EggService = nil
local DataService = nil
local NotificationController = nil
local UIFramesController = nil
local UIController = nil
local InventoryUIController = nil

local eggHatchScreenGui: ScreenGui = nil
local eggHatchDimmer: Frame = nil
local eggviewport: ViewportFrame = nil
local eggHatchFlash: Frame? = nil

local CurrentWorldName = "Main"
local EggConnections: { [string]: { RBXScriptConnection } } = {}
local AutoHatchActive: { [string]: boolean } = {}
local IsHatching = false

local MULTI_HATCH_COUNT = 4
local AUTO_HATCH_DELAY = 0.5
local AUTO_HATCH_RANGE = 30

local function GetCurrentWorld(): string
	local worldAttr = Player:GetAttribute("CurrentWorld")
	if worldAttr then
		return worldAttr
	end
	return CurrentWorldName
end

local function GetEggConfig(eggName: string): { Cost: number, Currency: string, Pets: { { Pet: string, Probability: number } } }?
	return Stats.Eggs[eggName]
end

local function GetPetConfig(petName: string): { Name: string, Rarity: string? }?
	return Stats.Pets[petName]
end

local function FormatPercentage(probability: number): string
	return string.format("%.1f%%", probability * 100)
end

local function GetCurrentEggRoot(): BasePart?
	local worldFolder = Workspace:FindFirstChild(CurrentWorldName)
	if not worldFolder then
		return nil
	end
	
	local eggShopStands = worldFolder:FindFirstChild("EggShop_Stands")
	if not eggShopStands then
		return nil
	end
	
	local standardEgg = eggShopStands:FindFirstChild("StandardEgg")
	if not standardEgg then
		return nil
	end
	
	return standardEgg:FindFirstChild("EggRoot")
end

local function IsPlayerInRange(): boolean
	local eggRoot = GetCurrentEggRoot()
	if not eggRoot then
		return false
	end
	
	local character = Player.Character
	if not character then
		return false
	end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return false
	end
	
	local distance = (humanoidRootPart.Position - eggRoot.Position).Magnitude
	return distance <= AUTO_HATCH_RANGE
end

local function UpdateBillboardAdornees(worldName: string)
	local worldFolder = Workspace:FindFirstChild(worldName)
	if not worldFolder then
		return
	end
	
	local eggShopStands = worldFolder:FindFirstChild("EggShop_Stands")
	if not eggShopStands then
		return
	end
	
	local standardEgg = eggShopStands:FindFirstChild("StandardEgg")
	if not standardEgg then
		return
	end
	
	local eggRoot = standardEgg:FindFirstChild("EggRoot")
	if not eggRoot then
		return
	end
	
	local uiHatchBoard = PlayerGui:FindFirstChild("UI_HatchBoard")
	if uiHatchBoard and uiHatchBoard:IsA("BillboardGui") then
		uiHatchBoard.Adornee = eggRoot
	end
end

local function SetupPetTemplates(mainBoard: Frame, eggName: string)
	local eggConfig = GetEggConfig(eggName)
	if not eggConfig or not eggConfig.Pets then
		return
	end

	local contentFrame = mainBoard:FindFirstChild("Frame")
	if not contentFrame then
		return
	end

	local gridLayout = contentFrame:FindFirstChild("UIGridLayout")
	local template = gridLayout and gridLayout:FindFirstChild("Template")
	if not template then
		template = contentFrame:FindFirstChild("Template")
	end

	if not template then
		return
	end

	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "Template" and child ~= gridLayout and not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end

	for i, petOption in ipairs(eggConfig.Pets) do
		local petName = petOption.Pet
		local probability = petOption.Probability
		local petConfig = GetPetConfig(petName)

		local newTemplate = template:Clone()
		newTemplate.Name = "Pet_" .. i
		newTemplate.Visible = true
		newTemplate.Parent = contentFrame

		local rarityLabel = newTemplate:FindFirstChild("Rarity")
		if rarityLabel and rarityLabel:IsA("TextLabel") then
			rarityLabel.Text = FormatPercentage(probability)
		end

		local nameLabel = newTemplate:FindFirstChild("Name") or newTemplate:FindFirstChild("PetName")
		if nameLabel and nameLabel:IsA("TextLabel") and petConfig then
			nameLabel.Text = petConfig.Name or petName
		end
	end

	template.Visible = false
end

local function PurchaseSingleEgg(eggName: string)
	if IsHatching then return end
	if EggHatchAnimation.IsPlaying() then return end
	
	IsHatching = true
	UIFramesController:DisableFrames(true)
	eggviewport.Parent.Visible = true
	
	EggHatchAnimation.PlayHatch(
		eggviewport,
		eggName,
		eggHatchDimmer,
		eggHatchFlash,
		function(animationSuccess)
			if animationSuccess then
				EggService:RequestPurchaseEgg(eggName):andThen(function(success, errorMsg, petInfo)
					if success and petInfo then
						local data = UIController:GetData()
						if not data.Inventory.PetInventory then
							data.Inventory.PetInventory = {}
						end
						table.insert(data.Inventory.PetInventory, petInfo)
						if InventoryUIController then
							InventoryUIController:UpdatePetsInventory()
						end
					elseif not success and NotificationController then
						NotificationController:ShowNotification(
							errorMsg or "Failed to purchase egg",
							NotificationController.Category.Warning,
							3
						)
					end
				end)
			end
			eggviewport.Parent.Visible = false
			UIFramesController:DisableFrames(false)
			IsHatching = false
		end
	)
end

local function PurchaseMultipleEggs(eggName: string, count: number)
	if IsHatching then return end
	if EggHatchAnimation.IsPlaying() then return end
	
	IsHatching = true
	local purchasedCount = 0
	local currentIndex = 0
	
	local function HatchNext()
		currentIndex = currentIndex + 1
		if currentIndex > count then
			if purchasedCount > 0 and NotificationController then
				NotificationController:ShowNotification(
					string.format("Hatched %d eggs!", purchasedCount),
					NotificationController.Category.Success,
					3
				)
			end
			IsHatching = false
			return
		end
		
		UIFramesController:DisableFrames(true)
		eggviewport.Parent.Visible = true
		
		EggHatchAnimation.PlayHatch(
			eggviewport,
			eggName,
			eggHatchDimmer,
			eggHatchFlash,
			function(animationSuccess)
				if animationSuccess then
					EggService:RequestPurchaseEgg(eggName):andThen(function(success, _errorMsg, petInfo)
						if success and petInfo then
							purchasedCount = purchasedCount + 1
							local data = UIController:GetData()
							if not data.Inventory.PetInventory then
								data.Inventory.PetInventory = {}
							end
							table.insert(data.Inventory.PetInventory, petInfo)
							if InventoryUIController then
								InventoryUIController:UpdatePetsInventory()
							end
							eggviewport.Parent.Visible = false
							UIFramesController:DisableFrames(false)
							task.wait(0.1)
							HatchNext()
						else
							eggviewport.Parent.Visible = false
							UIFramesController:DisableFrames(false)
							if purchasedCount > 0 and NotificationController then
								NotificationController:ShowNotification(
									string.format("Hatched %d eggs!", purchasedCount),
									NotificationController.Category.Success,
									3
								)
							end
							IsHatching = false
						end
					end)
				else
					eggviewport.Parent.Visible = false
					UIFramesController:DisableFrames(false)
					IsHatching = false
				end
			end
		)
	end
	
	HatchNext()
end

local function StartAutoHatch(eggName: string)
	if AutoHatchActive[eggName] then
		return
	end
	
	if not IsPlayerInRange() then
		if NotificationController then
			NotificationController:ShowNotification(
				"Move closer to the egg to auto-hatch!",
				NotificationController.Category.Warning,
				3
			)
		end
		return
	end

	AutoHatchActive[eggName] = true

	task.spawn(function()
		while AutoHatchActive[eggName] do
			if not IsPlayerInRange() then
				AutoHatchActive[eggName] = false
				if NotificationController then
					NotificationController:ShowNotification(
						"Auto-hatch stopped: Too far from egg",
						NotificationController.Category.Warning,
						3
					)
				end
				break
			end
			
			if IsHatching or EggHatchAnimation.IsPlaying() then
				task.wait(AUTO_HATCH_DELAY)
				continue
			end

			IsHatching = true
			UIFramesController:DisableFrames(true)
			eggviewport.Parent.Visible = true
			
			local continueAutoHatch = true
			
			EggHatchAnimation.PlayHatch(
				eggviewport,
				eggName,
				eggHatchDimmer,
				eggHatchFlash,
				function(animationSuccess)
					if animationSuccess then
						EggService:RequestPurchaseEgg(eggName):andThen(function(success, _errorMsg, petInfo)
							if success and petInfo then
								local data = UIController:GetData()
								if not data.Inventory.PetInventory then
									data.Inventory.PetInventory = {}
								end
								table.insert(data.Inventory.PetInventory, petInfo)
								if InventoryUIController then
									InventoryUIController:UpdatePetsInventory()
								end
							else
								continueAutoHatch = false
								AutoHatchActive[eggName] = false
								if NotificationController then
									NotificationController:ShowNotification(
										"Auto-hatch stopped: Not enough currency",
										NotificationController.Category.Warning,
										3
									)
								end
							end
						end)
					else
						continueAutoHatch = false
					end
					eggviewport.Parent.Visible = false
					UIFramesController:DisableFrames(false)
					IsHatching = false
				end
			)
			
			while IsHatching do
				task.wait(0.1)
			end
			
			if not continueAutoHatch then
				break
			end

			task.wait(AUTO_HATCH_DELAY)
		end
	end)
end

local function StopAutoHatch(eggName: string)
	AutoHatchActive[eggName] = false
end

local function ToggleAutoHatch(eggName: string)
	if AutoHatchActive[eggName] then
		StopAutoHatch(eggName)
	else
		StartAutoHatch(eggName)
	end
end

local function SetupUIButtons()
	local uiHatchBoard = PlayerGui:FindFirstChild("UI_HatchBoard")
	if not uiHatchBoard then
		return
	end
	
	local container = uiHatchBoard:FindFirstChild("Container")
	if not container then
		return
	end
	
	local mainBoard = container:FindFirstChild("MainBoard")
	if not mainBoard then
		return
	end
	
	local actionButtons = mainBoard:FindFirstChild("ActionButtons")
	if not actionButtons then
		return
	end
	
	local eggName = "StandardEgg"
	EggConnections[eggName] = {}
	
	local btnHatch = actionButtons:FindFirstChild("Btn_Hatch")
	if btnHatch and btnHatch:IsA("TextButton") then
		local conn = btnHatch.MouseButton1Click:Connect(function()
			PurchaseSingleEgg(eggName)
		end)
		table.insert(EggConnections[eggName], conn)
		
		if UIFramesController then
			UIFramesController:SetupButtonAnimation(btnHatch)
		end
	end
	
	local btnMulti = actionButtons:FindFirstChild("Btn_Multi")
	if btnMulti and btnMulti:IsA("TextButton") then
		local conn = btnMulti.MouseButton1Click:Connect(function()
			PurchaseMultipleEggs(eggName, MULTI_HATCH_COUNT)
		end)
		table.insert(EggConnections[eggName], conn)
		
		if UIFramesController then
			UIFramesController:SetupButtonAnimation(btnMulti)
		end
	end
	
	local btnAuto = actionButtons:FindFirstChild("Btn_Auto")
	if btnAuto and btnAuto:IsA("TextButton") then
		local conn = btnAuto.MouseButton1Click:Connect(function()
			ToggleAutoHatch(eggName)
		end)
		table.insert(EggConnections[eggName], conn)
		
		if UIFramesController then
			UIFramesController:SetupButtonAnimation(btnAuto)
		end
	end
	
	SetupPetTemplates(mainBoard, eggName)
end

function EggController:UpdateEggUI()
	local worldName = GetCurrentWorld()
	UpdateBillboardAdornees(worldName)
end

function EggController:OnWorldChanged(newWorldName: string)
	for eggName, _ in pairs(AutoHatchActive) do
		StopAutoHatch(eggName)
	end

	CurrentWorldName = newWorldName
	UpdateBillboardAdornees(newWorldName)
end

function EggController:KnitInit()
	UIFramesController = Knit.GetController("UIFramesController")
	UIController = Knit.GetController("UIController")
	InventoryUIController = Knit.GetController("InventoryUIController")
	
	eggHatchScreenGui = PlayerGui:WaitForChild("EggHatchScreen")
	eggHatchDimmer = eggHatchScreenGui:WaitForChild("Dimmer")
	eggviewport = eggHatchDimmer:WaitForChild("Viewport")
	eggHatchFlash = eggHatchScreenGui:FindFirstChild("Flash")
	
	SetupUIButtons()
end

function EggController:KnitStart()
	EggService = Knit.GetService("EggService")
	DataService = Knit.GetService("DataService")
	NotificationController = Knit.GetController("NotificationController")

	CurrentWorldName = GetCurrentWorld()
	UpdateBillboardAdornees(CurrentWorldName)

	DataService.DataReady:Connect(function(_newData)
		self:UpdateEggUI()
	end)

	Player:GetAttributeChangedSignal("CurrentWorld"):Connect(function()
		local newWorld = Player:GetAttribute("CurrentWorld")
		if newWorld and newWorld ~= CurrentWorldName then
			self:OnWorldChanged(newWorld)
		end
	end)

	EggService.PetObtained:Connect(function(petInfo)
		if NotificationController and petInfo then
			NotificationController:ShowNotification(
				string.format("🥚 Hatched: %s!", petInfo.Name or "Unknown Pet"),
				NotificationController.Category.Success,
				3
			)
		end
	end)
end

return EggController
