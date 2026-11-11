extends RefCounted
## 无场景、无计时器、无文件读写的经营内核（任务005：接入农田缓冲与建筑技能）。
## UI 只调用 act / snapshot / view，不直接修改 _state。
const B = preload("res://core/balance.gd")
const FarmBuffer = preload("res://core/farm_buffer.gd")
const BuildingSkills = preload("res://core/building_skills.gd")

var _state: Dictionary
var _farm = FarmBuffer.new()
var _skills = BuildingSkills.new()

func _init() -> void:
	_reset()

func _reset() -> void:
	_state = B.INITIAL.duplicate(true)
	_state.merge({"housing_level": 1, "pending": {}, "last_refugee_month": -1, "expedition": {},
		"ended": false, "records": [], "battle_log": [], "journal": [],
		"deaths": {"starvation": 0, "battle": 0}, "progress": {"ruins": 0, "mine": 0}})
	_farm = FarmBuffer.new()
	_farm.begin_month(int(_state.months))
	_skills = BuildingSkills.new()

func snapshot() -> Dictionary:
	var result: Dictionary = _state.duplicate(true)
	result["farm"] = _farm.snapshot()
	result["skills"] = _skills.snapshot()
	return result

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

func _batch_food() -> int:
	if _home() == 0:
		return 0
	var base_food: int = B.FOOD_BASE + (int(_state.agriculture) - 1) * B.FOOD_PER_FARM_LEVEL
	return _skills.farm_yield(base_food, B.DROUGHT_FACTOR if is_drought() else 1.0)

func _farm_cost() -> int:
	return B.FARM_COST_BASE * int(_state.agriculture)

func _forge_cost() -> Dictionary:
	var level: int = int(_state.forge) + 1
	return {"wood": B.FORGE_WOOD_BASE * level, "ore": B.FORGE_ORE_BASE * level}

func _earned_points(tree_id: String) -> int:
	match tree_id:
		"farm": return int(_state.agriculture)
		"housing": return int(_state.housing_level)
		"forge": return int(_state.forge)
	return 0

func emergency_points() -> Dictionary:
	return {"farm": _earned_points("farm"), "housing": _earned_points("housing"), "forge": _earned_points("forge")}

func _skills_view() -> Dictionary:
	var catalog: Dictionary = _skills.catalog()
	var unlocked: Dictionary = _skills.snapshot().unlocked
	var result: Dictionary = {}
	for tree_id in catalog:
		var earned: int = _earned_points(tree_id)
		var spent: int = unlocked[tree_id].size()
		var nodes: Array = []
		for node in catalog[tree_id].nodes:
			var problem: String = _skills.unlock_problem(tree_id, node.id, earned)
			var is_unlocked: bool = node.id in unlocked[tree_id]
			nodes.append({"id": node.id, "name": node.name, "description": node.description,
				"requires": node.requires, "cost": node.cost, "unlocked": is_unlocked,
				"available": (not is_unlocked) and problem.is_empty(), "problem": problem})
		result[tree_id] = {"name": catalog[tree_id].name, "earned": earned, "spent": spent,
			"available": maxi(0, earned - spent), "nodes": nodes}
	return result

func view() -> Dictionary:
	var next_month: int = int(_state.months) + 1
	while refugee_at(next_month).is_empty():
		next_month += 1
	return {"date": date_label(), "home_population": _home(),
		"food_demand": _state.population, "batch_food": _batch_food(),
		"wood_production": _skills.wood_production(_home(), B.WOOD_PER_PERSON),
		"drought": is_drought(), "next_refugees": refugee_at(next_month),
		"farm_cost": _farm_cost(), "forge_cost": _forge_cost(),
		"housing_cost": B.HOUSING_COST, "sites": B.SITES.duplicate(true),
		"mine_unlocked": _state.progress.ruins == 3 and _state.forge >= 1,
		"housing_capacity": _skills.housing_capacity(int(_state.housing)),
		"housing_level": int(_state.housing_level),
		"farm": _farm.view(), "skills": _skills_view(),
		"expedition_wood_cost": _skills.expedition_wood_cost(2, 1)}

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
			_state.housing_level += 1
			_record("扩建住房，容量增加%d，民居升至%d级。" % [B.HOUSING_GAIN, _state.housing_level])
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
				if _state.population + pending.visitors > _skills.housing_capacity(int(_state.housing)):
					return _reply(false, "住房不足，可以先扩建住房。")
				_state.population += pending.visitors
				_record("接纳%d名流民。" % pending.visitors)
			else:
				_record("婉拒%d名流民。" % pending.visitors)
			_state.pending = {}
		"harvest_farm":
			var collected: Dictionary = _farm.collect()
			if int(collected.food) <= 0:
				return _reply(false, "农田里没有成熟的粮食。")
			_state.food += int(collected.food)
			_record("收割%d批，粮仓+%d。" % [collected.batches, collected.food])
		"assist_farm":
			var source = args.get("source", "click")
			if not source is String or not (source in ["click", "typing"]):
				return _reply(false, "无效加速来源。")
			var count = args.get("count", 1)
			if not _integer(count, 1, 1000000):
				return _reply(false, "无效加速次数。")
			var blocked: bool = _state.ended or not _state.pending.is_empty() or _home() <= 0
			var assisted: Dictionary = _farm.apply_activity(source, int(count), _batch_food(), blocked)
			if not assisted.ok:
				return _reply(false, assisted.message)
			if int(assisted.applied_points) == 0:
				return _reply(false, "本月加速额度已用完，或农田已满。")
			return _reply(true, "助耕：生长进度推进。")
		"unlock_skill":
			var tree = args.get("tree")
			var node = args.get("node")
			if not tree is String or not node is String:
				return _reply(false, "参数无效。")
			var unlocked: Dictionary = _skills.unlock(tree, node, _earned_points(tree))
			if not unlocked.ok:
				return _reply(false, unlocked.message)
			_record("研究完成：" + str(unlocked.message))
		"dispatch":
			var problem: String = dispatch_problem(args)
			if not problem.is_empty():
				return _reply(false, problem)
			var troops: int = int(args.troops)
			_state.food -= troops
			_state.wood -= _skills.expedition_wood_cost(troops, 1)
			_state.expedition = {"site": args.site, "mode": args.mode, "troops": troops,
				"initial_troops": troops, "attack": _skills.expedition_attack(2 + int(_state.forge)), "room": 0,
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
	var wood_cost: int = _skills.expedition_wood_cost(int(args.troops), 1)
	if _state.food < args.troops or _state.wood < wood_cost:
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
	var home: int = _home()
	var batch_food: int = _batch_food()
	var natural_work: int = _skills.natural_growth_points(FarmBuffer.FULL_BATCH)
	var demand: int = int(_state.population)
	var wood_gain: int = _skills.wood_production(home, B.WOOD_PER_PERSON)

	# 1. 农田自然生长：进入待收区，不进粮仓
	if home > 0:
		_farm.grow_naturally(natural_work, batch_food, false)

	# 2. 只从粮仓扣口粮
	var available: int = int(_state.food)
	var shortfall: int = maxi(0, demand - available)
	_state.food = maxi(0, available - demand)
	_state.wood += wood_gain
	var fv: Dictionary = _farm.view()
	_record("结算：粮仓%d，待收%d批/%d，每批%d，需求%d，缺口%d；木材+%d。" % [int(_state.food), fv.ready_batches, fv.ready_food, batch_food, demand, shortfall, wood_gain])

	if shortfall > 0:
		var loss: int = mini(int(_state.population), int(ceil(shortfall / 2.0)))
		var away_loss: int = maxi(0, loss - _home())
		_state.population -= loss
		_state.deaths.starvation += loss
		if not _state.expedition.is_empty():
			_state.expedition.troops -= away_loss
		_record("饥饿造成%d人死亡，其中远征队%d人。%s" % [loss, away_loss, ("粮食还在农田，请先收获。" if int(fv.ready_food) > 0 else "")])
		if not _state.expedition.is_empty() and _state.expedition.troops == 0:
			_return_expedition("饥饿覆灭")

	_state.months += 1
	_farm.begin_month(int(_state.months))
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

func _valid_base(s: Dictionary, skills) -> bool:
	if not s is Dictionary:
		return false
	for key in B.INITIAL:
		if not _integer(s.get(key)):
			return false
	if not _integer(s.get("housing_level"), 1, 100000):
		return false
	if s.population > skills.housing_capacity(int(s.housing)) or s.agriculture < 1 or s.forge > B.FORGE_MAX_LEVEL:
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
		if not _integer(e.get("troops"), 1, int(s.population)) or not _integer(e.get("initial_troops"), int(e.troops)):
			return false
		if not _integer(e.get("attack"), 2, 2 + B.FORGE_MAX_LEVEL + 2):
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
	if not value is Dictionary:
		return false
	var farm_snapshot = value.get("farm")
	var skills_snapshot = value.get("skills")
	if not farm_snapshot is Dictionary or not skills_snapshot is Dictionary:
		return false
	var earned: Dictionary = {"farm": int(value.get("agriculture", 0)),
		"housing": int(value.get("housing_level", 0)), "forge": int(value.get("forge", 0))}
	var temp_skills = BuildingSkills.new()
	if not temp_skills.restore(skills_snapshot, earned):
		return false
	var temp_farm = FarmBuffer.new()
	if not temp_farm.restore(farm_snapshot):
		return false
	var base: Dictionary = value.duplicate(true)
	base.erase("farm")
	base.erase("skills")
	if not _valid_base(base, temp_skills):
		return false
	_state = _normalize(base)
	_skills = temp_skills
	_farm = temp_farm
	return true

func import_v3(old: Variant) -> bool:
	if not old is Dictionary:
		return false
	var candidate: Dictionary = old.duplicate(true)
	candidate["housing_level"] = maxi(1, 1 + int(floor((float(candidate.get("housing", 0)) - 14.0) / 6.0)))
	var temp_skills = BuildingSkills.new()
	if not _valid_base(candidate, temp_skills):
		return false
	_state = _normalize(candidate)
	_skills = temp_skills
	_farm = FarmBuffer.new()
	_farm.begin_month(int(_state.months))
	return true
