extends RefCounted
## 任务3 T3-02：内容动作的纯计划接口。
## plan(context, action) 只读 context 深复制，返回 {ok, problem, costs, effects, facts}。
## 不读取文件/时钟、不随机、不修改传入状态；执行与提交由任务2负责。

const Catalog = preload("res://core/content/content_catalog.gd")

var _catalog: RefCounted = null

func _data() -> Dictionary:
	if _catalog == null:
		_catalog = Catalog.new()
	return _catalog.catalog()

func _building(id: String) -> Dictionary:
	for building in _data().get("buildings", []):
		if String((building as Dictionary).get("id", "")) == id:
			return building
	return {}

func _talent(id: String) -> Dictionary:
	for talent in _data().get("talents", []):
		if String((talent as Dictionary).get("id", "")) == id:
			return talent
	return {}

func _event(id: String) -> Dictionary:
	for event in _data().get("events", []):
		if String((event as Dictionary).get("id", "")) == id:
			return event
	return {}

func _tree(tree_id: String) -> Dictionary:
	return _data().get("skills", {}).get("trees", {}).get(tree_id, {})

func _node(tree_id: String, node_id: String) -> Dictionary:
	for node in _tree(tree_id).get("nodes", []):
		if String((node as Dictionary).get("id", "")) == node_id:
			return node
	return {}

func _fail(problem: String, code: String = "") -> Dictionary:
	return {"ok": false, "problem": problem, "problem_code": code, "costs": {}, "effects": [], "facts": []}

func _ok(costs: Dictionary, effects: Array, facts: Array) -> Dictionary:
	return {"ok": true, "problem": "", "problem_code": "", "costs": costs, "effects": effects, "facts": facts}

## 兼容报价入口：quote_content 与 plan 共用同一逻辑。
func quote(context: Dictionary, action: Dictionary) -> Dictionary:
	return plan(context, action)

func plan(context: Dictionary, action: Dictionary) -> Dictionary:
	if typeof(context) != TYPE_DICTIONARY or typeof(action) != TYPE_DICTIONARY:
		return _fail("上下文或动作无效。", "E_BAD_TYPE")
	var kind := String(action.get("kind", ""))
	match kind:
		"construct_building":
			return _plan_construct(context, action)
		"trade_resources":
			return _plan_trade(context, action)
		"recruit_talent":
			return _plan_recruit(context, action)
		"assign_talent":
			return _plan_assign(context, action)
		"unlock_content_skill":
			return _plan_skill(context, action)
		"resolve_event":
			return _plan_event(context, action)
		"set_policy":
			return _plan_policy(context, action)
	return _fail("未知动作类型: %s" % kind, "E_UNKNOWN_ACTION")

func _resources(context: Dictionary) -> Dictionary:
	var resources = context.get("resources", {})
	return resources if typeof(resources) == TYPE_DICTIONARY else {}

func _can_pay(context: Dictionary, costs: Dictionary) -> String:
	var resources := _resources(context)
	for key in costs:
		if key == "points":
			continue
		var have := int(resources.get(key, 0))
		if have < int(costs[key]):
			return "%s 不足（需要 %d，现有 %d）。" % [key, int(costs[key]), have]
	return ""

func _buildings(context: Dictionary) -> Array:
	var list = context.get("buildings", [])
	return list if typeof(list) == TYPE_ARRAY else []

func _plan_construct(context: Dictionary, action: Dictionary) -> Dictionary:
	var building_id := String(action.get("building_id", ""))
	var building := _building(building_id)
	if building.is_empty():
		return _fail("未知建筑: %s" % building_id, "E_UNKNOWN_REF")
	if not bool(building.get("implemented", false)):
		return _fail("该建筑尚为候选，未实现。", "E_NOT_IMPLEMENTED")
	if _buildings(context).has(building_id):
		return _fail("该建筑已经建成。", "E_ALREADY_BUILT")
	var month := int(context.get("month", 0))
	var unlock: Dictionary = building.get("unlock", {})
	if month < int(unlock.get("require_months", 0)):
		return _fail("建造时段未到。", "E_UNLOCK_MONTH")
	var progress: Dictionary = context.get("progress", {})
	for site in unlock.get("require_progress", {}):
		if int(progress.get(site, 0)) < int(unlock.require_progress[site]):
			return _fail("%s 进度不足。" % site, "E_UNLOCK_PROGRESS")
	var have_buildings := _buildings(context)
	for required in unlock.get("require_buildings", []):
		if not have_buildings.has(String(required)):
			return _fail("需要先建造 %s。" % str(required), "E_UNLOCK_BUILDING")
	var costs: Dictionary = (building.get("cost", {}) as Dictionary).duplicate(true)
	var problem := _can_pay(context, costs)
	if not problem.is_empty():
		return _fail(problem, "E_INSUFFICIENT")
	var effects: Array = [{"type": "building_built", "args": {"building_id": building_id}}]
	for effect in building.get("effects", []):
		effects.append((effect as Dictionary).duplicate(true))
	return _ok(costs, effects, ["building_constructed:" + building_id])

func _trade_config(building_id: String) -> Dictionary:
	for effect in _building(building_id).get("effects", []):
		if String((effect as Dictionary).get("type", "")) == "trade_limit":
			return effect.get("args", {})
	return {}

func _plan_trade(context: Dictionary, action: Dictionary) -> Dictionary:
	var building_id := String(action.get("building_id", ""))
	if building_id.is_empty():
		building_id = "trading_post"
	if not _buildings(context).has(building_id):
		return _fail("尚未建成可交易的建筑。", "E_MISSING_BUILDING")
	var config: Dictionary = _trade_config(building_id)
	if config.is_empty():
		return _fail("该建筑没有交易能力。", "E_NO_TRADE")
	var offer := String(action.get("offer_id", ""))
	var quantity: Variant = action.get("quantity", 0)
	if typeof(quantity) != TYPE_INT or int(quantity) <= 0 or int(quantity) > 99:
		return _fail("数量必须是 1-99 的整数。", "E_BAD_RANGE")
	var buy: Dictionary = config.get("buy", {})
	var sell: Dictionary = config.get("sell", {})
	if not buy.has(offer) and not sell.has(offer):
		return _fail("未知交易项: %s" % offer, "E_UNKNOWN_REF")
	var used := int(context.get("trade_used_this_month", 0))
	var limit := int(config.get("monthly_units", 0))
	if used + int(quantity) > limit:
		return _fail("本月交易额度不足（已用 %d/%d）。" % [used, limit], "E_TRADE_LIMIT")
	var fee := float(config.get("fee_percent", 0)) / 100.0
	var costs := {}
	var gains := {}
	if buy.has(offer):
		var pay: Dictionary = buy[offer]
		for resource in pay:
			costs[resource] = int(ceil(float(pay[resource]) * int(quantity) * (1.0 + fee)))
		gains[offer] = int(quantity)
	else:
		var receive: Dictionary = sell[offer]
		costs[offer] = int(quantity)
		for resource in receive:
			gains[resource] = int(floor(float(receive[resource]) * int(quantity) * (1.0 - fee)))
	var arbitrage := _arbitrage_round_trip(buy, sell, fee)
	if not arbitrage.is_empty():
		return _fail("交易配置存在无成本套利: %s" % arbitrage, "E_ARBITRAGE")
	var problem := _can_pay(context, costs)
	if not problem.is_empty():
		return _fail(problem, "E_INSUFFICIENT")
	var effects: Array = []
	for resource in gains:
		effects.append({"type": "resource_delta", "args": {"resource": resource, "amount": int(gains[resource])}})
	for resource in costs:
		effects.append({"type": "resource_delta", "args": {"resource": resource, "amount": -int(costs[resource])}})
	return _ok(costs, effects, ["trade:" + offer + "x" + str(quantity)])

## 检查「卖出 A 得到 B，再用 B 买回 A」是否不亏。
func _arbitrage_round_trip(buy: Dictionary, sell: Dictionary, fee: float) -> String:
	for resource_a in sell:
		var received: Dictionary = sell[resource_a]
		for resource_b in received:
			if not buy.has(resource_b):
				continue
			var back_list: Dictionary = buy[resource_b]
			if not back_list.has(resource_a):
				continue
			var sell_rate := float(received[resource_b]) * (1.0 - fee)
			var buy_rate := float(back_list[resource_a]) * (1.0 + fee)
			if sell_rate >= buy_rate:
				return "%s→%s→%s" % [resource_a, resource_b, resource_a]
	return ""

func _plan_recruit(context: Dictionary, action: Dictionary) -> Dictionary:
	var talent_id := String(action.get("candidate_id", action.get("talent_id", "")))
	var talent := _talent(talent_id)
	if talent.is_empty():
		return _fail("未知人才候选: %s" % talent_id, "E_UNKNOWN_REF")
	if not bool(talent.get("implemented", false)):
		return _fail("该职业尚未实现。", "E_NOT_IMPLEMENTED")
	var talents: Dictionary = context.get("talents", {})
	if typeof(talents) == TYPE_DICTIONARY and talents.has(talent_id):
		return _fail("该人才已在册。", "E_ALREADY_RECRUITED")
	var costs: Dictionary = (talent.get("cost", {}) as Dictionary).duplicate(true)
	var problem := _can_pay(context, costs)
	if not problem.is_empty():
		return _fail(problem, "E_INSUFFICIENT")
	return _ok(costs, [{"type": "event_flag", "args": {"flag": "talent_recruited_" + talent_id}}], ["talent_recruited:" + talent_id])

func _plan_assign(context: Dictionary, action: Dictionary) -> Dictionary:
	var talent_id := String(action.get("talent_id", ""))
	var assignment_id := String(action.get("assignment_id", ""))
	var talent := _talent(talent_id)
	if talent.is_empty():
		return _fail("未知人才: %s" % talent_id, "E_UNKNOWN_REF")
	if not (talent.get("assignments", []) as Array).has(assignment_id):
		return _fail("该人才不能担任 %s。" % assignment_id, "E_BAD_ASSIGNMENT")
	var talents: Dictionary = context.get("talents", {})
	if not talents.has(talent_id):
		return _fail("该人才不在册。", "E_NOT_RECRUITED")
	var record: Dictionary = talents[talent_id]
	if bool(record.get("dead", false)):
		return _fail("该人才已经去世。", "E_DEAD")
	var assignments: Dictionary = context.get("assignments", {})
	for other_id in assignments:
		if String(assignments[other_id]) == assignment_id:
			if String(other_id) == talent_id:
				return _fail("该人才已在该岗位。", "E_ALREADY_ASSIGNED")
			return _fail("岗位 %s 已被占用。" % assignment_id, "E_SLOT_TAKEN")
	if int(record.get("garrison", 0)) > 0 and assignment_id == "expedition_general":
		return _fail("驻军中的人才不能同时出征。", "E_CONFLICT")
	return _ok({}, [{"type": "talent_assign", "args": {"talent_id": talent_id, "assignment_id": assignment_id}}], ["talent_assigned:%s:%s" % [talent_id, assignment_id]])

func _plan_skill(context: Dictionary, action: Dictionary) -> Dictionary:
	var tree_id := String(action.get("tree_id", ""))
	var node_id := String(action.get("node_id", ""))
	var node := _node(tree_id, node_id)
	if node.is_empty():
		return _fail("未知技能节点: %s" % node_id, "E_UNKNOWN_REF")
	var unlocked: Dictionary = context.get("unlocked_skills", {})
	var have: Array = unlocked.get(tree_id, []) if typeof(unlocked) == TYPE_DICTIONARY else []
	if have.has(node_id):
		return _fail("该节点已解锁。", "E_ALREADY_UNLOCKED")
	for prerequisite in node.get("requires", []):
		if not have.has(String(prerequisite)):
			return _fail("需要先解锁前置: %s。" % str(prerequisite), "E_MISSING_PREREQ")
	var costs := (node.get("cost", {}) as Dictionary).duplicate(true)
	var points_available := int((context.get("points", {}) as Dictionary).get(tree_id, 0))
	if int(costs.get("points", 1)) > points_available:
		return _fail("该建筑技能点不足。", "E_NO_POINTS")
	var problem := _can_pay(context, costs)
	if not problem.is_empty():
		return _fail(problem, "E_INSUFFICIENT")
	var effects: Array = [{"type": "skill_unlock", "args": {"tree_id": tree_id, "node_id": node_id, "effect": node.get("effect", {})}}]
	return _ok(costs, effects, ["skill_unlocked:%s/%s" % [tree_id, node_id]])

func _plan_event(context: Dictionary, action: Dictionary) -> Dictionary:
	var event_id := String(action.get("event_id", ""))
	var choice_id := String(action.get("choice_id", ""))
	var event := _event(event_id)
	if event.is_empty():
		return _fail("未知事件: %s" % event_id, "E_UNKNOWN_REF")
	if not (event.get("choices", []) as Array).has(choice_id):
		return _fail("无效选择: %s" % choice_id, "E_BAD_CHOICE")
	var pending: Dictionary = context.get("pending", {})
	if typeof(pending) == TYPE_DICTIONARY and not pending.is_empty() and String(pending.get("id", "")) != event_id:
		return _fail("当前待处理事件不是该事件。", "E_STALE_EVENT")
	return _ok({}, [{"type": "event_flag", "args": {"event_id": event_id, "choice_id": choice_id}}], ["event_resolved:%s:%s" % [event_id, choice_id]])

func _plan_policy(context: Dictionary, action: Dictionary) -> Dictionary:
	var attitude_id := String(action.get("attitude", ""))
	var attitudes: Array = _data().get("policies", {}).get("attitudes", [])
	var found := {}
	for attitude in attitudes:
		if String((attitude as Dictionary).get("id", "")) == attitude_id:
			found = attitude
	if found.is_empty():
		return _fail("未知态度: %s" % attitude_id, "E_UNKNOWN_REF")
	return _ok({}, [{"type": "event_flag", "args": {"policy": "trade", "attitude": attitude_id}}], ["policy_set:trade:" + attitude_id])
