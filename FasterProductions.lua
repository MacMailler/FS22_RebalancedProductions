FasterProductions = {}

local function round(x)
	return math.ceil(x / 1000) * 1000
end

function FasterProductions:onLoadProduction(success, components, xmlFile, key, customEnv, i3dMappings)
	if success then
	
		local PERIOD_FACTOR = 22
		local OUTPUT_CAPACITY_RATIO = 3
		
		for _, production in ipairs(self.productions) do
			if production.outputs[1] ~= nil then				
				local amount = 1
				for _, output in ipairs(production.outputs) do
					if amount < output["amount"] then
						amount = output["amount"]
					end
				end
				
				local oldCycles = production.cyclesPerHour * 24
				local oldPeriod = production.cyclesPerHour * amount
				
				production.cyclesPerHour = math.ceil(production.cyclesPerHour * math.max(1, math.sqrt(oldPeriod) / oldPeriod * PERIOD_FACTOR))
				production.cyclesPerMinute = production.cyclesPerHour / 60
				production.cyclesPerMonth = production.cyclesPerHour * 24

				if production.cyclesPerMonth ~= oldCycles then
					printf(
						"FASTER_PRODUCTIONS: increasing production cycles for production %s ( %d => %d )",
						production.name,
						oldCycles,
						production.cyclesPerMonth
					)
				end
				
				for fillType, accepted in pairs(self.storage.fillTypes) do
					for _, output in ipairs(production.outputs) do
						if output["type"] == fillType then
							local ratio = self.storage.capacities[output["type"]] / (output["amount"] * production.cyclesPerMonth)
							if ratio < OUTPUT_CAPACITY_RATIO then
								local capacity = self.storage.capacities[fillType]
								self.storage.capacities[fillType] = round(output["amount"] * (production.cyclesPerMonth * OUTPUT_CAPACITY_RATIO))
								printf(
									"FASTER_PRODUCTIONS: increasing output storage capacity %s ( %d => %d )",
									g_fillTypeManager:getFillTypeNameByIndex(fillType),
									capacity,
									self.storage.capacities[fillType]
								)
							end
						end
					end
				end
				
				local fillType = production.inputs[1]["type"]
				local consum = production.inputs[1].amount * production.cyclesPerMonth
				local oldConsum = production.inputs[1].amount * oldCycles
				local capacity = self.storage.capacities[fillType]
				
				if capacity / consum < 1 then
					local factor = capacity / oldConsum
					self.storage.capacities[fillType] = math.ceil(capacity * (consum / capacity) * factor)
					
					printf(
						"FASTER_PRODUCTIONS: increasing input storage capacity %s ( %d => %d )",
						g_fillTypeManager:getFillTypeNameByIndex(fillType),
						capacity,
						self.storage.capacities[fillType]
					)
				end
			end
		end
	end
	return success
end

function FasterProductions:onTimescaleChanged()
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

ProductionPoint.onTimescaleChanged = Utils.overwrittenFunction(ProductionPoint.onTimescaleChanged, FasterProductions.onTimescaleChanged)
ProductionPoint.load = appendedFunction(ProductionPoint.load, FasterProductions.onLoadProduction)

