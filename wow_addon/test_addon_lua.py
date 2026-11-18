"""Run the ExamQuest addon in Lua 5.1 against a mocked WoW API.

Needs `pip install lupa` (not a dependency of the tester). Usage:
    python wow_addon/test_addon_lua.py <installed ExamQuest folder>
(the installed one, because it has the generated Pool.lua)
"""
import sys
import lupa.lua51 as lupa

ADDON = sys.argv[1]  # installed addon dir (with generated Pool.lua)

MOCK = r"""
local log = {}
_LOG = log
local function mock(kind, name)
  local o = { _kind = kind, _name = name, _shown = true, _enabled = true,
              _scripts = {}, _hooks = {}, _text = "" }
  local m = {}
  function m:Show() self._shown = true; self:_fire("OnShow") end
  function m:Hide() self._shown = false end
  function m:SetShown(v) if v then self:Show() else self:Hide() end end
  function m:IsShown() return self._shown end
  function m:IsVisible() return self._shown end
  function m:Enable() self._enabled = true; self:_fire("OnEnable") end
  function m:Disable() self._enabled = false end
  function m:IsEnabled() return self._enabled end
  function m:SetScript(ev, fn) self._scripts[ev] = fn end
  function m:HookScript(ev, fn) table.insert(self._hooks, {ev, fn}) end
  function m:_fire(ev, ...)
    if self._scripts[ev] then self._scripts[ev](self, ...) end
    for _, h in ipairs(self._hooks) do
      if h[1] == ev then h[2](self, ...) end
    end
  end
  function m:SetText(t) self._text = t end
  function m:GetText() return self._text end
  function m:GetStringHeight() return 300 end
  function m:GetHeight() return 200 end
  function m:GetVerticalScroll() return 0 end
  function m:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
  function m:CreateFontString() return mock("FontString") end
  function m:RegisterEvent(e) self._events = self._events or {}; self._events[e] = true end
  setmetatable(o, { __index = function(t, k)
    if m[k] then return m[k] end
    if type(k) == "string" and k:sub(1, 1) == "_" then return nil end
    if k == "examQuestHooked" or k == "entry" then return nil end
    return function() end
  end })
  return o
end

FRAMES = {}
function CreateFrame(kind, name, parent, template)
  local f = mock(kind, name)
  table.insert(FRAMES, f)
  if name then _G[name] = f end
  return f
end
UIParent = mock("Frame", "UIParent")
GameTooltip = mock("GameTooltip")
GameTooltip_Hide = function() end
UIErrorsFrame = mock("Frame")
function UIErrorsFrame:AddMessage(t) table.insert(log, "ERR " .. t) end
UISpecialFrames = {}
tinsert = table.insert
BackdropTemplateMixin = {}
function print(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end table.insert(log, table.concat(t, " ")) end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
SlashCmdList = {}
ReloadUI = function() end
C_Timer = { After = function(_, fn) fn() end }
PLAYER_LEVEL = 5
function UnitLevel() return PLAYER_LEVEL end
function GetMaxLevelForPlayerExpansion() return 60 end
CURRENT_QUEST = 0
function GetQuestID() return CURRENT_QUEST end
QUESTS = {}
C_QuestLog = {
  GetTitleForQuestID = function(id) return QUESTS[id] end,
  IsOnQuest = function(id) return QUESTS[id] ~= nil end,
  GetNumQuestLogEntries = function() local n = 0 for _ in pairs(QUESTS) do n = n + 1 end return n + 1 end,
  GetInfo = function(i)
    if i == 1 then return { isHeader = true, title = "Zone" } end
    local k = 1
    for id, title in pairs(QUESTS) do
      k = k + 1
      if k == i then return { questID = id, title = title, isHeader = false } end
    end
  end,
}
QuestFrameCompleteQuestButton = mock("Button", "QuestFrameCompleteQuestButton")
QuestFrameCompleteButton = mock("Button", "QuestFrameCompleteButton")
math.randomseed(SEED or 1)

function FIRE(event, ...)
  for _, f in ipairs(FRAMES) do
    if f._events and f._events[event] then f:_fire("OnEvent", event, ...) end
  end
end
"""


def run_file(lua, path, ns=None):
    src = open(path, encoding="utf-8").read()
    chunk = lua.execute("return function(src, name) "
                        "local f, err = loadstring(src, name) "
                        "if not f then error(err) end return f end")(
                            src, "@" + path)
    if ns is None:
        chunk()
    else:
        chunk("ExamQuest", ns)


def to_py(v):
    if lupa.lua_type(v) == "table":
        return {k: to_py(x) for k, x in v.items()}
    return v


def to_lua(lua, v):
    if isinstance(v, dict):
        t = lua.table()
        for k, x in v.items():
            t[k] = to_lua(lua, x)
        return t
    return v


def boot(saved=None, quests=None, passes=None):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    g = lua.globals()
    for k, v in (quests or {}).items():
        g.QUESTS[k] = v
    if saved:
        g.ExamQuestDB = to_lua(lua, saved[0])
        g.ExamQuestCharDB = to_lua(lua, saved[1])
    ns = lua.table()
    for f in ("Pool.lua", "Results.lua", "Core.lua", "UI.lua"):
        run_file(lua, "%s/%s" % (ADDON, f), ns if f in ("Core.lua", "UI.lua") else None)
    for k, v in (passes or {}).items():
        g.ExamQuest_Results.exercises[k] = lua.table_from(
            {"passes": v, "last": 0})
    g.FIRE("ADDON_LOADED", "Other")
    g.FIRE("ADDON_LOADED", "ExamQuest")
    g.FIRE("PLAYER_LOGIN")
    return lua, g, ns


def drain(g, label):
    log = g._LOG
    print("--", label)
    for i in range(1, len(log) + 1):
        print("   ", log[i])
    for i in range(len(log), 0, -1):
        log[i] = None


def check(cond, what):
    print(("PASS " if cond else "FAIL ") + what)
    if not cond:
        global failed
        failed = True


failed = False
lua, g, ns = boot()
drain(g, "login")

btn = g.QuestFrameCompleteQuestButton
g.QUESTS[101] = "Kill 10 Troggs"
g.FIRE("QUEST_ACCEPTED", 101)
drain(g, "accept 101")
entry = g.ExamQuestCharDB.quests[101]
check(entry is not None, "quest 101 got an exercise")
ex = entry.ex

g.CURRENT_QUEST = 101
btn._enabled = True
g.FIRE("QUEST_COMPLETE")
drain(g, "try turn-in")
check(not btn._enabled, "Complete Quest button disabled while open")
btn.Enable(btn)
check(not btn._enabled, "re-enabling by Blizzard is undone")

# Unrelated quest is not gated
g.QUESTS[202] = "Talk to the dwarf"
g.ExamQuestDB.chance = 0
g.FIRE("QUEST_ACCEPTED", 202)
check(g.ExamQuestCharDB.quests[202] is None, "chance 0 -> no exercise")
g.CURRENT_QUEST = 202
btn._enabled = True
g.FIRE("QUEST_COMPLETE")
check(btn._enabled, "ungated quest can be turned in")
g.ExamQuestDB.chance = 100
drain(g, "quest 202")

# Simulate: companion recorded a pass, player does /reload.
saved = (to_py(g.ExamQuestDB), to_py(g.ExamQuestCharDB))
lua, g, ns = boot(saved, {101: "Kill 10 Troggs", 202: "Talk"}, {ex: 1})
drain(g, "after reload with pass")
btn = g.QuestFrameCompleteQuestButton
g.CURRENT_QUEST = 101
btn._enabled = True
g.FIRE("QUEST_COMPLETE")
check(btn._enabled, "after a pass the quest can be turned in")
g.FIRE("QUEST_TURNED_IN", 101, 0, 0)
g.FIRE("QUEST_REMOVED", 101)
check(g.ExamQuestCharDB.quests[101] is None and g.ExamQuestDB.turnedIn == 1,
      "turn-in cleans up and counts")

# The same exercise again later needs a NEW pass (baseline = 1).
g.ExamQuestDB.lastAssigned = lua.table()   # make ex likely again
g.QUESTS[303] = "More troggs"
for _ in range(20):
    g.ExamQuestCharDB.quests[303] = None
    g.FIRE("QUEST_ACCEPTED", 303)
    if g.ExamQuestCharDB.quests[303].ex == ex:
        break
e3 = g.ExamQuestCharDB.quests[303]
check(e3.ex != ex or (e3.baseline == 1 and not ns.IsDone(e3)),
      "old pass doesn't count for a new quest")

# Rotation: every exercise, of every level, before a repeat; and the
# order is random, not level by level.
g.ExamQuestDB.lastAssigned = lua.table()
g.ExamQuestCharDB.quests = lua.table()
exs = g.ExamQuest_Pool.exercises
pool = [exs[i].name for i in range(1, len(exs) + 1)]
picked = []
for q in range(1000, 1000 + len(pool)):
    g.QUESTS[q] = "Q%d" % q
    g.FIRE("QUEST_ACCEPTED", q)
    e = g.ExamQuestCharDB.quests[q]
    picked.append((e.ex, e.level))
check(sorted(n for n, _ in picked) == sorted(pool),
      "all %d exercises before a repeat" % len(pool))
first = {lv for _, lv in picked[:8]}
check(len(first) >= 3, "first 8 picks span levels %s" % sorted(first))
drain(g, "rotation")

# Character level doesn't matter.
g.ExamQuestCharDB.quests = lua.table()
g.ExamQuestDB.lastAssigned = lua.table()
g.PLAYER_LEVEL = 40
lv40 = set()
for q in range(3000, 3012):
    g.QUESTS[q] = "Q%d" % q
    g.FIRE("QUEST_ACCEPTED", q)
    lv40.add(g.ExamQuestCharDB.quests[q].level)
check(len(lv40) >= 3, "at char level 40, levels %s" % sorted(lv40))
drain(g, "char 40")

slash = g.SlashCmdList.EXAMQUEST
for c in ("status", "chance 50", "off", "on",
          "help", "", ""):
    slash(c)
drain(g, "slash")
check(g.ExamQuestDB.chance == 50, "/eq chance 50")

# adopt quests already in the log
g.ExamQuestCharDB.quests = lua.table()
g.QUESTS = lua.table_from({7: "Old quest", 8: "Older quest"})
slash("adopt")
check(g.ExamQuestCharDB.quests[7] is not None
      and g.ExamQuestCharDB.quests[8] is not None, "/eq adopt")
drain(g, "adopt")

# subject window with a '|' in the text
ns.ShowSubject(g.ExamQuestCharDB.quests[7])
body = [f for f in g.FRAMES.values()]
check(g.ExamQuestSubject._shown, "subject window opens")
print("\nRESULT:", "FAILED" if failed else "all checks passed")
