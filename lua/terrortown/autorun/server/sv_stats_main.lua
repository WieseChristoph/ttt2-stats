if not SERVER then return end

local DB = include("sv_stats_db.lua")
local Utils = include("terrortown/autorun/shared/sh_stats_utils.lua")

local website = ""

local function log(msg)
  print("[TTT2 Stats] " .. msg .. ".")
end

-- create data folder
if not file.IsDir("ttt2_stats", "DATA") then
  file.CreateDir("ttt2_stats")
end

-- create config.txt if it doesn't exist
if not file.Exists("ttt2_stats/config.txt", "DATA") then
  local config = {
    website = "",
    db = { host = "", port = 3306, username = "", password = "", database = "", caCert = "" }
  }
  local configJson = util.TableToJSON(config)
  file.Write("ttt2_stats/config.txt", configJson)
end

-- read config.txt
if file.Exists("ttt2_stats/config.txt", "DATA") then
  local configJson = file.Read("ttt2_stats/config.txt", "DATA")
  local config = util.JSONToTable(configJson)
  website = config.website
  DB.config.host = config.db.host
  DB.config.port = config.db.port
  DB.config.username = config.db.username
  DB.config.password = config.db.password
  DB.config.database = config.db.database
  DB.config.caCert = config.db.caCert
else
  log("Could not find config.txt")
end

-- open stats on command
hook.Add("PlayerSay", "PlayerChat", function(ply, text)
  if (text == "!stats") then
    ply:SendLua("gui.OpenURL('" .. website .. "')")
  end
end)

-- open stats when F4 is pressed
hook.Add("ShowSpare2", "F4Pressed", function(ply)
  ply:SendLua("gui.OpenURL('" .. website .. "')")
end)

hook.Add("Initialize", "Initialize", function()
  log("Initialized")
  DB:initMap(game.GetMap())
end)

hook.Add("TTTBeginRound", "BeginRound", function()
  -- init round stats
  DB.roundStats = Utils.shallowcopy(DB.initialRoundStats)
  DB.roundStats.startTime = Utils.getFormattedDate()
  -- init player stats
  for i, ply in ipairs(player.GetAll()) do
    if not ply:IsSpec() and not ply:IsBot() then
      DB.roundStats.playerStats[ply:SteamID64()] = Utils.shallowcopy(DB.initialPlayerStats)
    end
  end
end)

hook.Add("TTTEndRound", "EndRound", function(result)
  -- add endTime, winnerTeam to the round and teams to all players
  DB.roundStats.endTime = Utils.getFormattedDate()
  DB.roundStats.winnerTeam = result
  for steamID, stats in pairs(DB.roundStats.playerStats) do
    stats["team"] = player.GetBySteamID64(steamID):GetTeam()
  end

  DB:addRound()
  DB.roundStats = {}
end)

hook.Add("PlayerDeath", "PlayerDeath", function(victim, inflictor, attacker)
  -- round has not ended
  if DB.roundStats.endTime ~= nil and DB.roundStats.endTime == "" then
    -- victim is not a bot
    if not victim:IsBot() then
      -- attacker is a player
      if attacker:IsPlayer() then
        -- attacker and victim are in the current round
        if DB.roundStats.playerStats[attacker:SteamID64()] ~= nil and DB.roundStats.playerStats[victim:SteamID64()] ~= nil then
          -- attacker is not the victim
          if attacker ~= victim then
            -- attacker and victim are in the same team
            if attacker:GetTeam() == victim:GetTeam() then
              -- add teamkill to killer if they are in the same team
              DB.roundStats.playerStats[attacker:SteamID64()]["teamKills"] = DB.roundStats.playerStats
                  [attacker:SteamID64()]["teamKills"] + 1
            else
              -- else add normal kill
              DB.roundStats.playerStats[attacker:SteamID64()]["kills"] = DB.roundStats.playerStats[attacker:SteamID64()]
                  ["kills"] + 1
            end
          end
        end
      end
      -- add death to victim
      DB.roundStats.playerStats[victim:SteamID64()]["deaths"] = DB.roundStats.playerStats[victim:SteamID64()]["deaths"] +
      1
    end
  end
end)
