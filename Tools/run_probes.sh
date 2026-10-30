#!/usr/bin/env bash
# Runs every headless probe and fails if any probe exits non-zero OR prints a
# SCRIPT ERROR (a script error only aborts the current function, so a probe
# can crash mid-check and still exit 0). Same contract as run_probes.ps1.
#
#   Tools/run_probes.sh
#   GODOT=/path/to/godot Tools/run_probes.sh
#   Tools/run_probes.sh nav_bake_probe menu_probe   # run a subset
#   PROBE_RETRIES=1 Tools/run_probes.sh             # rerun a failed probe once
#
# A probe that fails and then passes on a retry is reported as FLAKY, not
# hidden: the live-physics AI probes are not fully deterministic.

set -u

GODOT="${GODOT:-godot}"
RETRIES="${PROBE_RETRIES:-0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$#" -gt 0 ]; then
	probes=("$@")
else
	probes=(
		nav_bake_probe nav_astar_probe nav_executor_probe
		hazard_damage_probe decision_probe pickup_cooldown_probe
		layout_probe touch_stick_probe auto_attack_probe
		touch_layout_editor_probe death_free_probe audit_regression_probe
		menu_probe swap_preview_probe melee_swing_probe
	)
fi

run_one() {
	out="$("$GODOT" --headless --path "$ROOT" -s "Tools/$1.gd" 2>&1)"
	code=$?
	script_errors="$(printf '%s\n' "$out" | grep -c "SCRIPT ERROR")"
	[ "$code" -eq 0 ] && [ "$script_errors" -eq 0 ]
}

failed=()
flaky=()
for p in "${probes[@]}"; do
	if run_one "$p"; then
		echo "pass  $p"
		continue
	fi
	first_out="$out"
	first_code=$code
	first_errors=$script_errors
	passed_on_retry=false
	for ((r = 1; r <= RETRIES; r++)); do
		if run_one "$p"; then
			passed_on_retry=true
			break
		fi
	done
	if $passed_on_retry; then
		flaky+=("$p")
		echo "FLAKY $p (failed once, passed on retry)"
	else
		failed+=("$p")
		echo "FAIL  $p (exit=$first_code, script errors=$first_errors)"
	fi
	printf '%s\n' "$first_out" | grep -E "FAIL|SCRIPT ERROR" | head -n 10 | sed 's/^/      /'
done

if [ "${#flaky[@]}" -gt 0 ]; then
	echo
	echo "${#flaky[@]} flaky probe(s): ${flaky[*]}"
	if [ -n "${GITHUB_ACTIONS:-}" ]; then
		echo "::warning title=Flaky probes::${flaky[*]} failed once and passed on retry"
	fi
fi

if [ "${#failed[@]}" -gt 0 ]; then
	echo
	echo "${#failed[@]} probe(s) failed: ${failed[*]}"
	exit 1
fi
echo
echo "All ${#probes[@]} probes passed."
