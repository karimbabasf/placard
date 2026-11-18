# Placard

Menu bar app that puts a big colored name strip in the title bar of each Terminal.app window, groups windows under one name, and shows whether the agent in each window is working or waiting for you.

## Run

    ./build.sh --install

Builds `build/Placard.app`, copies it to `~/Applications`, installs the `placard` CLI to `~/.local/bin`, and launches it. First launch asks once for permission to control Terminal.

## Use

- Click the `+` at the right end of any Terminal title bar to label that window. Typing an existing name joins its group.
- Click a label's name to rename the group. Click the chevron (or right-click) for the dropdown: color, emoji, bring group to front, tile, move, remove, show or hide labels, tint.
- Hotkeys: ctrl+opt+L label front window, ctrl+opt+U remove, ctrl+opt+T tile its group, ctrl+opt+1..9 bring group N to front.
- From a shell: `placard API`, `placard API blue`, `placard -u`, `placard -r API`, `placard -t API`.

## Test

    ./build.sh && open build/Placard.app
    open -g "placard://label?window=<terminal window id>&name=Test"

Window ids: `osascript -e 'tell application "Terminal" to get id of every window'`. Errors from Terminal scripting go to `~/Library/Logs/Placard.log`.

Geist and Geist Pixel fonts are bundled under the SIL Open Font License (`Resources/Fonts/OFL.txt`).
