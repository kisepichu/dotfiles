#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

; Keeps Start closed after GlazeWM's Win chords. GlazeWM starts this from
; `startup_commands`. Windows opens Start when LWin goes up without another
; key in between, and GlazeWM swallows the other key of an lwin binding, so a
; quick Win+2 or Win+Space can open Start (glazewm#1215). Sending an unassigned
; key (vkE8) as LWin goes down marks every Win press as a chord. A bare Win
; press therefore no longer opens Start; Ctrl+Esc and the Start button still do.
;
; SendEvent, not Send: Send defaults to SendInput, which takes the keyboard
; hook down around each send and puts it back only if the hook thread
; answered within 500 ms. Under heavy load it answers late, AHK skips the
; restore, and the late removal leaves the script without a hook until it
; restarts, so Start opens again. SendEvent never touches the hook.

~LWin::SendEvent("{Blind}{vkE8}")

; Restore the normal Win key once GlazeWM is gone (exit, crash, or restart;
; a restart starts a fresh copy through #SingleInstance Force).
SetTimer(() => ProcessExist("glazewm.exe") || ExitApp(), 5000)
