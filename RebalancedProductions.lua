RebalancedProductions = {}
RebalancedProductions.DEBUG = false
RebalancedProductions.PERIOD_FACTOR = 22
RebalancedProductions.COST_FACTOR = 1.0
RebalancedProductions.OUTPUT_CAPACITY_RATIO = 3.0
	
local function round(x, n)
	return math.ceil(x / n) * n
end

local function info(...)
	if RebalancedProductions.DEBUG then
		printf(...)
	end
end

function RebalancedProductions:load(success, components, xmlFile, key, customEnv, i3dMappings)
	if success then
		for _, production in ipairs(self.productions) do
			if production.id ~= "tomato" and production.id ~= "lettuce" and production.id ~= "strawberry" then
				self.sharedThroughputCapacity = false
			end
			
			if production.outputs[1] ~= nil then				
				local amount = 1
				for _, output in ipairs(production.outputs) do
					if amount < output.amount then
						amount = output.amount
					end
				end
				
				local oldCycles = production.cyclesPerHour * 24
				local oldPeriod = production.cyclesPerHour * amount
				
				local oldCosts = production.costsPerActiveHour
				local oldCostsFactor = (production.costsPerActiveHour / production.cyclesPerHour) * RebalancedProductions.COST_FACTOR
				
				production.cyclesPerHour = math.ceil(production.cyclesPerHour * math.max(1, math.sqrt(oldPeriod) / oldPeriod * RebalancedProductions.PERIOD_FACTOR))
				production.cyclesPerMinute = production.cyclesPerHour / 60
				production.cyclesPerMonth = production.cyclesPerHour * 24
				
				production.costsPerActiveHour = math.ceil(oldCosts * (production.cyclesPerHour / oldCosts) * oldCostsFactor)
				production.costsPerActiveMinute = production.costsPerActiveHour / 60
				production.costsPerActiveMonth  = production.costsPerActiveHour * 24
				
				info(
					"RebalancedProductions: increasing cost for production %s ( %s => %s )",
					production.id,
					string.format("%.01f", oldCosts),
					string.format("%.01f", production.costsPerActiveHour)
				)
					
				if production.cyclesPerMonth ~= oldCycles then
					info(
						"RebalancedProductions: increasing production cycles for production %s ( %d => %d )",
						production.id,
						oldCycles,
						production.cyclesPerMonth
					)
				end
				
				for fillType, accepted in pairs(self.storage.fillTypes) do
					for _, output in ipairs(production.outputs) do
						if output.type == fillType then
							local ratio = self.storage.capacities[output.type] / (output.amount * production.cyclesPerMonth)
							if ratio < RebalancedProductions.OUTPUT_CAPACITY_RATIO then
								local capacity = self.storage.capacities[fillType]
								self.storage.capacities[fillType] = round(output.amount * (production.cyclesPerMonth * RebalancedProductions.OUTPUT_CAPACITY_RATIO), 1000)
								info(
									"RebalancedProductions: increasing output storage capacity %s ( %d => %d )",
									g_fillTypeManager:getFillTypeNameByIndex(fillType),
									capacity,
									self.storage.capacities[fillType]
								)
							end
						end
					end
				end
				
				for _, input in ipairs(production.inputs) do
					if input.amount > 0 then
						local fillType = input.type
						local consum = input.amount * production.cyclesPerMonth
						local oldConsum = input.amount * oldCycles
						local capacity = self.storage.capacities[fillType]
						
						if capacity / consum < 1 then
							local factor = capacity / oldConsum
							self.storage.capacities[fillType] = math.ceil(capacity * (consum / capacity) * factor)
							
							info(
								"RebalancedProductions: increasing input storage capacity %s ( %d => %d )",
								g_fillTypeManager:getFillTypeNameByIndex(fillType),
								capacity,
								self.storage.capacities[fillType]
							)
						end
					end
				end
			end
		end
	end
	return success
end

function RebalancedProductions:onTimescaleChanged()
	self.minuteFactorTimescaled = self.mission:getEffectiveTimeScale() / 1000 / 60 / self.mission.environment.daysPerPeriod
end

local function appendedFunction(oldFunc, newFunc)
	if oldFunc ~= nil then
		return function (self, ...)
			retValue = oldFunc(self, ...)
			return newFunc(self, retValue, ...)
		end
	else
		return newFunc
	end
end

ProductionPoint.onTimescaleChanged = Utils.overwrittenFunction(ProductionPoint.onTimescaleChanged, RebalancedProductions.onTimescaleChanged)
ProductionPoint.load = appendedFunction(ProductionPoint.load, RebalancedProductions.load)

