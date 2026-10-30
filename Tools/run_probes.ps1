# Runs every headless probe and fails if any probe exits non-zero OR prints a
# SCRIPT ERROR (a script error only aborts the current function, so a probe
# can crash mid-check and still exit 0 — layout_probe did for weeks).
#
#   pwsh Tools/run_probes.ps1
#   pwsh Tools/run_probes.ps1 -Godot "C:\path\to\godot.exe"

param(
	[string]$Godot = "D:\Apps\godot\Godot_v4.7.1-stable_win64.exe"
)

$probes = @(
	"nav_bake_probe", "nav_astar_probe", "nav_executor_probe",
	"hazard_damage_probe", "decision_probe", "pickup_cooldown_probe",
	"layout_probe", "touch_stick_probe", "auto_attack_probe",
	"touch_layout_editor_probe", "death_free_probe", "audit_regression_probe",
	"menu_probe", "swap_preview_probe", "hit_feel_probe"
)

$root = Split-Path -Parent $PSScriptRoot
$failed = @()
foreach ($p in $probes) {
	$out = & $Godot --headless --path $root -s "Tools/$p.gd" 2>&1 | Out-String
	$code = $LASTEXITCODE
	$scriptErrors = ([regex]::Matches($out, "SCRIPT ERROR")).Count
	if ($code -ne 0 -or $scriptErrors -gt 0) {
		$failed += $p
		Write-Host "FAIL  $p (exit=$code, script errors=$scriptErrors)" -ForegroundColor Red
		$out -split "`n" | Select-String -Pattern "FAIL|SCRIPT ERROR" | Select-Object -First 10 | ForEach-Object { Write-Host "      $_" }
	} else {
		Write-Host "pass  $p" -ForegroundColor Green
	}
}

if ($failed.Count -gt 0) {
	Write-Host "`n$($failed.Count) probe(s) failed: $($failed -join ', ')" -ForegroundColor Red
	exit 1
}
Write-Host "`nAll $($probes.Count) probes passed."
exit 0
