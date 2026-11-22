# A vanilla session: every mod but the harness disabled for it, then exactly the previous state back. Run with the game closed.
#   pwsh -File isaac-test-harness\tools\vanilla-session.ps1 -Start   before launching the game
#   pwsh -File isaac-test-harness\tools\vanilla-session.ps1 -End     after the session (also after an interrupted -Start or -End)
# -Start writes disable.it only into folders without one, recording each path in the state file before writing it, so an interrupted
# -Start leaves nothing unrecorded; -End deletes only the recorded files, then the state file. Both are safe to run twice.
param(
	[switch]$Start,
	[switch]$End,
	[string]$Mods = 'C:\Program Files (x86)\Steam\steamapps\common\The Binding of Isaac Rebirth\mods',
	[string]$Keep = 'rehud_test_harness',
	[string]$State = (Join-Path $PSScriptRoot '..\.vanilla-session.txt')
)
$ErrorActionPreference = 'Stop'
if ($Start -eq $End) { throw 'pass -Start or -End' }
# any -Mods (the tests' temp folder) skips the check: the game reads only its own mods folder
if (-not $PSBoundParameters.ContainsKey('Mods') -and (Get-Process isaac-ng -ErrorAction SilentlyContinue)) { throw 'close the game first: it reads the mods folder only at launch' }

if ($End) {
	if (-not (Test-Path -LiteralPath $State)) { 'no vanilla session to end'; return }
	foreach ($file in Get-Content -LiteralPath $State) {
		if ($file -and (Test-Path -LiteralPath $file)) { Remove-Item -LiteralPath $file; "enabled $(Split-Path -Leaf (Split-Path -Parent $file))" }
	}
	Remove-Item -LiteralPath $State
	return
}

$harness = Join-Path $Mods $Keep
if (-not (Test-Path -LiteralPath $harness)) { throw "no harness folder $harness" }
if (Test-Path -LiteralPath (Join-Path $harness 'disable.it')) { Write-Warning "the harness is disabled: delete $harness\disable.it to run it" }
foreach ($dir in Get-ChildItem -LiteralPath $Mods -Directory) {
	$file = Join-Path $dir.FullName 'disable.it'
	if ($dir.Name -eq $Keep -or (Test-Path -LiteralPath $file)) { continue }
	Add-Content -LiteralPath $State -Value $file
	[System.IO.File]::Create($file).Dispose() # empty, as the game writes it; New-Item would read brackets in a folder name as wildcards
	"disabled $($dir.Name)"
}
