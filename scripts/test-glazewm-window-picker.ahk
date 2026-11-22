#Requires AutoHotkey v2.0
#NoTrayIcon
; Exercises the GlazeWM window picker's helpers headless. Run it through
; scripts/test-glazewm-window-picker.sh, which fails when this exits non-zero.
#Include %A_ScriptDir%\..\dot_glzr\glazewm\window-picker-lib.ahk

; Report runtime errors on stdout and fail, instead of an error dialog that
; would block the hook until someone closes it.
OnError((err, *) => (FileAppend("not ok - " err.Message " (line " err.Line ")`n", "*", "UTF-8"), ExitApp(1)))

failures := 0

Check(name, actual, expected) {
    global failures
    if (actual == expected) {
        FileAppend("ok - " name "`n", "*", "UTF-8")
        return
    }
    failures += 1
    FileAppend("not ok - " name ": expected [" expected "], got [" actual "]`n", "*", "UTF-8")
}

Ids(windows) {
    ids := ""
    for window in windows
        ids .= (ids = "" ? "" : ",") window["id"]
    return ids
}

; Shaped like `glazewm query workspaces` (GlazeWM 3.10.1): windows can sit in
; split containers, and titles carry escapes and non-ASCII text.
sample := "
(
{"clientMessage":"query workspaces","data":{"workspaces":[
{"type":"workspace","id":"w0","name":"0","hasFocus":false,"isDisplayed":true,"children":[
{"type":"window","id":"a1","title":"#general | server - Discord","processName":"Discord","tilingSize":0.5,"x":-1080,"state":{"type":"tiling"},"prevState":null}]},
{"type":"workspace","id":"w2","name":"2","hasFocus":false,"isDisplayed":false,"children":[
{"type":"split","id":"s1","tilingDirection":"vertical","children":[
{"type":"window","id":"b1","title":"Daily calendar","processName":"notes"},
{"type":"window","id":"b2","title":"ALCOM","processName":"ALCOM"}]},
{"type":"window","id":"b3","title":"Say \"hi\" \\ caf\u00e9","processName":"brave"}]},
{"type":"workspace","id":"w3","name":"3","hasFocus":true,"isDisplayed":true,"children":[
{"type":"window","id":"c1","title":"[1/4] tm ~","processName":"wezterm-gui"},
{"type":"window","id":"c2","title":"OBS 32.1.2 - Scenes: 無題","processName":"obs64"}]},
{"type":"workspace","id":"w1","name":"1","hasFocus":false,"isDisplayed":false,"children":[
{"type":"window","id":"d1","title":"VRChat","processName":"VRChat","state":{"type":"fullscreen","maximized":false}}]}
]},"error":null,"success":true}
)"

parsed := PickerParseJson('{"n":-1080,"f":0.5,"t":true,"z":null,"e":[],"a":[1,{"k":"v"}]}')
Check("parses negative integers", parsed["n"], -1080)
Check("parses decimals", parsed["f"], 0.5)
Check("parses true", parsed["t"], true)
Check("parses null as an empty string", parsed["z"], "")
Check("parses empty arrays", parsed["e"].Length, 0)
Check("parses objects nested in arrays", parsed["a"][2]["k"], "v")

threw := false
try PickerParseJson('{"a":')
catch
    threw := true
Check("rejects truncated JSON", threw, true)

windows := PickerCollectWindows(PickerParseJson(sample))
Check("collects windows in tree order, split children included", Ids(windows), "a1,b1,b2,b3,c1,c2,d1")
Check("tags a split child with its workspace", windows[3]["workspace"], "2")
Check("records that a window's workspace is shown", windows[1]["displayed"], true)
Check("records that a window's workspace is hidden", windows[3]["displayed"], false)
Check("decodes title escapes", windows[4]["title"], 'Say "hi" \ café')
Check("keeps non-ASCII titles", windows[6]["title"], "OBS 32.1.2 - Scenes: 無題")

Check("blank query keeps every window in order", Ids(PickerFilterWindows(windows, "  ")), "a1,b1,b2,b3,c1,c2,d1")
Check("matches case-insensitively, tightest match first", Ids(PickerFilterWindows(windows, "vrc")), "d1,a1")
Check("ranks a contiguous match above scattered ones", Ids(PickerFilterWindows(windows, "alc")), "b2,b1,a1")
Check("requires every term, workspace name included", Ids(PickerFilterWindows(windows, "3 wez")), "c1")
Check("returns nothing when no window matches", Ids(PickerFilterWindows(windows, "zzz")), "")

ExitApp(failures ? 1 : 0)
