extends RefCounted
## 无场景、无计时器、无文件读写的经营内核。
## UI 只调用 act / snapshot / view，不直接修改 _state。
const B = preload("res://core/balance.gd")
var _state: Dictionary

func _init() -> void:
	_reset()

func _reset() -> void:
	_state = B.INITIAL.duplicate(true)
	_state.merge({"pending": {}, "last_refugee_month": -1, "expedition": {},
		"ended": false, "records": [], "battle_log": [], "journal": [],
		"deaths": {"starvation": 0, "battle": 0}, "progress": {"ruins": 0, "mine": 0}})

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func date_label(months: int = -1) -> String:
	var m: int = int(_state.months) if months < 0 else months
	return "第%d年%d月" % [int(m / 12.0) + 1, m % 12 + 1]

func refugee_at(months: int) -> Dictionary:
	if B.EARLY_REFUGEES.has(months):
		return {"id": "refugee-m%d" % months, "month": months, "visitors": B.EARLY_REFUGEES[months]}
	if months >= B.RECURRING_REFUGEE_START and (months - B.RECURRING_REFUGEE_START) % B.RECURRING_REFUGEE_INTERVAL == 0:
		return {"id": "refugee-m%d" % months, "month": months, "visitors": B.RECURRING_REFUGEE_SIZE}
	return {}

func _home() -> int:
	return int(_state.population) - int(_state.expedition.get("troops", 0))

func is_drought() -> bool:
	var m: int = int(_state.months) % 12
	return m >= B.DROUGHT_FROM and m < B.DROUGHT_UNTIL

func _food_production() -> int:
	if _home() == 0:
		return 0
	var production: int = B.FOOD_BASE + (int(_state.agriculture) - 1) * B.FOOD_PER_FARM_LEVEL
	return int(floor(production * (B.DROUGHT_FACTOR if is_drought() else 1.0)))

func _farm_cost() -> int:
	return B.FARM_COST_BASE * int(_state.agriculture)

func _forge_cost() -> Dictionary:
	var level: int = int(_state.forge) + 1
	return {"wood": B.FORGE_WOOD_BASE * level, "ore": B.FORGE_ORE_BASE * level}

func view() -> Dictionary:
	var next_month: int = int(_state.months) + 1
	while refugee_at(next_month).is_empty():
		next_month += 1
	return {"date": date_label(), "home_population": _home(),
		"food_production": _food_production(), "food_demand": _state.population,
		"wood_production": int(floor(_home() * B.WOOD_PER_PERSON)),
		"drought": is_drought(), "next_refugees": refugee_at(next_month),
		"farm_cost": _farm_cost(), "forge_cost": _forge_cost(),
		"housing_cost": B.HOUSING_COST, "sites": B.SITES.duplicate(true),
		"mine_unlocked": _state.progress.ruins == 3 and _state.forge >= 1}

func _record(message: String) -> void:
	_state.records.append(date_label() + "｜" + message)
	if _state.records.size() > B.MAX_RECORDS:
		_state.records.pop_front()

func _battle_record(message: String) -> void:
	_state.battle_log.append(message)
	if _state.battle_log.size() > B.MAX_BATTLE_RECORDS:
		_state.battle_log.pop_front()
	_record(message)

func _achievement(id: String) -> void:
	for entry in _state.journal:
		if entry.id == id:
			return
	_state.journal.append({"id": id, "month": _state.months, "text": B.ACHIEVEMENTS[id]})

func _reply(ok: bool, message: String = "") -> Dictionary:
	return {"ok": ok, "message": message, "state": snapshot(), "view": view()}

func act(command: String, args: Dictionary = {}) -> Dictionary:
	if command == "restart":
		_reset()
		return _reply(true, "新王国已经开始，手动存档未删除。")
	if _state.ended:
		return _reply(false, "王国已无居民，可以读取存档或重新开始。")
	match command:
		"build_housing":
			if _state.wood < B.HOUSING_COST:
				return _reply(false, "木材不足。")
			_state.wood -= B.HOUSING_COST
			_state.housing += B.HOUSING_GAIN
			_record("扩建住房，容量增加%d。" % B.HOUSING_GAIN)
			_achievement("housing")
		"improve_agriculture":
			if _state.wood < _farm_cost():
				return _reply(false, "木材不足。")
			_state.wood -= _farm_cost()
			_state.agriculture += 1
			_record("农田升至%d级，下一次改善需要%d木材。" % [_state.agriculture, _farm_cost()])
			_achievement("agriculture")
		"upgrade_forge":
			var cost: Dictionary = _forge_cost()
			if _state.forge >= B.FORGE_MAX_LEVEL or _state.wood < cost.wood or _state.ore < cost.ore:
				return _reply(false, "铁匠铺已满级或资源不足。")
			_state.wood -= cost.wood
			_state.ore -= cost.ore
			_state.forge += 1
			_record("铁匠铺升至%d级，强化以后出发的队伍。" % _state.forge)
			_achievement("forge")
		"accept_refugees", "reject_refugees":
			var pending: Dictionary = _state.pending
			if pending.is_empty() or args.get("event_id", "") != pending.id:
				return _reply(false, "这批流民已处理，或事件编号不匹配。")
			if command == "accept_refugees":
				if _state.population + pending.visitors > _state.housing:
					return _reply(false, "住房不足，可以先扩建住房。")
				_state.population += pending.visitors
				_record("接纳%d名流民。" % pending.visitors)
			else:
				_record("婉拒%d名流民。" % pending.visitors)
			_state.pending = {}
		"dispatch":
			var problem: String = dispatch_problem(args)
			if not problem.is_empty():
				return _reply(false, problem)
			var troops: int = int(args.troops)
			_state.food -= troops
			_state.wood -= troops
			_state.expedition = {"site": args.site, "mode": args.mode, "troops": troops,
				"initial_troops": troops, "attack": 2 + int(_state.forge), "room": 0,
				"goal": 1 if args.mode == "clear" else 3, "loot": {"food": 0, "wood": 0, "ore": 0}}
			_state.battle_log = []
			_battle_record("%d人出征%s，出征不推进月份。" % [troops, B.SITES[args.site].name])
		"advance_month":
			if not _state.pending.is_empty():
				return _reply(false, "先处理来访事件，时间暂不推进。")
			_advance_month()
		_:
			return _reply(false, "未知操作。")
	return _reply(true)

func dispatch_problem(args: Dictionary) -> String:
	if _state.ended or not _state.pending.is_empty():
		return "王国已结束或有待处理事件。"
	if not _state.expedition.is_empty():
		return "已有一支队伍在外。"
	var site = args.get("site")
	if not site is String or not B.SITES.has(site):
		return "目的地无效。"
	if site == "mine" and not (_state.progress.ruins == 3 and _state.forge >= 1):
		return "需通关废墟并建成铁匠铺，才能进入矿井。"
	if args.get("mode") not in ["explore", "clear"]:
		return "任务类型无效。"
	if args.mode == "clear" and _state.progress[site] < 1:
		return "先探索通过入口，才能清理。"
	if not _integer(args.get("troops"), 2, int(_state.population) - 1):
		return "至少出征2人，并留1名居民在城内。"
	if _state.food < args.troops or _state.wood < args.troops:
		return "出征粮食或木材不足。"
	return ""

func _return_expedition(reason: String) -> void:
	var e: Dictionary = _state.expedition
	if e.troops > 0:
		for key in ["food", "wood", "ore"]:
			_state[key] += e.loot[key]
		_battle_record("%s：%d人返回，带回粮%d、木%d、矿%d。" % [reason, e.troops, e.loot.food, e.loot.wood, e.loot.ore])
	else:
		_battle_record("%s：无人归来，携带的战利品遗失。" % reason)
	_state.expedition = {}

func _settle_battle() -> void:
	if _state.expedition.is_empty():
		return
	var e: Dictionary = _state.expedition
	var room: Dictionary = B.SITES[e.site].rooms[e.room]
	var power: int = int(e.troops * e.attack)
	var win: bool = power >= room.threat
	var loss: int = int(floor(float(room.threat) / ((e.attack + 2) * 3))) if win else maxi(1, int(ceil((room.threat - power) / 4.0)))
	loss = mini(loss, int(e.troops))
	e.troops -= loss
	_state.population -= loss
	_state.deaths.battle += loss
	_battle_record("%s：战力%d / 威胁%d，%s，阵亡%d人。" % [room.name, power, room.threat, "胜利" if win else "战败", loss])
	if not win or e.troops == 0:
		_return_expedition("远征结束")
		return
	for key in ["food", "wood", "ore"]:
		e.loot[key] += room.loot[key]
	e.room += 1
	_state.progress[e.site] = maxi(int(_state.progress[e.site]), int(e.room))
	_achievement("first-victory")
	if e.room == 3:
		_achievement(e.site + "-clear")
	if e.room == e.goal:
		_return_expedition("任务完成")

func _advance_month() -> void:
	var produced: int = _food_production()
	var demand: int = int(_state.population)
	var available: int = int(_state.food) + produced
	var shortfall: int = maxi(0, demand - available)
	var wood: int = int(floor(_home() * B.WOOD_PER_PERSON))
	_state.food = maxi(0, available - demand)
	_state.wood += wood
	_record("结算：产粮%d，需求%d，缺口%d；木材+%d。" % [produced, demand, shortfall, wood])
	if shortfall > 0:
		var loss: int = mini(int(_state.population), int(ceil(shortfall / 2.0)))
		var away_loss: int = maxi(0, loss - _home())
		_state.population -= loss
		_state.deaths.starvation += loss
		if not _state.expedition.is_empty():
			_state.expedition.troops -= away_loss
		_record("饥饿造成%d人死亡，其中远征队%d人。" % [loss, away_loss])
		if not _state.expedition.is_empty() and _state.expedition.troops == 0:
			_return_expedition("饥饿覆灭")
	_state.months += 1
	if _state.population > 0:
		_settle_battle()
	if _state.population == 0:
		_state.ended = true
		_state.pending = {}
		_state.expedition = {}
		_record("王国已无居民。本轮结束，宰相记下了这段历史。")
		return
	if int(_state.months) % 12 == B.DROUGHT_UNTIL:
		_achievement("drought-survived")
		_record("这一年的旱季结束，农业恢复。")
	var event: Dictionary = refugee_at(int(_state.months))
	if not event.is_empty() and _state.last_refugee_month < _state.months:
		_state.pending = event
		_state.last_refugee_month = _state.months
		_record("%d名流民来访，请决定是否接纳。" % event.visitors)

func _integer(value: Variant, low: int = 0, high: int = 100000000) -> bool:
	if not (value is int or value is float):
		return false
	return is_finite(float(value)) and value >= low and value <= high and float(value) == floor(float(value))

func _string_list(value: Variant, limit: int) -> bool:
	if not value is Array or value.size() > limit:
		return false
	for item in value:
		if not item is String or item.length() > 2000:
			return false
	return true

func _valid(s: Variant) -> bool:
	if not s is Dictionary:
		return false
	for key in B.INITIAL:
		if not _integer(s.get(key)):
			return false
	if s.population > s.housing or s.agriculture < 1 or s.forge > B.FORGE_MAX_LEVEL:
		return false
	if not _integer(s.get("last_refugee_month"), -1, int(s.months)) or not s.get("ended") is bool:
		return false
	if not s.get("pending") is Dictionary or not s.get("expedition") is Dictionary:
		return false
	if not _string_list(s.get("records"), B.MAX_RECORDS) or not _string_list(s.get("battle_log"), B.MAX_BATTLE_RECORDS):
		return false
	if not s.get("deaths") is Dictionary or not s.get("progress") is Dictionary:
		return false
	for key in ["starvation", "battle"]:
		if not _integer(s.deaths.get(key)):
			return false
	for key in ["ruins", "mine"]:
		if not _integer(s.progress.get(key), 0, 3):
			return false
	if s.ended != (s.population == 0) or (s.ended and (not s.pending.is_empty() or not s.expedition.is_empty())):
		return false
	if not s.pending.is_empty():
		var expected: Dictionary = refugee_at(int(s.months))
		if expected.is_empty() or s.pending.size() != 3 or s.last_refugee_month != s.months:
			return false
		if s.pending.get("id") != expected.id or not _integer(s.pending.get("month")) or not _integer(s.pending.get("visitors")):
			return false
		if s.pending.month != expected.month or s.pending.visitors != expected.visitors:
			return false
	if s.last_refugee_month >= 0 and refugee_at(int(s.last_refugee_month)).is_empty():
		return false
	if not s.get("journal") is Array or s.journal.size() > B.ACHIEVEMENTS.size():
		return false
	var ids: Array = []
	for entry in s.journal:
		if not entry is Dictionary or not entry.get("id") is String:
			return false
		if not B.ACHIEVEMENTS.has(entry.id) or entry.id in ids or not _integer(entry.get("month"), 0, int(s.months)):
			return false
		if entry.get("text") != B.ACHIEVEMENTS[entry.id]:
			return false
		ids.append(entry.id)
	if not s.expedition.is_empty():
		var e: Dictionary = s.expedition
		if not e.get("site") is String or not B.SITES.has(e.site) or e.get("mode") not in ["clear", "explore"]:
			return false
		if e.get("goal") != (1 if e.mode == "clear" else 3) or not _integer(e.get("room"), 0, int(e.goal) - 1):
			return false
		if not _integer(e.get("troops"), 1, int(s.population)) or not _integer(e.get("initial_troops"), int(e.troops)) or not _integer(e.get("attack"), 2, 5):
			return false
		if not e.get("loot") is Dictionary:
			return false
		for key in ["food", "wood", "ore"]:
			if not _integer(e.loot.get(key)):
				return false
	return true

func _normalize(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[key] = _normalize(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_normalize(item))
		return result
	if value is float:
		return int(value)
	return value

func import_snapshot(value: Variant) -> bool:
	if not _valid(value):
		return false
	_state = _normalize(value)
	return true
