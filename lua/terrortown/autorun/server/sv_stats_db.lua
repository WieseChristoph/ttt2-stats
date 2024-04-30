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
      steam_id VARCHAR(17) NOT NULL,
      team_name VARCHAR(255) NOT NULL,

      PRIMARY KEY (statistics_id)
    );

    CREATE TABLE IF NOT EXISTS death (
      death_id MEDIUMINT NOT NULL AUTO_INCREMENT,
      statistics_id MEDIUMINT NOT NULL,
      attacker_id VARCHAR(17),
      teamkill_status BOOL NOT NULL,
      inflictor_name VARCHAR(255),
      hitgroup_id INT NOT NULL,

      PRIMARY KEY (death_id)
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
  deaths = {}
}

DB.initialDeathStats = {
  attacker = nil,
  teamkill = false,
  inflictor = nil,
  hitgroup = 0
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
  local connection = self:connect()
  DB.log("Checking for tables")

  local sql =
  "SELECT COUNT(*) AS tables_found_count FROM INFORMATION_SCHEMA.Tables WHERE TABLE_NAME IN ('map', 'round', 'statistics', 'death');"
  local query = connection:query(sql)
  function query:onError(err)
    DB.log("Error: " .. err)
  end

  function query:onSuccess(data)
    local tablesFound = data[1]["tables_found_count"]
    if tablesFound == 4 then
      DB.log("Tables found")
      DB:addMap(mapName)
    else
      DB.log("Tables not found")
      DB:createTables(mapName)
    end
  end

  query:start()
  connection:disconnect(true)
end

function DB:createTables(mapName)
  local connection = self:connect()
  DB.log("Creating tables")

  local query = connection:query(tablesSql)
  function query:onError(err)
    DB.log("Error: " .. err)
  end

  function query:onSuccess()
    DB.log("Tables created")
    DB:addMap(mapName)
  end

  query:start()

  connection:disconnect(true)
end

function DB:addMap(mapName)
  local connection = self:connect()
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

function DB:addRound()
  DB.log("Adding round")
  local connection = self:connect()

  local roundStats = Utils.deepcopy(self.roundStats)

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

    local statsSql = "INSERT INTO statistics (round_id, steam_id, team_name) VALUES (?, ?, ?);"
    local deathSql =
    "INSERT INTO death (statistics_id, attacker_id, teamkill_status, inflictor_name, hitgroup_id) VALUES (LAST_INSERT_ID(), ?, ?, ?, ?);"

    local statsPrep = connection:prepare(statsSql)
    local deathPrep = connection:prepare(deathSql)

    for steamID, stats in pairs(roundStats.playerStats) do
      statsPrep:setNumber(1, roundID)
      statsPrep:setString(2, steamID)
      statsPrep:setString(3, stats.team)
      transaction:addQuery(statsPrep)
      statsPrep:clearParameters()
      for index, death in ipairs(stats.deaths) do
        if (death.attacker == nil) then
          deathPrep:setNull(1)
        else
          deathPrep:setString(1, death.attacker)
        end
        deathPrep:setBoolean(2, death.teamkill)
        if (death.inflictor == nil) then
          deathPrep:setNull(3)
        else
          deathPrep:setString(3, death.inflictor)
        end
        deathPrep:setNumber(4, death.hitgroup)
        transaction:addQuery(deathPrep)
        deathPrep:clearParameters()
      end
    end

    transaction:start()

    connection:disconnect(true)
  end

  roundPrep:start()
end

return DB
