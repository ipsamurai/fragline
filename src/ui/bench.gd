class_name Bench
extends Node
## Frame-time benchmark (web: ?bench=SECONDS&map=N&bots=N). Runs an all-bot match with the
## HUD on, records every frame interval, then publishes a summary as window.__bench (and prints it).

const WARMUP := 3.0

var duration := 20.0
var _t := 0.0
var _frames := PackedFloat32Array()
var _cpu := 0.0
var _phys := 0.0
var _draw_calls := 0.0
var _samples := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000


func _process(delta: float) -> void:
	_t += delta
	if _t < WARMUP:
		return
	if _t < WARMUP + duration:
		_frames.append(delta * 1000.0)
		_cpu += Performance.get_monitor(Performance.TIME_PROCESS)
		_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		_draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_samples += 1
	elif _samples > 0:
		_report()
		_samples = 0
		set_process(false)


func _report() -> void:
	var sorted := _frames.duplicate()
	sorted.sort()
	var n := sorted.size()
	var total := 0.0
	var slow := 0
	for ms in sorted:
		total += ms
		if ms > 20.0:
			slow += 1
	var low1 := 0.0                       # average of the slowest 1% of frames
	var k := maxi(1, n / 100)
	for i in k:
		low1 += sorted[n - 1 - i]
	low1 /= k
	var result := {
		"frames": n,
		"avg_fps": snappedf(1000.0 * n / total, 0.1),
		"low1_fps": snappedf(1000.0 / low1, 0.1),
		"p50_ms": snappedf(sorted[n / 2], 0.01),
		"p99_ms": snappedf(sorted[mini(n - 1, n * 99 / 100)], 0.01),
		"max_ms": snappedf(sorted[n - 1], 0.01),
		"slow_frames_pct": snappedf(100.0 * slow / n, 0.01),
		"process_ms": snappedf(1000.0 * _cpu / _samples, 0.01),
		"physics_ms": snappedf(1000.0 * _phys / _samples, 0.01),
		"draw_calls": snappedf(_draw_calls / _samples, 0.1),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"quality": Settings.quality,
	}
	var json := JSON.stringify(result)
	print("BENCH ", json)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__bench = %s;" % json, true)
	else:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--bench-shot="):
				get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--bench-shot="))
		if "--bench-quit" in OS.get_cmdline_user_args():
			get_tree().quit()
