
--[[=====================================================

NULLE STUDIOS

ULTIMATE ANTI-CHEAT v9 - Factual Detection System

Temporary bans with factual violation messages

=====================================================]]

-- SERVICES

local Players = game:GetService("Players")

local DataStoreService = game:GetService("DataStoreService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")

print("🔄 ULTIMATE ANTI-CHEAT v9: Initializing...")

-- CRITICAL: CREATE REMOTES IMMEDIATELY

local BanEvent = Instance.new("RemoteEvent")

BanEvent.Name = "BanEvent"

BanEvent.Parent = ReplicatedStorage

local AntiCheatGUIRemote = Instance.new("RemoteEvent")

AntiCheatGUIRemote.Name = "AntiCheatGUIRemote"

AntiCheatGUIRemote.Parent = ReplicatedStorage

print("✅ Remotes created successfully")

--=====================================================

-- DATASTORE FOR TEMPORARY BANS

--=====================================================

local BanStore = DataStoreService:GetDataStore("Nulle_AntiCheat_TempBans_v9")

local banCache = {}

local function saveTempBan(userId, banData)

local success, err = pcall(function()

	BanStore:SetAsync(tostring(userId), banData)

end)



if success then

	banCache[userId] = banData

	print("📝 Temp ban saved:", userId, "| Duration:", banData.DurationMinutes, "minutes")

	return true

else

	warn("❌ Failed to save temp ban:", err)

	return false

end

end

local function getTempBan(userId)

if banCache[userId] then

	return banCache[userId]

end



local banData

local success = pcall(function()

	banData = BanStore:GetAsync(tostring(userId))

end)



if success and banData then

	-- Check if ban is still active

	if os.time() < banData.ExpiryTime then

		banCache[userId] = banData

		return banData

	else

		-- Remove expired ban

		pcall(function() BanStore:RemoveAsync(tostring(userId)) end)

		banCache[userId] = nil

	end

end



return nil

end

local function removeTempBan(userId)

pcall(function()

	BanStore:RemoveAsync(tostring(userId))

end)

banCache[userId] = nil

end

--=====================================================

-- FACTUAL CONFIGURATION

--=====================================================

local CONFIG = {

-- Network

PingKickMS = 800,



-- Movement Detection (Factual Limits)

NormalWalkSpeed = 16,

SprintSpeed = 30,

MaxPossibleSpeed = 50, -- Human running + game mechanics

SpeedHackThreshold = 60, -- Clearly impossible



-- Flight Detection (Factual Physics)

Gravity = 196.2, -- Roblox gravity

MaxJumpHeight = 7.5, -- Studs

TerminalVelocity = -100, -- Max fall speed

SuspiciousHoverTime = 2.0, -- Can't hover without falling

MaxAirTime = 5.0, -- Including double jumps, gliding



-- Teleport Detection

MaxMovementPerFrame = 30, -- Studs per 0.2 seconds

TeleportThreshold = 100, -- Definitely teleported



-- Noclip Detection

WallThicknessCheck = 3,



-- Violation System

ViolationsBeforeBan = {

	Minor = 5,    -- Multiple minor violations

	Major = 2,    -- Multiple major violations

	Critical = 1  -- Immediate for critical

},

ViolationDecayTime = 300, -- 5 minutes



-- Ban System

KickDelay = 10, -- 10 seconds warning

BanDurations = {

	Minor = 30 * 60,      -- 30 minutes

	Major = 60 * 60,      -- 1 hour

	Critical = 24 * 60 * 60, -- 24 hours

	Repeat = 7 * 24 * 60 * 60 -- 7 days for repeat offenders

},



-- Detection Timing

CheckInterval = 0.2,

RespawnGrace = 2.0

}

--=====================================================

-- FACTUAL VIOLATION DETECTION

--=====================================================

local VIOLATIONS = {

-- Speed violations

SPEED_HACK = {

	id = "SPEED_HACK",

	level = "CRITICAL",

	message = "Movement Speed Manipulation",

	description = "Your character was moving at %d studs/second, which exceeds the physically possible maximum of %d studs/second.",

	evidence = function(speed, maxSpeed) return {speed, maxSpeed} end

},



SPEED_EXCESS = {

	id = "SPEED_EXCESS",

	level = "MAJOR",

	message = "Excessive Movement Speed",

	description = "Your character moved at %d studs/second, significantly faster than normal game mechanics allow.",

	evidence = function(speed) return {speed} end

},



-- Flight violations

FLIGHT_HOVER = {

	id = "FLIGHT_HOVER",

	level = "CRITICAL",

	message = "Anti-Gravity / Hovering",

	description = "Your character hovered in place for %.1f seconds without falling, violating gravity physics.",

	evidence = function(hoverTime) return {hoverTime} end

},



FLIGHT_AIRTIME = {

	id = "FLIGHT_AIRTIME",

	level = "MAJOR",

	message = "Extended Air Time",

	description = "Your character remained airborne for %.1f seconds, exceeding the maximum possible air time of %.1f seconds.",

	evidence = function(airTime, maxAirTime) return {airTime, maxAirTime} end

},



-- Teleport violations

TELEPORT_DETECTED = {

	id = "TELEPORT_DETECTED",

	level = "CRITICAL",

	message = "Position Teleportation",

	description = "Your character moved %d studs in %.2f seconds, which is physically impossible without teleportation.",

	evidence = function(distance, time) return {distance, time} end

},



-- Wall violations

NOCLIP_DETECTED = {

	id = "NOCLIP_DETECTED",

	level = "CRITICAL",

	message = "Wall / Object Penetration",

	description = "Your character passed through solid objects, bypassing collision physics.",

	evidence = function() return {} end

},



-- Pattern violations

MULTIPLE_VIOLATIONS = {

	id = "MULTIPLE_VIOLATIONS",

	level = "MAJOR",

	message = "Multiple Violation Pattern",

	description = "You triggered %d separate violations within %d seconds, indicating systematic cheating.",

	evidence = function(count, seconds) return {count, seconds} end

}

}

--=====================================================

-- PLAYER STATE MANAGEMENT

--=====================================================

local playerStates = {}

local violationHistory = {}

local function initPlayerState(player)

playerStates[player] = {

	-- Movement tracking

	lastPosition = nil,

	lastVelocity = Vector3.zero,

	lastUpdate = os.clock(),



	-- Flight tracking

	groundContactTime = os.clock(),

	airStartTime = nil,

	hoverStartTime = nil,

	lastVerticalVelocity = 0,



	-- Jump tracking (for realistic limits)

	jumpCount = 0,

	lastJumpTime = 0,



	-- Violation tracking

	violations = {},

	violationScore = 0,



	-- Physics state

	lastFloorMaterial = Enum.Material.Air,

	isOnGround = true

}



violationHistory[player] = {}

print("👤 Monitoring started for:", player.Name)

end

local function clearPlayerState(player)

playerStates[player] = nil

violationHistory[player] = nil

end

--=====================================================

-- FACTUAL DETECTION FUNCTIONS

--=====================================================

local function logViolation(player, violationType, evidence)

if not violationHistory[player] then

	violationHistory[player] = {}

end



local state = playerStates[player]

if not state then return end



local violation = {

	type = violationType,

	time = os.time(),

	evidence = evidence,

	position = player.Character and player.Character:GetPivot().Position

}



table.insert(violationHistory[player], violation)



-- Keep only last 20 violations

while #violationHistory[player] > 20 do

	table.remove(violationHistory[player], 1)

end



-- Add to state violations

state.violations[violationType.id] = (state.violations[violationType.id] or 0) + 1



-- Calculate violation score based on level

local scoreMap = {MINOR = 1, MAJOR = 3, CRITICAL = 10}

state.violationScore = state.violationScore + (scoreMap[violationType.level] or 1)



-- Log to console

local evidenceText = ""

if evidence and #evidence > 0 then

	evidenceText = "Evidence: " .. table.concat(evidence, ", ")

end



print("⚠️ VIOLATION | Player:", player.Name, 

	"| Type:", violationType.message,

	"| Level:", violationType.level,

	evidenceText ~= "" and "| " .. evidenceText or "")



return violation

end

local function getRecentViolations(player, seconds)

if not violationHistory[player] then return 0 end



local count = 0

local cutoff = os.time() - seconds



for _, violation in ipairs(violationHistory[player]) do

	if violation.time >= cutoff then

		count = count + 1

	end

end



return count

end

-- FACTUAL SPEED CHECK

local function checkSpeed(player, state, hrp, hum)

local currentVelocity = hrp.AssemblyLinearVelocity

local speed = currentVelocity.Magnitude

local deltaTime = os.clock() - state.lastUpdate



if deltaTime <= 0 then return false end



-- Get humanoid state

local isSprinting = hum:GetAttribute("Sprinting") or false

local maxNaturalSpeed = isSprinting and CONFIG.SprintSpeed or CONFIG.NormalWalkSpeed



-- Check for speed hacks

if speed > CONFIG.SpeedHackThreshold then

	local violation = logViolation(player, VIOLATIONS.SPEED_HACK, 

		VIOLATIONS.SPEED_HACK.evidence(math.floor(speed), CONFIG.SpeedHackThreshold))



	-- Immediate ban for extreme speed

	return true, violation



elseif speed > CONFIG.MaxPossibleSpeed then

	logViolation(player, VIOLATIONS.SPEED_EXCESS,

		VIOLATIONS.SPEED_EXCESS.evidence(math.floor(speed)))



elseif speed > maxNaturalSpeed * 1.8 then -- 80% over natural speed

	logViolation(player, VIOLATIONS.SPEED_EXCESS,

		VIOLATIONS.SPEED_EXCESS.evidence(math.floor(speed)))

end



-- Check acceleration (sudden speed changes)

if state.lastVelocity then

	local acceleration = (speed - state.lastVelocity.Magnitude) / deltaTime



	-- Humans can't accelerate instantly

	if math.abs(acceleration) > 500 then -- 500 studs/s² is impossible

		logViolation(player, VIOLATIONS.SPEED_EXCESS,

			VIOLATIONS.SPEED_EXCESS.evidence(math.floor(speed)))

	end

end



state.lastVelocity = currentVelocity

return false

end

-- FACTUAL FLIGHT CHECK

local function checkFlight(player, state, hrp, hum)

local currentVelocity = hrp.AssemblyLinearVelocity

local verticalVelocity = currentVelocity.Y

local isOnGround = hum.FloorMaterial ~= Enum.Material.Air



-- Update ground state

if isOnGround and not state.isOnGround then

	-- Just landed

	state.groundContactTime = os.clock()

	state.airStartTime = nil

	state.hoverStartTime = nil

	state.jumpCount = 0

elseif not isOnGround and state.isOnGround then

	-- Just left ground

	state.airStartTime = os.clock()

	state.hoverStartTime = nil

	state.jumpCount = state.jumpCount + 1

end



state.isOnGround = isOnGround

state.lastFloorMaterial = hum.FloorMaterial



-- Check for hovering (anti-gravity)

if not isOnGround then

	local airTime = state.airStartTime and (os.clock() - state.airStartTime) or 0



	-- Check vertical movement

	if math.abs(verticalVelocity) < 1.0 then -- Almost no vertical movement

		if not state.hoverStartTime then

			state.hoverStartTime = os.clock()

		else

			local hoverTime = os.clock() - state.hoverStartTime



			if hoverTime > CONFIG.SuspiciousHoverTime then

				local violation = logViolation(player, VIOLATIONS.FLIGHT_HOVER,

					VIOLATIONS.FLIGHT_HOVER.evidence(hoverTime))



				-- Immediate ban for extended hovering

				return true, violation

			end

		end

	else

		state.hoverStartTime = nil

	end



	-- Check total air time

	if airTime > CONFIG.MaxAirTime then

		logViolation(player, VIOLATIONS.FLIGHT_AIRTIME,

			VIOLATIONS.FLIGHT_AIRTIME.evidence(airTime, CONFIG.MaxAirTime))

	end



	-- Check falling speed (should accelerate due to gravity)

	if verticalVelocity > CONFIG.TerminalVelocity / 2 then

		-- Falling too slowly

		state.violationScore = state.violationScore + 0.5

	end

else

	state.hoverStartTime = nil

end



state.lastVerticalVelocity = verticalVelocity

return false

end

-- FACTUAL TELEPORT CHECK

local function checkTeleport(player, state, hrp)

if not state.lastPosition then

	state.lastPosition = hrp.Position

	return false

end



local deltaTime = os.clock() - state.lastUpdate

if deltaTime <= 0 then return false end



local distance = (hrp.Position - state.lastPosition).Magnitude

local maxPossible = (state.lastVelocity.Magnitude * deltaTime) + 5 -- Allow small margin



-- Check for teleportation

if distance > CONFIG.TeleportThreshold then

	local violation = logViolation(player, VIOLATIONS.TELEPORT_DETECTED,

		VIOLATIONS.TELEPORT_DETECTED.evidence(math.floor(distance), deltaTime))



	-- Immediate ban for extreme teleport

	return true, violation



elseif distance > maxPossible * 3 and deltaTime < 0.5 then

	logViolation(player, VIOLATIONS.TELEPORT_DETECTED,

		VIOLATIONS.TELEPORT_DETECTED.evidence(math.floor(distance), deltaTime))

end



state.lastPosition = hrp.Position

return false

end

-- FACTUAL NOCLIP CHECK

local function checkNoclip(player, state, hrp)

local raycastParams = RaycastParams.new()

raycastParams.FilterType = Enum.RaycastFilterType.Blacklist

raycastParams.FilterDescendantsInstances = {player.Character}

raycastParams.IgnoreWater = true



-- Check in 4 horizontal directions

local directions = {

	Vector3.new(1, 0, 0),

	Vector3.new(-1, 0, 0),

	Vector3.new(0, 0, 1),

	Vector3.new(0, 0, -1)

}



local rayCount = 0

local hitCount = 0



for _, dir in ipairs(directions) do

	local ray = workspace:Raycast(hrp.Position, dir * CONFIG.WallThicknessCheck, raycastParams)

	rayCount = rayCount + 1



	if ray then

		hitCount = hitCount + 1

	end

end



-- If no rays hit anything, player is inside walls

if hitCount == 0 and rayCount == 4 and not state.isOnGround then

	local violation = logViolation(player, VIOLATIONS.NOCLIP_DETECTED, {})

	return true, violation

end



return false

end

--=====================================================

-- ENFORCEMENT SYSTEM

--=====================================================

local function determineBanDetails(player, violation)

local state = playerStates[player]

if not state then return nil end



-- Get recent violation count

local recentCount = getRecentViolations(player, 60) -- Last minute



-- Determine ban level based on violation severity and pattern

local banLevel = "MINOR"

local banDuration = CONFIG.BanDurations.Minor



if violation then

	-- Base on violation level

	if violation.type.level == "CRITICAL" then

		banLevel = "CRITICAL"

		banDuration = CONFIG.BanDurations.Critical

	elseif violation.type.level == "MAJOR" then

		banLevel = "MAJOR"

		banDuration = CONFIG.BanDurations.Major

	end

end



-- Escalate based on violation pattern

if recentCount >= 3 then

	banLevel = "MAJOR"

	banDuration = CONFIG.BanDurations.Major

end



if state.violationScore >= 15 then

	banLevel = "CRITICAL"

	banDuration = CONFIG.BanDurations.Critical

end



-- Check for repeat offenses (previous bans)

local previousBan = getTempBan(player.UserId)

if previousBan and previousBan.OffenseCount then

	banLevel = "REPEAT"

	banDuration = CONFIG.BanDurations.Repeat

end



-- Generate factual ban message

local banMessage = violation and violation.type.message or "Multiple Violations"

local banDescription = violation and string.format(violation.type.description, table.unpack(violation.evidence or {})) or 

	string.format("You triggered %d violations within 60 seconds.", recentCount)



return {

	level = banLevel,

	duration = banDuration,

	message = banMessage,

	description = banDescription,

	violationCount = recentCount,

	offenseCount = previousBan and previousBan.OffenseCount + 1 or 1

}

end

local function enforceBan(player, violation)

if player:GetAttribute("BeingEnforced") then return end

player:SetAttribute("BeingEnforced", true)



local banDetails = determineBanDetails(player, violation)

if not banDetails then return end



-- Create ban data

local banData = {

	UserId = player.UserId,

	Username = player.Name,

	Reason = banDetails.message,

	Description = banDetails.description,

	Level = banDetails.level,

	DurationMinutes = math.floor(banDetails.duration / 60),

	ExpiryTime = os.time() + banDetails.duration,

	Timestamp = os.time(),

	OffenseCount = banDetails.offenseCount,

	ViolationCount = banDetails.violationCount

}



-- Save temporary ban

saveTempBan(player.UserId, banData)



-- CRITICAL LOGGING

print("\n🚨🚨🚨 TEMPORARY BAN ISSUED 🚨🚨🚨")

print("Player:", player.Name)

print("UserId:", player.UserId)

print("Violation:", banDetails.message)

print("Description:", banDetails.description)

print("Ban Level:", banDetails.level)

print("Duration:", banData.DurationMinutes, "minutes")

print("Expires:", os.date("%Y-%m-%d %H:%M:%S", banData.ExpiryTime))

print("Previous Offenses:", banDetails.offenseCount - 1)

print("Recent Violations:", banDetails.violationCount)

print("----------------------------------------")



-- Notify client

pcall(function()

	BanEvent:FireClient(player, banDetails.message, banDetails.description, banData.DurationMinutes)

	AntiCheatGUIRemote:FireClient(player, {

		Type = "Ban",

		Message = banDetails.message,

		Description = banDetails.description,

		DurationMinutes = banData.DurationMinutes,

		ExpiryTime = banData.ExpiryTime,

		ViolationCount = banDetails.violationCount

	})

end)



-- Kick after delay with countdown

local kickDelay = CONFIG.KickDelay

print("⏱️ Player will be kicked in", kickDelay, "seconds")



for i = kickDelay, 1, -1 do

	task.wait(1)

	if not player or not player.Parent then break end

	print("   " .. player.Name .. " kicking in " .. i .. "s...")

end



task.delay(kickDelay, function()

	if player and player.Parent then

		local kickMsg = string.format(

			"Anti-Cheat: %s\n\n%s\n\nTemporary ban: %d minutes\nYou may rejoin after %s",

			banDetails.message,

			banDetails.description,

			banData.DurationMinutes,

			os.date("%H:%M:%S", banData.ExpiryTime)

		)

		player:Kick(kickMsg)

	end

end)

end

--=====================================================

-- MAIN DETECTION LOOP

--=====================================================

local function performDetection(player)

local state = playerStates[player]

if not state then return end



-- Check if already being banned

if player:GetAttribute("BeingEnforced") then return end



-- Check respawn grace period

if os.clock() - (state.respawnTime or 0) < CONFIG.RespawnGrace then

	state.lastPosition = nil

	return

end



-- Validate character

if not player.Character then

	state.lastPosition = nil

	return

end



local hrp = player.Character:FindFirstChild("HumanoidRootPart")

local hum = player.Character:FindFirstChildOfClass("Humanoid")



if not hrp or not hum or hum.Health <= 0 then

	state.lastPosition = nil

	return

end



-- Check network ownership

local networkOwner

local success, owner = pcall(function() return hrp:GetNetworkOwner() end)

if success and owner and owner ~= player then

	state.lastPosition = nil

	return

end



-- Perform all checks

local criticalViolation = false

local violation



-- Check speed

local speedResult, speedViolation = checkSpeed(player, state, hrp, hum)

if speedResult then

	criticalViolation = true

	violation = speedViolation

end



-- Check flight

if not criticalViolation then

	local flightResult, flightViolation = checkFlight(player, state, hrp, hum)

	if flightResult then

		criticalViolation = true

		violation = flightViolation

	end

end



-- Check teleport

if not criticalViolation then

	local teleportResult, teleportViolation = checkTeleport(player, state, hrp)

	if teleportResult then

		criticalViolation = true

		violation = teleportViolation

	end

end



-- Check noclip

if not criticalViolation then

	local noclipResult, noclipViolation = checkNoclip(player, state, hrp)

	if noclipResult then

		criticalViolation = true

		violation = noclipViolation

	end

end



-- Check violation patterns

if not criticalViolation then

	local recentViolations = getRecentViolations(player, 60)

	if recentViolations >= CONFIG.ViolationsBeforeBan.Minor then

		violation = {

			type = VIOLATIONS.MULTIPLE_VIOLATIONS,

			evidence = {recentViolations, 60}

		}

		criticalViolation = true

	end

end



-- Enforce ban if needed
	if criticalViolation then
  
		enforceBan(player, violation)
  
	end
  

  
	-- Update timers
  
	state.lastUpdate = os.clock()
  

  
	-- Decay violation score over time
  
	if os.time() % 10 == 0 then -- Every 10 seconds
  
		state.violationScore = math.max(0, state.violationScore - 0.5)
  
	end
  
end
  

  
--=====================================================
  
-- PLAYER MANAGEMENT
  
--=====================================================
  
Players.PlayerAdded:Connect(function(player)
  
	print("🎮 Player joined:", player.Name, "ID:", player.UserId)
  

  
	task.wait(0.5)
  

  
	-- Check for active temp ban
  
	local tempBan = getTempBan(player.UserId)
  
	if tempBan then
  
		local timeLeft = tempBan.ExpiryTime - os.time()
  

  
		if timeLeft > 0 then
  
			local minutesLeft = math.floor(timeLeft / 60)
  
			local secondsLeft = math.floor(timeLeft % 60)
  

  
			print("🚫 Temporarily banned player attempted join:", player.Name)
  
			print("   Reason:", tempBan.Reason)
  
			print("   Time remaining:", minutesLeft, "minutes", secondsLeft, "seconds")
  
			print("   Expires:", os.date("%H:%M:%S", tempBan.ExpiryTime))
  

  
			-- Notify player
  
			pcall(function()
  
				BanEvent:FireClient(player, 
  
					"Temporary Ban Active", 
  
					string.format("You are temporarily banned for %d more minutes.\n\nReason: %s\n\nBan expires at: %s",
  
						minutesLeft,
  
						tempBan.Description or tempBan.Reason,
  
						os.date("%H:%M:%S", tempBan.ExpiryTime)
  
					),
  
					minutesLeft
  
				)
  
			end)
  

  
			task.delay(5, function()
  
				if player and player.Parent then
  
					player:Kick(string.format(
  
						"Temporary Ban\n\n%s\n\nTime remaining: %d minutes %d seconds\nExpires: %s",
  
						tempBan.Description or tempBan.Reason,
  
						minutesLeft,
  
						secondsLeft,
  
						os.date("%H:%M:%S", tempBan.ExpiryTime)
  
						))
  
				end
  
			end)
  

  
			return
  
		else
  
			-- Remove expired ban
  
			removeTempBan(player.UserId)
  
		end
  
	end
  

  
	-- Initialize player state
  
	initPlayerState(player)
  

  
	-- Send welcome notification
  
	pcall(function()
  
		AntiCheatGUIRemote:FireClient(player, {
  
			Type = "Notification",
  
			Message = "Factual Anti-Cheat System Active",
  
			Description = "Violations are detected based on factual physics limits.",
  
			Duration = 5
  
		})
  
	end)
  

  
	-- Handle respawns
  
	player.CharacterAdded:Connect(function(char)
  
		local state = playerStates[player]
  
		if state then
  
			state.respawnTime = os.clock()
  
			state.lastPosition = nil
  
			state.isOnGround = true
  
			state.groundContactTime = os.clock()
  

  
			-- Small violation reset on respawn
  
			state.violationScore = math.max(0, state.violationScore - 2)
  
		end
  

  
		task.wait(0.5)
  
	end)
  

  
	-- Start detection loop
  
	task.spawn(function()
  
		while player and player.Parent do
  
			performDetection(player)
  
			task.wait(CONFIG.CheckInterval)
  
		end
  
	end)
  
end)
  

  
Players.PlayerRemoving:Connect(function(player)
  
	clearPlayerState(player)
  
	print("👋 Player left:", player.Name)
  
end)
  

  
--=====================================================
  
-- ADMIN COMMANDS
  
--=====================================================
  
game:GetService("ReplicatedStorage"):SetAttribute("CheckPlayerBan", function(userId)
  
	local ban = getTempBan(userId)
  
	if ban then
  
		local timeLeft = ban.ExpiryTime - os.time()
  
		return string.format(
  
			"Player %s (%d) is banned.\nReason: %s\nTime left: %d minutes\nExpires: %s",
  
			ban.Username, userId, ban.Description, math.floor(timeLeft / 60),
  
			os.date("%Y-%m-%d %H:%M:%S", ban.ExpiryTime)
  
		)
  
	end
  
	return "No active ban found."
  
end)
  

  
game:GetService("ReplicatedStorage"):SetAttribute("UnbanPlayer", function(userId)
  
	removeTempBan(userId)
  
	return "Ban removed for user ID: " .. userId
  
end)
  

  
--=====================================================
  
-- SYSTEM STARTUP
  
--=====================================================
  
print("\n============================================")
  
print("✅ FACTUAL ANTI-CHEAT v9 LOADED")
  
print("✅ Temporary bans (30min - 7 days)")
  
print("✅ Factual violation messages")
  
print("✅ 10-second kick warning")
  
print("✅ Physics-based detection")
  
print("============================================")
  

  
warn("Factual Anti-Cheat System is now active!")
