extends SceneTree
## 任务2 T2-02/T2-03/T2-04：在线时钟、连续生长、暂停/阻塞、月界、格式5 往返与迁移。
const Kingdom = preload("res://core/kingdom.gd")
const SaveStore = preload("res://core/save_store.gd")
var checks: int = 0
var failures: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var g = Kingdom.new()
	check(g.view().clock.running == false, "新局自动时间关闭")
	check(g.view().clock.can_step, "新局可手动推进")
	check(int(g.view().clock.month_elapsed_ms) == 0, "时钟从0开始")
	check(g.act("set_auto_running", {"enabled": true}).ok, "开启自动时间")
	check(g.view().clock.running, "自动时间运行中")
	check(not g.view().clock.can_step, "自动运行禁止手动跳月")
	check(not g.act("advance_month").ok, "自动运行时手动推进被拒绝")
	check(not g.tick(1001).ok, "tick 超过1000被拒绝")
	check(not g.tick(-1).ok, "负 tick 被拒绝")
	g.tick(400)
	check(int(g.view().clock.month_elapsed_ms) == 400, "tick 累计400ms")
	check(int(g.view().clock.month_progress * 150000.0) == 400, "进度与毫秒一致")

	# 月界 149999 -> 150000
	var b = Kingdom.new()
	b.act("set_auto_running", {"enabled": true})
	for i in range(149):
		b.tick(1000)
	check(int(b.view().clock.month_elapsed_ms) == 149000, "149000ms")
	b.tick(999)
	check(int(b.view().clock.month_elapsed_ms) == 149999 and int(b.snapshot().months) == 0, "149999不结算")
	b.tick(1)
	check(int(b.snapshot().months) == 1, "150000结算一月")
	check(int(b.view().farm.ready_batches) == 1, "一月产生1批")
	check(int(b.view().clock.month_elapsed_ms) == 0, "结算后时钟归零")

	# 自动关闭时 tick 不推进
	var p = Kingdom.new()
	p.tick(1000)
	check(int(p.view().clock.month_elapsed_ms) == 0, "自动关闭时 tick 无效")

	# 外部阻塞
	var e = Kingdom.new()
	e.act("set_auto_running", {"enabled": true})
	e.act("set_time_blocked", {"reason": "exit", "blocked": true})
	e.tick(1000)
	check(int(e.view().clock.month_elapsed_ms) == 0, "外部阻塞停止时间")
	check(e.view().clock.pause_reasons.has("external:exit"), "阻塞原因可见")
	e.act("set_time_blocked", {"reason": "exit", "blocked": false})
	e.tick(1000)
	check(int(e.view().clock.month_elapsed_ms) == 1000, "解除阻塞后恢复")

	# 事件暂停
	var ev = Kingdom.new()
	ev.act("set_auto_running", {"enabled": true})
	for i in range(150):
		ev.tick(1000)
	check(int(ev.snapshot().months) == 1 and not ev.snapshot().pending.is_empty(), "一月后出现待决事件")
	ev.tick(1000)
	check(int(ev.view().clock.month_elapsed_ms) == 0, "事件期间时间停止")
	check(ev.view().clock.pause_reasons.has("event"), "事件原因可见")

	# 手动推进（自动关闭）
	var m = Kingdom.new()
	check(m.act("advance_month").ok, "手动推进成功")
	check(int(m.snapshot().months) == 1 and int(m.view().farm.ready_batches) == 1, "手动推进同样产生1批")

	# 格式5 往返
	var s = Kingdom.new()
	s.act("set_auto_running", {"enabled": true})
	for i in range(5):
		s.tick(1000)
	var store = SaveStore.new()
	var path := "user://task2-clock-test.json"
	var saved := s.snapshot()
	check(store.save_game(s, path).ok, "保存格式5")
	var loaded = Kingdom.new()
	check(store.load_game(loaded, path).ok, "读取格式5")
	check(int(loaded.view().clock.month_elapsed_ms) == 5000, "时钟恢复")
	check(loaded.snapshot().farm == saved.farm, "农田恢复")
	check(loaded.view().clock.running == false, "读档后自动时间关闭")

	# 格式4 迁移（无 clock）
	var v4_state: Dictionary = s.snapshot()
	v4_state.erase("clock")
	var v4_path := "user://task2-v4-test.json"
	var f := FileAccess.open(v4_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 4, "state": v4_state}))
	f.close()
	var loaded4 = Kingdom.new()
	check(store.load_game(loaded4, v4_path).ok, "格式4可迁移")
	check(int(loaded4.view().clock.month_elapsed_ms) == 0, "格式4时钟置0")

	# 较新文件损坏不能回退旧档
	var bad := "user://task2-bad-test.json"
	f = FileAccess.open(bad, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 5, "state": {"months": "x"}}))
	f.close()
	var before: Dictionary = loaded.snapshot()
	check(not store.load_game(loaded, bad).ok and loaded.snapshot() == before, "坏格式5被拒绝且当前局不变")

	for p2 in [path, v4_path, bad, path + ".bak", path + ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p2))

	print("TASK2 CLOCK TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
