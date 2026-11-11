extends SceneTree
## 任务005 UI 验证：街景 7 位、农田点击、技能面板，并截取窗口视口。
var checks: int = 0
var failures: int = 0
var config_path := "user://verify-005-" + str(Time.get_ticks_usec()) + ".json"

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	call_deferred("run")

func _shot(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	var img = root.get_texture().get_image()
	if img and not img.is_empty():
		img.save_png(path)

func run() -> void:
	# 使用专属路径，不删除玩家配置。截图只在图形环境获取。
	DirAccess.make_dir_recursive_absolute("user://verification")
	var packed = load("res://ui/main.tscn")
	var scene = packed.instantiate()
	scene.window_config_path = config_path
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

	await _shot("user://verification/street_005.png")

	# 技能面板
	scene._open_skills()
	await process_frame
	await process_frame
	check(scene.skill_panel.visible, "技能面板打开")
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(scene.skill_panel.get_global_rect()), "技能面板完全在窗口内")
	check(scene.skill_panel.get_global_rect().end.y <= scene.street_row.get_global_rect().position.y, "研究面板向上展开，不盖住街景")
	scene._act("improve_agriculture")
	var root_button: Button = skill_button(scene, "farm_tools")
	check(not root_button.disabled, "基础技能可点")
	root_button.pressed.emit()
	await process_frame
	check(scene.game.view().skills.farm.nodes[0].unlocked and skill_button(scene, "farm_tools").disabled, "解锁后即时显示已解锁")
	check(not skill_button(scene, "farm_irrigation").disabled, "前置解锁后分支按钮即时启用")
	skill_button(scene, "farm_irrigation").pressed.emit()
	await process_frame
	check(scene.game.view().skills.farm.available == 0 and skill_button(scene, "farm_rotation").disabled, "点数耗尽后分支即时禁用")
	check(scene.economy.text.contains("20%"), "灌溉技能更新旱季减产预览")
	await _shot("user://verification/skills_005.png")
	scene._close_panels()
	await process_frame
	await process_frame
	check(root.size.y == scene.STREET_HEIGHT, "关闭面板恢复街景高度")

	scene._open_detail("housing")
	await process_frame
	await process_frame
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(scene.detail_panel.get_global_rect()), "详情面板完全在窗口内")
	scene.detail_actions.get_child(0).pressed.emit()
	check(scene.detail_label.text.contains("民居 2 级"), "扩建后详情即时刷新")
	scene._close_panels()
	scene._on_slot_pressed("reserved_4")
	check(scene.street_notice.is_visible_in_tree() and scene.street_notice.text.contains("预留地块"), "街景可见操作反馈")
	scene._act("restart")
	for month in range(3):
		scene._act("advance_month")
		if not scene.game.snapshot().pending.is_empty():
			scene._act("reject_refugees", {"event_id": scene.game.snapshot().pending.id})
	check(scene.street_notice.text.contains("口粮警报") and scene.street_notice.text.contains("36粮"), "粮仓不足时提醒收获田里粮食")

	# 普通管理模式回退
	scene._toggle_street()
	await process_frame
	await process_frame
	check(scene.street_mode == false and scene.normal_root.visible, "展开普通管理视图")
	check(scene.harvest_button.is_visible_in_tree() and not scene.harvest_button.disabled, "普通管理也可收粮")
	scene.harvest_button.pressed.emit()
	check(scene.game.snapshot().food == 36 and scene.harvest_button.disabled, "普通管理收获一次后按钮禁用")
	scene._act("restart")
	scene.troops.value = 6
	check(scene.expedition_label.text.contains("6粮+6木"), "六人远征展示六人费用")
	scene.troops.value = 3
	check(scene.expedition_label.text.contains("3粮+3木"), "改人数即时更新费用")
	await _shot("user://verification/normal_005.png")

	print("VERIFY 005 UI: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	await process_frame
	if FileAccess.file_exists(config_path): DirAccess.remove_absolute(config_path)
	quit(1 if failures > 0 else 0)

func skill_button(scene, id: String) -> Button:
	for row in scene.skill_content.get_children():
		for child in row.get_children():
			if child is Button and child.get_meta("skill_id", "") == id:
				return child
	return null
