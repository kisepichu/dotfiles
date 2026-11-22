# Turn the displays off and keep them off until a key or mouse input from a
# real device.
#
# GlazeWM sends a synthetic mouse input (SendInput) every time it sets focus,
# and it sets focus whenever any window opens or closes. Windows counts that
# input as activity, so a window opening or closing while the displays are off
# wakes them. Raw input tells the two apart: input from a device carries its
# device handle, injected input does not. When the displays come back on
# without device input, this script turns them off again.
#
# Source: dot_glzr/glazewm/display-off.ps1 in the dotfiles repository. From
# WSL, `chezmoi apply` runs run_onchange_after_36-install-windows-glazewm-config.sh,
# which copies this file to %USERPROFILE%\.glzr\glazewm\ and points the Desktop
# shortcut "display off" at it. Edit the repository copy, not the installed one.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -ReferencedAssemblies System.Windows.Forms @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class DisplayOff : Form {
    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTDEVICE { public ushort UsagePage; public ushort Usage; public uint Flags; public IntPtr Target; }
    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTHEADER { public uint Type; public uint Size; public IntPtr Device; public IntPtr WParam; }
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    struct POWERBROADCAST_SETTING { public Guid PowerSetting; public uint DataLength; public uint Data; }

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] devices, uint count, uint size);
    [DllImport("user32.dll")]
    static extern uint GetRawInputData(IntPtr rawInput, uint command, out RAWINPUTHEADER data, ref uint size, uint headerSize);
    [DllImport("user32.dll", SetLastError = true)]
    static extern IntPtr RegisterPowerSettingNotification(IntPtr recipient, ref Guid setting, uint flags);

    const int WM_INPUT = 0x00FF;
    const int WM_POWERBROADCAST = 0x0218;
    const int PBT_POWERSETTINGCHANGE = 0x8013;
    const uint RID_HEADER = 0x10000005;
    const uint RIDEV_INPUTSINK = 0x100;
    static Guid ConsoleDisplayState = new Guid("6FE69556-704A-47A0-8F24-C28D936FDA47");

    readonly Timer reoff = new Timer();
    readonly Queue<DateTime> wakes = new Queue<DateTime>();

    public void Run() {
        // Mouse (generic desktop page 1, usage 2) and keyboard (usage 6),
        // delivered here even though this window is never in the foreground.
        // Without them a real input could not end the script, so fail
        // before turning anything off.
        var devices = new RAWINPUTDEVICE[2];
        devices[0].UsagePage = 1; devices[0].Usage = 2; devices[0].Flags = RIDEV_INPUTSINK; devices[0].Target = Handle;
        devices[1].UsagePage = 1; devices[1].Usage = 6; devices[1].Flags = RIDEV_INPUTSINK; devices[1].Target = Handle;
        if (!RegisterRawInputDevices(devices, 2, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE)))) throw new Win32Exception();
        if (RegisterPowerSettingNotification(Handle, ref ConsoleDisplayState, 0) == IntPtr.Zero) throw new Win32Exception();
        // A device input arriving with the wake gets this long to end the
        // script before the displays go off again.
        reoff.Interval = 250;
        reoff.Tick += delegate { reoff.Stop(); TurnOff(); };
        TurnOff();
        Application.Run();
    }

    void TurnOff() {
        // WM_SYSCOMMAND, SC_MONITORPOWER, 2 = off
        var message = Message.Create(Handle, 0x0112, (IntPtr)0xF170, (IntPtr)2);
        DefWndProc(ref message);
    }

    void DisplayStateChanged(uint state) {
        if (state == 0) { reoff.Stop(); return; }
        // Safety valve: if the displays keep coming back on, someone is
        // trying to use the PC and their input is not being recognised.
        var now = DateTime.UtcNow;
        wakes.Enqueue(now);
        while (now - wakes.Peek() > TimeSpan.FromSeconds(10)) wakes.Dequeue();
        if (wakes.Count >= 5) { Application.ExitThread(); return; }
        reoff.Stop();
        reoff.Start();
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_INPUT) {
            RAWINPUTHEADER header;
            uint size = (uint)Marshal.SizeOf(typeof(RAWINPUTHEADER));
            if (GetRawInputData(m.LParam, RID_HEADER, out header, ref size, size) != uint.MaxValue && header.Device != IntPtr.Zero) {
                Application.ExitThread();
            }
        } else if (m.Msg == WM_POWERBROADCAST && m.WParam.ToInt64() == PBT_POWERSETTINGCHANGE) {
            var setting = (POWERBROADCAST_SETTING)Marshal.PtrToStructure(m.LParam, typeof(POWERBROADCAST_SETTING));
            if (setting.PowerSetting == ConsoleDisplayState) DisplayStateChanged(setting.Data);
        }
        base.WndProc(ref m);
    }
}
'@
# Let the click or key press that started this script finish first.
Start-Sleep -Seconds 2
(New-Object DisplayOff).Run()
