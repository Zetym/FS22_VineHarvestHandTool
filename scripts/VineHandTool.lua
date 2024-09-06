VineHandTool = {}
local VineHandTool_mt = Class(VineHandTool, HandTool)
VineHandTool.className = "VineHandTool"
--InitStaticObjectClass(VineHandTool, "VineHandTool", ObjectIds.OBJECT_VineHandTool)
ObjectIds.assignObjectClassObjectId(VineHandTool, "VineHandTool", 69)
HandTool.handToolTypes["vineHandTool"] = VineHandTool

g_xmlManager:addInitSchemaFunction(function ()
	local schema = HandTool.xmlSchema

	schema:setXMLSpecializationType("VineHandTool")
	schema:register(XMLValueType.NODE_INDEX, "handTool.vineHandTool.raycast#node", "Raycast node")
	schema:register(XMLValueType.FLOAT, "handTool.vineHandTool.raycast#maxDistance", "Max raycast distance", 1)
	schema:register(XMLValueType.FLOAT, "handTool.vineHandTool.raycast#maxTrailerDistance", "Max raycast distance for trailer searching", 2)
	--SoundManager.registerSampleXMLPaths(schema, "handTool.VineHandTool.sounds", "cut")
	schema:setXMLSpecializationType()
end)

function VineHandTool.new(isServer, isClient, customMt)
	local self = HandTool.new(isServer, isClient, customMt or VineHandTool_mt)

	return self
end

function VineHandTool:postLoad(xmlFile)
	if not VineHandTool:superClass().postLoad(self, xmlFile) then
		return false
	end
	self.raycast = {
		node = xmlFile:getValue("handTool.vineHandTool.raycast#node", nil, self.rootNode)
	}

	if self.raycast.node == nil then
		Logging.xmlWarning(xmlFile, "Missing vine detector raycast node")
	end

	self.raycast.maxDistance = xmlFile:getValue("handTool.vineHandTool.raycast#maxDistance", 1)
	self.raycast.maxTrailerDistance = xmlFile:getValue("handTool.vineHandTool.raycast#maxTrailerDistance", 2)
	self.raycast.isRaycasting = false
	self.raycast.currentNode = nil
	self.isVineDetectionActive = false
	
	self.activatePressed = false
	self.wasLastActivated = false

    self.isCutting = false
    self.cutTimer = 0
    self.cutDuration = 1
    self.currentCutting = {
        placeable = nil,
        poleIndex = 0,
        pos = {0,0,0}
    }
	
	self.fillType = FillType.GRAPE
    self.fruitType = FruitType.GRAPE

    self.isRotating = false
    self.rotateSpeed = math.pi*2
    self.graphicsNode = getChildAt(getChildAt(getChildAt(self.rootNode, 0), 0), 0)
    self.originRotation = {getRotation(self.graphicsNode)}
	
	self.unloadRaycast = {
		found = false,
		object = nil,
		fillUnitIndex = nil
	}
	
	self.yieldContainer = {
		isSet = false,
		object = nil,
		fillUnitIndex = nil,
		distance = 0
	}
	self.containerMaxDistance = 8
	
	self.triggeredObjects = {}
	
	self.eventIdActivateUnload = ""
	self.inputActionActive = false
	
	return true
end

function VineHandTool:registerActionEvents()
	g_inputBinding:beginActionEventsModification(Player.INPUT_CONTEXT_NAME)
-- 	print("register action")

	local _, eventId = g_inputBinding:registerActionEvent(InputAction.IMPLEMENT_EXTRA, self, self.onInputActivateUnload, false, true, false, false)
	self.eventIdActivateUnload = eventId

	g_inputBinding:endActionEventsModification()
end

function VineHandTool:removeActionEvents()
	g_inputBinding:beginActionEventsModification(Player.INPUT_CONTEXT_NAME)
	g_inputBinding:removeActionEventsByTarget(self)
-- 	print("remove Actions")
	g_inputBinding:endActionEventsModification()
end

function VineHandTool:onInputActivateUnload(_, inputValue)
	if inputValue == 1 and self.unloadRaycast.found then
		self:setYieldContainer(self.unloadRaycast.object, self.unloadRaycast.fillUnitIndex, self.unloadRaycast.distance)
		--printf("Object type: %s ---- fillUnitIndex type: %s", type(self.yieldContainer.object), type(self.yieldContainer.fillUnitIndex))
	end
end

function VineHandTool:delete()
	VineHandTool:superClass().delete(self)
end

function VineHandTool:isBeingUsed()
	return self.activatePressed
end

function VineHandTool:onDeactivate(allowInput)
    VineHandTool:superClass().onDeactivate(self)

    self.isCutting = false
    self.wasLastActivated = false
    self.player:lockInput(false)
end

function VineHandTool:update(dt, allowInput)
	VineHandTool:superClass().update(self, dt, allowInput)
    local dtInSec = dt * 0.001

	if self.raycast.node ~= nil then --self.isServer and
		local x, y, z = getWorldTranslation(self.raycast.node)
		local dx, dy, dz = localDirectionToWorld(self.raycast.node, 0, 0, 1)
        if self.isCutting then
            if self.activatePressed then
                self.cutTimer = math.min(self.cutTimer + dtInSec, self.cutDuration)

--                 printf("isCutting: %f", self.cutTimer)
                if self.cutTimer == self.cutDuration then
                    local cutting = self.currentCutting
                    local x,y,z = unpack(cutting.pos)
--                     printf("cut: %f %f %f", x,y,z)

                    if self.yieldContainer.isSet then -- check if yield container is set
                        VineHandToolHarvestEvent.sendEvent(self.player, cutting.placeable, cutting.poleIndex, x, y, z)
                    else -- if not, try to prepare vine
                        VineHandToolPruneEvent.sendEvent(self.player, cutting.placeable, cutting.poleIndex, x, y, z)
                    end

                    self.isCutting = false
--                     print("Done cutting")
                else
                    rotateAboutLocalAxis(self.graphicsNode, dtInSec*self.rotateSpeed, 0, 1, 0)
                end
            else
                self.isCutting = false
            end
		elseif self:getCanHarvest() and self.activatePressed then
			self.isVineDetectionActive = true
			
			if not self.raycast.isRaycasting then
				self.raycast.isRaycasting = true

				raycastAll(x, y, z, dx, dy, dz, "raycastCallbackVineDetection", self.raycast.maxDistance, self, nil, false, true)
			end
		elseif self.isVineDetectionActive then
			self.raycast.currentNode = nil
			self.raycast.placeable = nil
			self.raycast.isRaycasting = false

			self.isVineDetectionActive = false
			if self.yieldContainer.isSet and self.yieldContainer.object:getFillUnitFreeCapacity(self.yieldContainer.fillUnitIndex, self.fillType) <= 0 then
				g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("warning_noMoreFreeCapacity"), g_fillTypeManager:getFillTypeByIndex(self.fillType).title), 4000)
			end
		end
		self.triggeredObjects = {}
		raycastAll(x, y, z, dx, dy, dz, "rayCastCallbackTrailerDetection", self.raycast.maxTrailerDistance, self, nil, false)
		if not self.activatePressed and self.wasLastActivated then
			self.wasLastActivated = false
		end
        self.player:lockInput(self.isCutting)
        if not self.isCutting then
            setRotation(self.graphicsNode, unpack(self.originRotation))
        end
	end

    self.activatePressed = false
end

function VineHandTool:updateTick(dt)
	if self.raycast.node ~= nil and self.isClient then
		if self.yieldContainer.isSet then
			self.yieldContainer.distance = calcDistanceFrom(self.raycast.node, self.yieldContainer.object.rootNode)
			if self.yieldContainer.distance > self.containerMaxDistance then
				self:setYieldContainer(nil, nil, 0)
				g_currentMission:showBlinkingWarning(g_i18n:getText("warning_tooFarAway"), 4000)
			end
		end
		if #self.triggeredObjects > 0 and self.triggeredObjects[1][1] ~= self.yieldContainer.object and not self.inputActionActive then
			self.unloadRaycast.found = true
			self.unloadRaycast.object = self.triggeredObjects[1][1]
			self.unloadRaycast.fillUnitIndex = self.triggeredObjects[1][2]
			self.unloadRaycast.distance = self.triggeredObjects[1][3]
			g_inputBinding:setActionEventText(self.eventIdActivateUnload, string.format(g_i18n:getText("action_setContainer"), self.unloadRaycast.object:getFullName()))
			g_inputBinding:setActionEventActive(self.eventIdActivateUnload, true)
			self.inputActionActive = true
		elseif #self.triggeredObjects == 0 and (self.inputActionActive or self.unloadRaycast.found) then
			g_inputBinding:setActionEventActive(self.eventIdActivateUnload, false)
			self.unloadRaycast.found = false
			self.unloadRaycast.object = nil
			self.unloadRaycast.fillUnitIndex = nil
			self.unloadRaycast.distance = 0
			self.inputActionActive = false
		elseif #self.triggeredObjects > 0 and self.yieldContainer.isSet and self.triggeredObjects[1][1] == self.yieldContainer.object and self.inputActionActive then
			g_inputBinding:setActionEventActive(self.eventIdActivateUnload, false)
		end
	end
end

function VineHandTool:getCanHarvest()
	if self.yieldContainer.isSet and self.yieldContainer.object:getFillUnitFreeCapacity(self.yieldContainer.fillUnitIndex, self.fillType) <= 0 then
		return false
	end
	if self.wasLastActivated then
		return false
	end
	return true
end

function VineHandTool:rayCastCallbackTrailerDetection(hitActorId, x, y, z, distance, nx, ny, nz, subShapeIndex, hitShapeId)
	if hitActorId ~= nil then
		local object = g_currentMission:getNodeObject(hitActorId)

		if VehicleDebug.state == VehicleDebug.DEBUG then
			DebugUtil.drawDebugGizmoAtWorldPos(x, y, z, 0, 0, 1, 0, 1, 0, string.format("hitActorId %s (%s); hitShape %s (%s); object %s", getName(hitActorId), hitActorId, getName(hitShapeId), hitShapeId, tostring(object)))
		end

		local validObject = object ~= nil and object ~= self

		if validObject then
			if object.getFirstValidFillUnitToFill ~= nil then
				local fillUnitIndex = object:getFirstValidFillUnitToFill(self.fillType)

				if fillUnitIndex ~= nil then
					table.insert(self.triggeredObjects, {object, fillUnitIndex, distance})
				end
			end
		end

		return true
	end
end

function VineHandTool:setYieldContainer(object, fillUnitIndex, distance, noEventSend)
	self.yieldContainer.isSet = object ~= nil
	self.yieldContainer.object = object
	if object ~= nil and fillUnitIndex == nil then
		self.yieldContainer.fillUnitIndex = object:getFirstValidFillUnitToFill(self.fillType)
	else
		self.yieldContainer.fillUnitIndex = fillUnitIndex
	end
	self.yieldContainer.distance = distance
	--print("Set yieldContainer to "..tostring(object))
	VineHandToolStateEvent.sendEvent(self.player, self.yieldContainer.object, noEventSend)
end

function VineHandTool:raycastCallbackVineDetection(hitActorId, x, y, z, distance, nx, ny, nz, subShapeIndex, hitShapeId, isLast)
	if hitActorId ~= 0 then
		if VehicleDebug.state == VehicleDebug.DEBUG then
			DebugUtil.drawDebugGizmoAtWorldPos(x, y, z, 0, 0, 1, 0, 1, 0, string.format("hitActorId %s (%s); hitShape %s (%s)", getName(hitActorId), hitActorId, getName(hitShapeId), hitShapeId))
		end

		if not self.raycast.isRaycasting then
			self.raycast.currentNode = nil
			self.raycast.placeable = nil
			self.raycast.isRaycasting = false

			return false
		end

		local placeable = g_currentMission.vineSystem:getPlaceable(hitActorId)

		if placeable == nil or g_currentMission.nodeToObject[hitActorId] == self then
			if isLast then
				self.raycast.currentNode = nil
				self.raycast.placeable = nil
				self.raycast.isRaycasting = false

				return false
			end

			return true
		end
		
		if self:handleVinePlaceable(hitActorId, placeable, x, y, z, distance) then
			self.raycast.isRaycasting = false

			return false
		end
		
		return true
	else
		self.raycast.currentNode = nil
		self.raycast.placeable = nil
		self.raycast.isRaycasting = false
	end
end

function VineHandTool:handleVinePlaceable(node, placeable, x, y, z)

    if placeable ~= nil and not self.isCutting then
        if placeable:getVineFruitTypeIndex() ~= self.fruitType then
            return
        end

        local spec = placeable.spec_vine
        local data = spec.nodes[node]

        self.isRotating = true

        self.isCutting = true
        self.wasLastActivated = true
        self.cutTimer = 0
        self.currentCutting.placeable = placeable
        self.currentCutting.poleIndex = data.poleIndex
        self.currentCutting.pos = {x, y, z}
    end

	return true
end


function VineHandTool:harvestCallback(placeable, area, totalArea, weedFactor, sprayFactor, plowFactor, sectionLength)
-- 	print("harvestCallback")
	--local spec = self.spec_vineCutter
	local limeFactor = 1
	local stubbleTillageFactor = 1
	local rollerFactor = 1
	local beeYieldBonusPerc = 0
	local multiplier = g_currentMission:getHarvestScaleMultiplier(FruitType.GRAPE, sprayFactor, plowFactor, limeFactor, weedFactor, stubbleTillageFactor, rollerFactor, beeYieldBonusPerc)
	local realArea = area * multiplier * g_currentMission:getFruitPixelsToSqm() * 1.1
	local farmId = placeable:getOwnerFarmId()

	--spec.currentCombineVehicle:addCutterArea(area, realArea, FruitType.GRAPE, spec.outputFillTypeIndex, 0, nil, farmId, 1)

	local stats = g_currentMission:farmStats(farmId)

	--if spec.inputFruitTypeIndex == FruitType.GRAPE then
	stats:updateStats("harvestedGrapes", sectionLength)
	--elseif spec.inputFruitTypeIndex == FruitType.OLIVE then
	--	stats:updateStats("harvestedOlives", sectionLength)
	--[[else
		local ha = MathUtil.areaToHa(area, g_currentMission:getFruitPixelsToSqm())

		stats:updateStats("threshedHectares", ha)
		stats:updateStats("workedHectares", ha)
	end]]
	--self.yieldContainer.object:addFillUnitFillLevel(g_farmManager:getFarmById(self.player.farmId), self.yieldContainer.fillUnitIndex, realArea, self.fillType, ToolType.UNDEFINED, nil)
	self.yieldContainer.object:addFillUnitFillLevel(self.yieldContainer.object:getOwnerFarmId(), self.yieldContainer.fillUnitIndex, realArea, self.fillType, ToolType.UNDEFINED, nil)
	self.wasLastActivated = true
	--local outputFillType = g_fruitTypeManager:getFillTypeIndexByFruitTypeIndex(FruitType.GRAPE)
	--self.fillLevel = self.fillLevel + realArea
end

function VineHandTool:draw(dt)
	if self.yieldContainer.isSet then
		local x,y = getNormalizedScreenValues(unpack(FillLevelsDisplay.POSITION.BACKGROUND))
		local scale = g_gameSettings:getValue("uiScale")
		local textSize = g_currentMission.inGameMenu.hud.fillLevelsDisplay.fillLevelTextSize or 0.015
		local capacity = self.yieldContainer.object:getFillUnitCapacity(self.yieldContainer.fillUnitIndex)
		local fillLevel = self.yieldContainer.object:getFillUnitFillLevel(self.yieldContainer.fillUnitIndex)
		
		setTextBold(true)
		if self.yieldContainer.distance > self.containerMaxDistance*0.75 then
			setTextColor(1,0,0,1)
		end
		renderText(1 - g_safeFrameOffsetX - 2 * x * scale, g_safeFrameOffsetY + y * scale + textSize*1.1, textSize*1.1, string.format("%s (%d m)", self.yieldContainer.object:getName(), self.yieldContainer.distance))
		setTextColor(1,1,1,1)
		setTextBold(false)
		renderText(1 - g_safeFrameOffsetX - 2 * x * scale, g_safeFrameOffsetY + y * scale, textSize, string.format("%d (%d %%)", fillLevel, math.min(fillLevel/capacity, 1)*100))
	end
	return true
end

--------
function VineHandTool.getNodeFromPoleIndex(placeable, poleIndex)
--     printf("Find index %d in placeable %s", poleIndex, tostring(placeable))
    local vine = placeable.spec_vine
    for node,data in pairs(vine.nodes) do
        if data.poleIndex == poleIndex then
            return node
        end
    end
    return nil
end