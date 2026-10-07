local prefix = "MPUI|"
local run = nil
local objectives = {}
local frame = CreateFrame("Frame", "MythicPlusUIFrame", UIParent)
frame:SetWidth(280)
frame:SetHeight(150)
frame:SetPoint("TOP", UIParent, "TOP", 0, -80)
frame:Hide()

local backdrop = frame:CreateTexture(nil, "BACKGROUND")
backdrop:SetAllPoints(frame)
backdrop:SetTexture(0, 0, 0, 0.65)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -8)

local timer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
timer:SetPoint("TOP", title, "BOTTOM", 0, -4)

local lines = {}
local function objectiveLine(index)
    if not lines[index] then
        lines[index] = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lines[index]:SetPoint("TOPLEFT", 14, -58 - (index - 1) * 16)
    end
    return lines[index]
end

local function formatTime(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    return string.format("%02d:%02d", math.floor(seconds / 60), math.mod(seconds, 60))
end

local function redrawObjectives()
    local index = 1
    for _, objective in pairs(objectives) do
        local line = objectiveLine(index)
        line:SetText(string.format("%d/%d  %s", objective.current, objective.required, objective.label))
        line:SetTextColor(objective.current >= objective.required and 0.35 or 1, objective.current >= objective.required and 1 or 0.82, 0.35)
        line:Show()
        index = index + 1
    end
    for i = index, #lines do lines[i]:Hide() end
end

local function handle(message)
    if string.sub(message, 1, string.len(prefix)) ~= prefix then return end
    local payload = string.sub(message, string.len(prefix) + 1)
    local parts = {}
    for value in string.gmatch(payload, "([^|]+)") do table.insert(parts, value) end
    local kind = parts[1]
    if kind == "START" then
        run = { map = tonumber(parts[2]), level = tonumber(parts[3]), limit = tonumber(parts[4]), start = tonumber(parts[5]), deaths = tonumber(parts[6]) or 0, penalty = tonumber(parts[7]) or 0 }
        objectives = {}
        title:SetText("大秘境  +" .. run.level)
        frame:Show()
    elseif kind == "OBJECTIVE" then
        objectives[tonumber(parts[2])] = { type = tonumber(parts[3]), entry = tonumber(parts[4]), current = tonumber(parts[5]), required = tonumber(parts[6]), label = parts[7] or "目标" }
        redrawObjectives()
    elseif kind == "PROGRESS" and objectives[tonumber(parts[2])] then
        objectives[tonumber(parts[2])].current = tonumber(parts[3])
        redrawObjectives()
    elseif kind == "DEATH" and run then
        run.deaths = tonumber(parts[2]) or run.deaths
        run.penalty = tonumber(parts[3]) or run.penalty or 0
    elseif kind == "COMPLETE" then
        frame:Hide()
        run = nil
        objectives = {}
        MythicPlusUI_ShowCompletion(tonumber(parts[2]), tonumber(parts[3]), tonumber(parts[4]) == 1)
    end
end

local function filter(_, event, message)
    if string.sub(message or "", 1, string.len(prefix)) == prefix then
        handle(message)
        return true
    end
end

ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", filter)
frame:SetScript("OnUpdate", function(_, elapsed)
    if not run then return end
    run.display = (run.display or 0) + elapsed
    if run.display < 0.1 then return end
    run.display = 0
    local elapsedSeconds = time() - run.start + (run.deaths * (run.penalty or 0))
    timer:SetText(formatTime(elapsedSeconds) .. " / " .. formatTime(run.limit))
    if elapsedSeconds > run.limit then timer:SetTextColor(1, 0.25, 0.25) else timer:SetTextColor(1, 0.82, 0.25) end
end)

function MythicPlusUI_ShowCompletion(level, elapsed, timed)
    local result = CreateFrame("Frame", nil, UIParent)
    result:SetWidth(430); result:SetHeight(190)
    result:SetPoint("TOP", UIParent, "TOP", 0, -180)
    local text = result:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("CENTER", 0, 12)
    text:SetText(string.format("大秘境 +%d 完成  %s", level or 0, timed and "限时" or "超时"))
    local sub = result:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("CENTER", 0, -18)
    sub:SetText("用时 " .. formatTime(elapsed or 0) .. "    队伍结算")
    local units = { "player", "party1", "party2", "party3", "party4" }
    for index, unit in ipairs(units) do
        local portrait = CreateFrame("Frame", nil, result)
        portrait:SetWidth(62); portrait:SetHeight(82)
        portrait:SetPoint("TOPLEFT", 8 + (index - 1) * 84, -62)
        local texture = portrait:CreateTexture(nil, "ARTWORK")
        texture:SetWidth(54); texture:SetHeight(54); texture:SetPoint("TOP", 0, 0)
        if UnitExists(unit) then SetPortraitTexture(texture, unit) else texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
        local name = portrait:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        name:SetPoint("TOP", texture, "BOTTOM", 0, -3)
        name:SetWidth(78); name:SetHeight(18); name:SetText(UnitExists(unit) and (UnitName(unit) or "未知") or "空位")
    end
    result:SetScript("OnShow", function(self) self.elapsed = 0 end)
    result:SetScript("OnUpdate", function(self, delta)
        self.elapsed = (self.elapsed or 0) + delta
        if self.elapsed > 8 then self:Hide(); self:SetScript("OnUpdate", nil) end
    end)
    result:Show()
end
