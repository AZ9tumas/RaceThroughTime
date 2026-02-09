--[[
	DevProducts Module
	Contains dev product IDs and their purchase handlers.
	
	Usage:
	local DevProducts = require(path.to.DevProducts)
	DevProducts.Initialize(Knit) -- Call once during KnitInit
	
	local handler = DevProducts.PurchasesManager[productId]
	if handler then
		handler.OnPurchase(player)
	end
]]

local DevProducts = {}

-- Dev Product IDs
DevProducts.Ids = {
	MediumCashPack = 3533352608,
	HugeCashPack = 3533356103,
	LargeGemPack = 3533356279,
	-- Egg Products
	BestFriendEgg = 3533366172,
	LimitedHistoricalEgg = 3533366398,
	PremiumWorldEgg = 3533366275,
	GoldenChronoEgg = 3533366982,
}

-- Purchases Manager - handlers are initialized when Initialize() is called
DevProducts.PurchasesManager = {}

-- Initialize purchase handlers (must be called after Knit is started)
function DevProducts.Initialize(Knit)
	local DataService = Knit.GetService("DataService")
	local NotificationService = Knit.GetService("NotificationService")
	local EggService = Knit.GetService("EggService")
	
	DevProducts.PurchasesManager = {
		[DevProducts.Ids.MediumCashPack] = {
			Name = "MediumCashPack",
			OnPurchase = function(player)
				DataService:Update(player, "Currencies", function(currencies)
					currencies.Cash = (currencies.Cash or 0) + 10000
					return currencies
				end)
				
				if NotificationService then
					NotificationService:SendNotification(
						player,
						"You received 10,000 Cash!",
						NotificationService.Category.Success
					)
				end
				
				return true
			end
		},
		[DevProducts.Ids.HugeCashPack] = {
			Name = "HugeCashPack",
			OnPurchase = function(player)
				DataService:Update(player, "Currencies", function(currencies)
					currencies.Cash = (currencies.Cash or 0) + 50000
					return currencies
				end)
				
				if NotificationService then
					NotificationService:SendNotification(
						player,
						"You received 50,000 Cash!",
						NotificationService.Category.Success
					)
				end
				
				return true
			end
		},
		[DevProducts.Ids.LargeGemPack] = {
			Name = "LargeGemPack",
			OnPurchase = function(player)
				DataService:Update(player, "Currencies", function(currencies)
					currencies.Gems = (currencies.Gems or 0) + 1000
					return currencies
				end)
				
				if NotificationService then
					NotificationService:SendNotification(
						player,
						"You received 1,000 Gems!",
						NotificationService.Category.Success
					)
				end
				
				return true
			end
		},
		[DevProducts.Ids.BestFriendEgg] = {
			Name = "BestFriendEgg",
			OnPurchase = function(player)
				local success = EggService:HatchEgg(player, "BestFriendEgg")
				return success
			end
		},
		[DevProducts.Ids.LimitedHistoricalEgg] = {
			Name = "LimitedHistoricalEgg",
			OnPurchase = function(player)
				local success = EggService:HatchEgg(player, "LimitedHistoricalEgg")
				return success
			end
		},
		[DevProducts.Ids.PremiumWorldEgg] = {
			Name = "PremiumWorldEgg",
			OnPurchase = function(player)
				local success = EggService:HatchEgg(player, "PremiumWorldEgg")
				return success
			end
		},
		[DevProducts.Ids.GoldenChronoEgg] = {
			Name = "GoldenChronoEgg",
			OnPurchase = function(player)
				local success = EggService:HatchEgg(player, "GoldenChronoEgg")
				return success
			end
		},
	}
end

-- Helper function to get product ID by name
function DevProducts.GetProductId(productName: string): number?
	return DevProducts.Ids[productName]
end

-- Helper function to get product handler by ID
function DevProducts.GetHandler(productId: number)
	return DevProducts.PurchasesManager[productId]
end

return DevProducts
