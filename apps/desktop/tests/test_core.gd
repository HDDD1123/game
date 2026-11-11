extends SceneTree
## 任务005：粮食模型从“每月自动入库”改为“农田待收 + 手动收获”。
## 基础流程按新粮食模型验证；远征完整生命周期、迁移组合与损坏字段见 test_v04_regressions.gd。
const Kingdom = preload("res://core/kingdom.gd")
const SaveStore = preload("res://core/save_store.gd")
var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var g = Kingdom.new()
	check(g.snapshot().population == 10 and g.view().farm_cost == 18, "initial config")
	check(g.snapshot().food == 30 and g.view().farm.ready_batches == 0, "initial granary, empty field")
	var detached: Dictionary = g.snapshot()
	detached.population = 0
	check(g.snapshot().population == 10, "snapshot isolated")

	g.act("advance_month")
	check(g.snapshot().food == 20 and g.snapshot().wood == 26, "settlement: granary pays food")
	check(g.view().farm.ready_food == 12 and g.view().farm.ready_batches == 1, "first batch stays in field")
	check(g.snapshot().pending.visitors == 4, "first refugee arrival")

	var frozen: Dictionary = g.snapshot()
	check(not g.act("advance_month").ok and g.snapshot() == frozen, "event pauses month")
	check(not g.act("assist_farm", {"source": "click", "count": 1}).ok and g.snapshot() == frozen, "pause blocks boost")

	check(g.act("harvest_farm").ok and g.snapshot().food == 32, "harvest during pause")
	check(g.view().farm.ready_food == 0, "field emptied")
	var harvested: Dictionary = g.snapshot()
	check(not g.act("harvest_farm").ok and g.snapshot() == harvested, "repeat harvest no double food")

	check(not g.act("accept_refugees", {"event_id": "wrong"}).ok, "stale event ID")
	check(g.act("accept_refugees", {"event_id": "refugee-m1"}).ok, "accept 4")
	check(not g.act("accept_refugees", {"event_id": "refugee-m1"}).ok and g.snapshot().population == 14, "no duplicate acceptance")

	g.act("advance_month")
	check(g.snapshot().food == 18 and g.snapshot().wood == 34, "second settlement")
	check(g.view().farm.ready_food == 12, "second batch pending")

	check(not g.act("dispatch", {"site": "mine", "mode": "explore", "troops": 6}).ok, "mine locked")
	check(not g.act("dispatch", {"site": "ruins", "mode": "clear", "troops": 6}).ok, "entry not cleared")
	check(not g.act("dispatch", {"site": "ruins", "mode": "explore", "troops": 3.5}).ok, "fractional troops rejected")

	# 长期推进：每月收获 + 拒绝流民，验证持续来访与生存
	var ongoing = Kingdom.new()
	var later: Array = []
	for i in range(36):
		ongoing.act("advance_month")
		var pend: Dictionary = ongoing.snapshot().pending
		if not pend.is_empty():
			if ongoing.snapshot().months > 20:
				later.append(ongoing.snapshot().months)
			ongoing.act("reject_refugees", {"event_id": pend.id})
		ongoing.act("harvest_farm")
	check(later == [23, 26, 29, 32, 35], "recurring refugees through third year")
	check(not ongoing.snapshot().ended and ongoing.snapshot().population == 10, "reject-all survival with harvest")
	check(ongoing.snapshot().records.size() <= 40, "bounded log")

	# 远征：战利品先留在队伍，归来才入库
	var raid = Kingdom.new()
	raid.act("advance_month")
	raid.act("accept_refugees", {"event_id": "refugee-m1"})
	raid.act("harvest_farm")
	check(raid.act("dispatch", {"site": "ruins", "mode": "explore", "troops": 12}).ok, "dispatch 12")
	raid.act("advance_month")
	check(raid.snapshot().expedition.loot.ore == 3, "loot stays in expedition")
	check(raid.snapshot().ore == 0, "granary ore not yet updated")

	# 存档 v4 往返与损坏保护
	var store = SaveStore.new()
	var path: String = "user://core-test-save.json"
	var snap: Dictionary = g.snapshot()
	check(store.save_game(g, path).ok, "save v4")
	var loaded = Kingdom.new()
	check(store.load_game(loaded, path).ok and loaded.snapshot() == snap, "load v4 identical")
	check(store.save_game(g, path).ok and FileAccess.file_exists(path + ".bak"), "second save keeps backup")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("not-json")
	file.close()
	var before_bad: Dictionary = loaded.snapshot()
	check(not store.load_game(loaded, path).ok and loaded.snapshot() == before_bad, "corrupt save leaves game intact")
	check(not store.save_game(g, "user://nonexistent-subdirectory/test.json").ok, "unwritable path reports failure")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)

	# 结束状态冻结与重新开始
	var ending = Kingdom.new()
	var fixture: Dictionary = ending.snapshot()
	fixture.population = 0
	fixture.ended = true
	fixture.pending = {}
	fixture.expedition = {}
	check(ending.import_snapshot(fixture), "ended fixture import")
	check(not ending.act("advance_month").ok and not ending.act("build_housing").ok, "ended state freezes commands")
	check(ending.act("restart").ok and ending.snapshot().population == 10 and ending.view().farm.ready_food == 0, "restart resets field and modules")

	# 边界：粮仓刚好够，无缺口；待收不应被计为库存
	var boundary = Kingdom.new()
	fixture = boundary.snapshot()
	fixture.population = 14
	fixture.food = 14
	fixture.housing = 14
	check(boundary.import_snapshot(fixture), "exact food fixture")
	boundary.act("advance_month")
	check(boundary.snapshot().food == 0 and boundary.snapshot().deaths.starvation == 0, "exact food does not kill")
	check(boundary.view().farm.ready_food == 12, "exact food still grows pending batch")

	# 无效状态原子拒绝
	var safe: Dictionary = boundary.snapshot()
	fixture = safe.duplicate(true)
	fixture.population = -1
	check(not boundary.import_snapshot(fixture) and boundary.snapshot() == safe, "invalid state atomic reject")
	fixture = safe.duplicate(true)
	fixture.pending = {"id": "invented", "month": 0, "visitors": 999}
	check(not boundary.import_snapshot(fixture), "fake event rejected")
	fixture = safe.duplicate(true)
	fixture.farm.progress = 1.5
	check(not boundary.import_snapshot(fixture), "fractional farm progress rejected")

	# 旧格式3迁移（构造一个 v3 状态）
	var v3 = Kingdom.new()
	var old_state: Dictionary = v3.snapshot()
	old_state.erase("farm")
	old_state.erase("skills")
	old_state.erase("housing_level")
	check(v3.import_v3(old_state), "v3 migration accepted")
	check(v3.snapshot().housing_level == 1 and v3.view().farm.ready_batches == 0, "v3 migration defaults")
	check(not v3.import_v3({"population": -5}), "v3 invalid rejected")

	print("CORE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
