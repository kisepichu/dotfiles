#Requires AutoHotkey v2.0 64-bit
#SingleInstance Force
#NoTrayIcon
#Include %A_ScriptDir%\window-picker-lib.ahk

; GlazeWM window picker (Mod+Space). GlazeWM starts it from a shell-exec
; keybinding. It lists every managed window, including those on hidden
; workspaces that PowerToys Command Palette's "Switch windows" leaves out
; (GlazeWM cloaks them), and focuses the chosen one, showing its workspace
; first when that workspace is hidden and restoring it when it is minimized.
; Type to filter, Up/Down to move, Enter to focus. Esc, or anything else
; taking focus, closes it. It is a tool window, so GlazeWM does not tile it.

glazewm := A_ProgramFiles "\glzr.io\GlazeWM\cli\glazewm.exe"
allWindows := []
shown := []
shownQuery := ""
choosing := false
SetWinDelay(-1)  ; no 100 ms pause after WinActivate

picker := Gui("+AlwaysOnTop +ToolWindow", "GlazeWM window picker")
pickerHwnd := picker.Hwnd
picker.SetFont("s11", "Segoe UI")
search := picker.AddEdit("w900")
list := picker.AddListView("w900 r16 -Multi NoSortHdr", ["WS", "App", "Title"])
search.OnEvent("Change", (*) => Refresh())
list.OnEvent("DoubleClick", (*) => Choose())
picker.OnEvent("Escape", (*) => ExitApp())
picker.OnEvent("Close", (*) => ExitApp())
OnMessage(0x0100, OnKeyDown)          ; WM_KEYDOWN

; Show the window first and fill it when GlazeWM answers (about 0.3 s), so
; typing can start at once; Refresh applies whatever was typed meanwhile.
picker.Show()
WinActivate(picker)
search.Focus()
; Close as soon as another window has focus. A WM_ACTIVATE hook would miss
; the case where something (e.g. Start) takes focus before the picker ever
; became active, leaving an always-on-top window that Esc cannot reach.
SetTimer(CloseIfInactive, 250)
try allWindows := PickerCollectWindows(PickerParseJson(RunGlazeWM("query workspaces")))
catch as err {
    SetTimer(CloseIfInactive, 0)
    picker.Hide()
    MsgBox("Could not list GlazeWM windows: " err.Message, "GlazeWM window picker", "Iconx")
    ExitApp(1)
}
Refresh()

Refresh() {
    global shown, shownQuery
    shownQuery := search.Value
    shown := PickerFilterWindows(allWindows, shownQuery)
    list.Opt("-Redraw")
    list.Delete()
    for window in shown
        list.Add(, window["workspace"], window["process"], window["title"])
    if shown.Length
        list.Modify(1, "Select Focus Vis")
    loop 3
        list.ModifyCol(A_Index, "AutoHdr")
    list.Opt("+Redraw")
}

; Enter focuses the selection from the search box or the list; Up/Down in the
; search box move the selection. Other keys keep their default handling.
OnKeyDown(wParam, lParam, msg, hwnd) {
    if (wParam = 0x0D && (hwnd = search.Hwnd || hwnd = list.Hwnd)) {  ; VK_RETURN
        Choose()
        return 0
    }
    if (hwnd != search.Hwnd || (wParam != 0x26 && wParam != 0x28))   ; VK_UP, VK_DOWN
        return
    if shown.Length {
        row := Max(1, Min(shown.Length, list.GetNext() + (wParam = 0x26 ? -1 : 1)))
        list.Modify(0, "-Select")
        list.Modify(row, "Select Focus Vis")
    }
    return 0
}

Choose() {
    global choosing
    ; Enter can arrive before the Change event for the last typed characters.
    if (shownQuery != search.Value)
        Refresh()
    row := list.GetNext()
    if !row
        return
    target := shown[row]
    choosing := true
    picker.Hide()
    try {
        for command in PickerFocusCommands(target)
            RunGlazeWM(command)
    }
    ExitApp()
}

CloseIfInactive() {
    if (!choosing && !WinActive(pickerHwnd))
        ExitApp()
}

; Runs the GlazeWM CLI and returns its stdout. The CLI is started directly
; with CREATE_NO_WINDOW and a pipe: going through cmd.exe for a redirect
; creates a hidden console and costs 0.3-0.6 s. The CLI waits for the WM
; without a deadline, so give up after 5 s in case GlazeWM hangs.
RunGlazeWM(args) {
    ; SECURITY_ATTRIBUTES with bInheritHandle, so the child gets the write end.
    attributes := Buffer(24, 0)
    NumPut("UInt", attributes.Size, attributes, 0)
    NumPut("Int", 1, attributes, 16)
    if !DllCall("CreatePipe", "Ptr*", &readPipe := 0, "Ptr*", &writePipe := 0, "Ptr", attributes, "UInt", 0)
        throw OSError()
    DllCall("SetHandleInformation", "Ptr", readPipe, "UInt", 1, "UInt", 0)  ; HANDLE_FLAG_INHERIT off

    ; STARTUPINFOW: dwFlags = STARTF_USESTDHANDLES, hStdOutput = hStdError = pipe.
    startup := Buffer(104, 0)
    NumPut("UInt", startup.Size, startup, 0)
    NumPut("UInt", 0x100, startup, 60)
    NumPut("Ptr", writePipe, startup, 88)
    NumPut("Ptr", writePipe, startup, 96)
    processInfo := Buffer(24, 0)
    created := DllCall("CreateProcessW", "Ptr", 0, "Str", '"' glazewm '" ' args, "Ptr", 0, "Ptr", 0
        , "Int", true, "UInt", 0x08000000, "Ptr", 0, "Ptr", 0, "Ptr", startup, "Ptr", processInfo)  ; CREATE_NO_WINDOW
    DllCall("CloseHandle", "Ptr", writePipe)
    if !created {
        DllCall("CloseHandle", "Ptr", readPipe)
        throw OSError()
    }
    process := NumGet(processInfo, 0, "Ptr")
    DllCall("CloseHandle", "Ptr", NumGet(processInfo, 8, "Ptr"))

    ; Drain the pipe while waiting, so a full pipe buffer cannot stall the CLI.
    ; Collect raw bytes and decode once: a read can end inside a UTF-8 character.
    output := Buffer(0)
    chunk := Buffer(65536)
    deadline := A_TickCount + 5000
    loop {
        ; Sleep lets the window paint and take keystrokes while the CLI runs.
        Sleep(10)
        exited := DllCall("WaitForSingleObject", "Ptr", process, "UInt", 0) = 0
        while DllCall("PeekNamedPipe", "Ptr", readPipe, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt*", &available := 0, "Ptr", 0) && available {
            DllCall("ReadFile", "Ptr", readPipe, "Ptr", chunk, "UInt", Min(available, chunk.Size), "UInt*", &read := 0, "Ptr", 0)
            size := output.Size
            output.Size := size + read
            DllCall("RtlMoveMemory", "Ptr", output.Ptr + size, "Ptr", chunk, "UPtr", read)
        }
        if exited
            break
        if (A_TickCount > deadline) {
            DllCall("TerminateProcess", "Ptr", process, "UInt", 1)
            DllCall("CloseHandle", "Ptr", process)
            DllCall("CloseHandle", "Ptr", readPipe)
            throw Error("GlazeWM did not answer within 5 s")
        }
    }
    DllCall("GetExitCodeProcess", "Ptr", process, "UInt*", &exitCode := 0)
    DllCall("CloseHandle", "Ptr", process)
    DllCall("CloseHandle", "Ptr", readPipe)
    if exitCode
        throw Error("glazewm " args " exited with " exitCode)
    return StrGet(output, output.Size, "UTF-8")
}
