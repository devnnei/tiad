-- main.lua

-- Window size
local WINDOW_WIDTH, WINDOW_HEIGHT = 400, 600

-- Scroll directions
local SCROLL_VERTICAL = "vertical"
local SCROLL_HORIZONTAL = "horizontal"

-- Settings (default)
local scrollDirection = SCROLL_VERTICAL
local verticalMode = "downscroll"  -- "downscroll" or "upscroll"
local horizontalMode = "rightscroll"  -- "rightscroll" or "leftscroll"

-- Lanes positions (centered on the white lines)
local LANES_VERTICAL = {100, 300}      -- x positions for vertical scroll
local LANES_HORIZONTAL = {100, 300}    -- y positions for horizontal scroll

-- Player setup
local player = {
    lane = 1,
    x = LANES_VERTICAL[1],
    y = WINDOW_HEIGHT - 100,
    width = 50,
    height = 50,
}

-- Game states
local gameState = "mainmenu" -- "mainmenu", "login", "register", "game", "gamemenu", "highscores"
local gameMode = "play" -- "play", "editor", "chartplay"
local obstacles = {}
local chartData = {}

-- Assets and UI effects
local logoImage = nil
local bgColor = {1, 1, 1} -- White background
local uiPulse = 0
local menuPulse = 0
local scorePulse = 0

-- User system
local currentUser = nil
local users = {} -- Will store user data
local userScores = {} -- Will store high scores per user

-- Timers and scoring
local spawnTimer = 0
local minSpawnInterval = 1.0
local maxSpawnInterval = 1.5
local nextSpawnTime = love.math.random(minSpawnInterval * 100, maxSpawnInterval * 10) / 1980
local obstacleSpeed = 2500
local editorTime = 0
local chartIndex = 1
local score = 0

-- Alternating obstacle system
local lastSpawnedLane = 2  -- Start with lane 2 so first obstacle goes to lane 1
local maxObstaclesPerLane = 2
local laneObstacleCounts = {0, 0}  -- Count obstacles currently in each lane

-- Botplay and input sequence for toggle
local botplay = false
local inputSequence = {}

-- Pause menu state
local paused = false
local pauseMenuOptions = {"Scroll Direction: Vertical", "Scroll Mode: Downscroll", "Resume"}
local selectedOption = 1

-- Main menu options
local mainMenuOptions = {"Login", "Register", "Exit"}
local mainMenuSelected = 1

-- Login/Register form state
local inputMode = "none" -- "username", "password"
local usernameInput = ""
local passwordInput = ""
local loginMessage = ""
local isTypingUsername = false
local isTypingPassword = false

-- Game menu options (after login)
local gameMenuOptions = {"Play Game", "Level Editor", "High Scores", "Load Level (.tiad)", "Logout"}
local gameMenuSelected = 1

-- Simple encryption function (XOR cipher using bit operations)
local function encrypt(text, key)
    local result = ""
    local keyLen = #key
    for i = 1, #text do
        local char = string.byte(text, i)
        local keyChar = string.byte(key, ((i - 1) % keyLen) + 1)
        -- Manual XOR implementation for compatibility
        local xorResult = 0
        local temp1, temp2 = char, keyChar
        local bit = 1
        while temp1 > 0 or temp2 > 0 do
            local bit1 = temp1 % 2
            local bit2 = temp2 % 2
            if bit1 ~= bit2 then
                xorResult = xorResult + bit
            end
            temp1 = math.floor(temp1 / 2)
            temp2 = math.floor(temp2 / 2)
            bit = bit * 2
        end
        result = result .. string.char(xorResult)
    end
    return result
end

local function decrypt(encrypted, key)
    return encrypt(encrypted, key) -- XOR is symmetric
end

-- Helper function: get app data directory
local function getAppDataDir()
    return love.filesystem.getAppdataDirectory() .. "/RhythmDodgeGame"
end

local function getTiadLevelsDir()
    return love.filesystem.getAppdataDirectory() .. "/tiadlevels"
end

-- Helper function: save user data to file with encryption
local function saveUserData()
    local data = "USERS\n"
    for username, userdata in pairs(users) do
        local encryptedPassword = encrypt(userdata.password, "tiad_key_2024")
        data = data .. username .. ":" .. love.data.encode("string", "base64", encryptedPassword) .. "\n"
    end
    data = data .. "SCORES\n"
    for username, scores in pairs(userScores) do
        data = data .. username .. ":" .. table.concat(scores, ",") .. "\n"
    end
    
    -- Create directory if it doesn't exist
    local success = love.filesystem.createDirectory("RhythmDodgeGame")
    if success then
        love.filesystem.write("RhythmDodgeGame/userdata.txt", data)
    end
end

-- Helper function: load user data from file with decryption
local function loadUserData()
    if not love.filesystem.getInfo("RhythmDodgeGame/userdata.txt") then
        return
    end
    
    local mode = "users"
    for line in love.filesystem.lines("RhythmDodgeGame/userdata.txt") do
        if line == "USERS" then
            mode = "users"
        elseif line == "SCORES" then
            mode = "scores"
        elseif line ~= "" then
            local username, data = line:match("([^:]+):(.*)")
            if username and data then
                if mode == "users" then
                    local decryptedPassword = decrypt(love.data.decode("string", "base64", data), "tiad_key_2024")
                    users[username] = {password = decryptedPassword}
                elseif mode == "scores" then
                    userScores[username] = {}
                    for score in data:gmatch("([^,]+)") do
                        table.insert(userScores[username], tonumber(score) or 0)
                    end
                end
            end
        end
    end
end

-- Helper function: register new user
local function registerUser(username, password)
    if username == "" or password == "" then
        return false, "Username and password cannot be empty"
    end
    if users[username] then
        return false, "Username already exists"
    end
    if #username < 3 then
        return false, "Username must be at least 3 characters"
    end
    if #password < 3 then
        return false, "Password must be at least 3 characters"
    end
    
    users[username] = {password = password}
    userScores[username] = {}
    saveUserData()
    return true, "Registration successful!"
end

-- Helper function: login user
local function loginUser(username, password)
    if username == "" or password == "" then
        return false, "Username and password cannot be empty"
    end
    if not users[username] then
        return false, "User not found"
    end
    if users[username].password ~= password then
        return false, "Incorrect password"
    end
    
    currentUser = username
    return true, "Login successful!"
end

-- Helper function: save high score
local function saveHighScore(score)
    if not currentUser then return end
    if not userScores[currentUser] then
        userScores[currentUser] = {}
    end
    
    table.insert(userScores[currentUser], score)
    table.sort(userScores[currentUser], function(a, b) return a > b end)
    
    -- Keep only top 10 scores
    while #userScores[currentUser] > 10 do
        table.remove(userScores[currentUser])
    end
    
    saveUserData()
end

-- Helper function: get user's best scores
local function getUserHighScores(username)
    return userScores[username] or {}
end

-- Helper function: toggle player lane
local function toggleLane()
    player.lane = 3 - player.lane
    if scrollDirection == SCROLL_VERTICAL then
        player.x = LANES_VERTICAL[player.lane]
    else
        player.y = LANES_HORIZONTAL[player.lane]
    end
end

-- Get the next lane for spawning (alternating pattern)
local function getNextLane()
    -- Always alternate lanes
    lastSpawnedLane = 3 - lastSpawnedLane
    return lastSpawnedLane
end

-- Count obstacles currently in each lane
local function updateLaneObstacleCounts()
    laneObstacleCounts = {0, 0}
    for _, obs in ipairs(obstacles) do
        laneObstacleCounts[obs.lane] = laneObstacleCounts[obs.lane] + 1
    end
end

-- Check if we can spawn in a specific lane
local function canSpawnInLane(lane)
    updateLaneObstacleCounts()
    return laneObstacleCounts[lane] < maxObstaclesPerLane
end

-- Spawn a new obstacle on lane (aligned to center of white line)
local function spawnObstacle(lane)
    if scrollDirection == SCROLL_VERTICAL then
        local x = LANES_VERTICAL[lane]
        local y = verticalMode == "downscroll" and -50 or WINDOW_HEIGHT + 50
        table.insert(obstacles, {
            lane = lane,
            x = x,  -- Centered on the lane line
            y = y,
            width = 50,
            height = 50,
        })
    else
        local y = LANES_HORIZONTAL[lane]
        local x = horizontalMode == "rightscroll" and -50 or WINDOW_WIDTH + 50
        table.insert(obstacles, {
            lane = lane,
            x = x,
            y = y,  -- Centered on the lane line
            width = 50,
            height = 50,
        })
    end
end

-- Collision check between rectangles a and b
local function checkCollision(a, b)
    return a.x - a.width / 2 < b.x + b.width / 2 and
           a.x + a.width / 2 > b.x - b.width / 2 and
           a.y - a.height / 2 < b.y + b.height / 2 and
           a.y + a.height / 2 > b.y - b.height / 2
end

-- Save chartData to .tiad file in tiadlevels directory
local function saveChart(filename)
    if not filename:match("%.tiad$") then
        filename = filename .. ".tiad"  -- Force .tiad extension
    end
    
    -- Sort chart data by time
    table.sort(chartData, function(a, b) return a.time < b.time end)
    
    local data = "# T.I.A.D Level File\n# Format: time;lane\n"
    for _, note in ipairs(chartData) do
        data = data .. string.format("%.3f;%d\n", note.time, note.lane)
    end
    
    -- Create tiadlevels directory in appdata
    local success = love.filesystem.createDirectory("tiadlevels")
    if success then
        love.filesystem.write("tiadlevels/" .. filename, data)
        print("Chart saved to tiadlevels/" .. filename)
        return true
    else
        print("Failed to create tiadlevels directory")
        return false
    end
end

-- Load chartData from .tiad file
local function loadTiadChart(filename)
    chartData = {}
    
    -- Try to load from tiadlevels directory first
    local filepath = "tiadlevels/" .. filename
    if not love.filesystem.getInfo(filepath) then
        -- Fallback to original path
        filepath = filename
        if not love.filesystem.getInfo(filepath) then
            print("File not found: " .. filename)
            return false, "File not found: " .. filename
        end
    end

    for line in love.filesystem.lines(filepath) do
        -- Simple trim function
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        -- Skip empty lines and comments
        if line ~= "" and not line:match("^#") then
            local t, lane = line:match("([^;]+);([^;]+)")
            if t and lane then
                t = tonumber(t)
                lane = tonumber(lane)
                if t and lane and (lane == 1 or lane == 2) then
                    table.insert(chartData, { time = t, lane = lane })
                else
                    print("Invalid line in .tiad file: " .. line)
                end
            else
                print("Malformed line: " .. line)
            end
        end
    end

    table.sort(chartData, function(a, b) return a.time < b.time end)
    print("Loaded " .. #chartData .. " notes from " .. filepath)
    return true, "Chart loaded successfully!"
end

-- Start playing chart playback mode
local function startChartPlay()
    gameMode = "chartplay"
    obstacles = {}
    editorTime = 0
    chartIndex = 1
    score = 0
    player.lane = 1
    lastSpawnedLane = 2  -- Reset alternating pattern
    if scrollDirection == SCROLL_VERTICAL then
        player.x = LANES_VERTICAL[1]
        player.y = verticalMode == "downscroll" and (WINDOW_HEIGHT - 100) or 100
    else
        player.x = horizontalMode == "rightscroll" and (WINDOW_WIDTH - 100) or 100
        player.y = LANES_HORIZONTAL[1]
    end
end

-- Game over function
local function gameOver()
    print("Game Over! Final Score: " .. score)
    saveHighScore(score)
    gameState = "gamemenu"
    gameMode = "play"
    obstacles = {}
    score = 0
    player.lane = 1
    if scrollDirection == SCROLL_VERTICAL then
        player.x = LANES_VERTICAL[1]
        player.y = verticalMode == "downscroll" and (WINDOW_HEIGHT - 100) or 100
    else
        player.x = horizontalMode == "rightscroll" and (WINDOW_WIDTH - 100) or 100
        player.y = LANES_HORIZONTAL[1]
    end
end

-- Update obstacles: movement, collision, off-screen removal
local function updateObstacles(dt)
    for i = #obstacles, 1, -1 do
        local obs = obstacles[i]

        if scrollDirection == SCROLL_VERTICAL then
            local direction = verticalMode == "downscroll" and 1 or -1
            obs.y = obs.y + direction * obstacleSpeed * dt
        else
            local direction = horizontalMode == "rightscroll" and 1 or -1
            obs.x = obs.x + direction * obstacleSpeed * dt
        end

        if gameMode == "play" or gameMode == "chartplay" then
            if checkCollision(player, obs) then
                gameOver()
                return
            end
        end

        local shouldRemove = false
        if scrollDirection == SCROLL_VERTICAL then
            if (verticalMode == "downscroll" and obs.y > WINDOW_HEIGHT + 50) or
               (verticalMode == "upscroll" and obs.y < -50) then
                shouldRemove = true
            end
        else
            if (horizontalMode == "rightscroll" and obs.x > WINDOW_WIDTH + 50) or
               (horizontalMode == "leftscroll" and obs.x < -50) then
                shouldRemove = true
            end
        end
        
        if shouldRemove then
            if gameMode ~= "editor" then 
                score = score + 1
                scorePulse = 0.3 -- Create pulse effect for score
            end
            table.remove(obstacles, i)
        end
    end
end

local botReactionDistance = 150
local function botThink()
    for _, obs in ipairs(obstacles) do
        if obs.lane == player.lane then
            if scrollDirection == SCROLL_VERTICAL then
                if verticalMode == "downscroll" then
                    if obs.y > player.y - botReactionDistance and obs.y < player.y then
                        toggleLane()
                        break
                    end
                else
                    if obs.y < player.y + botReactionDistance and obs.y > player.y then
                        toggleLane()
                        break
                    end
                end
            else
                if horizontalMode == "rightscroll" then
                    if obs.x > player.x - botReactionDistance and obs.x < player.x then
                        toggleLane()
                        break
                    end
                else
                    if obs.x < player.x + botReactionDistance and obs.x > player.x then
                        toggleLane()
                        break
                    end
                end
            end
        end
    end
end

function love.load()
    love.window.setMode(WINDOW_WIDTH, WINDOW_HEIGHT)
    love.window.setTitle("T.I.A.D vBeta0.2 - Enhanced Edition")
    
    -- Load user data
    loadUserData()
    
    -- Load logo image
    if love.filesystem.getInfo("assets/base_tiad.png") then
        logoImage = love.graphics.newImage("assets/base_tiad.png")
    end

    if scrollDirection == SCROLL_VERTICAL then
        player.x = LANES_VERTICAL[player.lane]
        player.y = verticalMode == "downscroll" and (WINDOW_HEIGHT - 100) or 100
    else
        player.x = horizontalMode == "rightscroll" and (WINDOW_WIDTH - 100) or 100
        player.y = LANES_HORIZONTAL[player.lane]
    end
end

function love.update(dt)
    -- Update UI effects
    uiPulse = uiPulse + dt * 3
    menuPulse = menuPulse + dt * 2
    if scorePulse > 0 then
        scorePulse = scorePulse - dt * 2
    end
    
    if gameState ~= "game" then return end
    if paused then return end

    if gameMode == "play" then
        spawnTimer = spawnTimer + dt
        if spawnTimer >= nextSpawnTime then
            local nextLane = getNextLane()
            if canSpawnInLane(nextLane) then
                spawnObstacle(nextLane)
            end
            spawnTimer = 0
            nextSpawnTime = love.math.random(minSpawnInterval * 100, maxSpawnInterval * 100) / 1980
        end
        updateObstacles(dt)

    elseif gameMode == "editor" then
        editorTime = editorTime + dt
        updateObstacles(dt)

    elseif gameMode == "chartplay" then
        editorTime = editorTime + dt
        -- Fixed chartplay obstacle spawning
        while chartIndex <= #chartData and chartData[chartIndex].time <= editorTime do
            spawnObstacle(chartData[chartIndex].lane)
            chartIndex = chartIndex + 1
        end
        updateObstacles(dt)
        
        -- Check if chart is complete
        if chartIndex > #chartData and #obstacles == 0 then
            print("Chart completed! Final Score: " .. score)
            saveHighScore(score)
            gameState = "gamemenu"
            gameMode = "play"
        end
    end

    if botplay and (gameMode == "play" or gameMode == "chartplay") then
        botThink()
    end
end

function love.draw()
    if gameState == "mainmenu" then
        -- Energetic animated background
        local pulse = math.sin(uiPulse) * 0.02 + 1
        love.graphics.setColor(bgColor[1] * pulse, bgColor[2] * pulse, bgColor[3] * pulse)
        love.graphics.rectangle("fill", 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
        
        -- Animated background lines
        love.graphics.setColor(0.9 + math.sin(uiPulse * 2) * 0.1, 0.9, 0.9)
        for i = 1, 5 do
            local offset = math.sin(uiPulse + i) * 20
            love.graphics.line(0, 100 + i * 80 + offset, WINDOW_WIDTH, 100 + i * 80 + offset)
        end
        
        -- Draw logo with rhythmic scaling
        if logoImage then
            local scale = 0.4 + math.sin(uiPulse * 1.5) * 0.05
            local logoWidth = logoImage:getWidth() * scale
            local logoHeight = logoImage:getHeight() * scale
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(logoImage, 
                              (WINDOW_WIDTH - logoWidth)/2, 50, 
                              0, scale, scale)
        end
        
        love.graphics.setFont(love.graphics.newFont(16))
        for i, option in ipairs(mainMenuOptions) do
            local y = 300 + i * 40
            local selectedPulse = i == mainMenuSelected and (1 + math.sin(menuPulse * 4) * 0.3) or 1
            love.graphics.setColor((i == mainMenuSelected and {0.2, 0.2, 0.8} or {0.2, 0.2, 0.2}))
            love.graphics.printf(option, selectedPulse * -5, y, WINDOW_WIDTH + selectedPulse * 10, "center")
        end
        
    elseif gameState == "login" or gameState == "register" then
        -- Animated login screen
        local pulse = math.sin(uiPulse) * 0.02 + 1
        love.graphics.setColor(bgColor[1] * pulse, bgColor[2] * pulse, bgColor[3] * pulse)
        love.graphics.rectangle("fill", 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
        
        love.graphics.setColor(0.2 + math.sin(uiPulse) * 0.1, 0.2, 0.8)
        love.graphics.setFont(love.graphics.newFont(20))
        local title = gameState == "login" and "LOGIN" or "REGISTER"
        local titleScale = 1 + math.sin(menuPulse) * 0.1
        love.graphics.printf(title, 0, 150, WINDOW_WIDTH, "center")
        
        love.graphics.setFont(love.graphics.newFont(14))
        
        -- Username field with glow effect
        local userGlow = isTypingUsername and (0.5 + math.sin(uiPulse * 6) * 0.3) or 0
        love.graphics.setColor(0.2 + userGlow, 0.2 + userGlow, 0.8)
        love.graphics.printf("Username:", 0, 220, WINDOW_WIDTH, "center")
        love.graphics.setColor(0.9, 0.9, 0.9)
        love.graphics.rectangle("fill", 100, 240, 200, 25)
        love.graphics.setColor(0, 0, 0)
        love.graphics.print(usernameInput .. (isTypingUsername and "_" or ""), 105, 245)
        
        -- Password field with glow effect
        local passGlow = isTypingPassword and (0.5 + math.sin(uiPulse * 6) * 0.3) or 0
        love.graphics.setColor(0.2 + passGlow, 0.2 + passGlow, 0.8)
        love.graphics.printf("Password:", 0, 280, WINDOW_WIDTH, "center")
        love.graphics.setColor(0.9, 0.9, 0.9)
        love.graphics.rectangle("fill", 100, 300, 200, 25)
        love.graphics.setColor(0, 0, 0)
        local hiddenPassword = string.rep("*", #passwordInput)
        love.graphics.print(hiddenPassword .. (isTypingPassword and "_" or ""), 105, 305)
        
        -- Animated message
        if loginMessage ~= "" then
            local messageGlow = 1 + math.sin(uiPulse * 3) * 0.2
            love.graphics.setColor((loginMessage:find("successful") and {0, 0.7 * messageGlow, 0} or {0.8 * messageGlow, 0, 0}))
            love.graphics.printf(loginMessage, 0, 350, WINDOW_WIDTH, "center")
        end
        
        -- Pulsing instructions
        love.graphics.setColor(0.4 + math.sin(uiPulse * 2) * 0.1, 0.4, 0.4)
        love.graphics.printf("Tab: Switch fields | Enter: Submit | Escape: Back", 0, 400, WINDOW_WIDTH, "center")
        
    elseif gameState == "gamemenu" then
        -- Energetic game menu
        local pulse = math.sin(uiPulse) * 0.02 + 1
        love.graphics.setColor(bgColor[1] * pulse, bgColor[2] * pulse, bgColor[3] * pulse)
        love.graphics.rectangle("fill", 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
        
        -- Draw rhythmic background pattern
        love.graphics.setColor(0.95 + math.sin(uiPulse * 3) * 0.05, 0.95, 0.95)
        for i = 1, 8 do
            local radius = 20 + math.sin(uiPulse * 2 + i) * 10
            love.graphics.circle("line", WINDOW_WIDTH/2 + math.sin(i) * 100, 100 + i * 40, radius)
        end
        
        -- Draw logo with pulse
        if logoImage then
            local scale = 0.3 + math.sin(uiPulse * 1.5) * 0.03
            local logoWidth = logoImage:getWidth() * scale
            local logoHeight = logoImage:getHeight() * scale
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(logoImage, 
                             (WINDOW_WIDTH - logoWidth)/2, 30, 
                             0, scale, scale)
        end
        
        love.graphics.setColor(0.2, 0.2 + math.sin(uiPulse * 2) * 0.1, 0.8)
        love.graphics.setFont(love.graphics.newFont(20))
        love.graphics.printf("Welcome, " .. (currentUser or "Player"), 0, 185, WINDOW_WIDTH, "center")
        
        love.graphics.setFont(love.graphics.newFont(16))
        for i, option in ipairs(gameMenuOptions) do
            local y = 200 + i * 40
            local selectedPulse = i == gameMenuSelected and (1.2 + math.sin(menuPulse * 5) * 0.2) or 1
            love.graphics.setColor(i == gameMenuSelected and {0.2, 0.2, 0.8} or {0.2, 0.2, 0.2})
            love.graphics.printf(option, selectedPulse * -10, y, WINDOW_WIDTH + selectedPulse * 20, "center")
        end
        
    elseif gameState == "highscores" then
        -- Animated high scores
        local pulse = math.sin(uiPulse) * 0.02 + 1
        love.graphics.setColor(bgColor[1] * pulse, bgColor[2] * pulse, bgColor[3] * pulse)
        love.graphics.rectangle("fill", 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
        
        love.graphics.setColor(0.2, 0.2 + math.sin(uiPulse * 2) * 0.1, 0.8)
        love.graphics.setFont(love.graphics.newFont(20))
        love.graphics.printf("HIGH SCORES", 0, 50, WINDOW_WIDTH, "center")
        
        if currentUser then
            local scores = getUserHighScores(currentUser)
            love.graphics.setFont(love.graphics.newFont(14))
            love.graphics.setColor(0.2, 0.2, 0.2)
            love.graphics.printf("Your Best Scores:", 0, 100, WINDOW_WIDTH, "center")
            
            for i = 1, math.min(10, #scores) do
                local rankGlow = 1 + math.sin(uiPulse * 2 + i) * 0.1
                love.graphics.setColor(0.2 * rankGlow, 0.2, 0.2)
                love.graphics.printf(i .. ". " .. scores[i], 0, 120 + i * 25, WINDOW_WIDTH, "center")
            end
            
            if #scores == 0 then
                local noScoreGlow = 1 + math.sin(uiPulse * 3) * 0.2
                love.graphics.setColor(0.4 * noScoreGlow, 0.4, 0.4)
                love.graphics.printf("No scores yet!", 0, 150, WINDOW_WIDTH, "center")
            end
        end
        
        love.graphics.setColor(0.4 + math.sin(uiPulse * 2) * 0.1, 0.4, 0.4)
        love.graphics.printf("Press Escape to go back", 0, 500, WINDOW_WIDTH, "center")
        
    elseif gameState == "game" then
        -- Energetic game background
        local pulse = math.sin(uiPulse * 2) * 0.02 + 1
        love.graphics.setColor(bgColor[1] * pulse, bgColor[2] * pulse, bgColor[3] * pulse)
        love.graphics.rectangle("fill", 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
        
        -- Draw lanes with rhythmic effects
        love.graphics.setColor(0.9 + math.sin(uiPulse * 4) * 0.05, 0.9, 0.9)
        if scrollDirection == SCROLL_VERTICAL then
            for _, x in ipairs(LANES_VERTICAL) do
                love.graphics.rectangle("fill", x - 25, 0, 50, WINDOW_HEIGHT)
            end
        else
            for _, y in ipairs(LANES_HORIZONTAL) do
                love.graphics.rectangle("fill", 0, y - 25, WINDOW_WIDTH, 50)
            end
        end

        -- Draw player with pulse effect
        local playerPulse = 1 + math.sin(uiPulse * 8) * 0.1
        love.graphics.setColor(0.1 * playerPulse, 0.9 * playerPulse, 0.1 * playerPulse)
        love.graphics.rectangle("fill", player.x - player.width / 2, player.y - player.height / 2, player.width, player.height)

        -- Draw obstacles with energy
        for _, obs in ipairs(obstacles) do
            local obsPulse = gameMode == "editor" and 0.4 or (1 + math.sin(uiPulse * 6) * 0.1)
            love.graphics.setColor(gameMode == "editor" and {1 * obsPulse, 0.2 * obsPulse, 0.2 * obsPulse, 0.4} or {0.9 * obsPulse, 0.1 * obsPulse, 0.1 * obsPulse})
            love.graphics.rectangle("fill", obs.x - obs.width / 2, obs.y - obs.height / 2, obs.width, obs.height)
        end

        -- Draw UI text with rhythmic effects
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.print("Mode: " .. gameMode, 10, 10)
        
        -- Animated score with pulse effect
        local scoreScale = 1 + (scorePulse > 0 and scorePulse * 0.5 or 0)
        love.graphics.setColor(0.2, 0.2 + scorePulse * 0.5, 0.2)
        love.graphics.print("Score: " .. score, 10, 30)
        
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.print("Player: " .. (currentUser or "Guest"), 10, 50)
        love.graphics.print("Scroll: " .. scrollDirection .. (scrollDirection == SCROLL_VERTICAL and (" (" .. verticalMode .. ")") or (" (" .. horizontalMode .. ")")), 10, 70)

        if gameMode == "editor" then
            love.graphics.setColor(0.2, 0.2 + math.sin(uiPulse * 3) * 0.1, 0.2)
            love.graphics.print("Editor Time: " .. string.format("%.2f", editorTime), 10, 90)
            love.graphics.print("L/R: place notes  S: save  P: play chart  Space: switch lane", 10, 110)
        elseif gameMode == "chartplay" then
            love.graphics.setColor(0.2, 0.2, 0.8 + math.sin(uiPulse * 4) * 0.1)
            love.graphics.print("CHART PLAYBACK - Time: " .. string.format("%.2f", editorTime), 10, 90)
            love.graphics.print("Notes: " .. chartIndex - 1 .. "/" .. #chartData, 10, 110)
        end

        if botplay then
            local botGlow = 1 + math.sin(uiPulse * 5) * 0.3
            love.graphics.setColor(1 * botGlow, 0.5 * botGlow, 0)
            love.graphics.print("BOTPLAY ENABLED", 10, 130)
        end

        -- Energetic debug info
        love.graphics.setColor(0.4 + math.sin(uiPulse) * 0.1, 0.4, 0.4)
        updateLaneObstacleCounts()
        love.graphics.print("Lane 1: " .. laneObstacleCounts[1] .. " | Lane 2: " .. laneObstacleCounts[2], 10, 150)

        if paused then
            -- Animated pause menu
            love.graphics.setColor(0, 0, 0, 0.7 + math.sin(uiPulse * 2) * 0.1)
            love.graphics.rectangle("fill", 50, 150, 300, 200)

            love.graphics.setColor(1, 1, 1)
            love.graphics.printf("PAUSE MENU", 50, 160, 300, "center")

            for i, option in ipairs(pauseMenuOptions) do
                local y = 180 + i * 30
                local selectedGlow = i == selectedOption and (1 + math.sin(menuPulse * 6) * 0.3) or 1
                love.graphics.setColor(i == selectedOption and {0.2, 0.2, 0.8 * selectedGlow} or {1, 1, 1})
                love.graphics.printf(option, 50, y, 300, "center")
            end
        end
    end
end

function love.keypressed(key)
    key = key:lower()

    if gameState == "mainmenu" then
        if key == "up" then
            mainMenuSelected = mainMenuSelected - 1
            if mainMenuSelected < 1 then mainMenuSelected = #mainMenuOptions end
        elseif key == "down" then
            mainMenuSelected = mainMenuSelected + 1
            if mainMenuSelected > #mainMenuOptions then mainMenuSelected = 1 end
        elseif key == "return" or key == "kpenter" then
            if mainMenuSelected == 1 then -- Login
                gameState = "login"
                usernameInput = ""
                passwordInput = ""
                loginMessage = ""
                isTypingUsername = true
                isTypingPassword = false
            elseif mainMenuSelected == 2 then -- Register
                gameState = "register"
                usernameInput = ""
                passwordInput = ""
                loginMessage = ""
                isTypingUsername = true
                isTypingPassword = false
            elseif mainMenuSelected == 3 then -- Exit
                love.event.quit()
            end
        end
        
    elseif gameState == "login" or gameState == "register" then
        if key == "escape" then
            gameState = "mainmenu"
        elseif key == "tab" then
            isTypingUsername = not isTypingUsername
            isTypingPassword = not isTypingPassword
        elseif key == "return" or key == "kpenter" then
            if gameState == "login" then
                local success, message = loginUser(usernameInput, passwordInput)
                loginMessage = message
                if success then
                    gameState = "gamemenu"
                end
            elseif gameState == "register" then
                local success, message = registerUser(usernameInput, passwordInput)
                loginMessage = message
                if success then
                    gameState = "login"
                    usernameInput = ""
                    passwordInput = ""
                end
            end
        elseif key == "backspace" then
            if isTypingUsername and #usernameInput > 0 then
                usernameInput = usernameInput:sub(1, -2)
            elseif isTypingPassword and #passwordInput > 0 then
                passwordInput = passwordInput:sub(1, -2)
            end
        end
        
    elseif gameState == "gamemenu" then
        if key == "up" then
            gameMenuSelected = gameMenuSelected - 1
            if gameMenuSelected < 1 then gameMenuSelected = #gameMenuOptions end
        elseif key == "down" then
            gameMenuSelected = gameMenuSelected + 1
            if gameMenuSelected > #gameMenuOptions then gameMenuSelected = 1 end
        elseif key == "return" or key == "kpenter" then
            if gameMenuSelected == 1 then -- Play Game
                gameState = "game"
                gameMode = "play"
                obstacles = {}
                score = 0
                player.lane = 1
                lastSpawnedLane = 2
                spawnTimer = 0
                nextSpawnTime = love.math.random(minSpawnInterval * 100, maxSpawnInterval * 100) / 100
                if scrollDirection == SCROLL_VERTICAL then
                    player.x = LANES_VERTICAL[1]
                    player.y = verticalMode == "downscroll" and (WINDOW_HEIGHT - 100) or 100
                else
                    player.x = horizontalMode == "rightscroll" and (WINDOW_WIDTH - 100) or 100
                    player.y = LANES_HORIZONTAL[1]
                end
            elseif gameMenuSelected == 2 then -- Level Editor
                gameState = "game"
                gameMode = "editor"
                editorTime = 0
                chartData = {}
                obstacles = {}
                score = 0
                player.lane = 1
                lastSpawnedLane = 2
                if scrollDirection == SCROLL_VERTICAL then
                    player.x = LANES_VERTICAL[1]
                    player.y = verticalMode == "downscroll" and (WINDOW_HEIGHT - 100) or 100
                else
                    player.x = horizontalMode == "rightscroll" and (WINDOW_WIDTH - 100) or 100
                    player.y = LANES_HORIZONTAL[1]
                end
            elseif gameMenuSelected == 3 then -- High Scores
                gameState = "highscores"
            elseif gameMenuSelected == 4 then -- Load Level (.tiad)
                local success, msg = loadTiadChart("custom.tiad")
                if success then
                    startChartPlay()
                    gameState = "game"
                else
                    loginMessage = msg
                    print(msg)
                end
            elseif gameMenuSelected == 5 then -- Logout
                currentUser = nil
                gameState = "mainmenu"
            end
        end
        
    elseif gameState == "highscores" then
        if key == "escape" then
            gameState = "gamemenu"
        end
        
    elseif gameState == "game" then
        -- Changed from escape to enter for pause/exit
        if key == "return" or key == "kpenter" then
            if gameMode == "editor" then
                -- In editor mode, enter toggles pause menu
                paused = not paused
            else
                -- In play mode, enter returns to main menu
                gameState = "gamemenu"
            end
            return
        end

        if paused then
            if key == "up" then
                selectedOption = selectedOption - 1
                if selectedOption < 1 then selectedOption = #pauseMenuOptions end
            elseif key == "down" then
                selectedOption = selectedOption + 1
                if selectedOption > #pauseMenuOptions then selectedOption = 1 end
            elseif key == "space" then
                if selectedOption == 1 then
                    if scrollDirection == SCROLL_VERTICAL then
                        scrollDirection = SCROLL_HORIZONTAL
                        pauseMenuOptions[1] = "Scroll Direction: Horizontal"
                    else
                        scrollDirection = SCROLL_VERTICAL
                        pauseMenuOptions[1] = "Scroll Direction: Vertical"
                    end
                    player.lane = 1
                    if scrollDirection == SCROLL_VERTICAL then
                        player.x = LANES_VERTICAL[1]
                        player.y = verticalMode == "downscroll" and (WINDOW_HEIGHT - 100) or 100
                    else
                        player.x = horizontalMode == "rightscroll" and (WINDOW_WIDTH - 100) or 100
                        player.y = LANES_HORIZONTAL[1]
                    end
                elseif selectedOption == 2 then
                    if scrollDirection == SCROLL_VERTICAL then
                        verticalMode = verticalMode == "downscroll" and "upscroll" or "downscroll"
                        pauseMenuOptions[2] = "Scroll Mode: " .. (verticalMode:gsub("^%l", string.upper))
                    else
                        horizontalMode = horizontalMode == "rightscroll" and "leftscroll" or "rightscroll"
                        pauseMenuOptions[2] = "Scroll Mode: " .. (horizontalMode:gsub("^%l", string.upper))
                    end
                    if scrollDirection == SCROLL_VERTICAL then
                        player.y = verticalMode == "downscroll" and (WINDOW_HEIGHT - 100) or 100
                    else
                        player.x = horizontalMode == "rightscroll" and (WINDOW_WIDTH - 100) or 100
                    end
                elseif selectedOption == 3 then
                    paused = false
                end
            end
            return
        end

        if key == "up" or key == "down" then
            table.insert(inputSequence, key)
            if #inputSequence > 3 then table.remove(inputSequence, 1) end
            if #inputSequence == 3 and inputSequence[1] == "up" and inputSequence[2] == "down" and inputSequence[3] == "up" then
                botplay = not botplay
                print("Botplay " .. (botplay and "enabled" or "disabled"))
                inputSequence = {}
            end
        end

        if gameMode == "editor" then
            if key == "l" then
                table.insert(chartData, {time = editorTime, lane = 1})
                spawnObstacle(1)
            elseif key == "r" then
                table.insert(chartData, {time = editorTime, lane = 2})
                spawnObstacle(2)
            elseif key == "s" then
                local filename = "level_" .. os.date("%Y%m%d_%H%M%S") .. ".tiad"
                if saveChart(filename) then
                    print("Chart saved as: " .. filename)
                else
                    print("Failed to save chart")
                end
            elseif key == "p" then
                if #chartData > 0 then
                    startChartPlay()
                else
                    print("No chart data to play!")
                end
            elseif key == "space" then
                toggleLane()
            elseif key == "q" then -- Quit to menu
                gameState = "gamemenu"
            end
        else
            if key == "space" then
                toggleLane()
            elseif key == "q" then -- Quit to menu
                gameState = "gamemenu"
            end
        end
    end
end

function love.textinput(text)
    if gameState == "login" or gameState == "register" then
        if isTypingUsername then
            usernameInput = usernameInput .. text
        elseif isTypingPassword then
            passwordInput = passwordInput .. text
        end
    end
end
