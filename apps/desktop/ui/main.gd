extends Control
## 最小接线演示，供 DSH 改造成桌面小窗。所有规则留在 core/。
const Kingdom = preload("res://core/kingdom.gd")
const SaveStore = preload("res://core/save_store.gd")
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

func _ready() -> void:
	var palette := Theme.new()
	palette.default_font_size = 16
	palette.set_color("font_color", "Label", Color("263b31"))
	palette.set_color("default_color", "RichTextLabel", Color("263b31"))
	palette.set_color("font_color", "CheckButton", Color("263b31"))
	palette.set_color("font_hover_color", "CheckButton", Color("263b31"))
	theme = palette
	get_window().title = "桌面王国 v0.3 · 开发底座"
	get_window().min_size = Vector2i(640, 420)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "荒地与地下城 · 桌面开发底座"
	heading.add_theme_font_size_override("font_size", 23)
	column.add_child(heading)
	var toolbar := HBoxContainer.new()
	column.add_child(toolbar)
	_button(toolbar, "保存", func(): _show_save_result(saves.save_game(game)))
	_button(toolbar, "读取", func(): _show_save_result(saves.load_game(game)))
	_button(toolbar, "重新开始", func(): _act("restart"))
	var pinned := CheckButton.new()
	pinned.text = "窗口置顶"
	pinned.toggled.connect(func(enabled: bool): get_window().always_on_top = enabled)
	toolbar.add_child(pinned)
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
	_refresh()

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
