--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function gadget:GetInfo()
  return {
    name      = "Mission Helper",
    desc      = "bla",
    author    = "KingRaptor",
    date      = "2014.04.26",
    license   = "GNU GPL, v2 or later",
    layer     = -100,
    enabled   = true  --  loaded by default?
  }
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- shared constants

local STAGE_PARAM = "tutorial_stage"
local MOVE_CIRCLE_RADIUS = 50
local MOVE_CIRCLE_RADIUS_SQ = MOVE_CIRCLE_RADIUS^2

local circles = {
	{4245, 0, 3445},
	{4140, 0, 3545},
	{4245, 0, 3645},
	{4140, 0, 3745},
}

local MOVE_DEST_1 = {3610, 3580}
local FIGHT_DEST = {6378, 3580}
local SOLAR_POS = {5112, 3464}
local MEX_POS = {5112, 3592}
local FAC_POS = {5120, 3752}

for i=1,#circles do
	local circle = circles[i]
	local y = Spring.GetGroundHeight(circle[1], circle[3])
	if y < 5 then
		y = 5
	end
	circle[2] = y
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
if (gadgetHandler:IsSyncedCode()) then
--------------------------------------------------------------------------------
-- SYNCED
--------------------------------------------------------------------------------
include("LuaRules/Configs/customcmds.h.lua")

local BUTTON_PARAM = "tutorial_show_next_button"

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local stages = {
	[1] = {name = "camera", trigger = "Comm Found"},
	[2] = {name = "select comm"},
	[3] = {name = "move comm"},
	[4] = {name = "select multiple", trigger = "Line Move"},
	[5] = {name = "line move", trigger = "Attack Target"},
	[6] = {name = "attack"},
	[7] = {name = "build mex"},
	[8] = {name = "build solar"},
	[9] = {name = "build factory"},
	[10] = {name = "assist fac", trigger = "Build Glaives"},
	[11] = {name = "build glaives"},
	[12] = {name = "attack move", trigger = "Victory"},
	[13] = {name = "end"},
}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local function AdvanceStage()
	local stage = Spring.GetGameRulesParam(STAGE_PARAM)		
	local stagedata = stages[stage]
	if stagedata and stagedata.trigger then
		GG.mission.ExecuteTriggerByName(stagedata.trigger)
	end
end

local function count(tab)
	local count = 0
	for i in pairs(tab) do
		count = count + 1
	end
	return count
end

local function ProcessForbiddenCommand(unitID, cmdID, cmdParams)
	if #cmdParams >= 3 then
		SendToUnsynced("mission_CommandBlocked", cmdID, cmdParams[1], cmdParams[2], cmdParams[3], cmdParams[4])
	else
		if #cmdParams == 1 then unitID = cmdParams[1] end
		local x, y, z = Spring.GetUnitPosition(unitID)
		if x and y and z then
			SendToUnsynced("mission_CommandBlocked", cmdID, x, y, z)
		end
	end
end

local function LineMoveCheck()
	-- check if all the circles have units already there or heading to it
	local validCircles = {}
	local occupiedCircles = {}
	local units = Spring.GetTeamUnits(0)
	for i=1,#units do
		local unitID = units[i]
		local unitDefID = Spring.GetUnitDefID(unitID)
		local unitDef = UnitDefs[unitDefID]
		if unitDef.canMove then
			local ux, uy, uz = Spring.GetUnitPosition(unitID)
			for i=1,#circles do
				if not validCircles[i] then
					local circle = circles[i]
					-- check if unit is already occupying it
					local distSq = (ux - circle[1])^2 + (uz - circle[3])^2
					if distSq < MOVE_CIRCLE_RADIUS_SQ then
						validCircles[i] = true
						occupiedCircles[i] = true
						break
					else
						-- check if unit is headed there
						local cmd = (Spring.GetUnitCommands(unitID, 1))[1]
						if cmd and (cmd.id == CMD.MOVE or cmd.id == CMD_RAW_MOVE) then
							distSq = (cmd.params[1] - circle[1])^2 + (cmd.params[3] - circle[3])^2
							if distSq < MOVE_CIRCLE_RADIUS_SQ then
								validCircles[i] = true
								break
							end
						end
					end
				end
			end
		end
		if count(validCircles) == 4 then
			break
		end
	end
	if count(occupiedCircles) == 4 then
		AdvanceStage()
	elseif count(validCircles) < 4 then
		for i=1,#units do
			local cmds = Spring.GetUnitCommands(units[i], 1)
			if cmds[1] then
				ProcessForbiddenCommand(units[i], cmds[1].id, cmds[1].params)
			end
		end
		Spring.GiveOrderToUnitArray(units, CMD.STOP, {}, 0)
	end
end

local function CmdDistCheck(cmdParams, targetPos, maxDist)
	maxDist = maxDist or 96
	local x, z = cmdParams[1], cmdParams[3]
	return math.abs(targetPos[1] - x) < maxDist and math.abs(targetPos[2] - z) < maxDist
end

local function IsCommandAllowed(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOpts, cmdTag, synced)
	if cmdID == CMD.INSERT then
		return gadget:AllowCommand(unitID, unitDefID, teamID, cmdParams[2],
		{cmdParams[4], cmdParams[5], cmdParams[6], cmdParams[7]}, cmdParams[3], cmdParams[1], synced)
	end
	
	if cmdID == CMD.RECLAIM then
		return false
	end
	
	if (cmdID == CMD_RAW_MOVE or cmdID == CMD.MOVE) and Spring.GetGameRulesParam(STAGE_PARAM) == 3 then
		return CmdDistCheck(cmdParams, MOVE_DEST_1, 120)
		
	elseif (cmdID == CMD.ATTACK) and Spring.GetGameRulesParam(STAGE_PARAM) == 6 then
		return #cmdParams == 1
		
	elseif (cmdID == -UnitDefNames.staticmex.id) and Spring.GetGameRulesParam(STAGE_PARAM) == 7 then
		return CmdDistCheck(cmdParams, MEX_POS)
		
	elseif (cmdID == -UnitDefNames.energysolar.id) and Spring.GetGameRulesParam(STAGE_PARAM) == 8 then
		return CmdDistCheck(cmdParams, SOLAR_POS)
		
	elseif (cmdID == -UnitDefNames.factorycloak.id) and Spring.GetGameRulesParam(STAGE_PARAM) == 9 then
		return CmdDistCheck(cmdParams, FAC_POS) and cmdParams[4] == 1
		
	elseif (cmdID == CMD.GUARD) and Spring.GetGameRulesParam(STAGE_PARAM) == 10 then
		local commID = GG.mission.FindUnitInGroup("Comm")
		if commID and commID ~= unitID then
			return false
		end
		
		local targetID = cmdParams[1]
		local tDefID = Spring.GetUnitDefID(targetID)
		if tDefID == UnitDefNames.factorycloak.id then
			AdvanceStage()
			return true
		else
			return false
		end
	
	elseif (cmdID == CMD.STOP) and Spring.GetGameRulesParam(STAGE_PARAM) == 11 then
		return false
	
	elseif Spring.GetGameRulesParam(STAGE_PARAM) == 12 and #cmdParams >= 3 then
		return cmdParams[2] >= 260 and CmdDistCheck(cmdParams, FIGHT_DEST, 1200)
	end
	
	return true
end
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
function gadget:AllowCommand_GetWantedCommand()	
	return {
		[CMD.MOVE] = true,
		[CMD_RAW_MOVE] = true,
		[CMD.ATTACK] = true,
		[CMD.FIGHT] = true,
		[CMD.RECLAIM] = true,
		[CMD.GUARD] = true,
		[CMD.STOP] = true,
		[CMD.INSERT] = true,
		
		[-UnitDefNames.staticmex.id] = true,
		[-UnitDefNames.energysolar.id] = true,
		[-UnitDefNames.factorycloak.id] = true
	}
end

function gadget:AllowCommand_GetWantedUnitDefID()	
	return true
end

function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOpts, cmdTag, synced)
	if teamID ~= 0 then
		return true
	end
	local allowed = IsCommandAllowed(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOpts, cmdTag, synced)
	if not allowed then
		ProcessForbiddenCommand(unitID, cmdID, cmdParams)
		return false
	end
	
	return true
end

function gadget:RecvLuaMsg(msg)
	if msg == "tutorial_next" then
		AdvanceStage()
	end
end

function gadget:Initialize()
	Spring.SetGameRulesParam(BUTTON_PARAM, 0)
	Spring.SetGameRulesParam(STAGE_PARAM, 0)
end

function gadget:Shutdown()
end

function gadget:GameFrame(n)
	if Spring.GetGameRulesParam(STAGE_PARAM) == 5 then
		LineMoveCheck()
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
else
--------------------------------------------------------------------------------
-- UNSYNCED
--------------------------------------------------------------------------------
local UPDATE_INTERVAL = 4	-- every 4 screenframes
local circleDivs = 65
local ZOOM_DIST_SQ = 900 * 900

local stageChecks = {
	[1] = function()
		local visible = Spring.GetVisibleUnits(0, nil, false)
		if #visible == 0 then
			return false
		end
		for i=1,#visible do
			local unitID = visible[i]
			local unitDefID = Spring.GetUnitDefID(unitID)
			
			local isComm = UnitDefs[unitDefID].customParams.level ~= nil
			if isComm then
				local x1, y1, z1 = Spring.GetCameraPosition()
				local x2, y2, z2 = Spring.GetUnitPosition(unitID)
				
				local distSq = (x2-x1)^2 + (z2-z1)^2
				if distSq <= ZOOM_DIST_SQ and (y1 - y2) < 700 then
					return true
				end
			end
		end
		return false
	end,
	
	[4] = function()
		local selected = Spring.GetSelectedUnits()
		if #selected >= 4 then
			local hasCommander = false
			for i=1,#selected do
				local unitID = selected[i]
				local unitDefID = Spring.GetUnitDefID(unitID)
				local unitDef = UnitDefs[unitDefID]
				if unitDef.customParams.level then	-- is comm
					hasCommander = true
					break
				end
			end
			return hasCommander
		end
		return false
	end,
}


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local screenTimer = 0
local stage = 1
function gadget:Update()
	screenTimer = screenTimer + 1
	if screenTimer > UPDATE_INTERVAL then
		screenTimer = 0
		stage = Spring.GetGameRulesParam(STAGE_PARAM)
		if stageChecks[stage] and stageChecks[stage]() == true then	-- NEXT!
			Spring.SendLuaRulesMsg("tutorial_next")
		end
	end
end

function gadget:DefaultCommand(type, targetID)
	--if stage == 12 then
	--	return CMD.FIGHT
	--end
	if (type == 'feature') then
		return CMD.MOVE
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- drawing functions

-- from customFormations2
local function tVerts(verts)
	for i = 1, #verts do
		local v = verts[i]
        if v[1] and v[2] and v[3] then
            gl.Vertex(v[1], v[2], v[3])
        end
	end
end

local function DrawFormationLines()
	gl.LineStipple(1, 4095)
	gl.LineWidth(4)
	
	gl.Color(0.5, 1.0, 0.5, 0.8)
	gl.BeginEnd(GL.LINE_STRIP, tVerts, circles)
	gl.Color(1,1,1,1)
	
	gl.LineWidth(1.0)
	gl.LineStipple(false)
end

local function DrawCircleInside(circleDivs, r, g, b, alpha, radius)
	local radstep = (2.0 * math.pi) / circleDivs
	for i = 1, circleDivs do
		local a1 = (i * radstep)
		local a2 = ((i+1) * radstep)
		gl.Color(r, g, b, 0)
		gl.Vertex(0, 0, 0)
		gl.Color(r, g, b, alpha)
		gl.Vertex(math.sin(a1)*radius, 0, math.cos(a1)*radius)
		gl.Vertex(math.sin(a2)*radius, 0, math.cos(a2)*radius)
	end
end

--[[
local function DrawCircleRim(circleDivs, numSlices, r, g, b, alpha, fadealpha, radius)
	local radstep = (2.0 * math.pi) / circleDivs
	for i = 1, numSlices do
		local a1 = (i * radstep)
		local a2 = ((i+1) * radstep)
		gl.Color(r, g, b, fadealpha)
		gl.Vertex(math.sin(a1)* radius * innersize, 0, math.cos(a1)*radius * innersize)
		gl.Vertex(math.sin(a2)* radius * innersize, 0, math.cos(a2)*radius * innersize)
		gl.Color(r, g, b, alpha)
		gl.Vertex(math.sin(a2) * radius * outersize, 0, math.cos(a2) * radius * outersize)
		gl.Vertex(math.sin(a1) * radius * outersize, 0, math.cos(a1) * radius * outersize)
	end
end
]]

local function DrawPointCircle(point)
	local r1, g1, b1 = 0.2, 0.4, 0.5
	
	gl.PushMatrix()
	gl.Translate(point[1], point[2] + 10, point[3])
	gl.BeginEnd(GL.TRIANGLES, DrawCircleInside, circleDivs, r1, g1, b1, 0.8, MOVE_CIRCLE_RADIUS)
	gl.PopMatrix()
end

function gadget:DrawWorldPreUnit()
	if not Spring.IsGUIHidden() and Spring.GetGameRulesParam(STAGE_PARAM) == 5 then
		--gl.DepthTest(true)
		for _,v in pairs(circles) do
			DrawPointCircle(v)
		end
		DrawFormationLines()
		gl.Color(1,1,1,1)
		--gl.DepthTest(false)
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
end
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------