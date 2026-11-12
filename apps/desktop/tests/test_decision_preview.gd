extends SceneTree
## 预览必须只读，并与真正结算共用规则；不把未收获粮食/未来战利品算入粮仓。
const Kingdom = preload("res://core/kingdom.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var game = Kingdom.new()
	var initial: Dictionary = game.snapshot()
	var preview: Dictionary = game.settlement_preview()
	check(preview.food_after == 20 and preview.starvation_losses == 0 and preview.wood_gain == 6, "initial month forecast")
	check(game.refugee_preview().is_empty(), "no visitors means no intake forecast")
	for i in range(10): game.view()
	check(game.snapshot() == initial, "view calls never advance, harvest, log or change quotas")
	game.act("advance_month")
	check(game.snapshot().food == preview.food_after and game.snapshot().wood == 20 + preview.wood_gain, "actual settlement equals preview")
	var refugees: Dictionary = game.refugee_preview()
	check(refugees.event_id == "refugee-m1" and refugees.population_after == 14, "correct pending group preview")
	check(refugees.can_accept and refugees.beds_missing == 0 and refugees.wood_gain == 2, "intake housing and labor benefit")
	check(refugees.rations.demand == 14 and refugees.rations.food_after == 6, "intake increases demand without instantly consuming food")
	check(refugees.after_harvest.food_after == 18, "ready crops only counted in explicit harvest scenario")
	check(not game.settlement_preview().can_advance, "event blocks advance but not forecast")
	game.act("accept_refugees", {"event_id": refugees.event_id})
	check(game.view().wood_production == refugees.wood_after and game.snapshot().food == 20, "acceptance matches economic preview")
	game.act("advance_month")
	check(game.snapshot().food == refugees.rations.food_after, "accepted population pays predicted rations")
	game.act("harvest_farm")
	game.act("advance_month")
	refugees = game.refugee_preview()
	check(refugees.visitors == 6 and refugees.beds_missing == 6 and not refugees.can_accept, "later group correctly needs six beds")
	game.act("build_housing")
	check(game.refugee_preview().can_accept and game.refugee_preview().beds_missing == 0, "housing upgrade immediately changes forecast")
	game.act("reject_refugees", {"event_id": refugees.event_id})
	check(game.refugee_preview().is_empty(), "decision clears preview")

	# 构造同一缺粮状态的两条实际分支：直接推进 vs 先手动收粮。
	var fixture: Dictionary = Kingdom.new().snapshot()
	fixture.food = 2
	fixture.farm.ready = [12]
	var hungry = Kingdom.new()
	var harvested = Kingdom.new()
	check(hungry.import_snapshot(fixture) and harvested.import_snapshot(fixture), "scarcity fixture")
	preview = hungry.settlement_preview()
	check(preview.shortfall == 8 and preview.starvation_losses == 4, "ready crops do not silently feed residents")
	check(preview.after_harvest.shortfall == 0 and preview.after_harvest.food_after == 4, "manual harvest alternative forecast")
	hungry.act("advance_month")
	harvested.act("harvest_farm")
	harvested.act("advance_month")
	check(hungry.snapshot().deaths.starvation == preview.starvation_losses and hungry.snapshot().food == preview.food_after, "direct advance starvation matches")
	check(harvested.snapshot().deaths.starvation == preview.after_harvest.starvation_losses and harvested.snapshot().food == preview.after_harvest.food_after, "harvest then advance matches")

	var army = Kingdom.new()
	army.act("dispatch", {"site": "ruins", "mode": "explore", "troops": 6})
	preview = army.settlement_preview()
	check(preview.battle_pending and preview.demand == 10 and preview.wood_gain == 2, "away soldiers eat but do not produce domestic wood")
	army.act("advance_month")
	refugees = army.refugee_preview()
	check(refugees.wood_before == 2 and refugees.wood_after == 4, "intake forecast respects expedition labor occupancy")
	var ended: Dictionary = Kingdom.new().snapshot()
	ended.population = 0
	ended.ended = true
	check(army.import_snapshot(ended), "ended fixture")
	check(not army.settlement_preview().can_advance and army.settlement_preview().starvation_losses == 0, "ended state never advertises advance")
	print("DECISION PREVIEW TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
