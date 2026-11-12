extends SceneTree
## 场景信号/几何/控件稳定性验证，不冒充真实鼠标和Windows DPI测试。
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var scene = load("res://ui/main.tscn").instantiate()
	scene.window_config_path = "user://street-workflow-" + str(Time.get_ticks_usec()) + ".json"
	root.add_child(scene)
	await process_frame
	await process_frame
	check(not scene.street_events.visible, "no event controls before visitors arrive")
	scene.street_next_button.pressed.emit()
	await process_frame
	check(scene.street_events.is_visible_in_tree() and scene.street_mode, "arrival can be handled in street mode")
	check(scene.street_notice.text.contains("月口粮14") and scene.street_notice.text.contains("木材8"), "street shows intake costs and benefits")
	check(not scene.street_accept_button.disabled and scene.street_next_button.disabled, "decision controls reflect paused state")
	scene.street_accept_button.pressed.emit()
	check(scene.game.snapshot().population == 14 and not scene.street_events.visible, "accept in street without expanding management")
	scene.street_accept_button.pressed.emit()
	check(scene.game.snapshot().population == 14, "repeated event signal does not add population twice")
	scene._act("restart")
	scene._open_detail("farm")
	var upgrade = scene.detail_upgrade_button
	check(scene.detail_label.text.contains("农田 1 级") and not upgrade.disabled, "farm detail exposes upgrade")
	upgrade.pressed.emit()
	check(scene.game.snapshot().agriculture == 2 and scene.game.snapshot().wood == 2, "farm detail upgrades exactly once")
	check(scene.detail_label.text.contains("农田 2 级") and scene.detail_upgrade_button == upgrade and upgrade.disabled, "detail updates without replacing its controls")
	scene._open_skills()
	await process_frame
	var root_button: Button = scene.skill_rows.farm_tools.button
	root_button.grab_focus()
	var ids := {}
	for i in range(20):
		scene._refresh()
		ids[scene.skill_rows.farm_tools.button.get_instance_id()] = true
	check(ids.size() == 1 and scene.skill_rows.size() == 9, "refresh reuses all skill widgets")
	check(root.gui_get_focus_owner() == root_button, "resource refresh preserves in-game keyboard focus")
	root_button.pressed.emit()
	check(scene.game.view().skills.farm.spent == 1 and not scene.skill_rows.farm_irrigation.button.disabled, "stable button fires once and enables branch")
	scene.skill_rows.farm_irrigation.button.pressed.emit()
	check(scene.game.view().skills.farm.spent == 2 and scene.skill_rows.farm_rotation.button.disabled, "points and disabled states remain current")
	scene._close_panels()
	scene._act("restart")
	for i in range(4): scene._on_slot_pressed("farm")
	check(scene.slot_buttons[1].tooltip_text.contains("额度已用完"), "click quota exhaustion explained")
	check(scene.game.view().farm.progress == 2000, "clicking remains bounded by shared cap")
	scene.street_next_button.pressed.emit()
	check(scene.slot_buttons[1].tooltip_text.contains("收取12粮"), "harvest affordance takes priority during event pause")
	scene._on_slot_pressed("farm")
	check(scene.slot_buttons[1].tooltip_text.contains("已暂停"), "empty paused field explains why assist unavailable")
	scene.street_reject_button.pressed.emit()
	check(scene.game.snapshot().population == 10 and not scene.street_events.visible, "reject directly from street")

	# 代表性缺粮+流民状态，在小窗720宽与960宽分别检查实际可见控件边界。
	var fixture: Dictionary = scene.game.snapshot()
	fixture.food = 0
	fixture.pending = scene.game.refugee_at(fixture.months)
	check(scene.game.import_snapshot(fixture), "scarcity plus pending visitor fixture")
	scene._refresh()
	for width in [720, 960]:
		root.size = Vector2i(width, scene.STREET_HEIGHT)
		await process_frame
		await process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(root.size))
		check(bounds.encloses(scene.street_notice.get_global_rect()), "scarcity message within %d-wide street" % width)
		check(bounds.encloses(scene.street_accept_button.get_global_rect()) and bounds.encloses(scene.street_row.get_global_rect()), "buildings and decision controls within %d-wide street" % width)
	check(scene.street_notice.text.contains("口粮警报") and scene.street_notice.text.contains("接纳后"), "risk and decision preview both visible")
	print("STREET WORKFLOW TESTS: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
