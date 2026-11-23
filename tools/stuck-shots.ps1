# Screenshots the game whenever the harness writes a new STUCK line (scripts\runner.lua stuck) as the last line of its mod data.
# Start it before launching the game: pwsh -File tools\stuck-shots.ps1 -Out <folder> [-File <save1.dat>]
# -File defaults to save slot 1's file under the default Steam path.
param(
	[Parameter(Mandatory)][string]$Out,
	[double]$Minutes = 30,
	[string]$File = 'C:\Program Files (x86)\Steam\steamapps\common\The Binding of Isaac Rebirth\data\isaac_test_framework\save1.dat'
)
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace W -Name U -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
'@
[void][W.U]::SetProcessDPIAware() # physical pixels, so the rect matches what CopyFromScreen grabs
New-Item -ItemType Directory -Force $Out | Out-Null

function Save-Shot([string]$name) {
	$p = Get-Process isaac-ng -ErrorAction SilentlyContinue | Where-Object MainWindowHandle -ne 0 | Select-Object -First 1
	$h = if ($p) { $p.MainWindowHandle } else { [W.U]::GetDesktopWindow() } # no game window: the desktop
	$r = New-Object W.U+RECT
	[void][W.U]::GetWindowRect($h, [ref]$r)
	$bmp = [System.Drawing.Bitmap]::new($r.R - $r.L, $r.B - $r.T)
	$g = [System.Drawing.Graphics]::FromImage($bmp)
	$g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
	$path = Join-Path $Out (($name -replace '[^A-Za-z0-9._-]+', '_') + '.png')
	$bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
	$g.Dispose(); $bmp.Dispose()
	"shot $path ($(if ($p) { 'isaac-ng' } else { 'desktop' }))"
}

$end, $last, $seenGame = (Get-Date).AddMinutes($Minutes), $null, $false
while ((Get-Date) -lt $end) {
	$running = [bool](Get-Process isaac-ng -ErrorAction SilentlyContinue)
	if ($running) { $seenGame = $true } elseif ($seenGame) { 'isaac-ng exited'; break }
	$line = try { ((Get-Content -Raw -LiteralPath $File -ErrorAction Stop) -split '\r?\n' | Where-Object { $_ })[-1] } catch { $null }
	if ($line -like 'STUCK*' -and $line -ne $last) { $last = $line; Save-Shot $line }
	Start-Sleep -Milliseconds 150
}
