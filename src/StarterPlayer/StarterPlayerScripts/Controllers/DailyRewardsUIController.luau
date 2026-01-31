local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

local modules = ReplicatedStorage:WaitForChild("Modules")
local DailyRewardsConfig = require(modules:WaitForChild("DailyRewards"))

local DailyRewardsUIController = Knit.CreateController({
	Name = "DailyRewardsUIController",
})

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local dailyButton: TextButton
local dailyFrame: Frame
local dailyFrameCloseButton: TextLabel
local cardHolders = {}

local _connections = {}

function DailyRewardsUIController:UpdateRewardsStatus()
	local UIController = Knit.GetController("UIController")
	local data = UIController:GetData()
	local collectedRewards = data.Meta.CollectedRewards or {}
	for _, cardData in pairs(cardHolders) do
		local rewardID = DailyRewardsConfig.GetRewardIDForDay(cardData.Day)
		if rewardID and collectedRewards[rewardID] then
			cardData.RedeemButton.Parent.PriceLabel.Text = "REDEEMED"
		end
	end
end

function DailyRewardsUIController:ToggleDailyFrame()
	local UIController = Knit.GetController("UIController")
	UIController:CloseAllFrames(dailyFrame)
	dailyFrame.Visible = not dailyFrame.Visible
end

function DailyRewardsUIController:CloseDailyFrame()
	dailyFrame.Visible = false
end

function DailyRewardsUIController:KnitInit()
	local mainUi: ScreenGui = PlayerGui:WaitForChild("RaceThroughTime_UI")
	local leftPanel: Frame = mainUi:WaitForChild("LeftPanel")
	local otherFrames: Frame = mainUi:WaitForChild("OtherFrames")
	dailyButton = leftPanel:WaitForChild("DailyButton")
	dailyFrame = otherFrames:WaitForChild("DailyFrame")
	local dailyFrameMain = dailyFrame:WaitForChild("Main")
	dailyFrameCloseButton = dailyFrame:WaitForChild("Close")
	local cardHolderFrame = dailyFrameMain:WaitForChild("CardHolder")
	cardHolders = {
		DayOne = {
			Day = 1,
			Frame = cardHolderFrame:WaitForChild("1"),
			RedeemButton = cardHolderFrame:WaitForChild("1"):WaitForChild("Claim"):WaitForChild("Interact"),
			Image = cardHolderFrame:WaitForChild("1"):WaitForChild("ImageLabel"),
			TextLabel = cardHolderFrame:WaitForChild("1"):WaitForChild("Amount"),
		},
		DayTwo = {
			Day = 2,
			Frame = cardHolderFrame:WaitForChild("2"),
			RedeemButton = cardHolderFrame:WaitForChild("2"):WaitForChild("Claim"):WaitForChild("Interact"),
			Image = cardHolderFrame:WaitForChild("2"):WaitForChild("ImageLabel"),
			TextLabel = cardHolderFrame:WaitForChild("2"):WaitForChild("Amount"),
		},
		DayThree = {
			Day = 3,
			Frame = cardHolderFrame:WaitForChild("3"),
			RedeemButton = cardHolderFrame:WaitForChild("3"):WaitForChild("Claim"):WaitForChild("Interact"),
			Image = cardHolderFrame:WaitForChild("3"):WaitForChild("ImageLabel"),
			TextLabel = cardHolderFrame:WaitForChild("3"):WaitForChild("Amount"),
		},
		DayFour = {
			Day = 4,
			Frame = cardHolderFrame:WaitForChild("4"),
			RedeemButton = cardHolderFrame:WaitForChild("4"):WaitForChild("Claim"):WaitForChild("Interact"),
			Image = cardHolderFrame:WaitForChild("4"):WaitForChild("ImageLabel"),
			TextLabel = cardHolderFrame:WaitForChild("4"):WaitForChild("Amount"),
		},
		DayFive = {
			Day = 5,
			Frame = cardHolderFrame:WaitForChild("5"),
			RedeemButton = cardHolderFrame:WaitForChild("5"):WaitForChild("Claim"):WaitForChild("Interact"),
			Image = cardHolderFrame:WaitForChild("5"):WaitForChild("ImageLabel"),
			TextLabel = cardHolderFrame:WaitForChild("5"):WaitForChild("Amount"),
		},
	}
end

function DailyRewardsUIController:KnitStart()
	local DailyRewardService = Knit.GetService("DailyRewardService")
	_connections["DailyButton"] = dailyButton.MouseButton1Click:Connect(function()
		self:ToggleDailyFrame()
	end)
	_connections["DailyFrameClose"] = dailyFrameCloseButton.MouseButton1Click:Connect(function()
		self:CloseDailyFrame()
	end)
	for _, cardData in pairs(cardHolders) do
		_connections["Day" .. cardData.Frame.Name] = cardData.RedeemButton.MouseButton1Click:Connect(function()
			DailyRewardService:RequestCollectReward(cardData.Day)
			self:UpdateRewardsStatus()
			dailyFrame.Visible = false
		end)
	end
end

return DailyRewardsUIController
