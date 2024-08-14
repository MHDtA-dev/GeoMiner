--[[
Copyright (C) 2024 Alexander Blinov

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

--]]


local basalt = require("basalt")

local w, h = term.getSize()
local currentFrameName = nil
local frames = {}

-- Scanner
local scanRadius = -1
local scanner = peripheral.find("geoScanner")
local blocks = {}
local blocksNamesSet = {}
local blocksToMine = {}

-- Utils

local minerStatusLabel = nil
local minerStartButton = nil
local minerProgressBar = nil
local minerProgressLabel = nil
local minerDirectionLabel = nil
local minerDirectionDropdown = nil
local minerCheckboxUsePathf = nil
local minerCheckboxRetH = nil
local minerCheckboxUsePathfLabel = nil
local minerCheckboxRetHLabel = nil
local returnAtStart = false
local goToChangeLabel = false
local currentBlockName = ""

function getSetLen(set)
    local ret = 0

    for k, v in pairs(set) do
        ret = ret + 1
    end

    return ret
end

function splitString(input, delimiter)
    if delimiter == nil then
        delimiter = "%s"
    end
    local t = {}
    for str in string.gmatch(input, "([^"..delimiter.."]+)") do
        table.insert(t, str)
    end
    return t
end


function manhattanDist(x1, y1, z1, x2, y2, z2)
    return math.abs(x1 - x2) + math.abs(y1 - y2) + math.abs(z1 - z2)
end


function directionFromTo(x1, y1, z1, x2, y2, z2)
    if x1 < x2 then return "E"
    elseif x1 > x2 then return "W"
    elseif z1 < z2 then return "S"
    elseif z1 > z2 then return "N"
    elseif y1 < y2 then return "up"
    elseif y1 > y2 then return "down"
    end
end


function createBlockMap(blocks)
    local map = {}
    for _, block in ipairs(blocks) do
        if block.name ~= "minecraft:air" and block.name ~= "computercraft:turtle_advanced" then
            map[block.x..","..block.y..","..block.z] = true
        end
    end
    return map
end


function aStar(start, goal, blockMap)
    local openSet = {[table.concat(start, ",")] = true}
    local cameFrom = {}
    local gScore = {[table.concat(start, ",")] = 0}
    local fScore = {[table.concat(start, ",")] = manhattanDist(start[1], start[2], start[3], goal[1], goal[2], goal[3])}

    while next(openSet) do

        local current, currentFScore = nil, math.huge
        for node in pairs(openSet) do
            if fScore[node] < currentFScore then
                current = node
                currentFScore = fScore[node]
            end
        end

        
        local curPos = {}
        for num in string.gmatch(current, "-?%d+") do
            table.insert(curPos, tonumber(num))
        end


        if curPos[1] == goal[1] and curPos[2] == goal[2] and curPos[3] == goal[3] then
            local path = {}
            while current do
                local pos = {}
                for num in string.gmatch(current, "-?%d+") do
                    table.insert(pos, tonumber(num))
                end
                table.insert(path, 1, pos)
                current = cameFrom[current]
            end
            return path
        end

        
        openSet[current] = nil

        
        local neighbors = {
            {curPos[1] + 1, curPos[2], curPos[3]},
            {curPos[1] - 1, curPos[2], curPos[3]},
            {curPos[1], curPos[2] + 1, curPos[3]},
            {curPos[1], curPos[2] - 1, curPos[3]},
            {curPos[1], curPos[2], curPos[3] + 1},
            {curPos[1], curPos[2], curPos[3] - 1}
        }

        for _, neighbor in ipairs(neighbors) do
            local neighborKey = table.concat(neighbor, ",")
            if not blockMap[neighborKey] then
                local tentativeGScore = gScore[current] + 1
                if not gScore[neighborKey] or tentativeGScore < gScore[neighborKey] then
                    cameFrom[neighborKey] = current
                    gScore[neighborKey] = tentativeGScore
                    fScore[neighborKey] = tentativeGScore + manhattanDist(neighbor[1], neighbor[2], neighbor[3], goal[1], goal[2], goal[3])
                    openSet[neighborKey] = true
                end
            end
        end
        os.sleep(0.05)
    end

    return nil
end


function moveTurtle(path, direction)
    local directions = {["N"] = 0, ["E"] = 1, ["S"] = 2, ["W"] = 3}
    for i = 2, #path do
        local cur, next = path[i-1], path[i]
        local dir = directionFromTo(cur[1], cur[2], cur[3], next[1], next[2], next[3])

        if dir == "up" then
            turtle.up()
        elseif dir == "down" then
            turtle.down()
        else
            local targetDirection = directions[dir]
            local currentDirection = directions[direction[1]]

            local turn_steps = (targetDirection - currentDirection) % 4

            if turn_steps == 3 then
                turtle.turnLeft()
            elseif turn_steps == 1 then
                turtle.turnRight()
            elseif turn_steps == 2 then
                turtle.turnRight()
                turtle.turnRight()
            end

            direction[1] = dir
            turtle.forward()
        end
    end
end


function goTo(x, y, z, startDirection, blocks)
    local start = {0, 0, 0}
    local goal = {x, y, z}
    local blockMap = createBlockMap(blocks)
    local path = aStar(start, goal, blockMap)
    
    if goToChangeLabel then
        minerStatusLabel:setForeground(colors.black)
        minerStatusLabel:setText("Moving to "..currentBlockName)
    end

    if path then
        moveTurtle(path, startDirection)
        return true
    else
        return false
    end

end

function isBlockFree(x, y, z, blockMap)
    return not blockMap[x..","..y..","..z]
end


function countNeededBlocks(blocksToMine, blocks)
    cnt = 0
    
    for i = 1, #blocks do
        if blocksToMine[splitString(blocks[i].name, ":")[2]] then
            cnt = cnt + 1
        end
    end

    return cnt
    
end


function moveToNearestFree(x, y, z, direction, blocks)
    local blockMap = createBlockMap(blocks)


    local neighbors = {
        {x + 1, y, z, "W"},
        {x - 1, y, z, "E"},
        {x, y + 1, z, "D"},
        {x, y - 1, z, "U"},
        {x, y, z + 1, "N"},
        {x, y, z - 1, "S"}
    }

    for _, neighbor in ipairs(neighbors) do
        local nx, ny, nz, blockDirection = neighbor[1], neighbor[2], neighbor[3], neighbor[4]
        if isBlockFree(nx, ny, nz, blockMap) then
            goTo(nx, ny, nz, direction, blocks)
            return {neighbor, {x, y, z}}
        end
    end

    return nil
end

function findClosestBlock(blocksToMine, blocks, startPos)
    local closestBlock = nil
    local min_distance = math.huge

    for _, block in ipairs(blocks) do
        local blockType = splitString(block.name, ":")[2]
        
        if blocksToMine[blockType] then
            local distance = manhattanDist(startPos[1], startPos[2], startPos[3], block.x, block.y, block.z)
            if distance < min_distance then
                min_distance = distance
                closestBlock = block
            end
        end
    end

    return closestBlock
end

function turnTo(newDirection, direction)
    if direction[1] == "S" then
        if newDirection == "W" then
            turtle.turnRight()
        elseif newDirection == "N" then
            turtle.turnLeft()
            turtle.turnLeft()
        elseif newDirection == "E" then
            turtle.turnLeft()
        end
    elseif direction[1] == "W" then
        if newDirection == "S" then
            turtle.turnLeft()
        elseif newDirection == "E" then
            turtle.turnLeft()
            turtle.turnLeft()
        elseif newDirection == "N" then
            turtle.turnRight()
        end
    elseif direction[1] == "N" then
        if newDirection == "W" then
            turtle.turnLeft()
        elseif newDirection == "E" then
            turtle.turnRight()
        elseif newDirection == "S" then
            turtle.turnLeft()
            turtle.turnLeft()
        end
    elseif direction[1] == "E" then
        if newDirection == "S" then
            turtle.turnRight()
        elseif newDirection == "N" then
            turtle.turnLeft()
        elseif newDirection == "W" then
            turtle.turnLeft()
            turtle.turnLeft()
        end
    end

    direction[1] = newDirection
end

local direction = {"S"}

function removeBlockAt(x, y, z, blocks)
    local indexToRemove = -1

    for i = 1, #blocks do
        if blocks[i].x == x and blocks[i].y == y and blocks[i].z == z then
            indexToRemove = i
            break
        end
    end

    table.remove(blocks, indexToRemove)
end

function AStarMiner()
    local startBlocksLen = countNeededBlocks(blocksToMine, blocks)
    local dug = 0
    minerStatusLabel:show()

    local currentPos = {0, 0, 0}
    local offset = {0, 0, 0}

    while true do
        local closestBlock = findClosestBlock(blocksToMine, blocks, offset)

        if closestBlock == nil then
            if returnAtStart then
                goToChangeLabel = false
                minerStatusLabel:setForeground(colors.black)
                minerStatusLabel:setText("Returning at start")

                goTo(-currentPos[1], -currentPos[2], -currentPos[3], direction, blocks)
            end

            minerStatusLabel:setForeground(colors.lime)
            minerStatusLabel:setText("Done!")
            minerProgressBar:hide()
            minerProgressLabel:hide()
            minerStartButton:show()
            minerDirectionLabel:show()
            minerDirectionDropdown:show()
            minerCheckboxUsePathf:show()
            minerCheckboxRetH:show()
            minerCheckboxUsePathfLabel:show()
            minerCheckboxRetHLabel:show()

            break
        end

        currentBlockName = splitString(closestBlock.name, ":")[2]
        
        minerStatusLabel:setForeground(colors.black)
        minerStatusLabel:setText("Finding path to "..currentBlockName)

        local moveResult = moveToNearestFree(closestBlock.x, closestBlock.y, closestBlock.z, direction, blocks)

        if moveResult == nil then
            minerStatusLabel:setForeground(colors.yellow)
            minerStatusLabel:setText("Can't find path to "..currentBlockName..". Skipping.")
            os.sleep(1)
            
            local removeIndex = -1

            for _, block in ipairs(blocks) do
                if block.x == closestBlock.x and block.y == closestBlock.y and block.z == closestBlock.z then
                    removeIndex = _
                end
            end

            table.remove(blocks, removeIndex)
            dug = dug + 1
            minerProgressBar:setProgress(math.floor(dug / startBlocksLen * 100))
            minerProgressLabel:setText(tostring(math.floor(dug / startBlocksLen * 100)).."%")
            goto continue
        end

        offset[1] = moveResult[1][1]
        offset[2] = moveResult[1][2]
        offset[3] = moveResult[1][3]

        minerStatusLabel:setForeground(colors.black)
        minerStatusLabel:setText("Digging "..currentBlockName)

        if moveResult[1][4] == "U" then
            while turtle.detectUp() do
                turtle.digUp()
            end
        elseif moveResult[1][4] == "D" then
            while turtle.detectDown() do
                turtle.digDown()
            end
        else
            turnTo(moveResult[1][4], direction)
            while turtle.detect() do
                turtle.dig()
            end
        end

        dug = dug + 1

        removeBlockAt(moveResult[2][1], moveResult[2][2], moveResult[2][3], blocks)

        for i = 1, #blocks do
            blocks[i].x = blocks[i].x - offset[1]
            blocks[i].y = blocks[i].y - offset[2]
            blocks[i].z = blocks[i].z - offset[3]
        end


        currentPos[1] = currentPos[1] + offset[1]
        currentPos[2] = currentPos[2] + offset[2]
        currentPos[3] = currentPos[3] + offset[3]
        offset = {0, 0, 0}

        minerProgressBar:setProgress(math.floor((dug / startBlocksLen) * 100))
        minerProgressLabel:setText(tostring(math.floor((dug / startBlocksLen) * 100)).."%")

        ::continue::
    end

end

function miner()
    local startBlocksLen = countNeededBlocks(blocksToMine, blocks)
    local dug = 0
    minerStatusLabel:show()

    local currentPos = {0, 0, 0}
    local offset = {0, 0, 0}

    while true do

        local block = findClosestBlock(blocksToMine, blocks, offset)

        if block == nil then
            if returnAtStart then
                goToChangeLabel = false
                minerStatusLabel:setForeground(colors.black)
                minerStatusLabel:setText("Returning at start")
        
                goTo(-currentPos[1], -currentPos[2], -currentPos[3], direction, blocks)
            end
        
            minerStatusLabel:setForeground(colors.lime)
            minerStatusLabel:setText("Done!")
            minerProgressBar:hide()
            minerProgressLabel:hide()
            minerStartButton:show()
            minerDirectionLabel:show()
            minerDirectionDropdown:show()
            minerCheckboxUsePathf:show()
            minerCheckboxRetH:show()
            minerCheckboxUsePathfLabel:show()
            minerCheckboxRetHLabel:show()


            break
        end
        
        currentBlockName = splitString(block.name, ":")[2]

        if blocksToMine[currentBlockName] then
            minerStatusLabel:setForeground(colors.black)
            minerStatusLabel:setText("Moving to "..currentBlockName)

            if block.x > 0 then
                turnTo("E", direction)
                while offset[1] ~= block.x do
                    while turtle.detect() do
                        turtle.dig()
                    end

                    offset[1] = offset[1] + 1
                    removeBlockAt(offset[1], offset[2], offset[3], blocks)
                    turtle.forward()
                end
            else
                turnTo("W", direction)
                while offset[1] ~= block.x do
                    while turtle.detect() do
                        turtle.dig()
                    end

                    offset[1] = offset[1] - 1
                    removeBlockAt(offset[1], offset[2], offset[3], blocks)
                    turtle.forward()
                end
            end

            if block.z > 0 then
                turnTo("S", direction)
                while offset[3] ~= block.z do
                    while turtle.detect() do
                        turtle.dig()
                    end

                    offset[3] = offset[3] + 1
                    removeBlockAt(offset[1], offset[2], offset[3], blocks)
                    turtle.forward()
                end
            else
                turnTo("N", direction)
                while offset[3] ~= block.z do
                    while turtle.detect() do
                        turtle.dig()
                    end

                    offset[3] = offset[3] - 1
                    removeBlockAt(offset[1], offset[2], offset[3], blocks)
                    turtle.forward()
                end
            end

            if block.y > 0 then
                while offset[2] ~= block.y do
                    while turtle.detectUp() do
                        turtle.digUp()
                    end

                    offset[2] = offset[2] + 1
                    removeBlockAt(offset[1], offset[2], offset[3], blocks)
                    turtle.up()
                end
            else
                while offset[2] ~= block.y do
                    while turtle.detectDown() do
                        turtle.digDown()
                    end

                    offset[2] = offset[2] - 1
                    removeBlockAt(offset[1], offset[2], offset[3], blocks)
                    turtle.down()
                end
            end

            dug = dug + 1


            for i = 1, #blocks do
                blocks[i].x = blocks[i].x - offset[1]
                blocks[i].y = blocks[i].y - offset[2]
                blocks[i].z = blocks[i].z - offset[3]
            end


            minerProgressBar:setProgress(math.floor((dug / startBlocksLen) * 100))
            minerProgressLabel:setText(tostring(math.floor((dug / startBlocksLen) * 100)).."%")
            
            currentPos[1] = currentPos[1] + offset[1]
            currentPos[2] = currentPos[2] + offset[2]
            currentPos[3] = currentPos[3] + offset[3]
            offset = {0, 0, 0}

        end 
    end

end

-- UI

local blocksDropdown = nil
local blocksToMineList = nil

local main = basalt.createFrame()

main:addPane():setPosition(1, 1):setSize(w, 1):setBackground(colors.gray)
main:addLabel():setText("Geo"):setForeground(colors.lime):setPosition(1, 1)
main:addLabel():setText("Miner"):setForeground(colors.red):setPosition(4, 1)

local menubar = main:addMenubar():setPosition(1, 2):setSize(w, 1)
menubar:addItem("Fuel")
menubar:addItem("Scanner")
menubar:addItem("Blocks")
menubar:addItem("Miner")
menubar:addItem("About")
menubar:addItem("How to use?")
menubar:onChange(function(self, event, item)
    frames[currentFrameName]:hide()
    frames[item.text]:show()
    currentFrameName = item.text
end)

frames["Fuel"] = main:addScrollableFrame():setBackground(colors.lightGray):setPosition(1, 3):setSize(w, h - 2)
frames["Scanner"] = main:addScrollableFrame():setBackground(colors.lightGray):setPosition(1, 3):setSize(w, h - 2):hide()
frames["Blocks"] = main:addScrollableFrame():setBackground(colors.lightGray):setPosition(1, 3):setSize(w, h - 2):hide()
frames["Miner"] = main:addScrollableFrame():setBackground(colors.lightGray):setPosition(1, 3):setSize(w, h - 2):hide()
frames["About"] = main:addScrollableFrame():setBackground(colors.lightGray):setPosition(1, 3):setSize(w, h - 2):hide()
frames["How to use?"] = main:addScrollableFrame():setBackground(colors.lightGray):setPosition(1, 3):setSize(w, h - 2):hide()
currentFrameName = "Fuel"

-- Fuel frame

local fuelLabel = frames["Fuel"]:addLabel():setText("Current fuel level: {}"):setPosition(2, 2)
frames["Fuel"]:addButton():setText("Refuel"):setPosition(2, 4):setSize(10, 1):onClick(function(self, event, button, x, y)
    if (event == "mouse_click") and (button == 1) then
      turtle.refuel()
    end
  end)

-- Scanner frame

local fuelNeedLabel = nil
local blocksList = nil
local relativePositionsLabel = nil

if scanner == nil then
    frames["Scanner"]:addLabel():setText("Geo Scanner is not attached!"):setForeground(colors.red):setPosition(2, 2)
    frames["Scanner"]:addLabel():setText("Attach Geo Scanner from"):setForeground(colors.red):setPosition(2, 3)
    frames["Scanner"]:addLabel():setText("\"Advanced Peripherals\" mod and"):setForeground(colors.red):setPosition(2, 4)
    frames["Scanner"]:addLabel():setText("restart this program!"):setForeground(colors.red):setPosition(2, 5)
else
    frames["Scanner"]:addButton():setText("Start scanning"):setPosition(2, 2):setSize(16, 1):onClick(function(self, event, button, x, y)
        if (event == "mouse_click") and (button == 1) then
            if scanRadius == -1 then
                fuelNeedLabel:show()
                fuelNeedLabel:setText("Incorrect radius"):setForeground(colors.red)
                return
            end

            if scanner.cost(scanRadius) > turtle.getFuelLevel() then
                fuelNeedLabel:show()
                fuelNeedLabel:setText("Not enough fuel"):setForeground(colors.red)
                return
            end
            
            blocks = scanner.scan(scanRadius)
            
            if blocks ~= nil then
                blocksNamesSet = {}
                blocksList:clear()
                blocksDropdown:clear()
                blocksToMineList:clear()
                blocksToMine = {}
                fuelNeedLabel:show()
                fuelNeedLabel:setText("Done. Found "..tostring(#blocks).."\nblocks."):setForeground(colors.lime)

                for i = 1, #blocks do
                    local blockName = splitString(blocks[i].name, ":")[2]
                    blocksList:addItem(blockName.." "..tostring(blocks[i].x).." "..tostring(blocks[i].y).." "..tostring(blocks[i].z))

                    if blocksNamesSet[blockName] == nil then
                        blocksDropdown:addItem(blockName)
                        blocksNamesSet[blockName] = true
                    end
                end
                relativePositionsLabel:show()

            else
                fuelNeedLabel:show()
                fuelNeedLabel:setText("Some error occured"):setForeground(colors.red)
            end
            
        end
    end)

    frames["Scanner"]:addLabel():setText("Radius:"):setPosition(2, 4)
    fuelNeedLabel = frames["Scanner"]:addLabel():setText("Fuel need:"):setPosition(2, 6):hide()
    local scanRadiusInput = frames["Scanner"]:addInput():setInputType("number"):setSize(4, 1):setPosition(10, 4):onChange(function(self, event, text)
        if text == "" or text == "-" then
            relativePositionsLabel:hide()
            scanRadius = -1
            fuelNeedLabel:hide()
        elseif tonumber(text) > 16 or tonumber(text) <= 0 then
            relativePositionsLabel:hide()
            scanRadius = -1
            fuelNeedLabel:show()
            fuelNeedLabel:setText("Radius should be\nin [1; 16]"):setForeground(colors.red)
        else
            relativePositionsLabel:hide()
            scanRadius = tonumber(text)
            fuelNeedLabel:show()
            fuelNeedLabel:setText("Fuel need: "..tostring(scanner.cost(scanRadius))):setForeground(colors.black)
        end
    end)

    blocksList = frames["Scanner"]:addList():setSize(20, h - 4):setPosition(w - 20, 2)
    relativePositionsLabel = frames["Scanner"]:addLabel():setText("All positions are relative to turtle"):setPosition(1, h - 2):setSize(w, 1):hide()

end

-- Blocks frame

blocksDropdown = frames["Blocks"]:addDropdown():setPosition(2, 2):setSize(20, 1)
frames["Blocks"]:addButton():setText("+"):setSize(3, 1):setPosition(2, 4):onClick(function(self, event, button, x, y)
    if (event == "mouse_click") and (button == 1) and #blocks ~= 0 then
        if blocksToMine[blocksDropdown:getItem(blocksDropdown:getItemIndex()).text] == nil then
            blocksToMineList:addItem(blocksDropdown:getItem(blocksDropdown:getItemIndex()).text)
            blocksToMine[blocksDropdown:getItem(blocksDropdown:getItemIndex()).text] = true
        end

    end
end)

frames["Blocks"]:addButton():setText("-"):setSize(3, 1):setPosition(7, 4):onClick(function(self, event, button, x, y)
    if (event == "mouse_click") and (button == 1) and #blocks ~= 0 then
        if blocksToMine[blocksDropdown:getItem(blocksDropdown:getItemIndex()).text] == true then
            tmp = blocksToMineList:getAll()
            indexToDelete = -1

            for i = 1, #tmp do
                if tmp[i].text == blocksDropdown:getItem(blocksDropdown:getItemIndex()).text then
                    indexToDelete = i
                    break
                end
            end
            blocksToMineList:removeItem(indexToDelete)
            blocksToMine[blocksDropdown:getItem(blocksDropdown:getItemIndex()).text] = nil
        end
    end
end)

blocksToMineList = frames["Blocks"]:addList():setSize(16, h - 4):setPosition(w - 16, 2):onChange(function(self, event, item)
    indexToSelect = -1
    tmp = blocksDropdown:getAll()

    for i = 1, #tmp do
        if tmp[i].text == item.text then
            indexToSelect = i
            break
        end
    end

    blocksDropdown:selectItem(indexToSelect)

end)

-- Miner frame

local usePathfinding = false
local returnHome = false


local minerThread = main:addThread()

local usePathfinding = false

minerCheckboxUsePathfLabel = frames["Miner"]:addLabel():setText("Use pathfinding algorithm"):setPosition(4, 2)
minerCheckboxUsePathf = frames["Miner"]:addCheckbox():setPosition(2, 2):setBackground(colors.gray):onChange(function (self)
    usePathfinding = self:getValue()
end)
minerCheckboxRetHLabel = frames["Miner"]:addLabel():setText("Return at start position"):setPosition(4, 4)
minerCheckboxRetH = frames["Miner"]:addCheckbox():setPosition(2, 4):setBackground(colors.gray):onChange(function (self)
    returnAtStart = self:getValue()
end)
minerDirectionLabel = frames["Miner"]:addLabel():setPosition(2, 6):setText("Select current direction:")
minerDirectionDropdown = frames["Miner"]:addDropdown():setPosition(2, 7):onChange(function(self, event, item)
    direction[1] = string.sub(item.text, 1, 1)
end)

minerDirectionDropdown:addItem("South")
minerDirectionDropdown:addItem("North")
minerDirectionDropdown:addItem("East")
minerDirectionDropdown:addItem("West")
minerStartButton = frames["Miner"]:addButton():setText("Start"):setPosition(w - 9, 6):setSize(9, 3):onClick(function(self, event, button, x, y)
    if (event == "mouse_click") and (button == 1) then
        if getSetLen(blocksToMine) == 0 then
            minerStatusLabel:show()
            minerStatusLabel:setText("You haven't selected blocks for mining. Please,\n go to \"Blocks\" tab.")
            minerStatusLabel:setForeground(colors.red)
            return
        end

        minerStartButton:hide()
        minerDirectionLabel:hide()
        minerDirectionDropdown:hide()
        minerCheckboxUsePathf:hide()
        minerCheckboxRetH:hide()
        minerCheckboxUsePathfLabel:hide()
        minerCheckboxRetHLabel:hide()
        minerProgressLabel:show()
        minerProgressBar:show()

        goToChangeLabel = true

        if usePathfinding then
            minerThread:start(AStarMiner)
        else
            minerThread:start(miner)
        end

    end
end)


minerProgressBar = frames["Miner"]:addProgressbar():setPosition(6, math.floor((h - 3) / 2)):setSize(w - 6, 1):setProgress(0):hide()
minerProgressLabel = frames["Miner"]:addLabel():setPosition(2, math.floor((h - 3) / 2)):hide():setText("0%")
minerStatusLabel = frames["Miner"]:addLabel():setPosition(1, 10):hide()

-- About frame
frames["About"]:addLabel():setText("Geo"):setForeground(colors.lime):setPosition(2, 2):setFontSize(2)
frames["About"]:addLabel():setText("Miner"):setForeground(colors.red):setPosition(11, 2):setFontSize(2)
frames["About"]:addLabel():setText("v1.0"):setPosition(2, 5)
frames["About"]:addLabel():setText("Copyright (C) 2024 Alexander Blinov"):setPosition(2, 7)
frames["About"]:addLabel():setText("Licensed under the Apache License,"):setPosition(2, 9)
frames["About"]:addLabel():setText("Version 2.0 (the \"License\");"):setPosition(2, 10)
frames["About"]:addLabel():setText("you may not use this file except in"):setPosition(2, 11)
frames["About"]:addLabel():setText("compliance with the License. You may"):setPosition(2, 12)
frames["About"]:addLabel():setText("obtain a copy of the License at"):setPosition(2, 13)
frames["About"]:addLabel():setText("http://www.apache.org/licenses/"):setPosition(2, 15)
frames["About"]:addLabel():setText("LICENSE-2.0"):setPosition(2, 16)
frames["About"]:addLabel():setText("Unless required by applicable law or"):setPosition(2, 18)
frames["About"]:addLabel():setText("agreed to in writing, software"):setPosition(2, 19)
frames["About"]:addLabel():setText("distributed under the License"):setPosition(2, 20)
frames["About"]:addLabel():setText("is distributed on an \"AS IS\" BASIS,"):setPosition(2, 21)
frames["About"]:addLabel():setText("WITHOUT WARRANTIES OR CONDITIONS OF"):setPosition(2, 22)
frames["About"]:addLabel():setText("ANY KIND, either express or implied."):setPosition(2, 23)
frames["About"]:addLabel():setText("See the License for the specific"):setPosition(2, 24)
frames["About"]:addLabel():setText("language governing permissions and"):setPosition(2, 25)
frames["About"]:addLabel():setText("limitations under the License."):setPosition(2, 26)
frames["About"]:addLabel():setText("Third-party libraries used:"):setPosition(2, 28)
frames["About"]:addLabel():setText("- Basalt"):setPosition(2, 29)
frames["About"]:addLabel():setText("by Robert Jelic, MIT License"):setPosition(11, 29):setForeground(colors.gray)

-- How to use frame
frames["How to use?"]:addLabel():setText("GeoMiner is a program for turtles that"):setPosition(2, 2)
frames["How to use?"]:addLabel():setText("allows you to search and mine any"):setPosition(2, 3)
frames["How to use?"]:addLabel():setText("blocks using a geo scanner from the"):setPosition(2, 4)
frames["How to use?"]:addLabel():setText("\"Advanced Peripherals\" mod. The"):setPosition(2, 5)
frames["How to use?"]:addLabel():setText("program can use A* pathfinding"):setPosition(2, 6)
frames["How to use?"]:addLabel():setText("algorithm in order for the turtle to"):setPosition(2, 7)
frames["How to use?"]:addLabel():setText("bypass obstacles and mine blocks."):setPosition(2, 8)
frames["How to use?"]:addLabel():setText("There is also an option to return to"):setPosition(2, 9)
frames["How to use?"]:addLabel():setText("the start location."):setPosition(2, 10)

frames["How to use?"]:addLabel():setText("The first \"Fuel\" tab contains"):setPosition(2, 12)
frames["How to use?"]:addLabel():setText("information about the remaining amount"):setPosition(2, 13)
frames["How to use?"]:addLabel():setText("of fuel, as well as a button to refuel"):setPosition(2, 14)
frames["How to use?"]:addLabel():setText("the turtle. The turtle needs fuel to"):setPosition(2, 15)
frames["How to use?"]:addLabel():setText("move as well as to operate the geo"):setPosition(2, 16)
frames["How to use?"]:addLabel():setText("scanner."):setPosition(2, 17)

frames["How to use?"]:addLabel():setText("The second tab \"Scanner\" is needed"):setPosition(2, 19)
frames["How to use?"]:addLabel():setText("to scan the environment. Enter the"):setPosition(2, 20)
frames["How to use?"]:addLabel():setText("required radius in the input field"):setPosition(2, 21)
frames["How to use?"]:addLabel():setText("(it must be between 1 and 16"):setPosition(2, 22)
frames["How to use?"]:addLabel():setText("inclusive) and press the \"Start"):setPosition(2, 23)
frames["How to use?"]:addLabel():setText("scanning\" button. Radius from 1 to"):setPosition(2, 24)
frames["How to use?"]:addLabel():setText("8 does not require fuel, a radius"):setPosition(2, 25)
frames["How to use?"]:addLabel():setText("from 9 to 16 requires some fuel."):setPosition(2, 26)
frames["How to use?"]:addLabel():setText("After pressing the button, the turtle"):setPosition(2, 27)
frames["How to use?"]:addLabel():setText("will scan the area and you will be"):setPosition(2, 28)
frames["How to use?"]:addLabel():setText("able to see the scanned blocks in"):setPosition(2, 29)
frames["How to use?"]:addLabel():setText("the list on the right side, as well"):setPosition(2, 30)
frames["How to use?"]:addLabel():setText("as their positions relative to the"):setPosition(2, 31)
frames["How to use?"]:addLabel():setText("turtle."):setPosition(2, 32)

frames["How to use?"]:addLabel():setText("The third \"Blocks\" tab is neeeded"):setPosition(2, 34)
frames["How to use?"]:addLabel():setText("to specify which kind of blocks the"):setPosition(2, 35)
frames["How to use?"]:addLabel():setText("turtle should mine. Select a block"):setPosition(2, 36)
frames["How to use?"]:addLabel():setText("from the drop-down list and press"):setPosition(2, 37)
frames["How to use?"]:addLabel():setText("the \"+\" button. To remove, select"):setPosition(2, 38)
frames["How to use?"]:addLabel():setText("select it from the drop-down list,"):setPosition(2, 39)
frames["How to use?"]:addLabel():setText("or select it from the list on the"):setPosition(2, 40)
frames["How to use?"]:addLabel():setText("right  side and press the \"-\""):setPosition(2, 41)
frames["How to use?"]:addLabel():setText("button. The available block types will"):setPosition(2, 42)
frames["How to use?"]:addLabel():setText("appear in the drop-down list after"):setPosition(2, 43)
frames["How to use?"]:addLabel():setText("scanning on the \"Scanner\" tab."):setPosition(2, 44)

frames["How to use?"]:addLabel():setText("To start mining, go to the \"Miner\""):setPosition(2, 46)
frames["How to use?"]:addLabel():setText("tab. If you need to mine blocks that"):setPosition(2, 47)
frames["How to use?"]:addLabel():setText("are freely accessible, such as trees,"):setPosition(2, 48)
frames["How to use?"]:addLabel():setText("harvesting, etc., select \"Use"):setPosition(2, 49)
frames["How to use?"]:addLabel():setText("pathfinding algorithm\". The turtle"):setPosition(2, 50)
frames["How to use?"]:addLabel():setText("will build a path to the block and"):setPosition(2, 51)
frames["How to use?"]:addLabel():setText("move towards it, avoiding obstacles."):setPosition(2, 52)
frames["How to use?"]:addLabel():setText("If there is no direct access to the"):setPosition(2, 53)
frames["How to use?"]:addLabel():setText("block, that is, it is forced by other"):setPosition(2, 54)
frames["How to use?"]:addLabel():setText("from all sides, this checkbox should"):setPosition(2, 55)
frames["How to use?"]:addLabel():setText("be turned off. In this case, the"):setPosition(2, 56)
frames["How to use?"]:addLabel():setText("turtle will dig other blocks and move"):setPosition(2, 57)
frames["How to use?"]:addLabel():setText("in the direction of the needed block."):setPosition(2, 58)
frames["How to use?"]:addLabel():setText("Enable the checkbox \"Return at start"):setPosition(2, 59)
frames["How to use?"]:addLabel():setText("position\" so that the turtle returns"):setPosition(2, 60)
frames["How to use?"]:addLabel():setText("to the starting point after all the"):setPosition(2, 61)
frames["How to use?"]:addLabel():setText("necessary blocks are dug up."):setPosition(2, 62)
frames["How to use?"]:addLabel():setText("IMPORTANT!"):setPosition(2, 63):setForeground(colors.red)
frames["How to use?"]:addLabel():setText("In the drop-down list,"):setPosition(13, 63)
frames["How to use?"]:addLabel():setText("select the direction in which the"):setPosition(2, 64)
frames["How to use?"]:addLabel():setText("turtle is currently looking, otherwise the"):setPosition(2, 65)
frames["How to use?"]:addLabel():setText("program will not work correctly!"):setPosition(2, 66)


-- Threads

function fuelLabelUpdate()
    while true do
        fuelLabel:setText("Current fuel level: "..tostring(turtle.getFuelLevel()))
        os.sleep(1)
    end
end
main:addThread():start(fuelLabelUpdate)

basalt.autoUpdate()