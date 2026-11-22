# Answers the harness's Exit & Continue requests with key presses into the game: on each new `WAIT exit-continue <n>` line in its mod
# data (scripts\runner.lua markWait) it sends -Keys to isaac-ng. Opt-in; watch its first run. Start it before launching the game:
#   pwsh -File isaac-test-harness\tools\auto-continue.ps1 [-File <save1.dat>] [-Keys <list>] [-Minutes 30] [-DryRun]
# -Keys: Escape, Return, Up, Down, or wait:<ms>. -DryRun prints the target window and the plan for each marker and sends nothing.
param(
	[string]$File = 'C:\Program Files (x86)\Steam\steamapps\common\The Binding of Isaac Rebirth\data\rehud_test_harness\save1.dat',
	# shortcut: the pause menu's path to Exit and the main menu's Continue position are unobserved; confirm with the user watching in the first session that runs the tool
	[string[]]$Keys = @('Escape', 'Down', 'Down', 'Return', 'wait:4000', 'Return'),
	[double]$Minutes = 30,
	[switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$SCAN = @{ Escape = 0x01; Return = 0x1C; Up = 0x48; Down = 0x50 }
$EXTENDED = @('Up', 'Down') # arrow keys are extended scan codes
$Keys = $Keys -split ',' | Where-Object { $_ } # pwsh -File passes `-Keys a,b` as one string
foreach ($k in $Keys) { if (-not $SCAN.ContainsKey($k) -and $k -notmatch '^wait:\d+$') { throw "unknown key '$k': use $($SCAN.Keys -join ', ') or wait:<ms>" } }

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

# The keys into isaac-ng's window, each event only while it is in front.
function Send-Plan {
	$p = Get-Process isaac-ng -ErrorAction SilentlyContinue | Where-Object MainWindowHandle -ne 0 | Select-Object -First 1
	if ($DryRun) {
		"target: $(if ($p) { "isaac-ng window $($p.MainWindowHandle)" } else { 'no isaac-ng window' })"
		"plan: $($Keys -join ', ')"
		return
	}
	if (-not $p) { 'not sent: no isaac-ng window'; return }
	$h = $p.MainWindowHandle
	# shortcut: Windows may refuse SetForegroundWindow from a background process; then the sequence is skipped, not forced
	[void][W.K]::SetForegroundWindow($h)
	foreach ($k in $Keys) {
		if ($k -match '^wait:(\d+)$') { Start-Sleep -Milliseconds ([int]$Matches[1]); "sent $k"; continue }
		foreach ($up in $false, $true) {
			if ([W.K]::GetForegroundWindow() -ne $h) { 'not sent: isaac-ng not in front'; return }
			Send-Key $k $up
			Start-Sleep -Milliseconds $(if ($up) { 250 } else { 80 }) # held for a few frames, then a gap the menu can follow
		}
		"sent $k"
	}
}

$end, $last = (Get-Date).AddMinutes($Minutes), $null
while ((Get-Date) -lt $end) {
	$lines = try { (Get-Content -Raw -LiteralPath $File -ErrorAction Stop) -split '\r?\n' } catch { @() }
	$marker = $lines | Where-Object { $_ -match '^WAIT exit-continue \d+$' } | Select-Object -First 1
	if (-not $marker) { $last = $null } # cleared after the Continue; a relaunch's marker 1 then acts again
	elseif ($marker -ne $last) { $last = $marker; "act on $marker"; Send-Plan }
	Start-Sleep -Milliseconds 150
}
