extends SceneTree
## 004B 窗口体验验证：小窗切换、置顶、关闭保存、窗口配置。真实窗口模式下运行。
var failures: int = 0
var checks: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# 清掉旧窗口配置，保证从默认开始
	if FileAccess.file_exists("user://window-config.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://window-config.json"))
	var packed = load("res://ui/main.tscn")
	var scene = packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var win: Window = scene.get_window()
	check(scene.compact == false, "初始为普通模式")
	check(scene.close_dialog != null, "关闭对话框已创建")
	check(scene.close_dialog.get_ok_button().text == "保存并退出", "关闭对话框按钮：保存并退出")
	check(scene.compact_toggle.text == "小窗", "工具栏有『小窗』按钮")
	check(win.always_on_top == false, "置顶默认关闭")

	DirAccess.make_dir_recursive_absolute("res://builds/verify")
	await process_frame
	var img = root.get_texture().get_image()
	if img and not img.is_empty():
		img.save_png("res://builds/verify/normal.png")
	var normal_size: Vector2i = win.size

	scene._toggle_compact()
	await process_frame
	await process_frame
	check(scene.compact == true, "进入小窗模式")
	check(scene.compact_root.visible and not scene.normal_root.visible, "小窗视图可见、普通视图隐藏")
	check(win.size.y <= 320 and win.size.y >= 180, "小窗高度约260（实际 %d）" % win.size.y)
	await process_frame
	var img2 = root.get_texture().get_image()
	if img2 and not img2.is_empty():
		img2.save_png("res://builds/verify/compact.png")

	scene._toggle_compact()
	await process_frame
	await process_frame
	check(scene.compact == false, "退出小窗恢复普通")
	check(win.size.x == normal_size.x and win.size.y == normal_size.y, "恢复普通尺寸")

	scene._on_pin_toggled(true)
	check(win.always_on_top == true, "置顶开启")
	scene._on_pin_toggled(false)
	check(win.always_on_top == false, "置顶关闭")

	var save_result: Dictionary = scene.saves.save_game(scene.game)
	check(save_result.get("ok", false), "存档可用（关闭时保存路径）")
	check(FileAccess.file_exists("user://window-config.json"), "窗口配置已写入")

	print("VERIFY 004B: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
