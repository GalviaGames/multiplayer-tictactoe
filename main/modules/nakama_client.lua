local nakama = require "nakama.nakama"
local log = require "nakama.util.log"
local defold = require "nakama.engine.defold"
local json = require "nakama.util.json"

local M = {}

M.msgs = {
    MATCH_UPDATE = hash("match_update"),
    OPPONENT_LEFT = hash("opponent_left"),
}

local client = nil
local socket = nil
local match = nil
local listener_url = nil
local match_update_data = nil

local function post_message(id, message)
    if listener_url == nil then
        print("ERROR", "no listener setup")
        return
    end

    msg.post(listener_url, id, message)
end

function M.get_match()
    return match
end

function M.set_listener_url(url, replay_last_message)
    print("setting listener url to", url)
    listener_url = url

    if replay_last_message ~= nil and replay_last_message and match_update_data ~= nil then
        post_message(M.msgs.MATCH_UPDATE, match_update_data)
    end
end

-- match data op-codes
local OP_CODE_MOVE = 1
local OP_CODE_STATE = 2

-- authentication using device id
local function device_login(client)
    local body = nakama.create_api_account_device(defold.uuid())
    -- login using the token and create an account if the user
    -- doesn't already exist
    local result = nakama.authenticate_device(client, body, true)
    if result.token then
        -- store the token and use it when communicating with the server
        nakama.set_bearer_token(client, result.token)
        return true
    end
    log("Unable to login")
    return false
end

-- join a match (provided by the matchmaker)
local function join_match(match_id, token, match_callback)
    nakama.sync(function()
        log("Sending match_join message")
        local message = nakama.create_match_join_message(match_id, token)
        local result = nakama.socket_send(socket, message)
        if result.match then
            match = result.match
            match_callback(true)
        elseif result.error then
            log(result.error.message)
            pprint(result)
            match = nil
            match_callback(false)
        end
    end)
end

-- leave a match
local function leave_match(match_id)
    nakama.sync(function()
        log("Sending match_leave message")
        local message = nakama.create_match_leave_message(match_id)
        local result = nakama.socket_send(socket, message)
        if result.error then
            log(result.error.message)
            pprint(result)
        end
    end)
end

-- find an opponent (using the matchmaker)
-- and then join the match
local function find_opponent_and_join_match(match_callback)
    nakama.on_matchmakermatched(socket, function(message)
        print("on_matchmakermatched")
        local matched = message.matchmaker_matched
        if matched and (matched.match_id or matched.token) then
            join_match(matched.match_id, matched.token, match_callback)
        else
            match_callback(nil)
        end
    end)

    nakama.sync(function()
        log("Sending matchmaker_add message")
        -- find a match with any other player
        -- make sure the match contains exactly 2 users (min 2 and max 2)
        local message = nakama.create_matchmaker_add_message("*", 2, 2)
        local result = nakama.socket_send(socket, message)
        if result.error then
            log(result.error.message)
            pprint(result)
            match_callback(nil)
        end
    end)
end

-- send move as match data
local function send_player_move(match_id, col, row)
    nakama.sync(function()
        local data = json.encode({
            col = col,
            row = row,
        })
        log("Sending match_data message")
        local message = nakama.create_match_data_message(match_id, OP_CODE_MOVE, data)
        local result = nakama.socket_send(socket, message)
        if result.error then
            log(result.error.message)
            pprint(result)
        end
    end)
end

-- handle received match data
-- decode it and pass it on to the game
local function handle_match_data(match_data)
    local data = json.decode(match_data.data)
    local op_code = tonumber(match_data.op_code)
    if op_code == OP_CODE_STATE then
        --xoxo.match_update(data.state, data.active_player, data.other_player, data.your_turn)
        match_update_data = data
        post_message(M.msgs.MATCH_UPDATE, data)
    else
        log(("Unknown opcode %d"):format(op_code))
    end
end

-- handle when a player leaves the match
-- pass this on to the game
local function handle_match_presence(match_presence_event)
    if match_presence_event.leaves and #match_presence_event.leaves > 0 then
        --xoxo.opponent_left()
        -- TODO: handle opponent leaving
        post_message(M.msgs.OPPONENT_LEFT)
    end
end

-- login to Nakama
-- setup listeners
-- * socket events from Nakama
-- * events from the game
function M.login(callback)
    -- enable logging
    log.print()

    -- create server config
    -- we read server url, port and server key from the game.project file
    local config = {}
    config.host = sys.get_config("nakama.host", "127.0.0.1")
    config.port = tonumber(sys.get_config("nakama.port", "7350"))
    config.use_ssl = (config.port == 443)
    config.username = sys.get_config("nakama.server_key", "defaultkey")
    config.password = ""
    config.engine = defold

    client = nakama.create_client(config)

    nakama.sync(function()
        -- Start by doing a device login (the login will be tied
        -- not to a specific user but to the device the game is
        -- running on)
        local ok = device_login(client)
        if not ok then
            callback(false, "Unable to login")
            return
        end

        -- the logged in account
        local account = nakama.get_account(client)
        pprint(account)

        -- Next we create a socket connection as well
        -- we use the socket connetion to exchange messages
        -- with the matchmaker and match
        socket = nakama.create_socket(client)
        local ok, err = nakama.socket_connect(socket)
        if not ok then
            log("Unable to connect: ", err)
            callback(false, "Unable to create socket connection")
            return
        end

        -- Called by Nakama when a player has left (or joined) the
        -- current match.
        -- We notify the game that the opponent has left.
        nakama.on_matchpresence(socket, function(message)
            log("nakama.on_matchpresence")
            handle_match_presence(message.match_presence_event)
        end)

        -- Called by Nakama when the game state has changed.
        -- We parse the data and send it to the game.
        nakama.on_matchdata(socket, function(message)
            log("nakama.on_matchdata")
            handle_match_data(message.match_data)
        end)

        -- This will get called by the game when the player pressed the
        -- Join button in the menu.
        -- We add the logged in player to the matchmaker and join a match
        -- once one is found. We then call the provided callback to let the
        -- game know that it can proceed into the game
        --[[
        xoxo.on_join_match(function(callback)
            log("xoxo.on_join_match")
            find_opponent_and_join_match(callback)
        end)

        -- Called by the game when the player pressed the Leave button
        -- when a game is finished (instead of waiting for the next match).
        -- We send a match leave message to Nakama. Fire and forget.
        xoxo.on_leave_match(function()
            log("xoxo.on_leave_match")
        end)

        -- Called by the game when the player is trying to make a move.
        -- We send a match data message to Nakama.
        xoxo.on_send_player_move(function(row, col)
            log("xoxo.on_send_player_move")
            send_player_move(match.match_id, row, col)
        end)
        ]]

        callback(true)
    end)
end

M.join_match = function(callback)
    if socket == nil then
        print("ERROR", "`socket` is empty")
        return
    end

    find_opponent_and_join_match(callback)
end

M.leave_match = function()
    if match == nil then
        print("ERROR", "`match` is empty")
        return
    end

    leave_match(match.match_id)
end

M.send_player_move = function(col, row)
    if match == nil then
        print("ERROR", "`match` is empty")
        return
    end

    send_player_move(match.match_id, col, row)
end

return M
