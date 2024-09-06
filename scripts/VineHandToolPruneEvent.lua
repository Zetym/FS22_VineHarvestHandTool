VineHandToolPruneEvent = {}
local VineHandToolPruneEvent_mt = Class(VineHandToolPruneEvent, Event)

InitEventClass(VineHandToolPruneEvent, "VineHandToolPruneEvent")

function VineHandToolPruneEvent.emptyNew()
	local self = Event.new(VineHandToolPruneEvent_mt)

	return self
end

function VineHandToolPruneEvent.new(player, placeable, poleIndex, x, y, z)
	local self = VineHandToolPruneEvent.emptyNew()
    self.player = player
	self.placeable = placeable
	self.poleIndex = poleIndex
    self.x = x
    self.y = y
    self.z = z

	return self
end

function VineHandToolPruneEvent:readStream(streamId, connection)
    self.player = NetworkUtil.readNodeObject(streamId)
	self.placeable = NetworkUtil.readNodeObject(streamId)
	self.poleIndex = streamReadInt32(streamId)
    self.x = streamReadFloat32(streamId)
    self.y = streamReadFloat32(streamId)
    self.z = streamReadFloat32(streamId)
	self:run(connection)
end

function VineHandToolPruneEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.player)
	NetworkUtil.writeNodeObject(streamId, self.placeable)
	streamWriteInt32(streamId, self.poleIndex)
    streamWriteFloat32(streamId, self.x)
    streamWriteFloat32(streamId, self.y)
    streamWriteFloat32(streamId, self.z)
end

function VineHandToolPruneEvent:run(connection)
	if not g_server then
        printError("VineHandToolPruneEvent sent to non-server. This is not intended")
        return
	end
--     print("Run vine prune")
    local tool = self.player.baseInformation.currentHandtool
    if tool ~= nil then
        local node = VineHandTool.getNodeFromPoleIndex(self.placeable, self.poleIndex)
        if node ~= nil then
            local x, y, z = self.x, self.y, self.z
            self.placeable:prepareVine(node, x-0.3, y-0.1, z-0.3, x+0.3, y+0.1, z+0.3)
        end
    end
end

function VineHandToolPruneEvent.sendEvent(player, placeable, poleIndex, x, y, z, noEventSend)
	local currentTool = player.baseInformation.currentHandtool
-- 	print("sendPruneEvent 1")
	if currentTool ~= nil and (noEventSend == nil or noEventSend == false) then
--         print("sendPruneEvent 2")
        g_client:getServerConnection():sendEvent(VineHandToolPruneEvent.new(player, placeable, poleIndex, x, y, z))
--         print("g_client:sendPruneEvent")
	end
end
