extends SceneTree
## T1-01（2.1）：农田单击只打开详情；收粮/助耕/升级/研究为显式动作，各结算一次。
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

	# 空田：单击只开面板
	var food0: int = int(scene.game.snapshot().food)
	var prog0: int = int(scene.game.view().farm.progress)
	scene._on_slot_pressed("farm")
	await process_frame
	check(scene.detail_panel.visible, "空田单击打开详情")
	check(scene.selected_slot == "farm", "选中农田")
	check(int(scene.game.snapshot().food) == food0, "空田单击不加粮")
	check(int(scene.game.view().farm.progress) == prog0, "空田单击不助耕")
	check(scene.detail_harvest_button.disabled, "空田收粮禁用")
	check(not scene.detail_assist_button.disabled, "空田助耕可用")

	# 空田点收粮：不加粮
	scene.detail_harvest_button.pressed.emit()
	await process_frame
	check(int(scene.game.snapshot().food) == food0, "空田点收粮不加粮")

	# 助耕：+5%
	scene.detail_assist_button.pressed.emit()
	await process_frame
	check(int(scene.game.view().farm.progress) == prog0 + 500, "助耕+5%")

	# 推进一月 -> 成熟
	scene.game.act("advance_month")
	scene._refresh()
	await process_frame
	var pend: Dictionary = scene.game.snapshot().pending
	if not pend.is_empty():
		scene.game.act("reject_refugees", {"event_id": pend.id})
	scene._refresh()
	var food_before: int = int(scene.game.snapshot().food)
	var ready_before: int = int(scene.game.view().farm.ready_food)
	check(ready_before > 0, "一月后有成熟粮")

	# 成熟田：单击只开面板，不自动收
	scene._on_slot_pressed("farm")
	await process_frame
	check(scene.detail_panel.visible, "成熟田单击打开详情")
	check(int(scene.game.snapshot().food) == food_before, "成熟田单击不自动收")
	check(int(scene.game.view().farm.ready_food) == ready_before, "待收不变")
	check(not scene.detail_harvest_button.disabled, "成熟田收粮可用")

	# 收粮：只入库一次
	scene.detail_harvest_button.pressed.emit()
	await process_frame
	check(int(scene.game.snapshot().food) == food_before + ready_before, "收粮入库一次")
	check(int(scene.game.view().farm.ready_food) == 0, "收后待收清零")

	# 重复点收粮：不再加
	scene.detail_harvest_button.pressed.emit()
	await process_frame
	check(int(scene.game.snapshot().food) == food_before + ready_before, "重复点收粮不重复加")

	# 升级/研究入口存在
	check(scene.detail_upgrade_button != null and scene.detail_upgrade_button.visible, "升级按钮存在")

	print("TASK1-21 FARM DETAIL: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
