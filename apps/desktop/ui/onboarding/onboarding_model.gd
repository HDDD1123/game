extends RefCounted
## 向导步骤模型（任务4 T4-09）。纯数据/逻辑：决定"现在该说哪一句"，不画 UI、不改世界。
##
## 界面由主UI装配（任务1持有主面板）；本模型只负责：
##   * 按 order 与真实状态选出第一个未看过且条件满足的步骤；
##   * 记录"已看过/已跳过"，支持重看；
##   * 条件缺失一律视为不满足，不猜测玩家状态，也不因为缺少证据而催促。
##
## 步骤数据：res://data/narrative/onboarding.json

const STEPS_PATH := "res://data/narrative/onboarding.json"

var _steps: Array = []
var _seen: Dictionary = {}
var _warnings: Array[String] = []

func _init() -> void:
	_load()

func _load() -> void:
	_steps = []
	_warnings = []
	if not FileAccess.file_exists(STEPS_PATH):
		_warnings.append("向导数据缺失：%s" % STEPS_PATH)
		return
	var file := FileAccess.open(STEPS_PATH, FileAccess.READ)
	if file == null:
		_warnings.append("向导数据无法打开")
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("steps")) != TYPE_ARRAY:
		_warnings.append("向导数据格式不符")
		return
	var raw: Array = parsed["steps"]
	for item: Variant in raw:
		if typeof(item) == TYPE_DICTIONARY and item.has("id"):
			_steps.append(item)
		else:
			_warnings.append("忽略一条缺少 id 的向导步骤")
	_steps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("order", 9999)) < int(b.get("order", 9999)))

## 全部步骤（只读副本，供"重看目录"或设置页列出）。
func all_steps() -> Array:
	return _steps.duplicate(true)

## 下一个应展示的步骤：{step: Dictionary 或 {}, reason: String}。
## 条件缺失、类型不明都当作不满足；全部看过/全不满足时返回空字典。
func next_step(facts: Array = [], counters: Dictionary = {}) -> Dictionary:
	for step: Dictionary in _steps:
		var id := str(step.get("id", ""))
		if _seen.has(id):
			continue
		if _trigger_met(step.get("trigger", {}), facts, counters):
			return {"step": step.duplicate(true), "reason": "trigger-met"}
	return {"step": {}, "reason": "nothing-pending"}

## 标记看过/跳过。只影响这一步，不关闭后续步骤（可逆，见 reset）。
func mark_seen(step_id: String) -> void:
	if not step_id.is_empty():
		_seen[step_id] = true

func is_seen(step_id: String) -> bool:
	return _seen.has(step_id)

## 重看：清空所有"已看过"记录，但不改变世界状态。
func reset() -> void:
	_seen.clear()

func warnings() -> Array[String]:
	return _warnings.duplicate()

func _trigger_met(trigger: Variant, facts: Array, counters: Dictionary) -> bool:
	if typeof(trigger) != TYPE_DICTIONARY:
		return false
	var spec: Dictionary = trigger
	var kind := str(spec.get("kind", ""))
	match kind:
		"always":
			return true
		"fact":
			var fact_type := str(spec.get("fact_type", ""))
			if fact_type.is_empty():
				return false
			var needed := int(spec.get("min_count", 1))
			var found := 0
			for item: Variant in facts:
				if typeof(item) == TYPE_DICTIONARY and str(item.get("type", "")) == fact_type:
					found += 1
			return found >= needed
		"counter":
			var name := str(spec.get("counter", ""))
			if name.is_empty() or not counters.has(name):
				return false
			var value: Variant = counters[name]
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return false
			return _compare(int(value), str(spec.get("op", ">=")), int(spec.get("value", 0)))
		_:
			_warnings.append("未知向导触发类型：%s" % kind)
			return false

func _compare(value: int, op: String, expected: int) -> bool:
	match op:
		"==":
			return value == expected
		"!=":
			return value != expected
		">=":
			return value >= expected
		"<=":
			return value <= expected
		">":
			return value > expected
		"<":
			return value < expected
		_:
			return false
