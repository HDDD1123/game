extends SceneTree
## 任务3 T3-02：内容目录 schema 与校验器测试。
## 运行：godot --headless --path apps/desktop --script res://tests/task3/test_content_catalog.gd

const Catalog = preload("res://core/content/content_catalog.gd")
const Rules = preload("res://core/content/content_rules.gd")

var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func _codes(result: Dictionary) -> Array:
	var codes := []
	for error in result.get("errors", []):
		codes.append(String((error as Dictionary).get("code", "")))
	return codes

func _has_code(result: Dictionary, code: String) -> bool:
	return _codes(result).has(code)

func _initialize() -> void:
	var catalog := Catalog.new()
	var valid := catalog.validate()
	check(valid.ok, "默认目录校验通过")
	check(valid.errors.is_empty(), "默认目录无错误")
	check(valid.stats.buildings == 6, "6 个建筑候选（含 2 个种子）")
	check(valid.stats.talents == 6, "6 种职业")
	check(valid.stats.skill_nodes == 24, "24 个技能节点")
	check(valid.stats.events == 12, "12 个事件")
	check(valid.content_version == "v0.5-preview-1", "内容版本")

	var data := catalog.catalog()
	check(not data.is_empty(), "目录可读取")
	var tampered: Dictionary = data.duplicate(true)
	tampered.population = 0
	check(not catalog.catalog().has("population"), "catalog() 返回副本，外部修改不污染缓存")

	# 坏 fixture 1：重复建筑 id
	var duplicate: Dictionary = data.duplicate(true)
	duplicate.buildings.append((duplicate.buildings[0] as Dictionary).duplicate(true))
	check(_has_code(catalog.validate_data(duplicate), "E_DUP_ID"), "重复 id 被拒绝")

	# 坏 fixture 2：未知效果类型
	var bad_effect: Dictionary = data.duplicate(true)
	bad_effect.buildings[0].effects.append({"type": "grant_everything", "args": {}})
	check(_has_code(catalog.validate_data(bad_effect), "E_UNKNOWN_EFFECT"), "未知效果类型被拒绝")

	# 坏 fixture 3：未知资源名
	var bad_resource: Dictionary = data.duplicate(true)
	bad_resource.buildings[0].cost["magic"] = 3
	check(_has_code(catalog.validate_data(bad_resource), "E_UNKNOWN_RESOURCE"), "未知资源被拒绝")

	# 坏 fixture 4：前置成环
	var cycle: Dictionary = data.duplicate(true)
	cycle.skills.trees.farm.nodes[0].requires = ["farm_harvest_helper"]
	check(_has_code(catalog.validate_data(cycle), "E_CYCLE"), "循环前置被拒绝")

	# 坏 fixture 5：未知前置引用
	var missing_ref: Dictionary = data.duplicate(true)
	missing_ref.skills.trees.housing.nodes[0].requires = ["not_a_node"]
	check(_has_code(catalog.validate_data(missing_ref), "E_UNKNOWN_REF"), "不存在的引用被拒绝")

	# 坏 fixture 6：删掉旧技能节点
	var legacy: Dictionary = data.duplicate(true)
	var farm_nodes: Array = legacy.skills.trees.farm.nodes
	for index in range(farm_nodes.size() - 1, -1, -1):
		if String(farm_nodes[index].id) == "farm_rotation":
			farm_nodes.remove_at(index)
	check(_has_code(catalog.validate_data(legacy), "E_LEGACY_MISSING"), "旧技能节点缺失被拒绝")

	# 坏 fixture 7：事件只有 1 个选择
	var bad_event: Dictionary = data.duplicate(true)
	bad_event.events[0].choices = ["accept"]
	check(_has_code(catalog.validate_data(bad_event), "E_BAD_RANGE"), "事件选择不足被拒绝")

	# 坏 fixture 8：非法槽位
	var bad_slot: Dictionary = data.duplicate(true)
	bad_slot.buildings[1].slot = "slot_99"
	check(_has_code(catalog.validate_data(bad_slot), "E_BAD_SLOT"), "非法槽位被拒绝")

	_test_rules()

	print("T3-02 content catalog: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _context() -> Dictionary:
	return {
		"month": 6,
		"resources": {"food": 40, "wood": 60, "ore": 12, "population": 12},
		"buildings": [],
		"garrison": 0,
		"talents": {},
		"assignments": {},
		"unlocked_skills": {"farm": [], "housing": [], "forge": [], "trading_post": [], "outpost_camp": []},
		"points": {"farm": 3, "housing": 1, "forge": 0, "trading_post": 1, "outpost_camp": 0},
		"progress": {"ruins": 3, "mine": 0},
		"trade_used_this_month": 0,
		"pending": {},
	}

func _test_rules() -> void:
	var rules := Rules.new()
	var context := _context()
	var frozen: Dictionary = context.duplicate(true)

	# 建造：成功、资源不足、候选未实现、重复建造
	var ok_plan: Dictionary = rules.plan(context, {"kind": "construct_building", "building_id": "trading_post"})
	check(ok_plan.ok and ok_plan.costs.wood == 30 and ok_plan.costs.ore == 6, "商栈建造计划与成本")
	check(ok_plan.facts.has("building_constructed:trading_post"), "建造事实")
	check(context == frozen, "plan 不修改传入 context")

	var poor := _context()
	poor.resources.wood = 5
	var poor_plan: Dictionary = rules.plan(poor, {"kind": "construct_building", "building_id": "trading_post"})
	check(not poor_plan.ok and poor_plan.problem_code == "E_INSUFFICIENT", "资源不足被拒绝")

	var candidate: Dictionary = rules.plan(context, {"kind": "construct_building", "building_id": "granary"})
	check(not candidate.ok and candidate.problem_code == "E_NOT_IMPLEMENTED", "候选建筑不可造")

	var built := _context()
	built.buildings = ["trading_post"]
	var again: Dictionary = rules.plan(built, {"kind": "construct_building", "building_id": "trading_post"})
	check(not again.ok and again.problem_code == "E_ALREADY_BUILT", "重复建造被拒绝")

	# 前哨营地需要清理废墟 3 层
	var no_progress := _context()
	no_progress.progress.ruins = 1
	var blocked: Dictionary = rules.plan(no_progress, {"kind": "construct_building", "building_id": "outpost_camp"})
	check(not blocked.ok and blocked.problem_code == "E_UNLOCK_PROGRESS", "前哨营地需废墟进度")

	# 交易：限额、套利检查、买入成本含手续费
	var trade_ctx := _context()
	trade_ctx.buildings = ["trading_post"]
	var buy: Dictionary = rules.plan(trade_ctx, {"kind": "trade_resources", "building_id": "trading_post", "offer_id": "food", "quantity": 2})
	check(buy.ok and buy.costs.wood == 8, "买 2 粮需要 8 木（3×2×1.2=7.2 向上取整）")
	trade_ctx.trade_used_this_month = 5
	var over: Dictionary = rules.plan(trade_ctx, {"kind": "trade_resources", "building_id": "trading_post", "offer_id": "food", "quantity": 2})
	check(not over.ok and over.problem_code == "E_TRADE_LIMIT", "超出月限额被拒绝")
	var no_building: Dictionary = rules.plan(_context(), {"kind": "trade_resources", "offer_id": "food", "quantity": 1})
	check(not no_building.ok and no_building.problem_code == "E_MISSING_BUILDING", "无商栈不能交易")

	# 人才：招募与委任（死亡者不能委任）
	var recruit: Dictionary = rules.plan(context, {"kind": "recruit_talent", "candidate_id": "steward"})
	check(recruit.ok and recruit.facts.has("talent_recruited:steward"), "农务官可招募")
	var not_impl: Dictionary = rules.plan(context, {"kind": "recruit_talent", "candidate_id": "cook"})
	check(not not_impl.ok and not_impl.problem_code == "E_NOT_IMPLEMENTED", "未实现职业不可招募")
	var assign_ctx := _context()
	assign_ctx.talents = {"steward": {"dead": false, "garrison": 0}}
	var assign: Dictionary = rules.plan(assign_ctx, {"kind": "assign_talent", "talent_id": "steward", "assignment_id": "farm_steward"})
	check(assign.ok and assign.facts.has("talent_assigned:steward:farm_steward"), "委任农务官")
	var dead_ctx := _context()
	dead_ctx.talents = {"steward": {"dead": true, "garrison": 0}}
	var dead: Dictionary = rules.plan(dead_ctx, {"kind": "assign_talent", "talent_id": "steward", "assignment_id": "farm_steward"})
	check(not dead.ok and dead.problem_code == "E_DEAD", "死亡人才不能委任")
	var wrong_slot: Dictionary = rules.plan(assign_ctx, {"kind": "assign_talent", "talent_id": "steward", "assignment_id": "expedition_general"})
	check(not wrong_slot.ok and wrong_slot.problem_code == "E_BAD_ASSIGNMENT", "岗位不匹配被拒绝")

	# 技能：前置、点数、旧节点可解锁
	var no_prereq: Dictionary = rules.plan(context, {"kind": "unlock_content_skill", "tree_id": "farm", "node_id": "farm_irrigation"})
	check(not no_prereq.ok and no_prereq.problem_code == "E_MISSING_PREREQ", "缺少前置被拒绝")
	var legacy_skill: Dictionary = rules.plan(context, {"kind": "unlock_content_skill", "tree_id": "farm", "node_id": "farm_tools"})
	check(legacy_skill.ok and legacy_skill.costs.points == 1, "旧节点仍可解锁")
	var no_points_ctx := _context()
	no_points_ctx.points = {"farm": 0, "housing": 0, "forge": 0, "trading_post": 0, "outpost_camp": 0}
	var no_points: Dictionary = rules.plan(no_points_ctx, {"kind": "unlock_content_skill", "tree_id": "farm", "node_id": "farm_tools"})
	check(not no_points.ok and no_points.problem_code == "E_NO_POINTS", "技能点不足被拒绝")

	# 事件：有效选择 / 过期事件
	var event_plan: Dictionary = rules.plan(context, {"kind": "resolve_event", "event_id": "ev_trade_fair", "choice_id": "trade"})
	check(event_plan.ok and event_plan.facts.has("event_resolved:ev_trade_fair:trade"), "事件选择计划")
	var stale_ctx := _context()
	stale_ctx.pending = {"id": "ev_other"}
	var stale: Dictionary = rules.plan(stale_ctx, {"kind": "resolve_event", "event_id": "ev_trade_fair", "choice_id": "trade"})
	check(not stale.ok and stale.problem_code == "E_STALE_EVENT", "过期事件被拒绝")

	# 报价入口与计划一致
	var quote: Dictionary = rules.quote(context, {"kind": "construct_building", "building_id": "trading_post"})
	check(quote.ok and quote.costs == ok_plan.costs, "quote 与 plan 使用同一逻辑")
