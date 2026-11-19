extends Node
## 唯一时间驱动（任务2 T2-02）。UI/平台只调用 command/set_block/refresh_after_load，
## 不另建 Timer；连续进度最多每秒 4 次通知，命令结果立即通知。
signal state_changed

const MIN_EMIT_INTERVAL_MS := 250

var _game: RefCounted
var _last_sample_ms := 0
var _last_emit_ms := 0

func attach_game(game: RefCounted) -> void:
	if _game == game:
		return
	_game = game
	_last_sample_ms = Time.get_ticks_msec()
	_last_emit_ms = 0

func command(name: String, args: Dictionary = {}) -> Dictionary:
	if _game == null:
		return {"ok": false, "message": "没有绑定游戏。"}
	var result: Dictionary = _game.act(name, args)
	if bool(result.get("ok", false)):
		state_changed.emit()
		_last_emit_ms = Time.get_ticks_msec()
	return result

func set_block(reason: String, blocked: bool) -> void:
	if _game != null:
		_game.set_time_blocked(reason, blocked)

func refresh_after_load() -> void:
	_last_sample_ms = Time.get_ticks_msec()
	_last_emit_ms = Time.get_ticks_msec()
	state_changed.emit()

func _process(_delta: float) -> void:
	if _game == null:
		return
	var now: int = Time.get_ticks_msec()
	var elapsed: int = now - _last_sample_ms
	if elapsed <= 0:
		return
	_last_sample_ms = now
	if elapsed > 1000:
		return  # 挂起/长卡顿：丢弃该段，不补跑
	if not bool(_game.view().clock.get("running", false)):
		return
	var result: Dictionary = _game.tick(elapsed)
	if bool(result.get("changed", false)):
		_emit_throttled(now)

func _emit_throttled(now: int) -> void:
	if _last_emit_ms == 0 or now - _last_emit_ms >= MIN_EMIT_INTERVAL_MS:
		state_changed.emit()
		_last_emit_ms = now
