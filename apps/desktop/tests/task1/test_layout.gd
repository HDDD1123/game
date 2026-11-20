extends SceneTree
## T1-02 布局检查：720/960/全宽三种宽度下关键控件在窗口内，并截图。
var checks: int = 0
var failures: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute("user://verification")
	var scene = load("res://ui/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.street_mode = true
	scene._sync_views()
	for width in [720, 960, 2536]:
		root.size = Vector2i(width, 280)
		await process_frame
		await process_frame
		scene._refresh()
		await process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(root.size))
		check(bounds.encloses(scene.info_label.get_global_rect()), "info bar within %d" % width)
		check(bounds.encloses(scene.street_row.get_global_rect()), "seven slots within %d" % width)
		check(bounds.encloses(scene.street_notice.get_global_rect()), "notice within %d" % width)
		check(scene.slot_buttons.size() == 7, "7 slots at %d" % width)
		if width < 900:
			check(not scene.info_secondary.visible, "secondary info hidden at %d" % width)
		else:
			check(scene.info_secondary.visible, "secondary info visible at %d" % width)
		await process_frame
		if DisplayServer.get_name() == "headless":
			continue
		var img = root.get_texture().get_image()
		if img and not img.is_empty():
			img.save_png("user://verification/layout_%d.png" % width)
	print("TASK1 LAYOUT: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
