extends RefCounted
## 任务3 T3-02：内容目录（纯数据）与校验器。
## 只读 res://data/content/catalog.json，不修改 Kingdom，不写文件，不使用随机。
## 校验失败返回带稳定错误码的清单，供测试与交付报告使用。

const CATALOG_PATH := "res://data/content/catalog.json"

const REQUIRED_EFFECT_TYPES := [
	"resource_delta", "building_built", "garrison_delta", "talent_assign",
	"skill_unlock", "event_flag", "trade_limit", "monthly_yield",
	"attack_modifier", "risk_modifier", "growth_modifier", "housing_capacity",
]
const SKILL_EFFECT_TYPES := [
	"farm_yield_flat", "drought_percentage_points", "natural_growth_percent",
	"housing_flat", "wood_percent", "attack_flat", "equipment_discount_percent",
	"housing_capacity", "growth_modifier", "monthly_yield", "trade_limit",
	"risk_modifier", "attack_modifier", "skill_unlock",
]
const RESOURCES := ["food", "wood", "ore", "population"]
const LEGACY_SKILL_IDS := [
	"farm_tools", "farm_irrigation", "farm_rotation",
	"housing_beams", "housing_lofts", "housing_cooperation",
	"forge_basics", "forge_blades", "forge_tooling",
]
const PERSONALITIES := ["prudent", "brave", "greedy", "diligent"]
const RECRUIT_SOURCES := ["refugee_event", "trade_event", "expedition_reward"]
const EVENT_CATEGORIES := ["refugees", "talents", "trade", "harvest", "expedition", "outpost"]
const TRIGGER_KEYS := ["min_month", "max_month", "season", "require_building", "require_progress", "require_expedition"]
const SLOT_IDS := ["reserved_1", "reserved_2", "candidate_a", "candidate_b", "candidate_c", "candidate_d"]

var _cache: Dictionary = {}

func catalog() -> Dictionary:
	if _cache.is_empty():
		var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
		if file == null:
			return {}
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			return {}
		_cache = parsed
	return _cache.duplicate(true)

## 返回 {ok, errors:[{code,path,detail}], stats, content_version}
func validate() -> Dictionary:
	return validate_data(catalog())

## 校验任意目录数据（测试用：注入坏 fixture，不写文件）
func validate_data(data: Dictionary) -> Dictionary:
	var errors: Array = []
	if data.is_empty():
		return {"ok": false, "errors": [{"code": "E_CATALOG_UNREADABLE", "path": CATALOG_PATH, "detail": "目录无法读取或不是 JSON 对象"}], "stats": {}, "content_version": ""}
	if not data.has("version") or not _is_int(data.version):
		errors.append(_err("E_MISSING_VERSION", "version", "缺少整数 version"))
	if typeof(data.get("content_version", "")) != TYPE_STRING or String(data.get("content_version", "")).is_empty():
		errors.append(_err("E_MISSING_VERSION", "content_version", "缺少 content_version"))
	_validate_resources(data, errors)
	_validate_buildings(data, errors)
	_validate_talents(data, errors)
	_validate_skills(data, errors)
	_validate_events(data, errors)
	_validate_policies(data, errors)
	var stats := {
		"buildings": (data.get("buildings", []) as Array).size(),
		"talents": (data.get("talents", []) as Array).size(),
		"events": (data.get("events", []) as Array).size(),
		"skill_nodes": _count_skill_nodes(data),
	}
	return {"ok": errors.is_empty(), "errors": errors, "stats": stats, "content_version": String(data.get("content_version", ""))}

func _count_skill_nodes(data: Dictionary) -> int:
	var total := 0
	var trees: Dictionary = data.get("skills", {}).get("trees", {})
	for tree_id in trees:
		total += (trees[tree_id].get("nodes", []) as Array).size()
	return total

func _err(code: String, path: String, detail: String) -> Dictionary:
	return {"code": code, "path": path, "detail": detail}

func _is_int(value) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_equal_approx(value, round(value)))

func _is_num(value) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

func _validate_resources(data: Dictionary, errors: Array) -> void:
	var resources = data.get("resources", null)
	if typeof(resources) != TYPE_ARRAY:
		errors.append(_err("E_MISSING_FIELD", "resources", "resources 必须是数组"))
		return
	for name in resources:
		if typeof(name) != TYPE_STRING or not RESOURCES.has(name):
			errors.append(_err("E_UNKNOWN_RESOURCE", "resources", "未知资源名: %s" % str(name)))
	var effect_types = data.get("effect_types", null)
	if typeof(effect_types) != TYPE_ARRAY:
		errors.append(_err("E_MISSING_FIELD", "effect_types", "effect_types 必须是数组"))
		return
	for name in REQUIRED_EFFECT_TYPES:
		if not (effect_types as Array).has(name):
			errors.append(_err("E_UNKNOWN_EFFECT", "effect_types", "缺少效果类型: %s" % name))

func _validate_buildings(data: Dictionary, errors: Array) -> void:
	var buildings = data.get("buildings", null)
	if typeof(buildings) != TYPE_ARRAY:
		errors.append(_err("E_MISSING_FIELD", "buildings", "buildings 必须是数组"))
		return
	var seen := {}
	for index in buildings.size():
		var building = buildings[index]
		var path := "buildings[%d]" % index
		if typeof(building) != TYPE_DICTIONARY:
			errors.append(_err("E_BAD_TYPE", path, "建筑必须是对象"))
			continue
		var id := String(building.get("id", ""))
		if id.is_empty():
			errors.append(_err("E_MISSING_FIELD", path, "缺少 id"))
		elif seen.has(id):
			errors.append(_err("E_DUP_ID", path, "重复建筑 id: %s" % id))
		else:
			seen[id] = true
		for field in ["name", "slot", "tags"]:
			if not building.has(field):
				errors.append(_err("E_MISSING_FIELD", path, "缺少字段: %s" % field))
		if not SLOT_IDS.has(String(building.get("slot", ""))):
			errors.append(_err("E_BAD_SLOT", path, "未知槽位: %s" % str(building.get("slot", ""))))
		if typeof(building.get("implemented", null)) != TYPE_BOOL:
			errors.append(_err("E_BAD_TYPE", path, "implemented 必须是布尔值"))
		if typeof(building.get("preview_only", null)) != TYPE_BOOL:
			errors.append(_err("E_BAD_TYPE", path, "preview_only 必须是布尔值"))
		_validate_cost(building.get("cost", {}), path + ".cost", errors)
		_validate_effect_list(building.get("effects", []), path + ".effects", errors)

func _validate_cost(cost, path: String, errors: Array) -> void:
	if typeof(cost) != TYPE_DICTIONARY:
		errors.append(_err("E_BAD_TYPE", path, "成本必须是对象"))
		return
	for key in cost:
		if not RESOURCES.has(key) and key != "points":
			errors.append(_err("E_UNKNOWN_RESOURCE", path, "未知资源: %s" % key))
		var value = cost[key]
		if not _is_num(value):
			errors.append(_err("E_BAD_TYPE", path + "." + key, "成本必须是数字"))
		elif float(value) < 0.0:
			errors.append(_err("E_BAD_RANGE", path + "." + key, "成本不能为负"))

func _validate_effect_list(effects, path: String, errors: Array) -> void:
	if typeof(effects) != TYPE_ARRAY:
		errors.append(_err("E_BAD_TYPE", path, "效果必须是数组"))
		return
	for index in effects.size():
		var effect = effects[index]
		var effect_path := "%s[%d]" % [path, index]
		if typeof(effect) != TYPE_DICTIONARY:
			errors.append(_err("E_BAD_TYPE", effect_path, "效果必须是对象"))
			continue
		var type_name := String(effect.get("type", ""))
		if not REQUIRED_EFFECT_TYPES.has(type_name):
			errors.append(_err("E_UNKNOWN_EFFECT", effect_path, "未知效果类型: %s" % type_name))

func _validate_talents(data: Dictionary, errors: Array) -> void:
	var talents = data.get("talents", null)
	if typeof(talents) != TYPE_ARRAY:
		errors.append(_err("E_MISSING_FIELD", "talents", "talents 必须是数组"))
		return
	var seen := {}
	var implemented := 0
	for index in talents.size():
		var talent = talents[index]
		var path := "talents[%d]" % index
		if typeof(talent) != TYPE_DICTIONARY:
			errors.append(_err("E_BAD_TYPE", path, "人才必须是对象"))
			continue
		var id := String(talent.get("id", ""))
		if id.is_empty():
			errors.append(_err("E_MISSING_FIELD", path, "缺少 id"))
		elif seen.has(id):
			errors.append(_err("E_DUP_ID", path, "重复人才 id: %s" % id))
		else:
			seen[id] = true
		if typeof(talent.get("implemented", null)) != TYPE_BOOL:
			errors.append(_err("E_BAD_TYPE", path, "implemented 必须是布尔值"))
		elif talent.implemented == true:
			implemented += 1
		var lifetime = talent.get("lifetime_months", null)
		if not _is_int(lifetime) or int(lifetime) <= 0:
			errors.append(_err("E_BAD_RANGE", path + ".lifetime_months", "寿命必须是正整数"))
		_validate_cost(talent.get("cost", {}), path + ".cost", errors)
		var assignments = talent.get("assignments", null)
		if typeof(assignments) != TYPE_ARRAY or (assignments as Array).is_empty():
			errors.append(_err("E_MISSING_FIELD", path + ".assignments", "需要至少一个委任位"))
		var personalities = talent.get("personalities", null)
		if typeof(personalities) != TYPE_DICTIONARY or (personalities as Dictionary).is_empty():
			errors.append(_err("E_MISSING_FIELD", path + ".personalities", "需要性格配置"))
		else:
			for key in personalities:
				if not PERSONALITIES.has(key):
					errors.append(_err("E_BAD_ENUM", path + ".personalities", "未知性格: %s" % key))
		var sources = talent.get("recruit_sources", null)
		if typeof(sources) != TYPE_ARRAY or (sources as Array).is_empty():
			errors.append(_err("E_MISSING_FIELD", path + ".recruit_sources", "需要招募来源"))
		else:
			for source in sources:
				if not RECRUIT_SOURCES.has(source):
					errors.append(_err("E_BAD_ENUM", path + ".recruit_sources", "未知招募来源: %s" % str(source)))
	if implemented < 2:
		errors.append(_err("E_BAD_RANGE", "talents", "至少需要实现 2 类人才，当前 %d" % implemented))

func _validate_skills(data: Dictionary, errors: Array) -> void:
	var trees = data.get("skills", {}).get("trees", null)
	if typeof(trees) != TYPE_DICTIONARY:
		errors.append(_err("E_MISSING_FIELD", "skills.trees", "skills.trees 必须是对象"))
		return
	var all_ids := {}
	var tree_ids := {}
	for tree_id in trees:
		var tree = trees[tree_id]
		var path := "skills.trees." + String(tree_id)
		if typeof(tree) != TYPE_DICTIONARY:
			errors.append(_err("E_BAD_TYPE", path, "技能树必须是对象"))
			continue
		tree_ids[tree_id] = true
		var nodes = tree.get("nodes", null)
		if typeof(nodes) != TYPE_ARRAY or (nodes as Array).is_empty():
			errors.append(_err("E_MISSING_FIELD", path + ".nodes", "技能树需要节点"))
			continue
		for index in nodes.size():
			var node = nodes[index]
			var node_path := "%s.nodes[%d]" % [path, index]
			if typeof(node) != TYPE_DICTIONARY:
				errors.append(_err("E_BAD_TYPE", node_path, "节点必须是对象"))
				continue
			var node_id := String(node.get("id", ""))
			if node_id.is_empty():
				errors.append(_err("E_MISSING_FIELD", node_path, "缺少 id"))
				continue
			if all_ids.has(node_id):
				errors.append(_err("E_DUP_ID", node_path, "重复节点 id: %s" % node_id))
			all_ids[node_id] = node_id
			var cost = node.get("cost", null)
			if typeof(cost) != TYPE_DICTIONARY:
				errors.append(_err("E_MISSING_FIELD", node_path + ".cost", "需要 cost"))
			else:
				var points = cost.get("points", null)
				if not _is_int(points) or int(points) < 1:
					errors.append(_err("E_BAD_RANGE", node_path + ".cost.points", "点数必须 >= 1"))
				for key in cost:
					if key != "points" and not RESOURCES.has(key):
						errors.append(_err("E_UNKNOWN_RESOURCE", node_path + ".cost", "未知资源: %s" % key))
			var effect = node.get("effect", null)
			if typeof(effect) != TYPE_DICTIONARY:
				errors.append(_err("E_MISSING_FIELD", node_path + ".effect", "需要 effect"))
			elif not SKILL_EFFECT_TYPES.has(String(effect.get("type", ""))):
				errors.append(_err("E_UNKNOWN_EFFECT", node_path + ".effect", "未知技能效果: %s" % str(effect.get("type", ""))))
			var requires = node.get("requires", null)
			if typeof(requires) != TYPE_ARRAY:
				errors.append(_err("E_BAD_TYPE", node_path + ".requires", "requires 必须是数组"))
	# 前置存在性与跨树引用
	for tree_id in trees:
		var nodes = (trees[tree_id] as Dictionary).get("nodes", [])
		for index in (nodes as Array).size():
			var node = nodes[index]
			var node_path := "skills.trees.%s.nodes[%d]" % [tree_id, index]
			for prerequisite in (node.get("requires", []) as Array):
				if not all_ids.has(String(prerequisite)):
					errors.append(_err("E_UNKNOWN_REF", node_path + ".requires", "前置不存在: %s" % str(prerequisite)))
				elif not _node_in_tree(trees, tree_id, String(prerequisite)):
					errors.append(_err("E_UNKNOWN_REF", node_path + ".requires", "前置不在同一棵树: %s" % str(prerequisite)))
	# 循环前置
	for tree_id in trees:
		var nodes = (trees[tree_id] as Dictionary).get("nodes", [])
		var state := {}
		for index in (nodes as Array).size():
			_skill_cycle(String((nodes[index] as Dictionary).get("id", "")), trees, tree_id, state, errors)
	# 旧节点保留
	for legacy_id in LEGACY_SKILL_IDS:
		if not all_ids.has(legacy_id):
			errors.append(_err("E_LEGACY_MISSING", "skills", "旧技能节点缺失: %s" % legacy_id))

func _node_in_tree(trees: Dictionary, tree_id: String, node_id: String) -> bool:
	for node in trees[tree_id].get("nodes", []):
		if String((node as Dictionary).get("id", "")) == node_id:
			return true
	return false

func _skill_cycle(node_id: String, trees: Dictionary, tree_id: String, state: Dictionary, errors: Array) -> void:
	if node_id.is_empty():
		return
	if state.get(node_id, 0) == 1:
		errors.append(_err("E_CYCLE", "skills.trees." + tree_id, "前置存在环: %s" % node_id))
		return
	if state.get(node_id, 0) == 2:
		return
	state[node_id] = 1
	for node in trees[tree_id].get("nodes", []):
		if String((node as Dictionary).get("id", "")) != node_id:
			continue
		for prerequisite in (node.get("requires", []) as Array):
			_skill_cycle(String(prerequisite), trees, tree_id, state, errors)
	state[node_id] = 2

func _validate_events(data: Dictionary, errors: Array) -> void:
	var events = data.get("events", null)
	if typeof(events) != TYPE_ARRAY:
		errors.append(_err("E_MISSING_FIELD", "events", "events 必须是数组"))
		return
	var seen := {}
	var building_ids := {}
	for building in data.get("buildings", []):
		building_ids[String((building as Dictionary).get("id", ""))] = true
	var categories := {}
	for index in events.size():
		var event = events[index]
		var path := "events[%d]" % index
		if typeof(event) != TYPE_DICTIONARY:
			errors.append(_err("E_BAD_TYPE", path, "事件必须是对象"))
			continue
		var id := String(event.get("id", ""))
		if id.is_empty():
			errors.append(_err("E_MISSING_FIELD", path, "缺少 id"))
		elif seen.has(id):
			errors.append(_err("E_DUP_ID", path, "重复事件 id: %s" % id))
		else:
			seen[id] = true
		var category := String(event.get("category", ""))
		if not EVENT_CATEGORIES.has(category):
			errors.append(_err("E_BAD_ENUM", path + ".category", "未知事件类别: %s" % category))
		else:
			categories[category] = int(categories.get(category, 0)) + 1
		var weight = event.get("weight", null)
		if not _is_int(weight) or int(weight) <= 0:
			errors.append(_err("E_BAD_RANGE", path + ".weight", "权重必须为正整数"))
		var repeat_limit = event.get("repeat_limit", null)
		if not _is_int(repeat_limit) or int(repeat_limit) < 1:
			errors.append(_err("E_BAD_RANGE", path + ".repeat_limit", "重复上限必须 >= 1"))
		var deadline = event.get("deadline_months", null)
		if not _is_int(deadline) or int(deadline) < 1:
			errors.append(_err("E_BAD_RANGE", path + ".deadline_months", "期限必须 >= 1 个月"))
		var choices = event.get("choices", null)
		if typeof(choices) != TYPE_ARRAY or (choices as Array).size() < 2:
			errors.append(_err("E_BAD_RANGE", path + ".choices", "至少需要两个选择"))
		else:
			var seen_choices := {}
			for choice in choices:
				if typeof(choice) != TYPE_STRING or String(choice).is_empty():
					errors.append(_err("E_BAD_TYPE", path + ".choices", "选择必须是字符串"))
				elif seen_choices.has(choice):
					errors.append(_err("E_DUP_ID", path + ".choices", "重复选择: %s" % choice))
				else:
					seen_choices[choice] = true
			if not seen_choices.has(String(event.get("default_choice", ""))):
				errors.append(_err("E_UNKNOWN_REF", path + ".default_choice", "默认选择不在 choices 中"))
		var facts = event.get("facts", null)
		if typeof(facts) != TYPE_ARRAY or (facts as Array).is_empty():
			errors.append(_err("E_MISSING_FIELD", path + ".facts", "需要事实输出"))
		var trigger = event.get("trigger", null)
		if typeof(trigger) != TYPE_DICTIONARY:
			errors.append(_err("E_MISSING_FIELD", path + ".trigger", "需要触发条件"))
		else:
			for key in trigger:
				if not TRIGGER_KEYS.has(key):
					errors.append(_err("E_BAD_ENUM", path + ".trigger", "未知触发键: %s" % key))
			if trigger.has("require_building") and not building_ids.has(String(trigger.require_building)):
				errors.append(_err("E_UNKNOWN_REF", path + ".trigger.require_building", "未知建筑: %s" % str(trigger.require_building)))
	if categories.size() < EVENT_CATEGORIES.size():
		errors.append(_err("E_BAD_RANGE", "events", "事件类别不全，缺少: %s" % str(_missing_categories(categories))))

func _missing_categories(categories: Dictionary) -> Array:
	var missing := []
	for category in EVENT_CATEGORIES:
		if int(categories.get(category, 0)) < 2:
			missing.append(category)
	return missing

func _validate_policies(data: Dictionary, errors: Array) -> void:
	var policies = data.get("policies", null)
	if typeof(policies) != TYPE_DICTIONARY:
		errors.append(_err("E_MISSING_FIELD", "policies", "policies 必须是对象"))
		return
	var attitudes = policies.get("attitudes", null)
	if typeof(attitudes) != TYPE_ARRAY or (attitudes as Array).is_empty():
		errors.append(_err("E_MISSING_FIELD", "policies.attitudes", "需要态度配置"))
		return
	var seen := {}
	for index in (attitudes as Array).size():
		var attitude = attitudes[index]
		var path := "policies.attitudes[%d]" % index
		if typeof(attitude) != TYPE_DICTIONARY:
			errors.append(_err("E_BAD_TYPE", path, "态度必须是对象"))
			continue
		var id := String((attitude as Dictionary).get("id", ""))
		if id.is_empty():
			errors.append(_err("E_MISSING_FIELD", path, "缺少 id"))
		elif seen.has(id):
			errors.append(_err("E_DUP_ID", path, "重复态度 id: %s" % id))
		else:
			seen[id] = true
	var defaults = policies.get("defaults", null)
	if typeof(defaults) != TYPE_DICTIONARY:
		errors.append(_err("E_MISSING_FIELD", "policies.defaults", "需要默认值"))
	else:
		for key in defaults:
			if not seen.has(String(defaults[key])):
				errors.append(_err("E_UNKNOWN_REF", "policies.defaults", "默认态度不存在: %s" % str(defaults[key])))
