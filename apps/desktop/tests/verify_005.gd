extends SceneTree
## 任务005 UI 验证：街景 7 位、农田点击、技能面板，并截取窗口视口。
var checks: int = 0
var failures: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	call_deferred("run")

func _shot(path: String) -> void:
	await process_frame
	var img = root.get_texture().get_image()
	if img and not img.is_empty():
		img.save_png(path)

func run() -> void:
	# 清掉旧窗口配置，确保从默认街景开始
	if FileAccess.file_exists("user://window-config.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://window-config.json"))
	DirAccess.make_dir_recursive_absolute("res://builds/verify")
	var packed = load("res://ui/main.tscn")
	var scene = packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	check(scene.slot_buttons.size() == 7, "街景有7个建筑位")
	check(scene.street_mode == true, "默认底部街景")
	check(scene.info_label.text.contains("粮仓") and scene.info_label.text.contains("待收"), "信息栏含粮仓与待收")
	check(scene.street_row.visible and not scene.normal_root.visible, "街景视图可见")

	# 农田点击：空田 +5% 进度
	scene._on_slot_pressed("farm")
	await process_frame
	check(int(scene.game.view().farm.progress) > 0, "点击空田加速生长")

	# 推进一月 → 1批待收（并产生流民事件）
	scene.game.act("advance_month")
	scene._refresh()
	check(int(scene.game.view().farm.ready_food) == 12, "一月后1批待收")

	# 点击农田收获
	scene._on_slot_pressed("farm")
	await process_frame
	check(int(scene.game.snapshot().food) == 32, "点击农田收获入库")
	scene._on_slot_pressed("farm")
	await process_frame
	check(int(scene.game.snapshot().food) == 32, "重复点击不重复加粮")

	# 处理流民事件后才可再次推进
	var pend: Dictionary = scene.game.snapshot().pending
	if not pend.is_empty():
		scene.game.act("reject_refugees", {"event_id": pend.id})
	scene.game.act("advance_month")
	scene._refresh()
	check(int(scene.game.view().farm.ready_food) == 12 and int(scene.game.snapshot().food) == 22, "粮仓与待收分开")

	await _shot("res://builds/verify/street_005.png")

	# 技能面板
	scene._open_skills()
	await process_frame
	check(scene.skill_panel.visible, "技能面板打开")
	await _shot("res://builds/verify/skills_005.png")
	scene.skill_panel.visible = false

	# 普通管理模式回退
	scene._toggle_street()
	await process_frame
	await process_frame
	check(scene.street_mode == false and scene.normal_root.visible, "展开普通管理视图")
	await _shot("res://builds/verify/normal_005.png")

	print("VERIFY 005 UI: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
