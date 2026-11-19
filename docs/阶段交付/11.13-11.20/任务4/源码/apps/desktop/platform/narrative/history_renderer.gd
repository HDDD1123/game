extends RefCounted
## 史书/结局渲染（任务4 T4-10）。只读事实，产出可展示文本；不改状态、不抽取新事实、不联网。
##
## 接口（docs/四机接口约定.md F 节）：
##   render_history(facts: Array, summary: Dictionary = {}, options: Dictionary = {}) -> Dictionary
##   * facts：任务2提供的结构化 history 事实（type / fact_id / game_month / 其它字段）
##   * summary：至少可带 counters（持久累计，如 expedition_count、months_played）与 ending_reason
##   * options：{"allow_preview": bool}——preview_only 结局只在 fixture 预览时出现
## 返回：
##   {ok, entries, chapters, ending, eligible_endings, fact_counts, used_fallback, warnings}
##
## 原则：
##   * 证据不足用中性叙述；不因为"最近 40 条日志里没有"就断言"历史上从未发生"。
##   * 随机只发生在同义 variants 之间，且按事实内容做确定性索引：同输入同输出，便于复盘与测试。
##   * 结局由 data/narrative/endings.json 的 requires 判定，多个满足取 priority 最小者。
##   * preview_only 条目默认不出现（主动隐退/跨局继承本轮未实现，正式界面不得有假入口）。

const ENDINGS_PATH := "res://data/narrative/endings.json"
const HANDBOOK_PATH := "res://data/narrative/handbook.json"

## 渲染器内置的最小标签；章节与文案仍由 data/narrative 维护。
const FACT_LABELS := {
	"expedition_departed": "派出远征",
	"expedition_returned": "远征归来",
	"expedition_failed": "远征失利",
	"casualty": "出现伤亡",
	"construction_completed": "建成建筑",
	"talent_recruited": "招募人才",
	"talent_died": "人才离世",
	"event_choice": "处理事件",
	"stronghold_gained": "取得据点",
	"stronghold_lost": "失去据点",
	"milestone_achieved": "达成里程碑",
	"harvest_summary": "收成记录",
	"starvation": "出现饥荒",
	"ending": "本局结束",
}

const DETAIL_FIELDS := [
	"destination_id", "site_id", "building_id", "talent_id", "general_id",
	"event_id", "choice_id", "cause", "reason", "severity", "amount", "losses",
]

const NEUTRAL_ENDING := {
	"id": "neutral_insufficient",
	"title": "手记的最后一页",
	"paragraphs": ["这一局的记录不足以下结论：手记只写下已经确认过的事，没有写下的不作推断。"],
}

var _warnings: Array[String] = []

func render_history(facts: Array, summary: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	_warnings = []
	var counts := _count_facts(facts)
	var counters := _counters(summary)
	var entries := _build_entries(facts)
	var chapters := _build_chapters(entries, counts)
	# 没有任何事实/计数时不下结论：否则"没记录"会被 fact_absent 类模板当成"中途退出"的证据。
	var has_evidence: bool = not facts.is_empty() or not counters.is_empty()
	var eligible: Array = _eligible_endings(counts, counters, facts, bool(options.get("allow_preview", false))) if has_evidence else []
	var selected: Dictionary = {}
	if eligible.is_empty():
		selected = _neutral_ending()
	else:
		selected = _render_ending(eligible[0]["ending"], _seed_text(counts, counters))
	var ids: Array[String] = []
	for item: Dictionary in eligible:
		ids.append(str(item["id"]))
	return {
		"ok": true,
		"entries": entries,
		"chapters": chapters,
		"ending": selected,
		"eligible_endings": ids,
		"fact_counts": counts,
		"counters": counters,
		"used_fallback": eligible.is_empty(),
		"warnings": _warnings,
	}

# ---------------- 读取数据 ----------------

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_warnings.append("数据文件缺失：%s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_warnings.append("数据文件无法打开：%s" % path)
		return null
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		_warnings.append("数据文件不是合法 JSON：%s" % path)
	return parsed

func _ending_templates() -> Array:
	var parsed: Variant = _read_json(ENDINGS_PATH)
	if typeof(parsed) == TYPE_DICTIONARY and typeof(parsed.get("endings")) == TYPE_ARRAY:
		return parsed["endings"]
	return []

func _handbook() -> Dictionary:
	var parsed: Variant = _read_json(HANDBOOK_PATH)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}

# ---------------- 事实与计数 ----------------

func _count_facts(facts: Array) -> Dictionary:
	var counts := {}
	for item: Variant in facts:
		if typeof(item) != TYPE_DICTIONARY:
			_warnings.append("忽略一条非字典事实")
			continue
		var type := str(item.get("type", ""))
		if type.is_empty():
			_warnings.append("忽略一条缺少 type 的事实")
			continue
		counts[type] = int(counts.get(type, 0)) + 1
	return counts

func _counters(summary: Dictionary) -> Dictionary:
	var raw: Variant = summary.get("counters", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var clean := {}
	for key: Variant in raw.keys():
		var value: Variant = raw[key]
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			clean[str(key)] = int(value)
		else:
			_warnings.append("忽略非数值计数：%s" % str(key))
	return clean

# ---------------- 条目与章节 ----------------

func _build_entries(facts: Array) -> Array:
	var entries: Array = []
	var order := 0
	for item: Variant in facts:
		order += 1
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var fact: Dictionary = item
		var type := str(fact.get("type", ""))
		entries.append({
			"order": order,
			"month": int(fact.get("game_month", -1)),
			"type": type,
			"fact_id": str(fact.get("fact_id", "")),
			"label": str(FACT_LABELS.get(type, type)),
			"detail": _detail(fact),
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["month"] == b["month"]:
			return str(a["fact_id"]) < str(b["fact_id"])
		return a["month"] < b["month"])
	return entries

func _detail(fact: Dictionary) -> String:
	var parts: Array[String] = []
	for key: String in DETAIL_FIELDS:
		if fact.has(key):
			parts.append("%s=%s" % [key, str(fact[key])])
	return "，".join(parts)

## 按 handbook 的 month_range 分段；最后一段吸收更大月份（规则见 handbook.chapter_rule）。
func _build_chapters(entries: Array, counts: Dictionary) -> Array:
	var book := _handbook()
	var raw: Variant = book.get("sections", [])
	var chapters: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return chapters
	var sections: Array = raw
	for index in sections.size():
		var section: Dictionary = sections[index]
		var range_value: Variant = section.get("month_range", [])
		var low := 0
		var high := 999999
		if typeof(range_value) == TYPE_ARRAY and range_value.size() >= 2:
			low = int(range_value[0])
			high = int(range_value[1])
		var is_last := index == sections.size() - 1
		var chapter_entries: Array = []
		for entry: Dictionary in entries:
			var month := int(entry["month"])
			if month >= low and (month <= high or is_last):
				chapter_entries.append(entry)
		var covered: Array[String] = []
		var declared: Variant = section.get("fact_types", [])
		if typeof(declared) == TYPE_ARRAY:
			for type: Variant in declared:
				if counts.has(str(type)):
					covered.append(str(type))
		chapters.append({
			"id": str(section.get("id", "")),
			"title": str(section.get("title", "")),
			"month_range": [low, high],
			"entries": chapter_entries,
			"covered_types": covered,
			"empty_text": "" if not chapter_entries.is_empty() else str(section.get("empty_text", "")),
		})
	return chapters

# ---------------- 结局判定 ----------------

## 返回按 priority 升序的候选：[{id, priority, ending}]，已排除不满足与（默认）preview_only。
func _eligible_endings(counts: Dictionary, counters: Dictionary, facts: Array, allow_preview: bool) -> Array:
	var candidates: Array = []
	for item: Variant in _ending_templates():
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var ending: Dictionary = item
		if bool(ending.get("preview_only", false)) and not allow_preview:
			continue
		if not _all_requirements_met(ending, counts, counters, facts):
			continue
		candidates.append({
			"id": str(ending.get("id", "")),
			"priority": int(ending.get("priority", 999)),
			"ending": ending,
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["priority"]) < int(b["priority"]))
	return candidates

func _all_requirements_met(ending: Dictionary, counts: Dictionary, counters: Dictionary, facts: Array) -> bool:
	var requires: Variant = ending.get("requires", [])
	if typeof(requires) != TYPE_ARRAY or requires.is_empty():
		# 没有证据条件的模板不允许自动命中：那会变成"没有事实也下结论"。
		return false
	for item: Variant in requires:
		if not _requirement_met(item, counts, counters, facts):
			return false
	return true

func _requirement_met(requirement: Variant, counts: Dictionary, counters: Dictionary, facts: Array) -> bool:
	if typeof(requirement) != TYPE_DICTIONARY:
		return false
	var req: Dictionary = requirement
	var kind := str(req.get("kind", ""))
	match kind:
		"counter":
			var name := str(req.get("counter", ""))
			if name.is_empty() or not counters.has(name):
				return false
			return _compare(int(counters[name]), str(req.get("op", ">=")), int(req.get("value", 0)))
		"fact":
			var fact_type := str(req.get("fact_type", ""))
			if fact_type.is_empty():
				return false
			return int(counts.get(fact_type, 0)) >= int(req.get("min_count", 1))
		"fact_absent":
			var absent_type := str(req.get("fact_type", ""))
			if absent_type.is_empty():
				return false
			return int(counts.get(absent_type, 0)) == 0
		"fact_field":
			return _fact_field_met(req, facts)
		_:
			# 未知条件形式一律视为不满足，不猜测。
			_warnings.append("未知结局条件 kind：%s" % kind)
			return false

func _fact_field_met(req: Dictionary, facts: Array) -> bool:
	var fact_type := str(req.get("fact_type", ""))
	var field := str(req.get("field", ""))
	if fact_type.is_empty() or field.is_empty():
		return false
	var expected := str(req.get("equals", ""))
	var matched := 0
	for item: Variant in facts:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var fact: Dictionary = item
		if str(fact.get("type", "")) != fact_type:
			continue
		if expected.is_empty() or str(fact.get(field, "")) == expected:
			matched += 1
	return matched >= int(req.get("min_count", 1))

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

# ---------------- 文案渲染 ----------------

func _render_ending(ending: Dictionary, seed_text: String) -> Dictionary:
	var paragraphs: Array[String] = []
	var raw: Variant = ending.get("paragraphs", [])
	if typeof(raw) == TYPE_ARRAY:
		for paragraph: Variant in raw:
			var text := ""
			if typeof(paragraph) == TYPE_STRING:
				text = paragraph
			elif typeof(paragraph) == TYPE_DICTIONARY:
				var variants: Variant = paragraph.get("variants", [])
				if typeof(variants) == TYPE_ARRAY and variants.size() > 0:
					var paragraph_id := str(paragraph.get("id", ""))
					var index := _stable_index(seed_text + str(ending.get("id", "")) + paragraph_id, variants.size())
					text = str(variants[index])
			if not text.is_empty():
				paragraphs.append(text)
	if paragraphs.is_empty():
		paragraphs.append(str(ending.get("neutral_fallback", "这一局的手记到此为止。")))
	return {
		"id": str(ending.get("id", "")),
		"title": str(ending.get("title", "")),
		"tone": str(ending.get("tone", "neutral")),
		"paragraphs": paragraphs,
		"preview_only": bool(ending.get("preview_only", false)),
	}

func _neutral_ending() -> Dictionary:
	return {
		"id": str(NEUTRAL_ENDING["id"]),
		"title": str(NEUTRAL_ENDING["title"]),
		"tone": "neutral",
		"paragraphs": NEUTRAL_ENDING["paragraphs"].duplicate(),
		"preview_only": false,
	}

func _seed_text(counts: Dictionary, counters: Dictionary) -> String:
	var parts: Array[String] = []
	var fact_keys: Array = counts.keys()
	fact_keys.sort()
	for key: Variant in fact_keys:
		parts.append("%s:%d" % [str(key), int(counts[key])])
	var counter_keys: Array = counters.keys()
	counter_keys.sort()
	for key: Variant in counter_keys:
		parts.append("%s=%d" % [str(key), int(counters[key])])
	return "|".join(parts)

func _stable_index(seed_text: String, size: int) -> int:
	if size <= 1:
		return 0
	return int(absi(seed_text.hash()) % size)
