--[[
    Pathfind Library
    
    A lightweight, modular, production-ready pathfinding library
    for Roblox that wraps PathfindingService with a clean, modern API.
    
    Features:
    - Smooth waypoint following with natural movement
    - Automatic jump handling
    - Intelligent line-of-sight waypoint skipping
    - Anti-stuck detection and recovery
    - Character respawn handling
    - Configurable timeout and settings
    - Debug visualization
    - Client-side compatible
    
    Usage:
        local Pathfind = require(path.to.Pathfind)
        
        local path = Pathfind.new(character, {
            debug = true,
            agentCanJump = true,
        })
        
        path.Completed:Connect(function(success)
            print("Path completed:", success)
        end)
        
        path:GoTo(workspace.TargetPart)
    
    @author SairyTheKing
    @version 1.2.0
    @license MIT
    @see https://github.com/SairyTheKing/Pathfind
]]

local Pathfind = require(script.Pathfind)

return Pathfind
