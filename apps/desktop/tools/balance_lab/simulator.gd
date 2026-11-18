extends RefCounted
## 任务3 T3-03：经营模拟器与重放记录。
## 只通过 Kingdom 的公开 act/snapshot/view 读取与驱动游戏，不访问 _state。
## 输出 CSV/JSONL 与源码指纹，供 T3-04 曲线与 T3-11 长期验证使用。

const Kingdom = preload("res://core/kingdom.gd")

const ROUTES := ["steady_farm", "town_growth", "adventure_mine"]
const HARVEST_MODES := ["monthly", "quarterly"]
const CORE_FILES := [
	"res://core/kingdom.gd",
	"res://core/balance.gd",
	"res://core/building_skills.gd",
	"res://core/farm_buffer.gd",
]
const CHECKPOINTS := [6, 12, 24, 36, 120]

var fingerprint_cache := ""

## 源码指纹：把参与结算的核心脚本拼接后取 SHA-256。
func fingerprint() -> String:
	if not fingerprint_cache.is_empty():
		return fingerprint_cache
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for path in CORE_FILES:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return "unavailable"
		# 行尾归一：LF 与 CRLF 检出必须得到同一指纹
		context.update(file.get_as_text().replace("\r\n", "\n").to_utf8_buffer())
		file.close()
	fingerprint_cache = context.finish().hex_encode()
	return fingerprint_cache

func new_game() -> RefCounted:
	return Kingdom.new()

## 运行一组路线：返回 {route, harvest, months_run, ended, fingerprint, rows, checkpoint}
func run(route: String, harvest_mode: String, months: int = 120, seed_id: String = "") -> Dictionary:
	var game = new_game()
	var rows: Array = []
	var months_run := 0
	var ended := false
	while months_run < months:
		var snapshot: Dictionary = game.snapshot()
		ended = bool(snapshot.get("ended", false))
		if ended:
			break
		# 处理来访事件，否则月份无法推进
		var pending: Dictionary = snapshot.get("pending", {})
		if not pending.is_empty():
			if _resolve_event(game, snapshot, pending):
				rows.append({"month": months_run, "error": "event_resolve_failed:" + String(pending.get("id", ""))})
				break
			continue
		_harvest(game, snapshot, harvest_mode)
		_spend(game, snapshot, route)
		var advanced: Dictionary = game.act("advance_month")
		if not advanced.ok:
			# 万一被拒绝，记录并退出，避免死循环
			rows.append({"month": months_run, "error": String(advanced.get("message", "advance_failed"))})
			break
		months_run += 1
		rows.append(_row(game, months_run, route, harvest_mode, seed_id))
	var last: Dictionary = game.snapshot()
	return {
		"route": route,
		"harvest": harvest_mode,
		"months_run": months_run,
		"ended": bool(last.get("ended", false)),
		"fingerprint": fingerprint(),
		"rows": rows,
		"checkpoint": _checkpoint(rows, last),
	}

var _event_failures: int = 0

## 处理来访事件。返回 true 表示连续失败应中止模拟（防止 while 死循环）。
func _resolve_event(game, snapshot: Dictionary, pending: Dictionary) -> bool:
	var visitors: int = int(pending.get("visitors", 0))
	var view: Dictionary = game.view()
	var room: int = int(view.get("housing_capacity", 0)) - int(snapshot.get("population", 0))
	if visitors > 0 and visitors <= room:
		game.act("accept_refugees", {"event_id": String(pending.get("id", ""))})
	else:
		game.act("reject_refugees", {"event_id": String(pending.get("id", ""))})
	# 事件没被清掉说明处理失败；连续 2 次失败就中止，避免 while 死循环
	if not (game.snapshot().get("pending", {}) as Dictionary).is_empty():
		_event_failures += 1
	else:
		_event_failures = 0
	return _event_failures >= 2

func _harvest(game, snapshot: Dictionary, harvest_mode: String) -> void:
	var view: Dictionary = game.view()
	var ready: int = int((view.get("farm", {}) as Dictionary).get("ready_batches", 0))
	if ready <= 0:
		return
	var month: int = int(snapshot.get("months", 0))
	if harvest_mode == "monthly" or (harvest_mode == "quarterly" and month % 3 == 2):
		game.act("harvest_farm")

func _spend(game, snapshot: Dictionary, route: String) -> void:
	var view: Dictionary = game.view()
	var wood: int = int(snapshot.get("wood", 0))
	var population: int = int(snapshot.get("population", 0))
	var capacity: int = int(view.get("housing_capacity", 0))
	var farm_cost: int = int(view.get("farm_cost", 999))
	var expedition: Dictionary = snapshot.get("expedition", {})
	var progress: Dictionary = snapshot.get("progress", {})
	var forge_cost: Dictionary = view.get("forge_cost", {})
	var forge: int = int(snapshot.get("forge", 0))
	match route:
		"steady_farm":
			if wood >= farm_cost + 10:
				game.act("improve_agriculture")
			elif population + 6 > capacity and wood >= 12:
				game.act("build_housing")
		"town_growth":
			if population + 6 > capacity and wood >= 12:
				game.act("build_housing")
			elif wood >= farm_cost + 30:
				game.act("improve_agriculture")
		"adventure_mine":
			if expedition.is_empty() and population >= 4:
				var site := "ruins"
				if int(progress.get("ruins", 0)) >= 3 and forge >= 1:
					site = "mine"
				var rooms := int(progress.get(site, 0))
				if rooms < 3:
					var mode := "explore" if rooms < 1 else "clear"
					game.act("dispatch", {"site": site, "mode": mode, "troops": maxi(2, population - 1)})
			if forge < 3 and wood >= int(forge_cost.get("wood", 999)) and int(snapshot.get("ore", 0)) >= int(forge_cost.get("ore", 999)):
				game.act("upgrade_forge")
			elif population + 6 > capacity and wood >= 12:
				game.act("build_housing")
			elif wood >= farm_cost + 20:
				game.act("improve_agriculture")

func _row(game, month: int, route: String, harvest_mode: String, seed_id: String) -> Dictionary:
	var snapshot: Dictionary = game.snapshot()
	var view: Dictionary = game.view()
	var farm: Dictionary = view.get("farm", {})
	var expedition: Dictionary = snapshot.get("expedition", {})
	var deaths: Dictionary = snapshot.get("deaths", {})
	var progress: Dictionary = snapshot.get("progress", {})
	return {
		"seed": seed_id,
		"route": route,
		"harvest": harvest_mode,
		"month": month,
		"food": int(snapshot.get("food", 0)),
		"wood": int(snapshot.get("wood", 0)),
		"ore": int(snapshot.get("ore", 0)),
		"population": int(snapshot.get("population", 0)),
		"agriculture": int(snapshot.get("agriculture", 0)),
		"forge": int(snapshot.get("forge", 0)),
		"housing_level": int(snapshot.get("housing_level", 0)),
		"ready_batches": int(farm.get("ready_batches", 0)),
		"ready_food": int(farm.get("ready_food", 0)),
		"expedition_site": String(expedition.get("site", "")),
		"expedition_troops": int(expedition.get("troops", 0)),
		"starved": int(deaths.get("starvation", 0)),
		"battle_deaths": int(deaths.get("battle", 0)),
		"ruins": int(progress.get("ruins", 0)),
		"mine": int(progress.get("mine", 0)),
		"fingerprint": fingerprint().substr(0, 16),
	}

func _checkpoint(rows: Array, last: Dictionary) -> Dictionary:
	var result := {"final": {"months": int(last.get("months", 0)), "population": int(last.get("population", 0)),
		"food": int(last.get("food", 0)), "wood": int(last.get("wood", 0)), "ore": int(last.get("ore", 0)),
		"deaths": last.get("deaths", {}), "progress": last.get("progress", {})}}
	for month in CHECKPOINTS:
		var found := {}
		for row in rows:
			if int((row as Dictionary).get("month", -1)) == month:
				found = row
				break
		if not found.is_empty():
			result["m%d" % month] = {"food": found.food, "wood": found.wood, "population": found.population,
				"agriculture": found.agriculture, "forge": found.forge}
	return result

## 把行数据写成 CSV（覆盖写），返回写入行数；失败返回 -1。
func write_csv(rows: Array, path: String) -> int:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return -1
	if rows.is_empty():
		file.store_line("empty")
		file.close()
		return 0
	var header: Array = (rows[0] as Dictionary).keys()
	file.store_line(",".join(header))
	for row in rows:
		var cells := []
		for key in header:
			cells.append(str((row as Dictionary).get(key, "")))
		file.store_line(",".join(cells))
	file.close()
	return rows.size()

## 把行数据写成 JSONL（每行一个 JSON 对象）。
func write_jsonl(rows: Array, path: String) -> int:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return -1
	for row in rows:
		file.store_line(JSON.stringify(row))
	file.close()
	return rows.size()

## 回放：重放同一路线并对比某个月的快照关键字段，返回差异数组。
func replay_matches(route: String, harvest_mode: String, months: int, expected_row: Dictionary) -> Array:
	var rerun := run(route, harvest_mode, months)
	var diffs: Array = []
	for row in rerun.rows:
		if int(row.month) != int(expected_row.get("month", -1)):
			continue
		for key in ["food", "wood", "ore", "population", "agriculture", "forge"]:
			if int(row.get(key, -1)) != int(expected_row.get(key, -1)):
				diffs.append({"key": key, "replay": row.get(key), "recorded": expected_row.get(key)})
	return diffs
