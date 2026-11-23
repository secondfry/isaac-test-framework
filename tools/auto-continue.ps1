# Answers the harness's exit requests with key presses into the game: on each new `WAIT exit-continue <n>` line in its mod data
# (scripts\runner.lua markWait) it sends -Keys to isaac-ng, and on the `WAIT exit-menu <n>` line written at HARNESS DONE -ExitKeys.
# Opt-in; watch its first run. Start it before launching the game:
#   pwsh -File tools\auto-continue.ps1 [-File <save1.dat>] [-Keys <list>] [-ExitKeys <list>] [-Minutes 30] [-DryRun]
# -File defaults to save slot 1's file under the default Steam path.
# -Keys, -ExitKeys: Escape, Return, Up, Down, or wait:<ms> (a leading wait is skipped). -DryRun prints the target window and the plan for each marker and sends nothing.
param(
	[string]$File = 'C:\Program Files (x86)\Steam\steamapps\common\The Binding of Isaac Rebirth\data\isaac_test_framework\save1.dat',
	# Esc opens the pause menu, Up reaches Exit, Enter exits; Enter on the main menu picks Continue (session 4b); the 1.5 s menu load is the user's setting, unconfirmed
	[string[]]$Keys = @('Escape', 'Up', 'Return', 'wait:1500', 'Return'),
	# the exit to the menu alone, at HARNESS DONE: exiting flushes log.txt
	[string[]]$ExitKeys = @('Escape', 'Up', 'Return'),
	[double]$Minutes = 30,
	[switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$SCAN = @{ Escape = 0x01; Return = 0x1C; Up = 0x48; Down = 0x50 }
$EXTENDED = @('Up', 'Down') # arrow keys are extended scan codes
$Keys, $ExitKeys = ($Keys, $ExitKeys) | ForEach-Object {
	$list = @($_ -split ',' | Where-Object { $_ }) # pwsh -File passes `-Keys a,b` as one string
	foreach ($k in $list) { if (-not $SCAN.ContainsKey($k) -and $k -notmatch '^wait:\d+$') { throw "unknown key '$k': use $($SCAN.Keys -join ', ') or wait:<ms>" } }
	, $list
}

Add-Type -Namespace W -Name K -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
[StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }
[StructLayout(LayoutKind.Explicit)] public struct UNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
[StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public UNION u; }
[DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
'@

# One key event by scan code (KEYEVENTF_SCANCODE 8, KEYUP 2, EXTENDEDKEY 1): games read scan codes, not virtual keys.
function Send-Key([string]$name, [bool]$up) {
	# built inside out: the structs are value types, so a nested field set in place ($i.u.ki.wScan = ...) is lost
	$ki = New-Object W.K+KEYBDINPUT
	$ki.wScan = $SCAN[$name]
	$ki.dwFlags = 8 -bor ($(if ($up) { 2 } else { 0 })) -bor ($(if ($EXTENDED -contains $name) { 1 } else { 0 }))
	$u = New-Object W.K+UNION
	$u.ki = $ki
	$i = New-Object W.K+INPUT
	$i.type = 1 # INPUT_KEYBOARD
	$i.u = $u
	if ([W.K]::SendInput(1, @($i), [System.Runtime.InteropServices.Marshal]::SizeOf([type][W.K+INPUT])) -ne 1) { throw "SendInput failed for $name" }
}

# The keys for $marker into isaac-ng's window (-Raise: bring it to the front first), each event only while it is in front: 'retry' if none was sent, else 'done'.
function Send-Plan([string]$marker, [switch]$Raise) {
	$menu = $marker -match '^WAIT exit-menu '
	$plan, $what = $(if ($menu) { $ExitKeys, 'the exit to the menu' } else { $Keys, 'the Exit & Continue' })
	$p = Get-Process isaac-ng -ErrorAction SilentlyContinue | Where-Object MainWindowHandle -ne 0 | Select-Object -First 1
	if ($DryRun) {
		Write-Host "target: $(if ($p) { "isaac-ng window $($p.MainWindowHandle)" } else { 'no isaac-ng window' })"
		Write-Host "plan: $($plan -join ', ')"
		return 'done'
	}
	if (-not $p) { Write-Host 'not sent: no isaac-ng window'; return 'done' }
	$h, $sent = $p.MainWindowHandle, 0
	# shortcut: Windows may refuse SetForegroundWindow from a background process; then it waits for the game in front and sends then, never forced
	if ($Raise) { [void][W.K]::SetForegroundWindow($h) }
	foreach ($k in $plan) {
		if ($k -match '^wait:(\d+)$') {
			if ($sent -eq 0) { continue } # a leading wait would repeat on every retry poll
			Start-Sleep -Milliseconds ([int]$Matches[1]); Write-Host "sent $k"; continue
		}
		foreach ($up in $false, $true) {
			if ([W.K]::GetForegroundWindow() -ne $h) {
				if ($sent -eq 0) { return 'retry' }
				# shortcut: whether isaac-ng sees a key-up sent while it is not in front is unobserved; confirm in the watched first run
				if ($up) { Send-Key $k $true } # never leave the key held down
				Write-Host "PARTIAL: finish $what by hand"
				return 'done'
			}
			if ($sent -eq 0 -and (Read-Marker) -ne $marker) { Write-Host "not sent: $marker changed before the first key"; return 'done' }
			Send-Key $k $up
			$sent++
			Start-Sleep -Milliseconds $(if ($up) { 250 } else { 80 }) # held, then a gap; whether the menu takes 80/250 ms is unobserved, confirm in the watched first run
		}
		Write-Host "sent $k"
	}
	return 'done'
}

function Read-Marker {
	$lines = try { (Get-Content -Raw -LiteralPath $File -ErrorAction Stop) -split '\r?\n' } catch { @() }
	$lines | Where-Object { $_ -match '^WAIT exit-(continue|menu) \d+$' } | Select-Object -First 1
}

# A marker already there at start is the last session's: the harness drops it at HARNESS START.
$end, $last, $acting = (Get-Date).AddMinutes($Minutes), (Read-Marker), $null
while ((Get-Date) -lt $end) {
	$marker = Read-Marker
	if (-not $marker) { $last = $acting = $null } # the harness cleared it (Continue, step given up, HARNESS START): the next marker acts, whatever its number
	elseif ($marker -ne $last) {
		$first = $marker -ne $acting # its first poll: announce, raise the window, and on a retry say so once
		if ($first) { Write-Host "act on $marker"; $acting = $marker }
		if ((Send-Plan $marker -Raise:$first) -ne 'retry') { $last = $marker }
		elseif ($first) { Write-Host 'waiting for isaac-ng in front: bring it to the front, press no keys' }
	}
	Start-Sleep -Milliseconds 150
}
