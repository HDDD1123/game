extends Control
## 桌面王国 v0.4：底部街景 + 农田手动收获 + 建筑技能树。
## 规则全部在 core/；本脚本只负责窗口、面板与按钮接线。
const Kingdom = preload("res://core/kingdom.gd")
const SaveStore = preload("res://core/save_store.gd")

const WINDOW_CONFIG := "user://window-config.json"
const NORMAL_MIN := Vector2i(640, 420)
const NORMAL_DEFAULT := Vector2i(1000, 640)
const STREET_HEIGHT := 280

var game = Kingdom.new()
var saves = SaveStore.new()
# 验证脚本可注入临时配置路径，不覆盖玩家的窗口偏好。
var window_config_path := WINDOW_CONFIG
var normal_size := NORMAL_DEFAULT
var panel_restore_rect := Rect2i()
var content_margin: MarginContainer

# 普通管理视图（004B 起保留）
var stats: Label
var economy: Label
var message: Label
var event_label: Label
var next_button: Button
var accept_button: Button
var reject_button: Button
var housing_button: Button
var farm_button: Button
var forge_button: Button
var dispatch_button: Button
var troops: SpinBox
var site: OptionButton
var mode: OptionButton
var expedition_label: Label
var details: RichTextLabel
var displayed_event_id: String = ""

# 街景
var normal_root: VBoxContainer
var street_root: VBoxContainer
var info_label: Label
var street_notice: Label
var street_next_button: Button
var harvest_button: Button
var street_row: HBoxContainer
var slot_buttons: Array = []
var slots: Array = []
var detail_panel: PanelContainer
var detail_label: RichTextLabel
var detail_actions: HBoxContainer
var skill_panel: PanelContainer
var skill_content: VBoxContainer
var pin_check: CheckButton
var street_toggle_button: Button
var close_dialog: ConfirmationDialog
var street_mode := true
var selected_slot := ""

func _ready() -> void:
	var palette := Theme.new()
	palette.default_font_size = 15
	palette.set_color("font_color", "Label", Color("263b31"))
	palette.set_color("default_color", "RichTextLabel", Color("263b31"))
	palette.set_color("font_color", "CheckButton", Color("263b31"))
	palette.set_color("font_hover_color", "CheckButton", Color("263b31"))
	theme = palette

	var win := get_window()
	win.title = "桌面王国 v0.4 · 底部街景"
	win.min_size = NORMAL_MIN
	get_tree().auto_accept_quit = false
	win.close_requested.connect(_request_close)
	win.focus_entered.connect(_clamp_window)

	var margin := MarginContainer.new()
	content_margin = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)

	normal_root = VBoxContainer.new()
	normal_root.add_theme_constant_override("separation", 6)
	margin.add_child(normal_root)

	street_root = VBoxContainer.new()
	street_root.add_theme_constant_override("separation", 6)
	margin.add_child(street_root)

	_load_slots()
	_build_normal()
	_build_street()
	_build_detail()
	_build_skill_panel()
	_build_close_dialog()
	resized.connect(_layout_panels)
	_apply_window_config()
	_refresh()

# ---------- 普通管理视图 ----------
func _build_normal() -> void:
	var toolbar := HBoxContainer.new()
	normal_root.add_child(toolbar)
	_button(toolbar, "保存", func(): _show_save_result(saves.save_game(game)))
	_button(toolbar, "读取", func(): _show_save_result(saves.load_game(game)))
	_button(toolbar, "重新开始", func(): _act("restart"))
	pin_check = CheckButton.new()
	pin_check.text = "窗口置顶"
	pin_check.toggled.connect(_on_pin_toggled)
	toolbar.add_child(pin_check)
	_button(toolbar, "收起街景", func(): _toggle_street())
	stats = _label(normal_root)
	economy = _label(normal_root)
	message = _label(normal_root)
	message.text = "手动推进月份；成熟粮食留在农田，点击农田收取。"
	event_label = _label(normal_root)
	var events := HBoxContainer.new()
	normal_root.add_child(events)
	accept_button = _button(events, "接纳流民", func(): _act("accept_refugees", {"event_id": displayed_event_id}))
	reject_button = _button(events, "拒绝流民", func(): _act("reject_refugees", {"event_id": displayed_event_id}))
	var buildings := HFlowContainer.new()
	normal_root.add_child(buildings)
	housing_button = _button(buildings, "扩建住房", func(): _act("build_housing"))
	farm_button = _button(buildings, "改善农业", func(): _act("improve_agriculture"))
	harvest_button = _button(buildings, "收取农田", func(): _act("harvest_farm"))
	forge_button = _button(buildings, "升级铁匠铺", func(): _act("upgrade_forge"))
	next_button = _button(buildings, "推进一个月", func(): _act("advance_month"))
	_button(buildings, "研究技能", func(): _open_skills())
	var army := HFlowContainer.new()
	normal_root.add_child(army)
	site = OptionButton.new()
	site.add_item("林间废墟")
	site.add_item("荒废矿井")
	site.item_selected.connect(func(_index: int): _refresh())
	army.add_child(site)
	mode = OptionButton.new()
	mode.add_item("深入探索")
	mode.add_item("清理入口")
	mode.item_selected.connect(func(_index: int): _refresh())
	army.add_child(mode)
	troops = SpinBox.new()
	troops.min_value = 2
	troops.max_value = 1000000
	troops.value = 6
	troops.prefix = "出征人数 "
	troops.value_changed.connect(func(_value: float): _refresh())
	army.add_child(troops)
	dispatch_button = _button(army, "出征", func(): _act("dispatch", _army_args()))
	expedition_label = _label(normal_root)
	details = RichTextLabel.new()
	details.bbcode_enabled = false
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.selection_enabled = true
	normal_root.add_child(details)

# ---------- 底部街景 ----------
func _load_slots() -> void:
	var text: String = ""
	var file := FileAccess.open("res://data/building_slots.json", FileAccess.READ)
	if file:
		text = file.get_as_text()
		file.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		slots = parsed.get("slots", [])

func _build_street() -> void:
	info_label = _label(street_root)
	info_label.add_theme_font_size_override("font_size", 14)
	street_row = HBoxContainer.new()
	street_row.add_theme_constant_override("separation", 8)
	street_root.add_child(street_row)
	var actions := HBoxContainer.new()
	street_root.add_child(actions)
	street_next_button = _button(actions, "推进一个月", func(): _act("advance_month"))
	_button(actions, "研究", func(): _open_skills())
	_button(actions, "保存", func(): _show_save_result(saves.save_game(game)))
	_button(actions, "读取", func(): _show_save_result(saves.load_game(game)))
	street_toggle_button = _button(actions, "展开管理", func(): _toggle_street())
	var reserved_hint := Label.new()
	reserved_hint.text = "预留地块：暂无生产与升级"
	reserved_hint.add_theme_color_override("font_color", Color(0.45, 0.42, 0.36))
	reserved_hint.add_theme_font_size_override("font_size", 11)
	street_root.add_child(reserved_hint)
	street_notice = _label(street_root)
	for slot in slots:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 84)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_slot_pressed.bind(str(slot.id)))
		street_row.add_child(button)
		slot_buttons.append(button)

func _on_slot_pressed(slot_id: String) -> void:
	if slot_id == "farm":
		var fv: Dictionary = game.view().farm
		if int(fv.ready_food) > 0:
			_act("harvest_farm")
		else:
			var r: Dictionary = game.act("assist_farm", {"source": "click", "count": 1})
			message.text = r.message
			_refresh()
		return
	if slot_id == "housing" or slot_id == "forge":
		_open_detail(slot_id)
		return
	message.text = "预留地块暂时没有生产或升级。"
	_refresh()

# ---------- 建筑详情 ----------
func _build_detail() -> void:
	detail_panel = PanelContainer.new()
	detail_panel.visible = false
	add_child(detail_panel)
	var column := VBoxContainer.new()
	detail_panel.add_child(column)
	var bar := HBoxContainer.new()
	column.add_child(bar)
	_button(bar, "关闭", _close_panels)
	detail_label = RichTextLabel.new()
	detail_label.bbcode_enabled = false
	detail_label.custom_minimum_size = Vector2(0, 90)
	detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(detail_label)
	detail_actions = HBoxContainer.new()
	column.add_child(detail_actions)

func _open_detail(slot_id: String) -> void:
	selected_slot = slot_id
	_show_panel(detail_panel)
	_render_detail()
	_layout_panels.call_deferred()

func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _render_detail() -> void:
	var v: Dictionary = game.view()
	var s: Dictionary = game.snapshot()
	_clear_children(detail_actions)
	if selected_slot == "housing":
		detail_label.text = "民居 %d 级\n基础住房 %d，有效容量 %d\n技能点：累计 %d / 可用 %d" % [v.housing_level, s.housing, v.housing_capacity, v.skills.housing.earned, v.skills.housing.available]
		var upgrade := _button(detail_actions, "扩建住房（%d木材，容量+6）" % v.housing_cost, func(): _act("build_housing"))
		upgrade.disabled = housing_button.disabled
		_button(detail_actions, "研究", func(): _open_skills())
	elif selected_slot == "forge":
		detail_label.text = "铁匠铺 %d/3 级\n升级消耗 %d木 + %d矿\n技能点：累计 %d / 可用 %d" % [s.forge, v.forge_cost.wood, v.forge_cost.ore, v.skills.forge.earned, v.skills.forge.available]
		var upgrade := _button(detail_actions, "升级铁匠铺", func(): _act("upgrade_forge"))
		upgrade.disabled = forge_button.disabled
		_button(detail_actions, "研究", func(): _open_skills())

# ---------- 技能树 ----------
func _build_skill_panel() -> void:
	skill_panel = PanelContainer.new()
	skill_panel.visible = false
	add_child(skill_panel)
	var outer := VBoxContainer.new()
	skill_panel.add_child(outer)
	var bar := HBoxContainer.new()
	outer.add_child(bar)
	_button(bar, "关闭", _close_panels)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	skill_content = VBoxContainer.new()
	skill_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(skill_content)

func _open_skills() -> void:
	_show_panel(skill_panel)
	_render_skills()
	_layout_panels.call_deferred()

func _render_skills() -> void:
	_clear_children(skill_content)
	var v: Dictionary = game.view()
	for tree_id in ["farm", "housing", "forge"]:
		var tree: Dictionary = v.skills[tree_id]
		var header := Label.new()
		header.text = "%s（累计 %d / 可用 %d）" % [tree.name, tree.earned, tree.available]
		header.add_theme_font_size_override("font_size", 16)
		skill_content.add_child(header)
		for node in tree.nodes:
			var row := HBoxContainer.new()
			skill_content.add_child(row)
			var label := Label.new()
			var state := "已解锁" if node.unlocked else ("可解锁" if node.available else ("未满足：" + str(node.problem)))
			label.text = "  %s — %s [%s]" % [node.name, node.description, state]
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var unlock := Button.new()
			unlock.text = "解锁"
			unlock.disabled = game.snapshot().ended or not node.available
			unlock.set_meta("skill_id", node.id)
			unlock.pressed.connect(func(): _act("unlock_skill", {"tree": tree_id, "node": node.id}))
			row.add_child(unlock)

# ---------- 公共 ----------
func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _label(parent: Control) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("263b31"))
	parent.add_child(label)
	return label

func _army_args() -> Dictionary:
	return {"site": "ruins" if site.selected == 0 else "mine",
		"mode": "explore" if mode.selected == 0 else "clear", "troops": int(troops.value)}

func _act(command: String, args: Dictionary = {}) -> void:
	var result: Dictionary = game.act(command, args)
	message.text = result.message
	_refresh()

func _show_save_result(result: Dictionary) -> void:
	message.text = result.message
	_refresh()

func _refresh() -> void:
	if details == null:
		return
	var s: Dictionary = game.snapshot()
	var v: Dictionary = game.view()
	stats.text = "%s   人口 %d/%d   粮仓 %d   待收 %d   木材 %d   矿石 %d" % [v.date, s.population, v.housing_capacity, s.food, v.farm.ready_food, s.wood, s.ore]
	economy.text = "城内%d人；每批产粮%d，需求%d，木材%d。农田%d级，铁匠铺%d级，民居%d级。%s减产%d%%。" % [v.home_population, v.batch_food, v.food_demand, v.wood_production, s.agriculture, s.forge, v.housing_level, "当前旱季" if v.drought else "每年7—9月旱季", v.drought_reduction_percent]
	displayed_event_id = s.pending.get("id", "")
	event_label.text = "%d名流民等待决定，时间暂不推进。" % s.pending.visitors if not s.pending.is_empty() else "下次来访：%s，%d人。" % [game.date_label(v.next_refugees.month), v.next_refugees.visitors]
	if s.ended:
		event_label.text = "王国已无居民，请读档或重新开始。"
	accept_button.disabled = s.ended or s.pending.is_empty() or s.population + s.pending.get("visitors", 0) > v.housing_capacity
	reject_button.disabled = s.ended or s.pending.is_empty()
	next_button.disabled = s.ended or not s.pending.is_empty()
	street_next_button.disabled = next_button.disabled
	harvest_button.text = "收取农田 · %d粮" % v.farm.ready_food
	harvest_button.disabled = s.ended or v.farm.ready_food <= 0
	housing_button.text = "住房+6 · %d木材" % v.housing_cost
	housing_button.disabled = s.ended or s.wood < v.housing_cost
	farm_button.text = "改善农业 · %d木材" % v.farm_cost
	farm_button.disabled = s.ended or s.wood < v.farm_cost
	forge_button.text = "铁匠铺满级" if s.forge >= 3 else "铁匠铺 · %d木+%d矿" % [v.forge_cost.wood, v.forge_cost.ore]
	forge_button.disabled = s.ended or s.forge >= 3 or s.wood < v.forge_cost.wood or s.ore < v.forge_cost.ore
	var args: Dictionary = _army_args()
	var problem: String = game.dispatch_problem(args)
	dispatch_button.disabled = not problem.is_empty()
	var e: Dictionary = s.expedition
	if not e.is_empty():
		expedition_label.text = "%s：在外%d人，已完成%d/%d层，战利品归来入库。" % [v.sites[e.site].name, e.troops, e.room, e.goal]
	else:
		var quote: Dictionary = game.expedition_quote(args.troops)
		expedition_label.text = "出征耗%d粮+%d木；初始战力%d。%s" % [quote.food, quote.wood, quote.power, problem]
	var lines: PackedStringArray = ["宰相手记"]
	for entry in s.journal:
		lines.append(game.date_label(entry.month) + "｜" + entry.text)
	lines.append("\n远征战报")
	for entry in s.battle_log:
		lines.append(entry)
	lines.append("\n王国记录（最新在前）")
	var records: Array = s.records.duplicate()
	records.reverse()
	for entry in records:
		lines.append(entry)
	details.text = "\n".join(lines)
	_refresh_street(s, v)
	if detail_panel.visible:
		_render_detail()
	if skill_panel.visible:
		_render_skills()

func _refresh_street(s: Dictionary, v: Dictionary) -> void:
	street_notice.text = message.text
	if s.ended:
		street_notice.text = "王国已无居民，请展开管理后重开，或读取存档。 " + message.text
	elif v.food_shortfall > 0:
		street_notice.text = "口粮警报：推进前粮仓还差%d粮，田里待收%d粮；请先收获或补足口粮。 " % [v.food_shortfall, v.farm.ready_food] + message.text
	street_notice.add_theme_color_override("font_color", Color("9e3228") if s.ended or v.food_shortfall > 0 else Color("263b31"))
	info_label.text = "%s   人口 %d/%d   粮仓 %d   待收 %d   木材 %d   矿石 %d   每批产粮 %d   需求 %d   木材/月 %d" % [v.date, s.population, v.housing_capacity, s.food, v.farm.ready_food, s.wood, s.ore, v.batch_food, v.food_demand, v.wood_production]
	if not s.pending.is_empty():
		info_label.text += "   ⚠ 流民待决定"
	if not s.expedition.is_empty():
		info_label.text += "   ⚔ 远征在外"
	for i in range(slot_buttons.size()):
		var slot: Dictionary = slots[i]
		var button: Button = slot_buttons[i]
		var sid: String = str(slot.id)
		if sid == "farm":
			var fv: Dictionary = v.farm
			var pct := int(int(fv.progress) * 100 / int(fv.full_batch))
			button.text = "农田\n待收 %d 批/%d\n生长 %d%%" % [fv.ready_batches, fv.ready_food, pct]
		elif sid == "housing":
			button.text = "民居\n%d级 容量%d" % [v.housing_level, v.housing_capacity]
		elif sid == "forge":
			button.text = "铁匠铺\n%d/3级" % s.forge
		else:
			button.text = str(slot.label) + "\n（预留）"

# ---------- 窗口（沿用 004B） ----------
func _on_pin_toggled(enabled: bool) -> void:
	get_window().always_on_top = enabled
	_save_window_config()

func _toggle_street() -> void:
	_close_panels()
	var win := get_window()
	if not street_mode:
		normal_size = win.size
	street_mode = not street_mode
	if street_mode:
		win.min_size = Vector2i(720, STREET_HEIGHT)
		_dock_street(win)
	else:
		var bottom := win.position.y + win.size.y
		win.min_size = NORMAL_MIN
		win.size = normal_size
		win.position.y = bottom - win.size.y
	_sync_views()
	_clamp_window()
	_save_window_config()
	_refresh()

func _sync_views() -> void:
	if content_margin:
		content_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if street_mode:
			content_margin.anchor_top = 1.0
			content_margin.offset_top = -STREET_HEIGHT
	if normal_root:
		normal_root.visible = not street_mode
	if street_root:
		street_root.visible = street_mode
	if street_toggle_button:
		street_toggle_button.text = "展开管理" if street_mode else "收起街景"
	_layout_panels.call_deferred()

func _show_panel(panel: PanelContainer) -> void:
	var win := get_window()
	if street_mode:
		if not panel_restore_rect.has_area():
			panel_restore_rect = Rect2i(win.position, win.size)
		var usable := _usable_rect()
		win.min_size = Vector2i(mini(720, usable.size.x), mini(STREET_HEIGHT + 200, usable.size.y))
		var height := STREET_HEIGHT + (480 if panel == skill_panel else 260)
		var desired := Rect2i(panel_restore_rect.position, Vector2i(maxi(720, win.size.x), height))
		desired.position.y = panel_restore_rect.end.y - height
		_set_window_rect(fit_window_rect(desired, _usable_rect()))
	detail_panel.visible = panel == detail_panel
	skill_panel.visible = panel == skill_panel
	_layout_panels()

func _close_panels() -> void:
	detail_panel.hide()
	skill_panel.hide()
	if panel_restore_rect.has_area():
		var restore := panel_restore_rect
		panel_restore_rect = Rect2i()
		get_window().min_size = Vector2i(720, STREET_HEIGHT)
		_set_window_rect(fit_window_rect(restore, _usable_rect()))

func _layout_panels() -> void:
	if detail_panel == null or skill_panel == null:
		return
	var available_height := maxf(100.0, size.y - (STREET_HEIGHT if street_mode else 0) - 20)
	for panel in [detail_panel, skill_panel]:
		if not panel.visible:
			continue
		var height := minf(460.0 if panel == skill_panel else 240.0, available_height)
		panel.size = Vector2(minf(720.0, size.x - 20), height)
		panel.position = Vector2((size.x - panel.size.x) / 2, 10 if street_mode else (size.y - panel.size.y) / 2)

func _request_close() -> void:
	if close_dialog:
		close_dialog.popup_centered()

func _on_close_save() -> void:
	var result: Dictionary = saves.save_game(game)
	if result.get("ok", false):
		_save_window_config()
		get_tree().quit()
	else:
		message.text = "保存失败：" + str(result.get("message", "未知原因")) + "，窗口保持打开。"
		_refresh()

func _on_close_custom(action: String) -> void:
	if action == "direct_exit":
		_save_window_config()
		get_tree().quit()

func _clamp_window() -> void:
	var win := get_window()
	var usable := _usable_rect()
	win.min_size = Vector2i(mini(win.min_size.x, usable.size.x), mini(win.min_size.y, usable.size.y))
	_set_window_rect(fit_window_rect(Rect2i(win.position, win.size), usable))

func _usable_rect() -> Rect2i:
	if DisplayServer.get_name() != "headless":
		var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		if usable.has_area():
			return usable
	# 无窗口测试的确定性画布，不代表真实显示器验收。
	return Rect2i(0, 0, 1920, 1080)

static func fit_window_rect(rect: Rect2i, usable: Rect2i) -> Rect2i:
	var fitted_size := Vector2i(clampi(rect.size.x, 1, usable.size.x), clampi(rect.size.y, 1, usable.size.y))
	var position := Vector2i(clampi(rect.position.x, usable.position.x, usable.end.x - fitted_size.x),
		clampi(rect.position.y, usable.position.y, usable.end.y - fitted_size.y))
	return Rect2i(position, fitted_size)

func _set_window_rect(rect: Rect2i) -> void:
	get_window().size = rect.size
	get_window().position = rect.position

func _save_window_config() -> void:
	var win := get_window()
	var rect := panel_restore_rect if panel_restore_rect.has_area() else Rect2i(win.position, win.size)
	if not street_mode:
		normal_size = win.size
	var data := {"position": [rect.position.x, rect.position.y], "size": [rect.size.x, rect.size.y],
		"street_mode": street_mode, "always_on_top": win.always_on_top,
		"normal_size": [normal_size.x, normal_size.y]}
	var f := FileAccess.open(window_config_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

func _load_window_config() -> Dictionary:
	if not FileAccess.file_exists(window_config_path):
		return {}
	var f := FileAccess.open(window_config_path, FileAccess.READ)
	if not f:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}

func _to_vec2i(value) -> Vector2i:
	if value is Array and value.size() == 2:
		for component in value:
			if not (component is int or component is float):
				return Vector2i.ZERO
			if not is_finite(float(component)) or absf(float(component)) > 100000 or float(component) != floorf(float(component)):
				return Vector2i.ZERO
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO

func _apply_window_config() -> void:
	var cfg := _load_window_config()
	var win := get_window()
	var fresh := not cfg.has("street_mode")
	street_mode = cfg.get("street_mode", true) != false
	var remembered_normal := _to_vec2i(cfg.get("normal_size"))
	if remembered_normal.x >= NORMAL_MIN.x and remembered_normal.y >= NORMAL_MIN.y:
		normal_size = remembered_normal
	win.min_size = Vector2i(720, STREET_HEIGHT) if street_mode else NORMAL_MIN
	if fresh:
		_dock_street(win)
	else:
		if cfg.has("size"):
			var s := _to_vec2i(cfg["size"])
			if s.x >= 600 and s.y >= 160:
				win.size = s
		if cfg.has("position"):
			var p := _to_vec2i(cfg["position"])
			win.position = p
	var top: bool = cfg.get("always_on_top", false) == true
	win.always_on_top = top
	pin_check.set_pressed_no_signal(top)
	_sync_views()
	_clamp_window()

func _dock_street(win: Window) -> void:
	var h := STREET_HEIGHT
	var w := 960
	var pos := Vector2i(0, 0)
	if DisplayServer.get_name() != "headless":
		var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		if usable.size.x > 0:
			w = usable.size.x - 24
			pos = Vector2i(usable.position.x + 12, usable.position.y + usable.size.y - h - 8)
	win.size = Vector2i(w, h)
	win.position = pos

func _build_close_dialog() -> void:
	close_dialog = ConfirmationDialog.new()
	close_dialog.title = "关闭桌面王国"
	close_dialog.dialog_text = "要保存当前进度再退出吗？"
	close_dialog.get_ok_button().text = "保存并退出"
	close_dialog.get_cancel_button().text = "取消"
	close_dialog.add_button("直接退出", true, "direct_exit")
	close_dialog.confirmed.connect(_on_close_save)
	close_dialog.custom_action.connect(_on_close_custom)
	add_child(close_dialog)
