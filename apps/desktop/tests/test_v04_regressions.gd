extends SceneTree
## v0.4 集成回归：预览/实际费用、远征完整生命周期、农田跨月、迁移与坏档。
const Kingdom = preload("res://core/kingdom.gd")
const SaveStore = preload("res://core/save_store.gd")
var checks := 0
var failures := 0
var test_dir := "user://review-005-" + str(Time.get_ticks_usec())

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func settle(game) -> void:
	var pending: Dictionary = game.snapshot().pending
	if not pending.is_empty():
		game.act("reject_refugees", {"event_id": pending.id})
	game.act("harvest_farm")
	game.act("advance_month")

func _initialize() -> void:
	var game = Kingdom.new()
	var original: Dictionary = game.snapshot()
	for key in ["agriculture", "housing_level", "forge", "months"]:
		for bad in [{}, [], "1", null, -1, 1.5]:
			var invalid: Dictionary = original.duplicate(true)
			invalid[key] = bad
			check(not game.import_snapshot(invalid) and game.snapshot() == original, "invalid %s rejected atomically: %s" % [key, str(bad)])
	var invalid: Dictionary = original.duplicate(true)
	invalid.farm.month = 12
	check(not game.import_snapshot(invalid) and game.snapshot() == original, "farm/calendar month mismatch rejected")
	invalid = original.duplicate(true)
	invalid.housing = {}
	check(not game.import_v3(invalid) and game.snapshot() == original, "v3 malformed housing rejected without conversion error")

	var rich: Dictionary = original.duplicate(true)
	rich.food = 1000
	rich.wood = 1000
	rich.ore = 100
	rich.forge = 3
	check(game.import_snapshot(rich), "setup funded kingdom")
	for node in ["forge_basics", "forge_blades", "forge_tooling"]:
		check(game.act("unlock_skill", {"tree": "forge", "node": node}).ok, "unlock " + node)
	var quote: Dictionary = game.expedition_quote(6)
	check(quote.food == 6 and quote.wood == 5 and quote.power == 42, "6 troops use discount and +2 attack skills")
	var before: Dictionary = game.snapshot()
	check(game.act("dispatch", {"site": "ruins", "mode": "explore", "troops": 6}).ok, "dispatch with skill quote")
	check(before.food - game.snapshot().food == quote.food and before.wood - game.snapshot().wood == quote.wood, "charged exactly quoted cost")
	check(game.snapshot().expedition.attack * 6 == quote.power, "actual strength equals preview")
	settle(game)
	check(game.snapshot().ore == 100 and game.snapshot().expedition.loot.ore == 3, "first room loot not yet deposited")
	var clone = Kingdom.new()
	check(clone.import_snapshot(JSON.parse_string(JSON.stringify(game.snapshot()))), "restore in-flight expedition with skills and farm")
	for step in range(2):
		settle(game)
		settle(clone)
		check(game.snapshot() == clone.snapshot(), "saved expedition replays identically, step %d" % step)
	check(game.snapshot().expedition.is_empty() and game.snapshot().ore == 114, "return deposits all three rooms once")
	check(game.snapshot().population == 10 and game.view().mine_unlocked, "survivors never added twice; mine unlocked")
	settle(game)
	check(game.snapshot().ore == 114, "later month does not repeat loot")
	if not game.snapshot().pending.is_empty():
		game.act("reject_refugees", {"event_id": game.snapshot().pending.id})
	check(game.act("dispatch", {"site": "ruins", "mode": "clear", "troops": 6}).ok, "clear explored entrance")
	settle(game)
	check(game.snapshot().expedition.is_empty() and game.snapshot().ore == 117, "clear returns after one room")
	if not game.snapshot().pending.is_empty():
		game.act("reject_refugees", {"event_id": game.snapshot().pending.id})
	check(game.act("dispatch", {"site": "mine", "mode": "explore", "troops": 8}).ok, "unlocked mine accepts expedition")
	for step in range(3): settle(game)
	check(game.snapshot().progress.mine == 3 and game.snapshot().ore == 147, "mine three rooms return thirty ore exactly once")
	check(game.snapshot().expedition.is_empty() and game.snapshot().population == 8, "mine casualties persist on return")

	var weak = Kingdom.new()
	check(weak.act("dispatch", {"site": "ruins", "mode": "explore", "troops": 2}).ok, "weak expedition dispatched")
	weak.act("advance_month")
	check(weak.snapshot().expedition.is_empty() and weak.snapshot().population == 8 and weak.snapshot().ore == 0, "wipeout removes troops and loses loot")
	var starving = Kingdom.new()
	starving.act("dispatch", {"site": "ruins", "mode": "explore", "troops": 9})
	var starved: Dictionary = starving.snapshot()
	starved.food = 0
	check(starving.import_snapshot(starved), "famine with expedition fixture")
	starving.act("advance_month")
	check(starving.snapshot().deaths.starvation == 5 and starving.snapshot().expedition.troops == 5, "famine removes home resident then four soldiers before battle")

	var farming = Kingdom.new()
	var field: Dictionary = farming.snapshot()
	field.food = 1000
	check(farming.import_snapshot(field), "buffer fixture")
	for month in range(4):
		var p: Dictionary = farming.snapshot().pending
		if not p.is_empty(): farming.act("reject_refugees", {"event_id": p.id})
		farming.act("advance_month")
	check(farming.view().farm.ready_batches == 3 and farming.view().farm.ready_food == 36 and farming.snapshot().food == 960, "full field stops at three batches; warehouse pays only")
	farming.act("harvest_farm")
	check(farming.snapshot().food == 996, "manual collection deposits exactly three batches")
	farming.act("assist_farm", {"source": "typing", "count": 1000})
	check(farming.view().farm.activity_left == 0 and farming.view().farm.progress == 2000, "typing bounded by shared monthly quota")
	farming.act("advance_month")
	check(farming.view().farm.activity_left == 2000, "calendar resets assist quota once")

	DirAccess.make_dir_recursive_absolute(test_dir)
	var store = SaveStore.new()
	store.primary_path = test_dir + "/v4.json"
	store.legacy_path = test_dir + "/v3.json"
	var old: Dictionary = rich.duplicate(true)
	for key in ["farm", "skills", "housing_level"]: old.erase(key)
	old.housing = 26
	write_json(store.legacy_path, {"version": 3, "state": old})
	var old_text := FileAccess.get_file_as_string(store.legacy_path)
	var migrated = Kingdom.new()
	check(store.load_game(migrated).ok and migrated.snapshot().housing_level == 3, "v3-only file migrates building points")
	check(migrated.snapshot().food == 1000 and migrated.view().farm.ready_batches == 0, "migration never generates historical harvest")
	check(FileAccess.get_file_as_string(store.legacy_path) == old_text, "migration preserves original v3 file")
	var safe: Dictionary = migrated.snapshot()
	check(not store.load_game(migrated, test_dir + "/missing.json").ok and migrated.snapshot() == safe, "explicit missing file never falls back to old default")
	check(store.save_game(game).ok, "save current v4 beside v3")
	check(store.load_game(migrated).ok and migrated.snapshot() == game.snapshot(), "v4 preferred over old v3")
	safe = migrated.snapshot()
	write_json(store.primary_path, {"version": 4, "state": {"agriculture": {}}})
	check(not store.load_game(migrated).ok and migrated.snapshot() == safe, "corrupt v4 never silently reverts to v3")
	DirAccess.remove_absolute(store.primary_path)
	write_json(store.legacy_path, {"version": 3, "state": {"housing": []}})
	check(not store.load_game(migrated).ok and migrated.snapshot() == safe, "corrupt v3 leaves all live state intact")
	for file in DirAccess.get_files_at(test_dir): DirAccess.remove_absolute(test_dir + "/" + file)
	DirAccess.remove_absolute(test_dir)
	print("V04 REGRESSIONS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
