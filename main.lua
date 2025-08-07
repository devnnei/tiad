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
local gameState = "mainmenu" -- "mainmenu", "login", "register", "game"
local gameMode = "play" -- "play", "editor", "chartplay"
local obstacles = {}
local chartData = {}

-- Assets
local logoImage = nil
local bgColor = {1, 1, 1} -- White background

-- User system
local currentUser = nil
local users = {} -- Will store user data
local userScores = {} -- Will store high scores per user

-- Timers and scoring
local spawnTimer = 0
local minSpawnInterval = 1.0
local maxSpawnInterval = 1.5
local nextSpawnTime = love.math.random(minSpawnInterval * 100, maxSpawnInterval * 100) / 100
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

-- Helper function: save user data to file
local function saveUserData()
    local data = "USERS\n"
    for username, userdata in pairs(users) do
        data = data .. username .. ":" .. userdata.password .. "\n"
    end
    data = data .. "SCORES\n"
    for username, scores in pairs(userScores) do
        data = data .. username .. ":" .. table.concat(scores, ",") .. "\n"
    end
    love.filesystem.write("userdata.txt", data)
end

-- Helper function: load user data from file
local function loadUserData()
    if not love.filesystem.getInfo("userdata.txt") then
        return
    end
    
    local mode = "users"
    for line in love.filesystem.lines("userdata.txt") do
        if line == "USERS" then
            mode = "users"
        elseif line == "SCORES" then
            mode = "scores"
        elseif line ~= "" then
            local username, data = line:match("([^:]+):(.*)")
            if username and data then
                if mode == "users" then
                    users[username] = {password = data}
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

-- Save chartData to file
-- Save chartData to .tiad file
local function saveChart(filename)
    if not filename:match("%.tiad$") then
        filename = filename .. ".tiad"  -- Force .tiad extension
    end
    local data = ""
    for _, note in ipairs(chartData) do
        data = data .. string.format("%.2f,%d\n", note.time, note.lane)
    end
    love.filesystem.write(filename, data)
    print("Chart saved to " .. filename)
end

-- Load chartData from file
local function loadChart(filename)
    -- Load chart from a .tiad file
local function loadTiadChart(filename)
    chartData = {}
    if not love.filesystem.getInfo(filename) then
        print("File not found: " .. filename)
        return false, "File not found: " .. filename
    end

    for line in love.filesystem.lines(filename) do
        line = line:trim()
        -- Skip empty lines and comments
        if line ~= "" and not line:match("^#") then
            local t, lane = line:match("([^,]+),([^,]+)")
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
    print("Loaded " .. #chartData .. " notes from " .. filename)
    return true, "Chart loaded successfully!"
end
    chartData = {}
    if not love.filesystem.getInfo(filename) then
        print("No chart file found: " .. filename)
        return
    end
    for line in love.filesystem.lines(filename) do
        local t, lane = line:match("([^,]+),([^,]+)")
        if t and lane then
            table.insert(chartData, {time = tonumber(t), lane = tonumber(lane)})
        end
    end
    print("Chart loaded with " .. #chartData .. " notes")
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

        if gameMode == "play" and checkCollision(player, obs) then
            gameOver()
            return
        end

        if scrollDirection == SCROLL_VERTICAL then
            if (verticalMode == "downscroll" and obs.y > WINDOW_HEIGHT + 50) or
               (verticalMode == "upscroll" and obs.y < -50) then
                if gameMode ~= "editor" then score = score + 1 end
                table.remove(obstacles, i)
            end
        else
            if (horizontalMode == "rightscroll" and obs.x > WINDOW_WIDTH + 50) or
               (horizontalMode == "leftscroll" and obs.x < -50) then
                if gameMode ~= "editor" then score = score + 1 end
                table.remove(obstacles, i)
            end
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
    love.window.setTitle("Rhythm Dodge Game")
    
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
        while chartIndex <= #chartData and chartData[chartIndex].time <= editorTime do
            spawnObstacle(chartData[chartIndex].lane)
            chartIndex = chartIndex + 1
        end
        updateObstacles(dt)
    end

    if botplay and (gameMode == "play" or gameMode == "chartplay") then
        botThink()
    end
end

function love.draw()
    if gameState == "mainmenu" then
        -- Draw main menu with white background
        love.graphics.setColor(bgColor)
        love.graphics.rectangle("fill", 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
        
        -- Draw logo (scaled down from 500x500 to fit)
        if logoImage then
            local scale = 0.4 -- Adjust scale to fit
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
            love.graphics.setColor(i == mainMenuSelected and {0.2, 0.2, 0.8} or {0.2, 0.2, 0.2})
            love.graphics.printf(option, 0, y, WINDOW_WIDTH, "center")
        end
        
    elseif gameState == "login" or gameState == "register" then
        -- Draw login/register screen with white background
        love.graphics.setColor(bgColor)
        love.graphics.rectangle("fill", 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
        
        love.graphics.setColor(0.2, 0.2, 0.8)
        love.graphics.setFont(love.graphics.newFont(20))
        local title = gameState == "login" and "LOGIN" or "REGISTER"
        love.graphics.printf(title, 0, 150, WINDOW_WIDTH, "center")
        
        love.graphics.setFont(love.graphics.newFont(14))
        
        -- Username field
        love.graphics.setColor(isTypingUsername and {0.2, 0.2, 0.8} or {0.2, 0.2, 0.2})
        love.graphics.printf("Username:", 0, 220, WINDOW_WIDTH, "center")
        love.graphics.setColor(0.9, 0.9, 0.9)
        love.graphics.rectangle("fill", 100, 240, 200, 25)
        love.graphics.setColor(0, 0, 0)
        love.graphics.print(usernameInput .. (isTypingUsername and "_" or ""), 105, 245)
        
        -- Password field
        love.graphics.setColor(isTypingPassword and {0.2, 0.2, 0.8} or {0.2, 0.2, 0.2})
        love.graphics.printf("Password:", 0, 280, WINDOW_WIDTH, "center")
        love.graphics.setColor(0.9, 0.9, 0.9)
        love.graphics.rectangle("fill", 100, 300, 200, 25)
        love.graphics.setColor(0, 0, 0)
        local hiddenPassword = string.rep("*", #passwordInput)
        love.graphics.print(hiddenPassword .. (isTypingPassword and "_" or ""), 105, 305)
        
        -- Message
        if loginMessage ~= "" then
            love.graphics.setColor(loginMessage:find("successful") and {0, 0.7, 0} or {0.8, 0, 0})
            love.graphics.printf(loginMessage, 0, 350, WINDOW_WIDTH, "center")
        end
        
        -- Instructions
        love.graphics.setColor(0.4, 0.4, 0.4)
        love.graphics.printf("Tab: Switch fields | Enter: Submit | Escape: Back", 0, 400, WINDOW_WIDTH, "center")
        
    elseif gameState == "gamemenu" then
        -- Draw game menu (after login) with white background
        love.graphics.setColor(bgColor)
        love.graphics.rectangle("fill", 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
        
        -- Draw logo if available
        if logoImage then
            local scale = 0.3
            local logoWidth = logoImage:getWidth() * scale
            local logoHeight = logoImage:getHeight() * scale
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(logoImage, 
                             (WINDOW_WIDTH - logoWidth)/2, 30, 
                             0, scale, scale)
        end
        
        love.graphics.setColor(0.2, 0.2, 0.8)
        love.graphics.setFont(love.graphics.newFont(20))
        love.graphics.printf("Welcome, " .. (currentUser or "Player"), 0, 185, WINDOW_WIDTH, "center")
        
        love.graphics.setFont(love.graphics.newFont(16))
        for i, option in ipairs(gameMenuOptions) do
            local y = 200 + i * 40
            love.graphics.setColor(i == gameMenuSelected and {0.2, 0.2, 0.8} or {0.2, 0.2, 0.2})
            love.graphics.printf(option, 0, y, WINDOW_WIDTH, "center")
        end
        
    elseif gameState == "highscores" then
        -- Draw high scores with white background
        love.graphics.setColor(bgColor)
        love.graphics.rectangle("fill", 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
        
        love.graphics.setColor(0.2, 0.2, 0.8)
        love.graphics.setFont(love.graphics.newFont(20))
        love.graphics.printf("HIGH SCORES", 0, 50, WINDOW_WIDTH, "center")
        
        if currentUser then
            local scores = getUserHighScores(currentUser)
            love.graphics.setFont(love.graphics.newFont(14))
            love.graphics.setColor(0.2, 0.2, 0.2)
            love.graphics.printf("Your Best Scores:", 0, 100, WINDOW_WIDTH, "center")
            
            for i = 1, math.min(10, #scores) do
                love.graphics.printf(i .. ". " .. scores[i], 0, 120 + i * 25, WINDOW_WIDTH, "center")
            end
            
            if #scores == 0 then
                love.graphics.printf("No scores yet!", 0, 150, WINDOW_WIDTH, "center")
            end
        end
        
        love.graphics.setColor(0.4, 0.4, 0.4)
        love.graphics.printf("Press Escape to go back", 0, 500, WINDOW_WIDTH, "center")
        
    elseif gameState == "game" then
        -- Draw game with white background
        love.graphics.setColor(bgColor)
        love.graphics.rectangle("fill", 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
        
        -- Draw lanes
        love.graphics.setColor(0.9, 0.9, 0.9)
        if scrollDirection == SCROLL_VERTICAL then
            for _, x in ipairs(LANES_VERTICAL) do
                love.graphics.rectangle("fill", x - 25, 0, 50, WINDOW_HEIGHT)
            end
        else
            for _, y in ipairs(LANES_HORIZONTAL) do
                love.graphics.rectangle("fill", 0, y - 25, WINDOW_WIDTH, 50)
            end
        end

        -- Draw player (centered on lane line)
        love.graphics.setColor(0.1, 0.9, 0.1)
        love.graphics.rectangle("fill", player.x - player.width / 2, player.y - player.height / 2, player.width, player.height)

        -- Draw obstacles (centered on lane lines)
        for _, obs in ipairs(obstacles) do
            love.graphics.setColor(gameMode == "editor" and {1, 0.2, 0.2, 0.4} or {0.9, 0.1, 0.1})
            love.graphics.rectangle("fill", obs.x - obs.width / 2, obs.y - obs.height / 2, obs.width, obs.height)
        end

        -- Draw UI text
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.print("Mode: " .. gameMode, 10, 10)
        love.graphics.print("Score: " .. score, 10, 30)
        love.graphics.print("Player: " .. (currentUser or "Guest"), 10, 50)
        love.graphics.print("Scroll: " .. scrollDirection .. (scrollDirection == SCROLL_VERTICAL and (" (" .. verticalMode .. ")") or (" (" .. horizontalMode .. ")")), 10, 70)

        if gameMode == "editor" then
            love.graphics.print("Editor Time: " .. string.format("%.2f", editorTime), 10, 90)
            love.graphics.print("L/R: place notes  S: save  P: play chart  Space: switch lane", 10, 110)
        end

        if botplay then
            love.graphics.setColor(1, 0.5, 0)
            love.graphics.print("BOTPLAY ENABLED", 10, 130)
        end

        -- Debug info for obstacle counts
        love.graphics.setColor(0.4, 0.4, 0.4)
        updateLaneObstacleCounts()
        love.graphics.print("Lane 1: " .. laneObstacleCounts[1] .. " | Lane 2: " .. laneObstacleCounts[2], 10, 150)

        if paused then
            love.graphics.setColor(0, 0, 0, 0.7)
            love.graphics.rectangle("fill", 50, 150, 300, 200)

            love.graphics.setColor(1, 1, 1)
            love.graphics.printf("PAUSE MENU", 50, 160, 300, "center")

            for i, option in ipairs(pauseMenuOptions) do
                local y = 180 + i * 30
                love.graphics.setColor(i == selectedOption and {0.2, 0.2, 0.8} or {1, 1, 1})
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
        local success, msg = loadTiadChart("levels/custom.tiad") -- You can customize path
        if success then
            startChartPlay()
            gameState = "game"
            gameMode = "chartplay"
        else
            loginMessage = msg -- reuse message display (you may want a dedicated UI)
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
                saveChart("chart.txt")
            elseif key == "p" then
                loadChart("chart.txt")
                startChartPlay()
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