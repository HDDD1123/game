extends SceneTree
const Kingdom = preload("res://core/kingdom.gd")
const SaveStore = preload("res://core/save_store.gd")
var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func reject_if_pending(game: RefCounted) -> void:
	var event: Dictionary = game.snapshot().pending
	if not event.is_empty():
		check(game.act("reject_refugees", {"event_id": event.id}).ok, "reject pending")

func _initialize() -> void:
	var g = Kingdom.new()
	check(g.snapshot().population == 10 and g.view().farm_cost == 18, "initial config")
	var detached: Dictionary = g.snapshot()
	detached.population = 0
	check(g.snapshot().population == 10, "snapshot isolated")
	g.act("advance_month")
	check(g.snapshot().food == 32 and g.snapshot().wood == 26, "first monthly settlement")
	check(g.snapshot().pending.visitors == 4, "first refugee arrival")
	var frozen: Dictionary = g.snapshot()
	check(not g.act("advance_month").ok and g.snapshot() == frozen, "event pauses all month work")
	check(not g.act("accept_refugees", {"event_id": "wrong"}).ok, "stale event ID")
	check(g.act("accept_refugees", {"event_id": "refugee-m1"}).ok, "accept 4")
	check(not g.act("accept_refugees", {"event_id": "refugee-m1"}).ok and g.snapshot().population == 14, "no duplicate acceptance")
	check(not g.act("dispatch", {"site": "mine", "mode": "explore", "troops": 6}).ok, "mine locked")
	check(not g.act("dispatch", {"site": "ruins", "mode": "clear", "troops": 6}).ok, "entry not cleared")
	check(not g.act("dispatch", {"site": "ruins", "mode": "explore", "troops": 3.5}).ok, "fractional troops rejected")
	check(g.act("dispatch", {"site": "ruins", "mode": "explore", "troops": 12}).ok, "dispatch 12")
	check(g.snapshot().population == 14 and g.view().home_population == 2, "troops occupy labor not remove population")
	g.act("advance_month")
	check(g.snapshot().ore == 0 and g.snapshot().expedition.loot.ore == 3, "loot remains in expedition")
	g.act("advance_month")
	reject_if_pending(g)
	var during: Dictionary = g.snapshot()
	var restored = Kingdom.new()
	check(restored.import_snapshot(JSON.parse_string(JSON.stringify(during))), "in-flight JSON restore")
	g.act("advance_month")
	restored.act("advance_month")
	check(g.snapshot() == restored.snapshot(), "replay identical after restore")
	check(g.snapshot().population == 12 and g.snapshot().ore == 14 and g.snapshot().food == 40 and g.snapshot().wood == 35, "ruins clears with same v02 settlement")
	check(g.act("upgrade_forge").ok and g.view().mine_unlocked, "forge and mine unlock")
	check(g.snapshot().ore == 9 and g.snapshot().wood == 11, "forge costs")

	# 固定日程后的持续来访：36个月实际推进，无改日期。
	var ongoing = Kingdom.new()
	var later_arrivals: Array = []
	for i in range(36):
		check(ongoing.act("advance_month").ok, "long simulation month %d" % i)
		if not ongoing.snapshot().pending.is_empty():
			if ongoing.snapshot().months > 20:
				later_arrivals.append(ongoing.snapshot().months)
			reject_if_pending(ongoing)
	check(later_arrivals == [23, 26, 29, 32, 35], "refugees continue through third year")
	check(ongoing.snapshot().records.size() == 40, "bounded log")
	check(not ongoing.snapshot().ended, "reject-all survival baseline")

	# 构造边界状态，避免为设置极端情况添加正式版作弊按钮。
	var boundary = Kingdom.new()
	var fixture: Dictionary = boundary.snapshot()
	fixture.population = 14
	fixture.food = 2
	check(boundary.import_snapshot(fixture), "exact food fixture")
	boundary.act("advance_month")
	check(boundary.snapshot().food == 0 and boundary.snapshot().deaths.starvation == 0, "exact food does not kill")
	fixture = Kingdom.new().snapshot()
	fixture.population = 28
	fixture.housing = 32
	fixture.food = 12
	fixture.months = 6
	check(boundary.import_snapshot(fixture), "famine fixture")
	boundary.act("advance_month")
	check(boundary.snapshot().population == 23 and not boundary.snapshot().ended, "drought deficit 9 kills 5, can recover")
	fixture = Kingdom.new().snapshot()
	fixture.months = 18
	check(boundary.import_snapshot(fixture) and boundary.view().drought and boundary.view().food_production == 7, "second year drought")
	fixture.months = 21
	check(boundary.import_snapshot(fixture) and not boundary.view().drought and boundary.view().food_production == 12, "second year recovery")
	fixture = Kingdom.new().snapshot()
	fixture.wood = 100
	check(boundary.import_snapshot(fixture), "farm cost fixture")
	boundary.act("improve_agriculture")
	check(boundary.view().farm_cost == 36 and boundary.snapshot().wood == 82, "farm next cost grows")
	boundary.act("improve_agriculture")
	check(boundary.view().farm_cost == 54 and boundary.snapshot().wood == 46, "farm second cost charged")
	var safe_state: Dictionary = boundary.snapshot()
	fixture = safe_state.duplicate(true)
	fixture.population = -1
	check(not boundary.import_snapshot(fixture) and boundary.snapshot() == safe_state, "invalid state atomic reject")
	fixture = safe_state.duplicate(true)
	fixture.pending = {"id": "invented", "month": 0, "visitors": 999}
	check(not boundary.import_snapshot(fixture), "fake event rejected")
	# 重复清理、战败、全灭与待处理事件保存。
	var pending_game = Kingdom.new()
	pending_game.act("advance_month")
	var pending_copy = Kingdom.new()
	check(pending_copy.import_snapshot(JSON.parse_string(JSON.stringify(pending_game.snapshot()))), "pending event JSON restore")
	check(not pending_copy.act("advance_month").ok, "restored pending event still blocks month")
	var raid = Kingdom.new()
	raid.act("advance_month")
	reject_if_pending(raid)
	check(raid.act("dispatch", {"site": "ruins", "mode": "explore", "troops": 6}).ok, "small raid departs")
	check(not raid.act("dispatch", {"site": "ruins", "mode": "explore", "troops": 2}).ok, "only one army")
	raid.act("advance_month")
	raid.act("advance_month")
	check(raid.snapshot().population == 9 and raid.snapshot().ore == 3 and raid.snapshot().expedition.is_empty(), "defeat returns survivors and held loot")
	reject_if_pending(raid)
	check(raid.act("dispatch", {"site": "ruins", "mode": "clear", "troops": 6}).ok, "entry cleaning unlocked")
	raid.act("advance_month")
	check(raid.snapshot().ore == 6 and raid.snapshot().expedition.is_empty(), "entry clear returns after one battle")
	fixture = Kingdom.new().snapshot()
	fixture.population = 20
	fixture.housing = 24
	fixture.food = 100
	fixture.wood = 100
	fixture.forge = 1
	fixture.months = 9
	fixture.progress.ruins = 3
	check(boundary.import_snapshot(fixture), "mine preparation fixture")
	check(boundary.act("dispatch", {"site": "mine", "mode": "explore", "troops": 18}).ok, "mine dispatch")
	for _i in range(3):
		boundary.act("advance_month")
		reject_if_pending(boundary)
	check(boundary.snapshot().progress.mine == 3 and boundary.snapshot().population == 15 and boundary.snapshot().ore == 30, "mine completion and casualties")
	fixture = Kingdom.new().snapshot()
	fixture.population = 2
	fixture.food = 0
	fixture.months = 6
	fixture.progress.ruins = 3
	fixture.forge = 1
	fixture.expedition = {"site": "mine", "mode": "explore", "troops": 2, "initial_troops": 2, "attack": 3, "room": 2, "goal": 3, "loot": {"food": 1, "wood": 2, "ore": 3}}
	check(boundary.import_snapshot(fixture), "starvation and defeat fixture")
	boundary.act("advance_month")
	check(boundary.snapshot().ended and boundary.snapshot().population == 0 and boundary.snapshot().ore == 0, "total loss ends and loses loot")
	check(boundary.snapshot().deaths == {"starvation": 1, "battle": 1}, "separate death causes")
	var ended_state: Dictionary = boundary.snapshot()
	check(not boundary.act("build_housing").ok and not boundary.act("advance_month").ok and boundary.snapshot() == ended_state, "ended state freezes commands")
	check(Kingdom.new().import_snapshot(JSON.parse_string(JSON.stringify(ended_state))), "ended game JSON restore")
	check(boundary.act("restart").ok and boundary.snapshot().population == 10, "restart ended game")

	var store = SaveStore.new()
	var path: String = "user://core-test-save.json"
	check(store.save_game(g, path).ok, "save to disk")
	var saved: Dictionary = g.snapshot()
	g.act("restart")
	check(store.load_game(g, path).ok and g.snapshot() == saved, "disk restore same snapshot")
	check(store.save_game(g, path).ok and FileAccess.file_exists(path + ".bak"), "second save keeps backup")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("not-json")
	file.close()
	check(not store.load_game(g, path).ok and g.snapshot() == saved, "corrupt disk save leaves game intact")
	check(not store.save_game(g, "user://nonexistent-subdirectory/test.json").ok, "unwritable path reports failure")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	print("CORE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
