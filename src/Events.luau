--[[
    Pathfind Library - Event System
    
    Lightweight event bus for Pathfind events.
    Wraps BindableEvents for clean connection management.
    
    @author Pathfind Contributors
    @version 1.2.0
    @license MIT
]]

local Event = {}
Event.__index = Event

export type Event = typeof(setmetatable({} :: {
    _bindable: BindableEvent,
    _connections: { RBXScriptConnection },
}, Event))

function Event.new(): Event
    local self = setmetatable({}, Event)
    self._bindable = Instance.new("BindableEvent")
    self._connections = {}
    return self
end

function Event:Fire(...: any)
    self._bindable:Fire(...)
end

function Event:Connect(callback: (...any) -> ()): RBXScriptConnection
    local connection = self._bindable.Event:Connect(callback)
    table.insert(self._connections, connection)
    return connection
end

function Event:Once(callback: (...any) -> ())
    local connection
    connection = self._bindable.Event:Connect(function(...)
        callback(...)
        if connection.Connected then
            connection:Disconnect()
        end
    end)
    table.insert(self._connections, connection)
    return connection
end

function Event:Wait(): ...any
    return self._bindable.Event:Wait()
end

function Event:DisconnectAll()
    for _, conn in self._connections do
        if conn.Connected then
            conn:Disconnect()
        end
    end
    table.clear(self._connections)
end

function Event:Destroy()
    self:DisconnectAll()
    self._bindable:Destroy()
end

return Event
