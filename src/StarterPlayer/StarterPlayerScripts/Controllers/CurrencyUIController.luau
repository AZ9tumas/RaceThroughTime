local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

local CurrencyUIController = Knit.CreateController({
	Name = "CurrencyUIController",
})

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local cashDisplay: TextLabel
local gemsDisplay: TextLabel
local fuelText: TextLabel
local multiplierLabel: TextLabel
local starCountText: TextLabel
local worldLabel: TextLabel
local shopCashCount: TextLabel
local shopGemsCount: TextLabel

local leaderstats
local gemsVal
local cashVal
local fuelVal

local function TruncateNumber(n: number): string
	if n >= 1e12 then
		return string.format("%.2fT", n / 1e12)
	elseif n >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.2fK", n / 1e3)
	end
	return tostring(n)
end

function CurrencyUIController:UpdateFuelUI(amount: number)
	if fuelText then
		fuelText.Text = "⛽ FUEL: " .. math.floor(amount)
	end
end

function CurrencyUIController:UpdateCashUI(amount: number)
	if cashDisplay then
		cashDisplay.Text = "💵 " .. TruncateNumber(amount)
	end
	if shopCashCount then
		shopCashCount.Text = TruncateNumber(amount)
	end
end

function CurrencyUIController:UpdateGemsUI(amount: number)
	if gemsDisplay then
		gemsDisplay.Text = "💎 " .. TruncateNumber(amount)
	end
	if shopGemsCount then
		shopGemsCount.Text = TruncateNumber(amount)
	end
end

function CurrencyUIController:UpdateStarCount(amount: number)
	if starCountText then
		starCountText.Text = "⭐ " .. TruncateNumber(amount)
	end
end

function CurrencyUIController:UpdateMultiplier(multiplier: number)
	if multiplierLabel then
		multiplierLabel.Text = "⚡ x" .. TruncateNumber(multiplier)
	end
end

function CurrencyUIController:UpdateWorldLabel(worldName: string)
	if worldLabel then
		worldLabel.Text = "🌍 " .. worldName
	end
end

function CurrencyUIController:UpdateAllDisplays()
	local UIController = Knit.GetController("UIController")
	local data = UIController:GetData()
	if fuelVal then
		self:UpdateFuelUI(fuelVal.Value)
	end
	if cashVal then
		self:UpdateCashUI(cashVal.Value)
	end
	if gemsVal then
		self:UpdateGemsUI(gemsVal.Value)
	end
	if data and data.Stats and data.Stats.Stars then
		self:UpdateStarCount(data.Stats.Stars)
	end
end

function CurrencyUIController:UpdateFromLeaderstats()
	local UIController = Knit.GetController("UIController")
	local data = UIController:GetData()
	if fuelVal then
		self:UpdateFuelUI(fuelVal.Value)
	end
	if cashVal then
		self:UpdateCashUI(cashVal.Value)
	end
	if gemsVal then
		self:UpdateGemsUI(gemsVal.Value)
	end
	if data and data.Progression then
		self:UpdateWorldLabel(data.Progression.CurrentWorld)
	end
	local totalMultiplier = UIController:CalculateTotalMultiplier()
	self:UpdateMultiplier(totalMultiplier)
end

function CurrencyUIController:KnitInit()
	local mainUi: ScreenGui = PlayerGui:WaitForChild("RaceThroughTime_UI")
	local uiShop: ScreenGui = PlayerGui:WaitForChild("UI_Shop")
	local leftPanel: Frame = mainUi:WaitForChild("LeftPanel")
	local centerHUD: Frame = mainUi:WaitForChild("CenterHUD")
	local fuelBar = centerHUD:WaitForChild("FuelBar")
	cashDisplay = leftPanel:WaitForChild("CashDisplay")
	gemsDisplay = leftPanel:WaitForChild("GemsDisplay")
	fuelText = fuelBar:WaitForChild("FuelText")
	multiplierLabel = fuelBar:WaitForChild("SpeedStat")
	starCountText = fuelBar:WaitForChild("StarStat")
	worldLabel = mainUi:WaitForChild("TopInfo"):WaitForChild("WorldName")
	local shopMain = uiShop:WaitForChild("MainFrame")
	local shopTop = shopMain:WaitForChild("Top")
	shopCashCount = shopTop:WaitForChild("Cash"):WaitForChild("Count")
	shopGemsCount = shopTop:WaitForChild("Gems"):WaitForChild("Count")
	leaderstats = player:WaitForChild("leaderstats")
	gemsVal = leaderstats:WaitForChild("Gems")
	cashVal = leaderstats:WaitForChild("Cash")
	local statsfolder = player:WaitForChild("Stats")
	fuelVal = statsfolder:WaitForChild("Fuel")
end

function CurrencyUIController:KnitStart()
end

return CurrencyUIController
