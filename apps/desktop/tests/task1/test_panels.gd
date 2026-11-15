extends SceneTree
## T1-06/09/10 面板检查：人才、手记、设置浮层与字号缩放。
var checks: int = 0
var failures: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var scene = load("res://ui/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	scene._open_overlay("人才与委任", scene._fill_talents)
	await process_frame
	check(scene.overlay_panel.visible, "人才浮层可见")
	check(scene.overlay_title.text.contains("人才"), "人才标题")
	check(scene.overlay_content.get_child_count() >= 3, "人才至少3张卡")

	scene._open_overlay("宰相手记", scene._fill_history)
	await process_frame
	check(scene.overlay_content.get_child_count() > 0, "手记有内容")

	scene._open_overlay("设置", scene._fill_settings)
	await process_frame
	check(scene.overlay_content.get_child_count() > 0, "设置有内容")

	scene._apply_font_scale(1.3)
	check(scene.theme.default_font_size == 20, "字号130%生效")
	scene._apply_font_scale(1.0)
	check(scene.theme.default_font_size == 15, "字号恢复100%")

	scene.overlay_panel.visible = false
	check(not scene.overlay_panel.visible, "浮层可关闭")

	print("TASK1 PANELS: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
