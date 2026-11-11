extends SceneTree
const Skills = preload("res://core/building_skills.gd")
const Farm = preload("res://core/farm_buffer.gd")
var checks: int = 0
var failures: int = 0

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + description)

func _initialize() -> void:
	var skills = Skills.new()
	check(skills.catalog().size() == 3, "three trees")
	for tree in skills.catalog().values():
		check(tree.nodes.size() == 3, "three base nodes per tree")
	check(skills.farm_yield(12) == 12 and skills.farm_yield(12, 0.6) == 7, "no skill base production")
	check(skills.housing_capacity(14) == 14 and skills.expedition_attack(3) == 3, "no skill capacity and attack")
	check(not skills.unlock("forge", "forge_basics", 0).ok, "unbuilt forge has zero points")
	check(not skills.unlock("farm", "farm_irrigation", 3).ok, "prerequisite enforced")
	check(not skills.unlock("farm", "unknown", 3).ok, "unknown node rejected")
	check(skills.unlock("farm", "farm_tools", 1).ok, "spend first farm point")
	check(skills.available_points("farm", 1) == 0 and skills.farm_yield(12) == 14, "point and harvest effect")
	check(not skills.unlock("farm", "farm_tools", 3).ok, "duplicate upgrade rejected")
	check(not skills.unlock("farm", "farm_irrigation", 1).ok, "points insufficient")
	check(skills.unlock("farm", "farm_irrigation", 2).ok, "unlock irrigation")
	check(skills.farm_yield(12, 0.6) == 11, "drought additive percentage points and rounding")
	check(skills.farm_yield(12) == 14, "irrigation does not boost normal months")
	check(skills.unlock("farm", "farm_rotation", 3).ok, "both branches may eventually unlock")
	check(skills.natural_growth_points(10000) == 11000, "rotation changes natural growth")
	for pair in [["housing", "housing_beams"], ["housing", "housing_lofts"], ["housing", "housing_cooperation"], ["forge", "forge_basics"], ["forge", "forge_blades"], ["forge", "forge_tooling"]]:
		check(skills.unlock(pair[0], pair[1], 3).ok, "unlock " + pair[1])
	check(skills.housing_capacity(14) == 20, "housing bonuses derived once")
	check(skills.wood_production(14) == 9, "wood rounds only at the end")
	check(skills.expedition_attack(3) == 5, "forge bonuses")
	check(skills.expedition_wood_cost(5) == 4, "equipment cost rounds up")
	var saved: Dictionary = skills.snapshot()
	var copy = Skills.new()
	check(copy.restore(JSON.parse_string(JSON.stringify(saved)), {"farm": 3, "housing": 3, "forge": 3}), "skill JSON round trip")
	check(copy.modifiers() == skills.modifiers(), "restore does not stack effects")
	var invalid: Dictionary = saved.duplicate(true)
	invalid.unlocked.farm.append("farm_tools")
	check(not copy.restore(invalid, {"farm": 9, "housing": 3, "forge": 3}) and copy.snapshot() == saved, "bad restore leaves skills intact")
	check(not Skills.new().restore(saved, {"farm": 2, "housing": 3, "forge": 3}), "saved spending cannot exceed earned points")
	invalid = {"version": 1, "unlocked": {"farm": ["farm_irrigation"], "housing": [], "forge": []}}
	check(not Skills.new().restore(invalid, {"farm": 3, "housing": 3, "forge": 3}), "saved prerequisites enforced")

	var farm = Farm.new()
	check(farm.view().ready_food == 0 and farm.view().progress == 0, "empty farm")
	check(farm.grow_naturally(10000, 12, false).applied_points == 10000, "one month grows one batch")
	check(farm.view().ready_batches == 1 and farm.view().ready_food == 12, "mature food stays in field")
	check(farm.collect() == {"food": 12, "batches": 1}, "manual harvest")
	check(farm.collect() == {"food": 0, "batches": 0}, "repeat harvest yields nothing")
	farm.grow_naturally(40000, 12, false)
	check(farm.view().full and farm.view().ready_food == 36 and farm.view().progress == 0, "three batch cap freezes growth")
	var full_state: Dictionary = farm.snapshot()
	check(farm.grow_naturally(10000, 12, false).applied_points == 0 and farm.snapshot() == full_state, "no hidden backlog when full")
	check(farm.apply_activity("click", 1, 12, false).applied_points == 0 and farm.snapshot() == full_state, "full field consumes no activity quota")
	farm.collect()
	farm.grow_naturally(100, 12, false)
	check(farm.view().progress == 100 and farm.view().ready_batches == 0, "resume without catch-up")
	var before_pause: Dictionary = farm.snapshot()
	check(not farm.grow_naturally(10000, 12, true).ok and farm.snapshot() == before_pause, "paused natural growth frozen")
	check(not farm.apply_activity("typing", 100, 12, true).ok and farm.snapshot() == before_pause, "paused typing frozen")
	check(not farm.apply_activity("clipboard", 100, 12, false).ok, "unknown input source rejected")
	check(not farm.grow_naturally(-1, 12, false).ok and not farm.apply_activity("typing", -1, 12, false).ok, "negative work rejected")
	check(farm.apply_activity("click", 1, 12, false).applied_points == 500, "click boosts five percent")
	check(farm.apply_activity("typing", 500, 12, false).applied_points == 1500, "typing shares remaining cap")
	check(farm.view().activity_left == 0 and farm.apply_activity("click", 1000, 12, false).applied_points == 0, "activity cannot be spammed beyond twenty percent")
	check(farm.begin_month(0) and farm.view().activity_left == 0, "same month cannot reset cap")
	check(farm.begin_month(1) and farm.view().activity_left == 2000, "new month resets cap")
	check(not farm.begin_month(0), "old month cannot reset cap")
	var snapshot: Dictionary = farm.snapshot()
	var restored = Farm.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(snapshot))) and restored.snapshot() == snapshot, "farm JSON round trip")
	check(restored.grow_naturally(1000, 14, false) == farm.grow_naturally(1000, 14, false) and restored.snapshot() == farm.snapshot(), "same progression after restore")
	var stable: Dictionary = restored.snapshot()
	invalid = stable.duplicate(true)
	invalid.ready = [12, 12, 12, 12]
	check(not restored.restore(invalid) and restored.snapshot() == stable, "oversized buffer rejected atomically")
	invalid = stable.duplicate(true)
	invalid.ready = [12, 12, 12]
	invalid.progress = 1
	check(not restored.restore(invalid), "full buffer cannot hide growth")
	invalid = stable.duplicate(true)
	invalid.progress = 1.5
	check(not restored.restore(invalid), "fractional progress rejected")
	invalid = stable.duplicate(true)
	invalid.activity_used = 2001
	check(not restored.restore(invalid), "invalid bonus quota rejected")
	var yield_lock = Farm.new()
	yield_lock.grow_naturally(10000, 12, false)
	yield_lock.grow_naturally(10000, skills.farm_yield(12), false)
	check(yield_lock.collect().food == 26, "skill upgrade cannot retroactively change a mature batch")
	print("BUILDING MODULE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
