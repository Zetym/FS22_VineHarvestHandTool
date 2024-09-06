VineHandToolHarvestEvent = {}
local VineHandToolHarvestEvent_mt = Class(VineHandToolHarvestEvent, Event)

InitEventClass(VineHandToolHarvestEvent, "VineHandToolHarvestEvent")

function VineHandToolHarvestEvent.emptyNew()
	local self = Event.new(VineHandToolHarvestEvent_mt)

	return self
end

function VineHandToolHarvestEvent.new(player, placeable, poleIndex, x, y, z)
	local self = VineHandToolHarvestEvent.emptyNew()
    self.player = player
	self.placeable = placeable
	self.poleIndex = poleIndex
    self.x = x
    self.y = y
    self.z = z

	return self
end

function VineHandToolHarvestEvent:readStream(streamId, connection)
    self.player = NetworkUtil.readNodeObject(streamId)
	self.placeable = NetworkUtil.readNodeObject(streamId)
	self.poleIndex = streamReadInt32(streamId)
    self.x = streamReadFloat32(streamId)
    self.y = streamReadFloat32(streamId)
    self.z = streamReadFloat32(streamId)
	self:run(connection)
end

function VineHandToolHarvestEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.player)
	NetworkUtil.writeNodeObject(streamId, self.placeable)
	streamWriteInt32(streamId, self.poleIndex)
    streamWriteFloat32(streamId, self.x)
    streamWriteFloat32(streamId, self.y)
    streamWriteFloat32(streamId, self.z)
end

function VineHandToolHarvestEvent:run(connection)
	if not g_server then
        printError("VineHandToolHarvestEvent sent to non-server. This is not intended")
        return
	end
    local tool = self.player.baseInformation.currentHandtool
--     print("Run vine harvest")
    if tool ~= nil and tool.yieldContainer.isSet then
        local node = VineHandTool.getNodeFromPoleIndex(self.placeable, self.poleIndex)
--         printf("harvestVine %s", tostring(node))
        if node ~= nil then
            local x, y, z = self.x, self.y, self.z
            self.placeable:harvestVine(node, x-0.3, y-0.2, z-0.3, x+0.3, y+0.2, z+0.3, tool.harvestCallback, tool)
        end
    end
end

function VineHandToolHarvestEvent.sendEvent(player, placeable, poleIndex, x, y, z, noEventSend)
	local currentTool = player.baseInformation.currentHandtool
-- 	print("sendHarvestEvent 1")
	if currentTool ~= nil and (noEventSend == nil or noEventSend == false) then
--         print("sendHarvestEvent 2")
        g_client:getServerConnection():sendEvent(VineHandToolHarvestEvent.new(player, placeable, poleIndex, x, y, z))
--         print("g_client:sendHarvestEvent")
	end
end
