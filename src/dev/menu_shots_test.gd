extends Node
## Dev tool (excluded from exports): screenshots of the menu screens. Needs a real window:
##   godot --path . --rendering-driver opengl3 --resolution 1600x900 -- --test=menu_shots [--out=<dir>]
## Saves menu_<screen>_<width>.png. Restores your settings file after.

var out_dir := "C:/Users/Soumya/AppData/Local/Temp/claude/C--Users-Soumya-Desktop-HACKOINVERSE/4b7ea364-2f11-4ca6-907e-8768f0ed2a2b/scratchpad"
var _backup := ""


func _ready() -> void:
	Sfx.muted = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	if FileAccess.file_exists(Settings.PATH):
		_backup = FileAccess.get_file_as_string(Settings.PATH)
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/menu_%s_%d.png" % [out_dir, name, img.get_width()]
	img.save_png(path)
	print("saved ", path)


func _run() -> void:
	var main := get_parent()
	main.show_menu()
	var menu: Menu = main.menu
	await _wait(1.6)
	await _shot("main")
	# Hover the second entry to show the hover state.
	var b: Control = menu._screen.find_child("Armory", true, false)
	if b:
		b.grab_focus()
	await _wait(3.5)
	await _shot("main_b")
	menu.show_armory(5)
	await _wait(0.8)
	await _shot("armory")
	menu.show_customize()
	await _wait(0.6)
	await _shot("customize")
	menu.show_credits()
	await _wait(0.6)
	await _shot("credits")
	menu.show_settings()
	await _wait(0.6)
	await _shot("settings")
	if _backup != "":
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	print("DONE fails=0")
	get_tree().quit()
