-- ExamQuest · core: assigns exercises to quests and gates the turn-in.
--
-- How a pass reaches the game: WoW addons cannot read files at runtime,
-- but /reload re-reads the addon's own Lua files. examquest.py grades
-- rendu/<exercise>.py and rewrites Results.lua with a pass COUNTER per
-- exercise. When a quest is accepted we remember the counter's value;
-- the exam objective is done once the counter has gone up since then.
-- That makes it a fresh solve, and no clocks have to agree (WSL vs
-- Windows).

local addonName, ns = ...

local DEFAULTS = {
    enabled = true,
    chance = 100,       -- % of accepted quests that get an exercise
    lastAssigned = {},  -- exercise -> counter, to rotate the pool
    serial = 0,
    turnedIn = 0,
}

ns.listeners = {}

local function msg(text)
    print("|cff33ff99ExamQuest|r " .. text)
end
ns.msg = msg

-- ── data access ─────────────────────────────────────────────────

local function pool()
    return ExamQuest_Pool or { exercises = {}, levels = 1 }
end

function ns.Exercise(name)
    for _, ex in ipairs(pool().exercises) do
        if ex.name == name then return ex end
    end
end

function ns.Passes(name)
    local res = ExamQuest_Results and ExamQuest_Results.exercises
    local row = res and res[name]
    return (row and row.passes) or 0
end

function ns.IsDone(entry)
    return ns.Passes(entry.ex) > (entry.baseline or 0)
end

function ns.Quests()
    return ExamQuestCharDB.quests
end

function ns.Changed()
    for _, fn in ipairs(ns.listeners) do fn() end
end

-- ── choosing an exercise ────────────────────────────────────────

local function busy(name)
    for _, entry in pairs(ns.Quests()) do
        if entry.ex == name and not ns.IsDone(entry) then return true end
    end
    return false
end

-- Random difficulty: any exercise of any level, preferring the ones
-- assigned the longest ago (never assigned first) that aren't already
-- open on another quest. So the whole pool comes round before a repeat.
local function pickExercise()
    local best, bestKey = {}, nil
    for _, ex in ipairs(pool().exercises) do
        if not busy(ex.name) then
            local key = ExamQuestDB.lastAssigned[ex.name] or -1
            if bestKey == nil or key < bestKey then
                best, bestKey = { ex }, key
            elseif key == bestKey then
                table.insert(best, ex)
            end
        end
    end
    if #best == 0 then
        -- Every exercise is open on some quest already: take any.
        for _, ex in ipairs(pool().exercises) do
            table.insert(best, ex)
        end
    end
    if #best == 0 then return nil end
    return best[math.random(#best)]
end

local function questTitle(questID)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local title = C_QuestLog.GetTitleForQuestID(questID)
        if title and title ~= "" then return title end
    end
    return "Quest " .. questID
end

local function onQuestOnLog(questID)
    if C_QuestLog and C_QuestLog.IsOnQuest then
        return C_QuestLog.IsOnQuest(questID)
    end
    return true
end

function ns.Assign(questID, force)
    if ns.Quests()[questID] then return ns.Quests()[questID] end
    if not force then
        if not ExamQuestDB.enabled then return nil end
        -- Area bonus objectives also fire QUEST_ACCEPTED; they have
        -- no turn-in to gate.
        if C_QuestLog and C_QuestLog.IsQuestTask
                and C_QuestLog.IsQuestTask(questID) then
            return nil
        end
        if math.random(100) > ExamQuestDB.chance then return nil end
    end
    local ex = pickExercise()
    if not ex then
        msg("no exercises in the pool - run `examquest.py install`.")
        return nil
    end
    ExamQuestDB.serial = ExamQuestDB.serial + 1
    ExamQuestDB.lastAssigned[ex.name] = ExamQuestDB.serial
    local entry = {
        ex = ex.name,
        level = ex.level,
        title = questTitle(questID),
        baseline = ns.Passes(ex.name),
    }
    ns.Quests()[questID] = entry
    msg(("new exam objective for |cffffd100%s|r: |cff00ccff%s|r "
        .. "(level %d) - write rendu/%s.py"):format(
        entry.title, ex.name, ex.level, ex.name))
    ns.Changed()
    return entry
end

-- ── the turn-in gate ────────────────────────────────────────────

local BUTTONS = { "QuestFrameCompleteQuestButton", "QuestFrameCompleteButton" }

local function currentGate()
    local questID = GetQuestID and GetQuestID()
    if not questID or questID == 0 then return nil end
    local entry = ns.Quests()[questID]
    if entry and not ns.IsDone(entry) then return entry end
    return nil
end

local function applyGate(announce)
    local entry = currentGate()
    for _, name in ipairs(BUTTONS) do
        local button = _G[name]
        if button and button:IsVisible() and entry then
            button:Disable()
        end
    end
    if entry and announce then
        local text = ("Exam objective missing: %s"):format(entry.ex)
        if UIErrorsFrame then UIErrorsFrame:AddMessage(text, 1, 0.2, 0.2) end
        msg(text .. " - pass it, then /reload.")
    end
end

local function hookButtons()
    for _, name in ipairs(BUTTONS) do
        local button = _G[name]
        if button and not button.examQuestHooked then
            button.examQuestHooked = true
            -- Blizzard re-enables the button when the panel refreshes
            -- (e.g. picking a reward); keep it disabled while gated.
            button:HookScript("OnEnable", function(self)
                if currentGate() then self:Disable() end
            end)
            button:HookScript("OnShow", function(self)
                if currentGate() then self:Disable() end
            end)
        end
    end
end

-- ── events ──────────────────────────────────────────────────────

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:RegisterEvent("QUEST_REMOVED")
frame:RegisterEvent("QUEST_PROGRESS")
frame:RegisterEvent("QUEST_COMPLETE")

local function lastArg(...)
    -- QUEST_ACCEPTED was (logIndex, questID) on old clients and is
    -- (questID) on the modern one; the questID is last either way.
    return (select(select("#", ...), ...))
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= addonName then return end
        ExamQuestDB = ExamQuestDB or {}
        for key, value in pairs(DEFAULTS) do
            if ExamQuestDB[key] == nil then
                ExamQuestDB[key] = type(value) == "table" and {} or value
            end
        end
        ExamQuestCharDB = ExamQuestCharDB or {}
        ExamQuestCharDB.quests = ExamQuestCharDB.quests or {}
    elseif event == "PLAYER_LOGIN" then
        -- Forget quests that left the log while the addon was off.
        for questID in pairs(ns.Quests()) do
            if not onQuestOnLog(questID) then ns.Quests()[questID] = nil end
        end
        hookButtons()
        local open = 0
        for _, entry in pairs(ns.Quests()) do
            if not ns.IsDone(entry) then open = open + 1 end
        end
        msg(("%s, %d exercises, %d open exam objective(s). /eq help")
            :format(pool().label or "?", #pool().exercises, open))
        ns.Changed()
    elseif event == "QUEST_ACCEPTED" then
        local questID = lastArg(...)
        if type(questID) == "number" then ns.Assign(questID) end
    elseif event == "QUEST_TURNED_IN" then
        local questID = ...
        if ns.Quests()[questID] then
            ExamQuestDB.turnedIn = ExamQuestDB.turnedIn + 1
        end
    elseif event == "QUEST_REMOVED" then
        local questID = ...
        if ns.Quests()[questID] then
            ns.Quests()[questID] = nil
            ns.Changed()
        end
    elseif event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
        hookButtons()
        applyGate(true)
        -- The panel finishes setting itself up after the event.
        C_Timer.After(0, function() applyGate(false) end)
    end
end)

-- ── slash commands ──────────────────────────────────────────────

local HELP = {
    "/eq - show or hide the tracker",
    "/eq status - your open exam objectives",
    "/eq chance <0-100> - share of quests that get an exercise",
    "/eq on, /eq off - pause or resume handing out exercises",
    "/eq adopt - give the quests already in your log an exercise",
}

SLASH_EXAMQUEST1 = "/eq"
SLASH_EXAMQUEST2 = "/examquest"
SlashCmdList.EXAMQUEST = function(input)
    local cmd, arg = strtrim(input or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        if ns.ToggleTracker then ns.ToggleTracker() end
    elseif cmd == "status" then
        local any = false
        for questID, entry in pairs(ns.Quests()) do
            any = true
            msg(("%s %s - %s"):format(
                ns.IsDone(entry) and "|cff00ff00[done]|r" or "|cffff3333[open]|r",
                entry.title or questID, entry.ex))
        end
        if not any then msg("no exam objectives.") end
        msg(("chance %d%%, %s, %d quests turned in")
            :format(ExamQuestDB.chance,
                    ExamQuestDB.enabled and "on" or "off",
                    ExamQuestDB.turnedIn))
    elseif cmd == "chance" and tonumber(arg) then
        ExamQuestDB.chance = math.max(0, math.min(100, tonumber(arg)))
        msg(("%d%% of new quests get an exercise."):format(ExamQuestDB.chance))
    elseif cmd == "on" or cmd == "off" then
        ExamQuestDB.enabled = (cmd == "on")
        msg("handing out exercises: " .. cmd)
    elseif cmd == "adopt" then
        local n = 0
        if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
            for i = 1, C_QuestLog.GetNumQuestLogEntries() do
                local info = C_QuestLog.GetInfo(i)
                if info and not info.isHeader and not info.isHidden
                        and info.questID
                        and not ns.Quests()[info.questID] then
                    if ns.Assign(info.questID, true) then n = n + 1 end
                end
            end
        end
        msg(("%d quest(s) adopted."):format(n))
    else
        for _, line in ipairs(HELP) do msg(line) end
    end
end
