extends SceneTree
## 任务4 T4-10 史书/结局渲染测试：用 data/narrative/fixtures 的虚构样例断言可复现的选择。
## 运行（4.6.3）：
##   godot --headless --path apps/desktop --script res://tests/task4/test_narrative_render.gd
## 说明：fixtures 是**虚构样例**，不是真实存档；这里只验证"事实→可展示文本"的确定性映射。

const Renderer = preload("res://platform/narrative/history_renderer.gd")
const FIXTURES := [
	{"file": "res://data/narrative/fixtures/fixture_new_game_no_expedition.json", "selected": "ending_no_expedition", "eligible": ["ending_no_expedition", "ending_exited_midway"]},
	{"file": "res://data/narrative/fixtures/fixture_multiple_failures_hunger.json", "selected": "ending_repeated_failure", "eligible": ["ending_repeated_failure", "ending_exited_midway"]},
	{"file": "res://data/narrative/fixtures/fixture_player_ended.json", "selected": "ending_player_ended", "eligible": ["ending_player_ended", "ending_long_reign"]},
	{"file": "res://data/narrative/fixtures/fixture_insufficient_evidence.json", "selected": "ending_exited_midway", "eligible": ["ending_exited_midway"]},
]

var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func _load_fixture(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		printerr("FAIL: 无法打开 fixture %s" % path)
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _initialize() -> void:
	var renderer = Renderer.new()
	for item: Dictionary in FIXTURES:
		var path := str(item["file"])
		var fixture := _load_fixture(path)
		check(not fixture.is_empty(), "fixture 可读：%s" % path)
		if fixture.is_empty():
			continue
		var facts: Array = fixture.get("facts", [])
		var summary := {"counters": fixture.get("counters", {})}

		var result: Dictionary = renderer.render_history(facts, summary)
		check(result.ok, "render ok：%s" % path)
		check(result.eligible_endings == item["eligible"], "候选结局顺序与期望一致：%s（实际 %s）" % [path, str(result.eligible_endings)])
		check(result.ending.id == item["selected"], "选中结局正确：%s（实际 %s）" % [path, result.ending.id])
		check(not result.used_fallback, "有证据时不使用中性兜底：%s" % path)
		check(result.ending.paragraphs.size() > 0, "结局至少一段文本：%s" % path)
		check(result.warnings.is_empty(), "无未预期警告：%s（%s）" % [path, str(result.warnings)])

		# 确定性：同输入两次渲染，文字完全一致（随机只发生在 variants 之间）
		var again: Dictionary = renderer.render_history(facts, summary)
		check(again.ending.paragraphs == result.ending.paragraphs, "同输入同输出：%s" % path)

		# 章节：所有事实都应落进某一章，且空章节给 empty_text
		var total_entries := 0
		var empty_chapters := 0
		for chapter: Dictionary in result.chapters:
			total_entries += chapter.entries.size()
			if chapter.entries.is_empty():
				empty_chapters += 1
				check(not str(chapter.empty_text).is_empty(), "空章节有中性文案：%s" % chapter.id)
		check(total_entries == result.entries.size(), "章节覆盖全部条目：%s（%d vs %d）" % [path, total_entries, result.entries.size()])
		check(result.chapters.size() == 4, "四条章节骨架：%s" % path)

		# preview_only 默认不出现；显式预览时是否出现，取决于该 fixture 是否满足它的证据条件：
		# ending_abdication_inheritance 要求"没有 ending 事实"且 months_played >= 1。
		var has_ending_fact := false
		for fact_item: Variant in facts:
			if typeof(fact_item) == TYPE_DICTIONARY and str(fact_item.get("type", "")) == "ending":
				has_ending_fact = true
		var months_played := int(summary.get("counters", {}).get("months_played", 0))
		var expect_preview := (not has_ending_fact) and months_played >= 1
		var preview: Dictionary = renderer.render_history(facts, summary, {"allow_preview": true})
		check(not result.eligible_endings.has("ending_abdication_inheritance"), "默认隐藏 preview_only 结局：%s" % path)
		check(
			preview.eligible_endings.has("ending_abdication_inheritance") == expect_preview,
			"预览模式下 preview_only 的可见性符合证据条件（应可见=%s）：%s" % [str(expect_preview), path]
		)
		check(preview.ending.id == result.ending.id, "预览不改变选中结局：%s" % path)

	# 空事实 + 空计数：不应凭空缺下结论，应当用中性兜底
	var empty: Dictionary = renderer.render_history([], {})
	check(empty.used_fallback and empty.ending.id == "neutral_insufficient", "无证据时中性兜底")
	check(empty.entries.is_empty(), "无事实不造条目")

	# 坏数据：计数不是数字时不应崩，只记警告
	var messy: Dictionary = renderer.render_history([{"type": "starvation", "fact_id": "x", "game_month": 3}], {"counters": {"starvation_month_count": "一"}})
	check(messy.ok, "脏计数不崩溃")
	check(not messy.counters.has("starvation_month_count"), "非数值计数被丢弃")

	print("TASK4 NARRATIVE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
