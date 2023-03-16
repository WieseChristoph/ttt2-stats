require("mysqloo")
local Utils = include("terrortown/autorun/shared/sh_stats_utils.lua")

local tablesSql = [[
    CREATE TABLE IF NOT EXISTS map (
      map_id MEDIUMINT NOT NULL AUTO_INCREMENT,
      map_name VARCHAR(255) NOT NULL,
      map_start_date DATETIME NOT NULL,

      PRIMARY KEY (map_id)
    );

    CREATE TABLE IF NOT EXISTS round (
      round_id MEDIUMINT NOT NULL AUTO_INCREMENT,
      map_id MEDIUMINT NOT NULL,
      round_start_date DATETIME NOT NULL,
      round_end_date DATETIME NOT NULL,
      winner_team_name VARCHAR(255) NOT NULL,

      PRIMARY KEY (round_id)
    );

    CREATE TABLE IF NOT EXISTS statistics (
      statistics_id MEDIUMINT NOT NULL AUTO_INCREMENT,
      round_id MEDIUMINT NOT NULL,
      steam_id BIGINT UNSIGNED NOT NULL,
      team_name VARCHAR(255) NOT NULL,
      kill_num INT NOT NULL,
      team_kill_num INT NOT NULL,
      death_num INT NOT NULL,
      headshot_num INT NOT NULL,

      PRIMARY KEY (statistics_id)
    );
  ]]

local DB = {}

DB.config = {
  host = "",
  port = 3306,
  username = "",
  password = "",
  database = "",
  caCert = ""
}

DB.roundStats = {}

DB.initialRoundStats = {
  startTime = "",
  endTime = "",
  winnerTeam = "",
  playerStats = {}
}

DB.initialPlayerStats = {
  team = "",
  kills = 0,
  teamKills = 0,
  deaths = 0,
  headshots = 0,
}

function DB.log(msg)
  print("[TTT2 Stats][DB] " .. msg .. ".")
end

function DB:connect()
  local connection = mysqloo.connect(
    self.config.host,
    self.config.username,
    self.config.password,
    self.config.database,
    self.config.port
  )

  connection:setSSLSettings(nil, nil, self.config.caCert == "" and nil or self.config.caCert, nil, nil)

  function connection:onConnectionFailed(err)
    DB.log("Connection to database failed")
    DB.log("Error: " .. err)
  end

  connection:connect()

  return connection
end

function DB:initMap(mapName)
  DB.log("Creating tables")
  local connection = self:connect()

  local query = connection:query(tablesSql)
  function query:onError(err)
    DB.log("Error: " .. err)
    return connection:disconnect()
  end

  function query:onSuccess()
    DB.log("Adding map " .. mapName)

    local sql = "INSERT INTO map (map_name, map_start_date) VALUES (?, ?)"
    local prep = connection:prepare(sql)
    prep:setString(1, mapName)
    prep:setString(2, Utils.getFormattedDate())
    function prep:onError(err)
      DB.log("Error: " .. err)
    end

    prep:start()

    connection:disconnect(true)
  end

  query:start()
end

function DB:addRound()
  DB.log("Adding round")
  local connection = self:connect()

  local roundStats = Utils.shallowcopy(self.roundStats)

  local roundSql =
  "INSERT INTO round (map_id, round_start_date, round_end_date, winner_team_name) VALUES ((SELECT map_id FROM map ORDER BY map_start_date DESC LIMIT 1), ?, ?, ?)"
  local roundPrep = connection:prepare(roundSql)
  roundPrep:setString(1, roundStats.startTime)
  roundPrep:setString(2, roundStats.endTime)
  roundPrep:setString(3, roundStats.winnerTeam)

  function roundPrep:onError(err)
    DB.log("Error: " .. err)
    return connection:disconnect()
  end

  function roundPrep:onSuccess()
    local roundID = roundPrep:lastInsert()

    local transaction = connection:createTransaction()

    function transaction:onError(err)
      DB.log("Error: " .. err)
    end

    local statsSql =
    "INSERT INTO statistics (round_id, steam_id, team_name, kill_num, team_kill_num, death_num, headshot_num) VALUES (?, ?, ?, ?, ?, ?, ?)"
    local statsPrep = connection:prepare(statsSql)
    statsPrep:setNumber(1, roundID)
    for steamID, stats in pairs(roundStats.playerStats) do
      statsPrep:setString(2, steamID)
      statsPrep:setString(3, stats.team)
      statsPrep:setNumber(4, stats.kills)
      statsPrep:setNumber(5, stats.teamKills)
      statsPrep:setNumber(6, stats.deaths)
      statsPrep:setNumber(7, stats.headshots)
      transaction:addQuery(statsPrep)
    end

    transaction:start()

    connection:disconnect(true)
  end

  roundPrep:start()
end

return DB
