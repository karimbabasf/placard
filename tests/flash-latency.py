#!/usr/bin/env python3
"""End-to-end check of Christmas mode against the running Placard.

Opens one small scratch Terminal window that imitates a Claude prompt (idle glyph
in the title, "Esc to cancel" on screen), lets it flash, "answers" it, and times
how long the window takes to get its own colors back. Three rounds back to back,
because a prompt that follows an answer within a second is what used to leave
the text in a flash color.

Pass: every round restores in under LIMIT seconds, the flash never comes back
after an answer, and the text ends on the profile's color.

    python3 tests/flash-latency.py
"""
import os, subprocess, sys, tempfile, time

LIMIT = 1.0
ROUNDS = 3

SCRATCH = r'''
import os, sys, time
d = sys.argv[1]
def title(s): sys.stdout.write("\033]0;" + s + "\007"); sys.stdout.flush()
def there(n): return os.path.exists(os.path.join(d, n))
def stamp(n): open(os.path.join(d, n), "w").write(repr(time.time()))
n = 0
while True:
    sys.stdout.write("\033[2J\033[H Run the test?\n  1. Yes\n  2. No\n\n Enter to select · Esc to cancel\n")
    title("✳ Flash test")
    stamp("asked%d" % n)
    while not there("answer%d" % n): time.sleep(0.005)
    sys.stdout.write("\033[2J\033[H working\n")
    title("⠐ Flash test")
    stamp("t0_%d" % n)
    while not there("ask%d" % (n + 1)) and not there("quit"): time.sleep(0.005)
    if there("quit"): break
    n += 1
'''


def osa(src):
    r = subprocess.run(["osascript", "-e", src], capture_output=True, text=True)
    return r.stdout.strip()


def colors(win):
    out = osa(f'''tell application "Terminal"
set AppleScript's text item delimiters to ","
set t to tab 1 of window id {win}
set s to settings set (name of current settings of t)
return ((normal text color of t) as string) & "|" & ((normal text color of s) as string) & "|" & ((bold text color of t) as string) & "|" & ((bold text color of s) as string)
end tell''')
    return out.split("|") if out.count("|") == 3 else None


def main():
    d = tempfile.mkdtemp(prefix="placard-flash-")
    script = os.path.join(d, "scratch.py")
    open(script, "w").write(SCRATCH)
    win = osa(f'''tell application "Terminal"
set prev to id of front window
set newTab to do script "exec python3 {script} {d}"
set w to id of front window
set bounds of window id w to {{40, 60, 460, 300}}
set index of window id prev to 1
return w
end tell''')
    print(f"scratch window {win}")
    worst, blips, ok = 0.0, 0, True
    try:
        for n in range(ROUNDS):
            deadline = time.time() + 10
            while time.time() < deadline:
                c = colors(win)
                if c and c[0] != c[1]: break
            else:
                print(f"round {n + 1}: never started flashing"); ok = False; break
            time.sleep(1.0 if n else 2.5)
            open(os.path.join(d, f"answer{n}"), "w").close()
            while not os.path.exists(os.path.join(d, f"t0_{n}")): time.sleep(0.005)
            time.sleep(0.02)
            t0 = float(open(os.path.join(d, f"t0_{n}")).read())
            streak, first, deadline = 0, None, time.time() + 20
            while time.time() < deadline and streak < 4:
                c = colors(win)
                if c and c[0] == c[1]:
                    if streak == 0: first = time.time()
                    streak += 1
                else:
                    streak = 0
            if streak < 4:
                print(f"round {n + 1}: colors not back after 20 s"); ok = False; break
            lag = first - t0
            worst = max(worst, lag)
            # The flash must stay off while the agent works.
            back, until = 0, time.time() + 1.2
            while time.time() < until:
                c = colors(win)
                if c and c[0] != c[1]: back += 1
            blips += back
            print(f"round {n + 1}: colors back {lag:.2f} s after the answer" + (f", flash came back ({back} reads)" if back else ""))
            if n + 1 < ROUNDS: open(os.path.join(d, f"ask{n + 1}"), "w").close()
        time.sleep(1.5)
        c = colors(win)
        clean = bool(c) and c[0] == c[1] and c[2] == c[3]
        print(f"final text {c[0] if c else '?'} vs profile {c[1] if c else '?'}: {'clean' if clean else 'STUCK'}")
        ok = ok and clean and blips == 0 and worst < LIMIT
        print(f"worst {worst:.2f} s (limit {LIMIT} s): {'PASS' if ok else 'FAIL'}")
    finally:
        open(os.path.join(d, "quit"), "w").close()
        time.sleep(0.6)
        osa(f'tell application "Terminal" to close window id {win}')
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
