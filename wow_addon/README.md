# ExamQuest — exam exercises as WoW quest objectives

Every quest you accept in **World of Warcraft: Forever** gets an extra
objective: an exercise from **Python Exam Rank 03** (all 44, levels 1–6,
picked at random — your character level doesn't matter). You can kill all ten
troggs you want — the *Complete Quest* button stays greyed out until that
exercise passes.

```
 accept quest ──► addon assigns a random Rank 03 exercise, e.g. py_inter
                  tracker + subject window in game  (/eq)
 write rendu/py_inter.py ──► examquest.py watch grades it on save
                  SUCCESS ──► Results.lua in the addon folder gets +1 pass
 /reload in game ──► objective done ──► turn in
```

## Why the /reload

WoW addons can't read files or start programs. The only way in is the
addon's own Lua files, which the game re-reads on `/reload`. The companion
writes `Results.lua`; `/reload` (or the *Reload* button on the tracker)
picks it up.

A pass only counts if it happened **after** you accepted the quest (the
addon remembers the pass counter at accept time). A passing file is moved
to `rendu/.examquest_passed/`, so when the same exercise comes up again,
you write it from scratch. `--keep` turns that off.

## Setup at home

The grader needs Linux or macOS (it uses `SIGALRM`). On **Windows use
WSL**: the companion runs in WSL and writes into the Windows WoW folder
through `/mnt/c`.

1. In WSL (or on macOS), get this branch and Python 3.9+:
   ```bash
   git clone <your copy of this repo> exam_tester && cd exam_tester
   git switch wow-addon
   ```
   No `make install` needed — the companion uses only the standard
   library and this repo's grader.

2. Find the Forever folder: Battle.net → WoW Forever → gear icon →
   *Show in Explorer*. It should be `…\World of Warcraft\_forever_`.
   Install (WoW closed, or restart it afterwards):
   ```bash
   python3 wow_addon/examquest.py install \
       --wow "/mnt/c/Program Files (x86)/World of Warcraft/_forever_"
   ```
   (macOS: `--wow "/Applications/World of Warcraft/_forever_"`.)

3. Leave this running in a terminal:
   ```bash
   python3 wow_addon/examquest.py watch
   ```

4. Start WoW. If the AddOns list says *out of date*, tick **Load out of
   date AddOns** (the TOC says Interface 16001; if Forever's number has
   moved, edit the first line of `ExamQuest.toc`).

5. Accept a quest. Chat says e.g. `new exam objective for Kill 10 Troggs:
   py_inter (level 1)`. Click it in the tracker for the subject, then
   ```bash
   python3 wow_addon/examquest.py new py_inter   # just the signature
   code rendu/py_inter.py                         # VS Code + WSL works
   ```
   Save → the watcher prints SUCCESS / FAILURE (first 3 failing tests) →
   `/reload` → turn in.

## In game

| | |
|---|---|
| `/eq` | show / hide the tracker (drag to move; click a line for the subject) |
| `/eq status` | open objectives and settings |
| `/eq chance 30` | only 30 % of new quests get an exercise |
| `/eq off` · `/eq on` | pause handing out exercises |
| `/eq adopt` | give the quests already in your log an exercise |

Difficulty is random: any of the 44 Rank 03 exercises, any level. The
ones you haven't had yet (or had longest ago) come first, so the whole
pool comes round before an exercise repeats.

## Companion

| | |
|---|---|
| `install --wow <dir>` | copy the addon, write `Pool.lua` (Rank 03); re-run to update the addon |
| `watch [--keep] [--rendu DIR]` | grade on save (only files that change while it runs) |
| `grade <exercise> [--keep]` | grade once |
| `new <exercise>` | signature-only stub |

Settings and the pass history live in `~/.examshell/examquest.json` and
`examquest_results.json` (the history survives reinstalls).

## Limits

- It's honour-system: disabling the addon, or another addon that
  auto-completes quests, gets around the gate.
- Quests that complete without the quest dialog (some auto-complete
  popups on the modern client open it anyway) aren't gated.
- Tested against a mocked WoW API (`test_addon_lua.py`, needs
  `pip install lupa`), not yet in the real Forever client.
