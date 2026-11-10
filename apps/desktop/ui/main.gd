extends Control
## 最小接线演示 + 桌面窗口体验（004B：小窗、置顶、关闭保存提示、窗口记忆）。
## 所有规则留在 core/；本脚本只负责窗口与界面。
const Kingdom = preload("res://core/kingdom.gd")
const SaveStore = preload("res://core/save_store.gd")

const WINDOW_CONFIG := "user://window-config.json"
const NORMAL_MIN := Vector2i(640, 420)
const NORMAL_DEFAULT := Vector2i(960, 620)
const COMPACT_SIZE := Vector2i(960, 260)
const COMPACT_MIN := Vector2i(520, 170)

var game = Kingdom.new()
var saves = SaveStore.new()
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

# 004B：窗口相关
var normal_root: VBoxContainer
var compact_root: VBoxContainer
var compact_stats: Label
var compact_economy: Label
var compact_event: Label
var compact_advance: Button
var compact_expand: Button
var pin_check: CheckButton
var compact_toggle: Button
var close_dialog: ConfirmationDialog
var compact := false
var normal_size := NORMAL_DEFAULT

func _ready() -> void:
	var palette := Theme.new()
	palette.default_font_size = 16
	palette.set_color("font_color", "Label", Color("263b31"))
	palette.set_color("default_color", "RichTextLabel", Color("263b31"))
	palette.set_color("font_color", "CheckButton", Color("263b31"))
	palette.set_color("font_hover_color", "CheckButton", Color("263b31"))
	theme = palette

	var win := get_window()
	win.title = "桌面王国 v0.3 · 开发底座"
	win.min_size = NORMAL_MIN
	get_tree().auto_accept_quit = false
	win.close_requested.connect(_request_close)
	win.focus_entered.connect(_clamp_window)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	normal_root = VBoxContainer.new()
	normal_root.add_theme_constant_override("separation", 8)
	margin.add_child(normal_root)

	compact_root = VBoxContainer.new()
	compact_root.add_theme_constant_override("separation", 6)
	margin.add_child(compact_root)

	_build_normal()
	_build_compact()
	_build_close_dialog()
	_apply_window_config()
	_refresh()

func _build_normal() -> void:
	var column := normal_root
	var heading := Label.new()
	heading.text = "荒地与地下城 · 桌面开发底座"
	heading.add_theme_font_size_override("font_size", 23)
	column.add_child(heading)
	var toolbar := HBoxContainer.new()
	column.add_child(toolbar)
	_button(toolbar, "保存", func(): _show_save_result(saves.save_game(game)))
	_button(toolbar, "读取", func(): _show_save_result(saves.load_game(game)))
	_button(toolbar, "重新开始", func(): _act("restart"))
	pin_check = CheckButton.new()
	pin_check.text = "窗口置顶"
	pin_check.toggled.connect(_on_pin_toggled)
	toolbar.add_child(pin_check)
	compact_toggle = _button(toolbar, "小窗", func(): _toggle_compact())
	stats = _label(column)
	economy = _label(column)
	message = _label(column)
	message.text = "本底座仍手动推进。每年7—9月旱季；后续流民持续出现。"
	event_label = _label(column)
	var events := HBoxContainer.new()
	column.add_child(events)
	accept_button = _button(events, "接纳流民", func(): _act("accept_refugees", {"event_id": displayed_event_id}))
	reject_button = _button(events, "拒绝流民", func(): _act("reject_refugees", {"event_id": displayed_event_id}))
	var buildings := HFlowContainer.new()
	column.add_child(buildings)
	housing_button = _button(buildings, "扩建住房", func(): _act("build_housing"))
	farm_button = _button(buildings, "改善农业", func(): _act("improve_agriculture"))
	forge_button = _button(buildings, "升级铁匠铺", func(): _act("upgrade_forge"))
	next_button = _button(buildings, "推进一个月", func(): _act("advance_month"))
	var army := HFlowContainer.new()
	column.add_child(army)
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
	expedition_label = _label(column)
	details = RichTextLabel.new()
	details.bbcode_enabled = false
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.selection_enabled = true
	column.add_child(details)

func _build_compact() -> void:
	compact_stats = _label(compact_root)
	compact_economy = _label(compact_root)
	compact_event = _label(compact_root)
	var bar := HBoxContainer.new()
	compact_root.add_child(bar)
	compact_advance = _button(bar, "推进一个月", func(): _act("advance_month"))
	compact_expand = _button(bar, "展开", func(): _toggle_compact())
	compact_root.visible = false

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
	stats.text = "%s   人口 %d/%d   粮食 %d   木材 %d   矿石 %d" % [v.date, s.population, s.housing, s.food, s.wood, s.ore]
	economy.text = "城内%d人；本月产粮%d / 需求%d，产木%d。农田%d级，铁匠铺%d级。%s" % [v.home_population, v.food_production, v.food_demand, v.wood_production, s.agriculture, s.forge, "当前旱季减产40%。" if v.drought else "每年7—9月旱季减产40%。"]
	displayed_event_id = s.pending.get("id", "")
	event_label.text = "%d名流民等待决定，时间暂不推进。" % s.pending.visitors if not s.pending.is_empty() else "下次来访：%s，%d人。" % [game.date_label(v.next_refugees.month), v.next_refugees.visitors]
	if s.ended:
		event_label.text = "王国已无居民，请读档或重新开始。"
	accept_button.disabled = s.ended or s.pending.is_empty() or s.population + s.pending.get("visitors", 0) > s.housing
	reject_button.disabled = s.ended or s.pending.is_empty()
	next_button.disabled = s.ended or not s.pending.is_empty()
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
		expedition_label.text = "出征耗%d粮+%d木；初始战力%d。%s" % [args.troops, args.troops, args.troops * (2 + s.forge), problem]
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
	if compact_stats:
		compact_stats.text = stats.text
	if compact_economy:
		compact_economy.text = economy.text
	if compact_event:
		compact_event.text = event_label.text
	if compact_advance:
		compact_advance.disabled = next_button.disabled

# ---------- 窗口体验 ----------

func _on_pin_toggled(enabled: bool) -> void:
	get_window().always_on_top = enabled
	_save_window_config()

func _toggle_compact() -> void:
	var win := get_window()
	if compact:
		compact = false
		win.min_size = NORMAL_MIN
		win.size = normal_size if normal_size.x >= NORMAL_MIN.x and normal_size.y >= NORMAL_MIN.y else NORMAL_DEFAULT
	else:
		normal_size = win.size
		compact = true
		win.min_size = COMPACT_MIN
		win.size = COMPACT_SIZE
	_sync_views()
	_clamp_window()
	_save_window_config()
	_refresh()

func _sync_views() -> void:
	if normal_root:
		normal_root.visible = not compact
	if compact_root:
		compact_root.visible = compact
	if compact_toggle:
		compact_toggle.text = "展开" if compact else "小窗"

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
	if DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	var idx := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(idx)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	var size := win.size
	var pos := win.position
	var min_x := usable.position.x
	var min_y := usable.position.y
	var max_x := usable.position.x + usable.size.x - size.x
	var max_y := usable.position.y + usable.size.y - size.y
	pos.x = clampi(pos.x, min_x, maxi(max_x, min_x))
	pos.y = clampi(pos.y, min_y, maxi(max_y, min_y))
	win.position = pos

func _save_window_config() -> void:
	var win := get_window()
	var data := {
		"position": [win.position.x, win.position.y],
		"size": [win.size.x, win.size.y],
		"normal_size": [normal_size.x, normal_size.y],
		"compact": compact,
		"always_on_top": win.always_on_top,
	}
	var f := FileAccess.open(WINDOW_CONFIG, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

func _load_window_config() -> Dictionary:
	if not FileAccess.file_exists(WINDOW_CONFIG):
		return {}
	var f := FileAccess.open(WINDOW_CONFIG, FileAccess.READ)
	if not f:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}

func _to_vec2i(value) -> Vector2i:
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO

func _apply_window_config() -> void:
	var cfg := _load_window_config()
	var win := get_window()
	compact = bool(cfg.get("compact", false))
	win.min_size = COMPACT_MIN if compact else NORMAL_MIN
	if cfg.has("normal_size"):
		var ns := _to_vec2i(cfg["normal_size"])
		if ns.x >= NORMAL_MIN.x and ns.y >= NORMAL_MIN.y:
			normal_size = ns
	if cfg.has("size"):
		var s := _to_vec2i(cfg["size"])
		if s.x >= COMPACT_MIN.x and s.y >= COMPACT_MIN.y:
			win.size = s
	if cfg.has("position"):
		var p := _to_vec2i(cfg["position"])
		if p != Vector2i.ZERO:
			win.position = p
	var top := bool(cfg.get("always_on_top", false))
	win.always_on_top = top
	pin_check.button_pressed = top
	_sync_views()
	_clamp_window()
