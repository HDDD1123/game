extends RefCounted
## 单一生长入口、三批待收、手动收获；不读系统键盘、不计离线时间。
## points是整数工作量：10000为一批。时间与日历由Kingdom统一控制。
const FULL_BATCH = 10000
const MAX_BATCHES = 3
const MONTHLY_ACTIVITY_CAP = 2000
const CLICK_POINTS = 500
const TYPING_POINTS = 10
var _progress: int = 0
var _ready: Array = []
var _month: int = 0
var _activity_used: int = 0

func snapshot() -> Dictionary:
	return {"version": 1, "progress": _progress, "ready": _ready.duplicate(),
		"month": _month, "activity_used": _activity_used}

func view() -> Dictionary:
	var total: int = 0
	for amount in _ready:
		total += int(amount)
	return {"progress": _progress, "full_batch": FULL_BATCH,
		"ready_batches": _ready.size(), "ready_food": total,
		"capacity": MAX_BATCHES, "full": _ready.size() == MAX_BATCHES,
		"activity_left": MONTHLY_ACTIVITY_CAP - _activity_used}

func begin_month(month: int) -> bool:
	if month < _month or month < 0:
		return false
	if month > _month:
		_month = month
		_activity_used = 0
	return true

func _grow(points: int, batch_food: int) -> int:
	var used: int = 0
	while used < points and _ready.size() < MAX_BATCHES:
		var step: int = mini(points - used, FULL_BATCH - _progress)
		_progress += step
		used += step
		if _progress == FULL_BATCH:
			_ready.append(batch_food)
			_progress = 0
	return used

func grow_naturally(points: int, batch_food: int, blocked: bool) -> Dictionary:
	if blocked:
		return {"ok": false, "message": "生产已暂停。", "applied_points": 0}
	if points < 0 or points > 100000000 or batch_food < 1 or batch_food > 100000000:
		return {"ok": false, "message": "无效生产参数。", "applied_points": 0}
	var used: int = _grow(points, batch_food)
	return {"ok": true, "applied_points": used, "discarded_points": points - used}

func apply_activity(source: String, count: int, batch_food: int, blocked: bool) -> Dictionary:
	if blocked:
		return {"ok": false, "message": "生产暂停期间不会获得加速。", "applied_points": 0}
	if source not in ["click", "typing"] or count < 1 or count > 1000000 or batch_food < 1 or batch_food > 100000000:
		return {"ok": false, "message": "无效加速参数。", "applied_points": 0}
	var each: int = CLICK_POINTS if source == "click" else TYPING_POINTS
	var requested: int = mini(count * each, MONTHLY_ACTIVITY_CAP - _activity_used)
	var used: int = _grow(requested, batch_food)
	_activity_used += used
	return {"ok": true, "applied_points": used, "activity_left": MONTHLY_ACTIVITY_CAP - _activity_used}

func collect() -> Dictionary:
	var amount: int = int(view().ready_food)
	var batches: int = _ready.size()
	_ready.clear()
	return {"food": amount, "batches": batches}

func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high and float(value) == floor(float(value))

func restore(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1:
		return false
	if not _integer(value.get("progress"), 0, FULL_BATCH - 1) or not _integer(value.get("month"), 0, 100000000):
		return false
	if not _integer(value.get("activity_used"), 0, MONTHLY_ACTIVITY_CAP):
		return false
	if not value.get("ready") is Array or value.ready.size() > MAX_BATCHES:
		return false
	for amount in value.ready:
		if not _integer(amount, 1, 100000000):
			return false
	if value.ready.size() == MAX_BATCHES and value.progress != 0:
		return false
	var amounts: Array = []
	for amount in value.ready:
		amounts.append(int(amount))
	_progress = int(value.progress)
	_month = int(value.month)
	_activity_used = int(value.activity_used)
	_ready = amounts
	return true
