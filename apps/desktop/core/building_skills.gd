extends RefCounted
## 技能规则模块。由Kingdom提供建筑累计获得的点数，UI不能自行发点。
## 已通过 Kingdom 接入 v0.4 主场景。
const TREES = {
	"farm": {"name": "农田", "nodes": [
		{"id": "farm_tools", "name": "精细采收", "description": "每批正常产粮+2，再计算旱季影响。", "requires": [], "effect": "farm_yield_flat", "amount": 2},
		{"id": "farm_irrigation", "name": "灌溉水渠", "description": "旱季产出系数由60%提高至80%。", "requires": ["farm_tools"], "effect": "drought_percentage_points", "amount": 20},
		{"id": "farm_rotation", "name": "轮作耕种", "description": "自然生长速度+10%。", "requires": ["farm_tools"], "effect": "natural_growth_percent", "amount": 10},
	]},
	"housing": {"name": "民居", "nodes": [
		{"id": "housing_beams", "name": "加固屋梁", "description": "王国住房容量+2。", "requires": [], "effect": "housing_flat", "amount": 2},
		{"id": "housing_lofts", "name": "加建阁楼", "description": "王国住房容量再+4。", "requires": ["housing_beams"], "effect": "housing_flat", "amount": 4},
		{"id": "housing_cooperation", "name": "邻里互助", "description": "城内居民木材产出+10%，最终向下取整。", "requires": ["housing_beams"], "effect": "wood_percent", "amount": 10},
	]},
	"forge": {"name": "铁匠铺", "nodes": [
		{"id": "forge_basics", "name": "基础锻造", "description": "以后出发队伍的单兵战力+1。", "requires": [], "effect": "attack_flat", "amount": 1},
		{"id": "forge_blades", "name": "淬火兵刃", "description": "以后出发队伍的单兵战力再+1。", "requires": ["forge_basics"], "effect": "attack_flat", "amount": 1},
		{"id": "forge_tooling", "name": "制式装备", "description": "出征木材费用减少25%，总费用向上取整。", "requires": ["forge_basics"], "effect": "equipment_discount_percent", "amount": 25},
	]},
}
const EFFECT_DEFAULTS = {"farm_yield_flat": 0, "drought_percentage_points": 0,
	"natural_growth_percent": 0, "housing_flat": 0, "wood_percent": 0,
	"attack_flat": 0, "equipment_discount_percent": 0}
var _unlocked: Dictionary = {"farm": [], "housing": [], "forge": []}

func catalog() -> Dictionary:
	var result: Dictionary = TREES.duplicate(true)
	for tree in result.values():
		for node in tree.nodes:
			node["cost"] = 1
			node["max_level"] = 1
	return result

func _node(tree_id: String, node_id: String) -> Dictionary:
	if not TREES.has(tree_id):
		return {}
	for node in TREES[tree_id].nodes:
		if node.id == node_id:
			return node
	return {}

func available_points(tree_id: String, earned_points: int) -> int:
	if not _unlocked.has(tree_id):
		return 0
	return maxi(0, earned_points - _unlocked[tree_id].size())

func unlock_problem(tree_id: String, node_id: String, earned_points: int) -> String:
	var node: Dictionary = _node(tree_id, node_id)
	if node.is_empty():
		return "未知建筑或技能。"
	if node_id in _unlocked[tree_id]:
		return "该技能已经解锁。"
	for prerequisite in node.requires:
		if prerequisite not in _unlocked[tree_id]:
			return "需要先解锁前置技能。"
	if available_points(tree_id, earned_points) < 1:
		return "该建筑的技能点不足。"
	return ""

func unlock(tree_id: String, node_id: String, earned_points: int) -> Dictionary:
	var problem: String = unlock_problem(tree_id, node_id, earned_points)
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	_unlocked[tree_id].append(node_id)
	return {"ok": true, "message": "已解锁：" + _node(tree_id, node_id).name}

func modifiers() -> Dictionary:
	var result: Dictionary = EFFECT_DEFAULTS.duplicate()
	for tree_id in TREES:
		for node_id in _unlocked[tree_id]:
			var node: Dictionary = _node(tree_id, node_id)
			result[node.effect] += node.amount
	return result

func farm_yield(base_food: int, drought_factor: float = 1.0) -> int:
	var effects: Dictionary = modifiers()
	var factor: float = clampf(drought_factor, 0.0, 1.0)
	if factor < 1.0:
		factor = minf(1.0, factor + effects.drought_percentage_points / 100.0)
	return maxi(0, int(floor((base_food + effects.farm_yield_flat) * factor)))

func natural_growth_points(base_points: int) -> int:
	return maxi(0, int(floor(base_points * (100 + modifiers().natural_growth_percent) / 100.0)))

func housing_capacity(base_capacity: int) -> int:
	return base_capacity + int(modifiers().housing_flat)

func wood_production(home_population: int, per_person: float = 0.6) -> int:
	return maxi(0, int(floor(home_population * per_person * (100 + modifiers().wood_percent) / 100.0)))

func expedition_attack(base_attack: int) -> int:
	return base_attack + int(modifiers().attack_flat)

func expedition_wood_cost(troops: int, per_person: int = 1) -> int:
	return maxi(0, int(ceil(troops * per_person * (100 - modifiers().equipment_discount_percent) / 100.0)))

func snapshot() -> Dictionary:
	return {"version": 1, "unlocked": _unlocked.duplicate(true)}

func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high and float(value) == floor(float(value))

func restore(value: Variant, earned_points: Dictionary) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not value.get("unlocked") is Dictionary:
		return false
	if value.unlocked.size() != TREES.size():
		return false
	for tree_id in TREES:
		var nodes = value.unlocked.get(tree_id)
		if not nodes is Array or nodes.size() > TREES[tree_id].nodes.size():
			return false
		if not _integer(earned_points.get(tree_id), 0, 100000000) or nodes.size() > earned_points[tree_id]:
			return false
		var seen: Array = []
		for node_id in nodes:
			if not node_id is String or node_id in seen:
				return false
			var node: Dictionary = _node(tree_id, node_id)
			if node.is_empty():
				return false
			for prerequisite in node.requires:
				if prerequisite not in nodes:
					return false
			seen.append(node_id)
	_unlocked = value.unlocked.duplicate(true)
	return true
