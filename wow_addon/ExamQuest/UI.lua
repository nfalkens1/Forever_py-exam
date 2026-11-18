-- ExamQuest · UI: a small tracker of exam objectives and a subject window.

local _, ns = ...

local MAX_ROWS = 25
local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function panel(name, parent)
    local f = CreateFrame("Frame", name, parent or UIParent,
                          BackdropTemplateMixin and "BackdropTemplate" or nil)
    if f.SetBackdrop then
        f:SetBackdrop(BACKDROP)
        f:SetBackdropColor(0, 0, 0, 0.8)
        f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    end
    return f
end

local function smallButton(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 20)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

-- WoW reads "|" as the start of an escape sequence (|c colour, |T
-- texture …); a subject that contains one has to double it.
local function plain(text)
    return (text or ""):gsub("|", "||")
end

-- ── subject window ──────────────────────────────────────────────

local subject = panel("ExamQuestSubject")
subject:SetSize(560, 460)
subject:SetPoint("CENTER")
subject:SetFrameStrata("DIALOG")
subject:SetMovable(true)
subject:EnableMouse(true)
subject:RegisterForDrag("LeftButton")
subject:SetScript("OnDragStart", subject.StartMoving)
subject:SetScript("OnDragStop", subject.StopMovingOrSizing)
subject:Hide()
tinsert(UISpecialFrames, "ExamQuestSubject")  -- Escape closes it

subject.title = subject:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
subject.title:SetPoint("TOPLEFT", 14, -12)

subject.status = subject:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subject.status:SetPoint("TOPLEFT", subject.title, "BOTTOMLEFT", 0, -6)
subject.status:SetPoint("RIGHT", -14, 0)
subject.status:SetJustifyH("LEFT")

local close = CreateFrame("Button", nil, subject, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -2, -2)

local scroll = CreateFrame("ScrollFrame", nil, subject)
scroll:SetPoint("TOPLEFT", 14, -56)
scroll:SetPoint("BOTTOMRIGHT", -14, 40)
scroll:EnableMouseWheel(true)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(530, 10)
scroll:SetScrollChild(content)
local body = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
body:SetPoint("TOPLEFT")
body:SetWidth(530)
body:SetJustifyH("LEFT")
body:SetJustifyV("TOP")
scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, content:GetHeight() - self:GetHeight())
    local y = self:GetVerticalScroll() - delta * 40
    self:SetVerticalScroll(math.max(0, math.min(max, y)))
end)

local reload = smallButton(subject, "Reload (check result)", 170, ReloadUI)
reload:SetPoint("BOTTOMRIGHT", -12, 12)

subject.hint = subject:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
subject.hint:SetPoint("BOTTOMLEFT", 14, 16)
subject.hint:SetPoint("RIGHT", reload, "LEFT", -8, 0)
subject.hint:SetJustifyH("LEFT")

local shownEntry

local function fillSubject()
    local entry = shownEntry
    if not entry then return end
    local ex = ns.Exercise(entry.ex)
    subject.title:SetText(("%s  |cff888888(level %d)|r"):format(
        entry.ex, entry.level or 0))
    if ns.IsDone(entry) then
        subject.status:SetText(("|cff00ff00Passed.|r You can turn in %s.")
            :format(entry.title or "the quest"))
    else
        subject.status:SetText(("|cffff3333Open|r - blocks the turn-in of %s.")
            :format(entry.title or "the quest"))
    end
    subject.hint:SetText(("Write rendu/%s.py - examquest.py grades it on "
        .. "save. Then reload."):format(entry.ex))
    body:SetText(plain(ex and ex.subject
        or "This exercise is not in the installed pool any more."))
    content:SetHeight(body:GetStringHeight() + 20)
    scroll:SetVerticalScroll(0)
end

function ns.ShowSubject(entry)
    shownEntry = entry
    fillSubject()
    subject:Show()
end

-- ── tracker ─────────────────────────────────────────────────────

local tracker = panel("ExamQuestTracker")
tracker:SetSize(280, 60)
tracker:SetClampedToScreen(true)
tracker:SetMovable(true)
tracker:EnableMouse(true)
tracker:RegisterForDrag("LeftButton")
tracker:SetScript("OnDragStart", tracker.StartMoving)
tracker:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    ExamQuestDB.trackerPos = { point, rel, x, y }
end)
tracker:Hide()

local header = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
header:SetPoint("TOPLEFT", 10, -8)
header:SetText("Exam objectives")

local reloadSmall = smallButton(tracker, "Reload", 60, ReloadUI)
reloadSmall:SetPoint("TOPRIGHT", -6, -5)

local empty = tracker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
empty:SetPoint("TOPLEFT", 10, -30)
empty:SetText("None - accept a quest.")

local rows = {}
for i = 1, MAX_ROWS do
    local row = CreateFrame("Button", nil, tracker)
    row:SetSize(260, 16)
    row:SetPoint("TOPLEFT", 10, -10 - i * 18)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetAllPoints()
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight",
                            "ADD")
    row:SetScript("OnClick", function(self) ns.ShowSubject(self.entry) end)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.entry.title or "?")
        GameTooltip:AddLine("Exam: " .. self.entry.ex, 0.4, 0.8, 1)
        GameTooltip:AddLine("Click to read the subject.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:Hide()
    rows[i] = row
end

local placed = false

local function refresh()
    if not placed then
        placed = true
        local pos = ExamQuestDB.trackerPos
        tracker:ClearAllPoints()
        if pos then
            tracker:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        else
            tracker:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120)
        end
        tracker:SetShown(ExamQuestDB.trackerShown ~= false)
    end

    -- Open objectives first, then by quest title.
    local list = {}
    for _, entry in pairs(ns.Quests()) do table.insert(list, entry) end
    table.sort(list, function(a, b)
        local da, db = ns.IsDone(a), ns.IsDone(b)
        if da ~= db then return not da end
        return (a.title or "") < (b.title or "")
    end)

    for i, row in ipairs(rows) do
        local entry = list[i]
        if entry then
            row.entry = entry
            local mark = ns.IsDone(entry) and "|cff00ff00done|r"
                or "|cffff3333open|r"
            row.text:SetText(("%s  %s |cff888888-|r |cff66ccff%s|r")
                :format(mark, plain(entry.title or "?"), entry.ex))
            row:Show()
        else
            row:Hide()
        end
    end
    local shown = math.min(#list, MAX_ROWS)
    empty:SetShown(shown == 0)
    tracker:SetHeight(36 + math.max(1, shown) * 18)
    if subject:IsShown() then fillSubject() end
end
table.insert(ns.listeners, refresh)

function ns.ToggleTracker()
    tracker:SetShown(not tracker:IsShown())
    ExamQuestDB.trackerShown = tracker:IsShown()
end
