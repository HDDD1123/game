#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T4-10 史书事实与结局模板：纯静态数据校验器。

只读取 apps/desktop/data/narrative/ 下的 JSON 与 README，不启动 Godot，
不读取真实存档，也不验证引擎侧渲染或事实注入。标准库实现。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

FACT_TYPES_REQUIRED = {
    "expedition_departed",
    "expedition_returned",
    "expedition_failed",
    "casualty",
    "construction_completed",
    "talent_recruited",
    "talent_died",
    "event_choice",
    "stronghold_gained",
    "stronghold_lost",
    "milestone_achieved",
    "ending",
    "harvest_summary",
    "starvation",
}

ENDING_CATEGORIES_REQUIRED = {
    "no_expedition",
    "repeated_expedition_failure",
    "starvation",
    "defeat",
    "player_ended",
    "kingdom_fallen",
    "long_reign",
    "exited_midway",
}

ALLOWED_FIELD_TYPES = {"int", "string", "bool", "enum"}
ALLOWED_REQUIRE_KINDS = {"counter", "fact", "fact_absent", "fact_field"}
ALLOWED_OPS = {"==", "!=", ">=", "<=", ">", "<"}
ALLOWED_TONES = {"neutral", "somber", "hopeful", "martial", "reflective"}

BLAME_WORDS = ["都怪", "你本可以", "愚蠢", "活该"]
BANNED_KEY_TOKENS = ["prompt", "api_key", "apikey", "http", "openai", "chatgpt", "llm"]
WIN_ABS_RE = re.compile(r"(?<![A-Za-z0-9_])[A-Za-z]:[\\/]")
UNC_RE = re.compile(r"\\\\[A-Za-z0-9_.\-]+\\")
UNIX_ABS_RE = re.compile(r"(?<![\w])/(?:home|Users|root|opt|usr|var|etc|mnt)/")
URL_RE = re.compile(r"(?:https?://|file://|www\.)")


def is_int(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


class Reporter:
    def __init__(self) -> None:
        self.ok_count = 0
        self.fail_count = 0

    def ok(self, message: str) -> None:
        self.ok_count += 1
        print(f"OK: {message}")

    def fail(self, message: str) -> None:
        self.fail_count += 1
        print(f"FAIL: {message}")

    def check(self, condition: bool, ok_message: str, fail_message: str) -> bool:
        if condition:
            self.ok(ok_message)
        else:
            self.fail(fail_message)
        return condition


def display(path: Path, root: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return path.name


def load_json(path: Path, root: Path, reporter: Reporter):
    label = display(path, root)
    if not path.is_file():
        reporter.fail(f"{label}: 文件不存在")
        return None
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        reporter.fail(f"{label}: 无法按 UTF-8 读取（{exc}）")
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        reporter.fail(f"{label}: JSON 解析失败（{exc}）")
        return None


def check_schema_version(doc, label: str, reporter: Reporter) -> bool:
    if not isinstance(doc, dict):
        reporter.fail(f"{label}: 顶层必须是 JSON 对象")
        return False
    if "schema_version" not in doc:
        reporter.fail(f"{label}: 缺少 schema_version")
        return False
    if not is_int(doc["schema_version"]) or doc["schema_version"] < 1:
        reporter.fail(f"{label}: schema_version 必须是 >=1 的整数")
        return False
    reporter.ok(f"{label}: schema_version={doc['schema_version']}")
    return True


def check_field_spec(field_name: str, spec, label: str, reporter: Reporter) -> bool:
    before = reporter.fail_count
    loc = f"{label}.{field_name}"
    if not isinstance(spec, dict):
        reporter.fail(f"{loc}: 字段定义必须是对象")
        return False
    ftype = spec.get("type")
    if ftype not in ALLOWED_FIELD_TYPES:
        reporter.fail(f"{loc}: 未知字段类型 {ftype!r}")
    elif ftype == "int":
        if "min" in spec and not is_int(spec["min"]):
            reporter.fail(f"{loc}: int.min 必须是整数")
        if "max" in spec and not is_int(spec["max"]):
            reporter.fail(f"{loc}: int.max 必须是整数")
        if "min" in spec and "max" in spec and is_int(spec["min"]) and is_int(spec["max"]) and spec["min"] > spec["max"]:
            reporter.fail(f"{loc}: int.min 大于 int.max")
    elif ftype == "enum":
        values = spec.get("values")
        if not isinstance(values, list) or not values:
            reporter.fail(f"{loc}: enum 必须提供非空 values")
        else:
            seen = set()
            for value in values:
                if not isinstance(value, str) or not value.strip():
                    reporter.fail(f"{loc}: enum 值必须是非空字符串")
                elif value in seen:
                    reporter.fail(f"{loc}: enum 值重复 {value!r}")
                else:
                    seen.add(value)
    elif ftype == "string" and "min_length" in spec and not is_int(spec["min_length"]):
        reporter.fail(f"{loc}: string.min_length 必须是整数")
    return reporter.fail_count == before


def check_counter_spec(name: str, spec, label: str, reporter: Reporter) -> bool:
    before = reporter.fail_count
    loc = f"{label}.{name}"
    if not isinstance(spec, dict):
        reporter.fail(f"{loc}: 计数器定义必须是对象")
        return False
    if spec.get("type") not in {"int", "string"}:
        reporter.fail(f"{loc}: 计数器 type 只允许 int/string")
    if not isinstance(spec.get("meaning"), str) or not spec["meaning"].strip():
        reporter.fail(f"{loc}: 缺少非空 meaning")
    if spec.get("type") == "int":
        if not is_int(spec.get("min")):
            reporter.fail(f"{loc}: int 计数器必须提供整数 min")
        if not isinstance(spec.get("required_in_snapshot"), bool):
            reporter.fail(f"{loc}: 缺少 required_in_snapshot 布尔值")
    evidence = spec.get("evidence_of")
    if evidence is not None and not isinstance(evidence, list):
        reporter.fail(f"{loc}: evidence_of 必须是列表")
    return reporter.fail_count == before


def validate_schema(schema, root: Path, reporter: Reporter) -> bool:
    label = "facts_schema"
    before = reporter.fail_count
    if not check_schema_version(schema, label, reporter):
        return False

    constraints = schema.get("constraints")
    if not isinstance(constraints, dict):
        reporter.fail(f"{label}: 缺少 constraints 对象")
    else:
        if constraints.get("runtime_ai_dependency") != "forbidden":
            reporter.fail(f"{label}: constraints.runtime_ai_dependency 必须为 forbidden")
        if constraints.get("network_dependency") != "forbidden":
            reporter.fail(f"{label}: constraints.network_dependency 必须为 forbidden")

    common = schema.get("common_rules")
    if not isinstance(common, dict):
        reporter.fail(f"{label}: 缺少 common_rules 对象")
        common = {}
    else:
        if common.get("log_window_size") != 40:
            reporter.fail(f"{label}: common_rules.log_window_size 必须为 40")
        rule_text = common.get("log_truncation_rule")
        if not isinstance(rule_text, str) or "expedition_count" not in rule_text:
            reporter.fail(f"{label}: log_truncation_rule 必须写明 expedition_count 等计数证据规则")

    fact_types = schema.get("fact_types")
    if not isinstance(fact_types, dict):
        reporter.fail(f"{label}: 缺少 fact_types 对象")
        return False

    missing = sorted(FACT_TYPES_REQUIRED - set(fact_types))
    if missing:
        reporter.fail(f"{label}: 缺少事实类型 {missing}")
    extra = sorted(set(fact_types) - FACT_TYPES_REQUIRED)
    if extra:
        reporter.fail(f"{label}: 存在未登记的事实类型 {extra}")

    for name in sorted(fact_types):
        item = fact_types[name]
        if not isinstance(item, dict):
            reporter.fail(f"{label}.fact_types.{name}: 必须是对象")
            continue
        if item.get("id") != name:
            reporter.fail(f"{label}.fact_types.{name}: id 必须与键名一致")
        if not isinstance(item.get("summary"), str) or not item["summary"].strip():
            reporter.fail(f"{label}.fact_types.{name}: 缺少 summary")
        required = item.get("required_fields")
        if not isinstance(required, dict) or not required:
            reporter.fail(f"{label}.fact_types.{name}: required_fields 必须是非空对象")
            required = {}
        else:
            for common_field in ("fact_id", "game_month"):
                if common_field not in required:
                    reporter.fail(f"{label}.fact_types.{name}: required_fields 缺少公共字段 {common_field}")
        optional = item.get("optional_fields")
        if not isinstance(optional, dict):
            reporter.fail(f"{label}.fact_types.{name}: optional_fields 必须是对象")
            optional = {}
        overlap = set(required) & set(optional)
        if overlap:
            reporter.fail(f"{label}.fact_types.{name}: 字段同时出现在 required/optional: {sorted(overlap)}")
        for field_name in sorted(required):
            check_field_spec(field_name, required[field_name], f"{label}.fact_types.{name}.required", reporter)
        for field_name in sorted(optional):
            check_field_spec(field_name, optional[field_name], f"{label}.fact_types.{name}.optional", reporter)
        evidence = item.get("evidence_of")
        if not isinstance(evidence, list) or not evidence:
            reporter.fail(f"{label}.fact_types.{name}: evidence_of 必须是非空列表")
        else:
            for index, entry in enumerate(evidence):
                if not isinstance(entry, dict):
                    reporter.fail(f"{label}.fact_types.{name}.evidence_of[{index}]: 必须是对象")
                elif not isinstance(entry.get("conclusion"), str) or not entry["conclusion"].strip():
                    reporter.fail(f"{label}.fact_types.{name}.evidence_of[{index}]: 缺少 conclusion")

    counters = schema.get("counters")
    if not isinstance(counters, dict):
        reporter.fail(f"{label}: 缺少 counters 对象")
        return reporter.fail_count == before
    if not is_int(counters.get("schema_version")) or counters["schema_version"] < 1:
        reporter.fail(f"{label}.counters: schema_version 必须是 >=1 的整数")
    fields = counters.get("fields")
    if not isinstance(fields, dict) or not fields:
        reporter.fail(f"{label}.counters: fields 必须是非空对象")
        return reporter.fail_count == before
    for name in sorted(fields):
        check_counter_spec(name, fields[name], f"{label}.counters.fields", reporter)
    required_counters = {
        name
        for name, spec in fields.items()
        if isinstance(spec, dict) and spec.get("required_in_snapshot") is True
    }
    if "expedition_count" not in required_counters:
        reporter.fail(f"{label}.counters: expedition_count 必须 required_in_snapshot")
    truncation = counters.get("truncation_rule")
    if not isinstance(truncation, dict):
        reporter.fail(f"{label}.counters: 缺少 truncation_rule")
    else:
        if truncation.get("log_window_size") != 40:
            reporter.fail(f"{label}.counters.truncation_rule: log_window_size 必须为 40")
        if not isinstance(truncation.get("rule"), str) or "expedition_count" not in truncation["rule"]:
            reporter.fail(f"{label}.counters.truncation_rule: rule 必须写明 expedition_count 证据规则")
        if not isinstance(truncation.get("counter_write_rule"), str) or not truncation["counter_write_rule"].strip():
            reporter.fail(f"{label}.counters.truncation_rule: 缺少 counter_write_rule")

    if reporter.fail_count == before:
        reporter.ok(f"{label}: 事实类型 {len(fact_types)} 类、计数器 {len(fields)} 项，结构与证据规则通过")
    return reporter.fail_count == before


def check_fact_value(value, spec, loc: str, reporter: Reporter) -> bool:
    ftype = spec.get("type")
    if ftype == "int":
        if not is_int(value):
            reporter.fail(f"{loc}: 应为 int，实际 {type(value).__name__}")
            return False
        if "min" in spec and is_int(spec["min"]) and value < spec["min"]:
            reporter.fail(f"{loc}: {value} 小于 min {spec['min']}")
            return False
        if "max" in spec and is_int(spec["max"]) and value > spec["max"]:
            reporter.fail(f"{loc}: {value} 大于 max {spec['max']}")
            return False
        return True
    if ftype == "string":
        if not isinstance(value, str):
            reporter.fail(f"{loc}: 应为 string，实际 {type(value).__name__}")
            return False
        if not value.strip():
            reporter.fail(f"{loc}: 字符串不能为空")
            return False
        return True
    if ftype == "bool":
        if not isinstance(value, bool):
            reporter.fail(f"{loc}: 应为 bool，实际 {type(value).__name__}")
            return False
        return True
    if ftype == "enum":
        values = spec.get("values")
        if not isinstance(values, list):
            reporter.fail(f"{loc}: schema 中 enum.values 非法")
            return False
        if value not in values:
            reporter.fail(f"{loc}: {value!r} 不在枚举 {values}")
            return False
        return True
    reporter.fail(f"{loc}: schema 中字段类型非法 {ftype!r}")
    return False


def validate_fact(fact, schema, loc: str, reporter: Reporter) -> bool:
    before = reporter.fail_count
    if not isinstance(fact, dict):
        reporter.fail(f"{loc}: 事实必须是对象")
        return False
    ftype = fact.get("type")
    fact_types = schema.get("fact_types", {})
    if not isinstance(ftype, str) or ftype not in fact_types:
        reporter.fail(f"{loc}: 未知事实类型 {ftype!r}")
        return False
    spec = fact_types[ftype]
    required = spec.get("required_fields", {})
    optional = spec.get("optional_fields", {})
    allowed = set(required) | set(optional) | {"type"}
    unknown = sorted(set(fact) - allowed)
    if unknown:
        reporter.fail(f"{loc} ({ftype}): 未知字段 {unknown}")
    for field_name, field_spec in required.items():
        if field_name not in fact:
            reporter.fail(f"{loc} ({ftype}): 缺少必填字段 {field_name}")
        else:
            check_fact_value(fact[field_name], field_spec, f"{loc}.{field_name}", reporter)
    for field_name, field_spec in optional.items():
        if field_name in fact:
            check_fact_value(fact[field_name], field_spec, f"{loc}.{field_name}", reporter)
    return reporter.fail_count == before


def validate_requires(ending, schema, loc: str, reporter: Reporter) -> bool:
    before = reporter.fail_count
    requires = ending.get("requires")
    if not isinstance(requires, list) or not requires:
        reporter.fail(f"{loc}: requires 必须是非空列表")
        return False
    fact_types = schema.get("fact_types", {})
    counter_fields = schema.get("counters", {}).get("fields", {})
    for index, require in enumerate(requires):
        rloc = f"{loc}.requires[{index}]"
        if not isinstance(require, dict):
            reporter.fail(f"{rloc}: 条件必须是对象")
            continue
        kind = require.get("kind")
        if kind not in ALLOWED_REQUIRE_KINDS:
            reporter.fail(f"{rloc}: 未知条件类型 {kind!r}")
            continue
        if kind == "counter":
            counter = require.get("counter")
            if counter not in counter_fields:
                reporter.fail(f"{rloc}: 引用了未知计数器 {counter!r}")
            op = require.get("op")
            if op not in ALLOWED_OPS:
                reporter.fail(f"{rloc}: 未知比较符 {op!r}")
            if not is_int(require.get("value")):
                reporter.fail(f"{rloc}: value 必须是整数")
        elif kind in {"fact", "fact_absent"}:
            fact_type = require.get("fact_type")
            if fact_type not in fact_types:
                reporter.fail(f"{rloc}: 引用了未知事实类型 {fact_type!r}")
            if kind == "fact":
                min_count = require.get("min_count")
                if not is_int(min_count) or min_count < 1:
                    reporter.fail(f"{rloc}: fact.min_count 必须是 >=1 的整数")
        elif kind == "fact_field":
            fact_type = require.get("fact_type")
            if fact_type not in fact_types:
                reporter.fail(f"{rloc}: 引用了未知事实类型 {fact_type!r}")
                continue
            field_name = require.get("field")
            type_spec = fact_types[fact_type]
            field_spec = type_spec.get("required_fields", {}).get(field_name)
            if field_spec is None:
                field_spec = type_spec.get("optional_fields", {}).get(field_name)
            if field_spec is None:
                reporter.fail(f"{rloc}: 事实 {fact_type} 没有字段 {field_name!r}")
                continue
            if "equals" not in require:
                reporter.fail(f"{rloc}: fact_field 缺少 equals")
            elif field_spec.get("type") == "enum" and require["equals"] not in field_spec.get("values", []):
                reporter.fail(f"{rloc}: equals {require['equals']!r} 不在字段枚举内")
            min_count = require.get("min_count", 1)
            if not is_int(min_count) or min_count < 1:
                reporter.fail(f"{rloc}: fact_field.min_count 必须是 >=1 的整数")
    return reporter.fail_count == before


def validate_endings(endings_doc, schema, root: Path, reporter: Reporter):
    label = "endings"
    if not check_schema_version(endings_doc, label, reporter):
        return []
    tone_values = endings_doc.get("tone_values")
    if not isinstance(tone_values, list) or not tone_values or any(tone not in ALLOWED_TONES for tone in tone_values):
        reporter.fail(f"{label}: tone_values 必须是 {sorted(ALLOWED_TONES)} 的非空子集")

    endings = endings_doc.get("endings")
    if not isinstance(endings, list):
        reporter.fail(f"{label}: 缺少 endings 列表")
        return []
    reporter.check(
        len(endings) >= 8,
        f"{label}: 结局模板 {len(endings)} 类（>=8）",
        f"{label}: 至少需要 8 类结局，实际 {len(endings)}",
    )

    ids = {}
    categories = {}
    priorities = {}
    required_category_coverage = set()
    for index, ending in enumerate(endings):
        loc = f"{label}.endings[{index}]"
        before = reporter.fail_count
        if not isinstance(ending, dict):
            reporter.fail(f"{loc}: 结局必须是对象")
            continue
        ending_id = ending.get("id")
        if not isinstance(ending_id, str) or not ending_id.strip():
            reporter.fail(f"{loc}: 缺少非空 id")
        elif ending_id in ids:
            reporter.fail(f"{loc}: id 重复 {ending_id!r}")
        else:
            ids[ending_id] = ending
            loc = f"{label}.endings[{ending_id}]"

        category = ending.get("category")
        if not isinstance(category, str) or not category.strip():
            reporter.fail(f"{loc}: 缺少非空 category")
        elif category in categories:
            reporter.fail(f"{loc}: category 重复 {category!r}（另见 {categories[category]}）")
        else:
            categories[category] = ending_id

        preview_only = ending.get("preview_only", False)
        if not isinstance(preview_only, bool):
            reporter.fail(f"{loc}: preview_only 必须是布尔值")
            preview_only = False
        if preview_only:
            note = ending.get("note")
            if not isinstance(note, str) or not note.strip():
                reporter.fail(f"{loc}: preview_only=true 时必须提供非空 note，说明仅用于预览/校验")
        else:
            required_category_coverage.add(category)

        priority = ending.get("priority")
        if not is_int(priority):
            reporter.fail(f"{loc}: priority 必须是整数")
        elif priority in priorities:
            reporter.fail(f"{loc}: priority 重复 {priority}（另见 {priorities[priority]}）")
        else:
            priorities[priority] = ending_id

        tone = ending.get("tone")
        if tone not in ALLOWED_TONES:
            reporter.fail(f"{loc}: 未知 tone {tone!r}")

        title = ending.get("title")
        if not isinstance(title, str) or not title.strip():
            reporter.fail(f"{loc}: 缺少非空 title")

        neutral = ending.get("neutral_fallback")
        if not isinstance(neutral, str) or len(neutral.strip()) < 5:
            reporter.fail(f"{loc}: neutral_fallback 必须是长度 >=5 的非空字符串")

        paragraphs = ending.get("paragraphs")
        if not isinstance(paragraphs, list) or not paragraphs:
            reporter.fail(f"{loc}: paragraphs 至少需要 1 段")
        else:
            for p_index, paragraph in enumerate(paragraphs):
                ploc = f"{loc}.paragraphs[{p_index}]"
                if not isinstance(paragraph, dict):
                    reporter.fail(f"{ploc}: 段落必须是对象")
                    continue
                variants = paragraph.get("variants")
                if not isinstance(variants, list) or not (2 <= len(variants) <= 4):
                    reporter.fail(f"{ploc}: variants 必须是 2~4 条列表，实际 {len(variants) if isinstance(variants, list) else 'N/A'}")
                    continue
                seen = set()
                for v_index, variant in enumerate(variants):
                    vloc = f"{ploc}.variants[{v_index}]"
                    if not isinstance(variant, str) or not variant.strip():
                        reporter.fail(f"{vloc}: 文案必须是非空字符串")
                    elif variant in seen:
                        reporter.fail(f"{vloc}: 同段 variants 重复 {variant!r}")
                    else:
                        seen.add(variant)

        validate_requires(ending, schema, loc, reporter)

        if reporter.fail_count == before:
            reporter.ok(f"{loc}: 证据条件、{len(paragraphs)} 段同义文案与中性回退通过")

    missing_categories = sorted(ENDING_CATEGORIES_REQUIRED - required_category_coverage)
    reporter.check(
        not missing_categories,
        f"{label}: 必需结局类别齐备 {sorted(ENDING_CATEGORIES_REQUIRED)}",
        f"{label}: 缺少必需结局类别 {missing_categories}",
    )
    real_endings = [
        ending for ending in endings if isinstance(ending, dict) and ending.get("preview_only") is not True
    ]
    reporter.check(
        len(real_endings) >= 8,
        f"{label}: 正式（非预览）结局 {len(real_endings)} 类（>=8）",
        f"{label}: 正式（非预览）结局不足 8 类，实际 {len(real_endings)}",
    )
    preview_entries = [e for e in endings if isinstance(e, dict) and e.get("preview_only") is True]
    if preview_entries:
        missing_notes = [
            entry.get("id")
            for entry in preview_entries
            if not isinstance(entry.get("note"), str) or not entry["note"].strip()
        ]
        if not missing_notes:
            reporter.ok(
                f"{label}: preview_only 条目 {[entry.get('id') for entry in preview_entries]} "
                "已带 note，正式渲染需排除"
            )
    return endings


def validate_handbook(handbook, schema, root: Path, reporter: Reporter) -> bool:
    label = "handbook"
    if not check_schema_version(handbook, label, reporter):
        return False
    before = reporter.fail_count
    if not isinstance(handbook.get("title"), str) or not handbook["title"].strip():
        reporter.fail(f"{label}: 缺少非空 title")
    fact_types = schema.get("fact_types", {})
    stages = handbook.get("stages")
    allowed_stages = set(stages) if isinstance(stages, list) and all(isinstance(s, str) for s in stages) else set()
    if not allowed_stages:
        reporter.fail(f"{label}: stages 必须是非空字符串列表")
    sections = handbook.get("sections")
    if not isinstance(sections, list) or not sections:
        reporter.fail(f"{label}: sections 必须是非空列表")
        return False
    seen_ids = set()
    prev_start = -1
    prev_end = -1
    for index, section in enumerate(sections):
        loc = f"{label}.sections[{index}]"
        if not isinstance(section, dict):
            reporter.fail(f"{loc}: 章节必须是对象")
            continue
        section_id = section.get("id")
        if not isinstance(section_id, str) or not section_id.strip():
            reporter.fail(f"{loc}: 缺少非空 id")
        elif section_id in seen_ids:
            reporter.fail(f"{loc}: id 重复 {section_id!r}")
        else:
            seen_ids.add(section_id)
        title = section.get("title")
        if not isinstance(title, str) or not title.strip():
            reporter.fail(f"{loc}: 缺少非空 title")
        stage = section.get("stage")
        if allowed_stages and stage not in allowed_stages:
            reporter.fail(f"{loc}: 未知 stage {stage!r}")
        month_range = section.get("month_range")
        if (
            not isinstance(month_range, list)
            or len(month_range) != 2
            or not all(is_int(value) for value in month_range)
            or month_range[0] < 0
            or month_range[0] > month_range[1]
        ):
            reporter.fail(f"{loc}: month_range 必须是 [start, end]，0 <= start <= end")
        else:
            start, end = month_range
            if start <= prev_start:
                reporter.fail(f"{loc}: month_range 起点必须严格递增（前一章起点 {prev_start}）")
            if start <= prev_end and prev_end >= 0:
                reporter.fail(f"{loc}: month_range 与前一章重叠（前一章结束 {prev_end}）")
            prev_start, prev_end = start, end
        refs = section.get("fact_types")
        if not isinstance(refs, list) or not refs:
            reporter.fail(f"{loc}: fact_types 必须是非空列表")
        else:
            for ref in refs:
                if ref not in fact_types:
                    reporter.fail(f"{loc}: 引用了 schema 中不存在的事实类型 {ref!r}")
            if len(set(refs)) != len(refs):
                reporter.fail(f"{loc}: fact_types 存在重复项")
        empty_text = section.get("empty_text")
        if not isinstance(empty_text, str) or not empty_text.strip():
            reporter.fail(f"{loc}: empty_text 必须是非空字符串")
    if reporter.fail_count == before:
        reporter.ok(f"{label}: {len(sections)} 章结构、月份区间与事实引用通过")
    return reporter.fail_count == before


def collect_strings(value, loc: str, strings, keys) -> None:
    if isinstance(value, str):
        strings.append((loc, value))
    elif isinstance(value, dict):
        for key, item in value.items():
            keys.append((loc, key))
            collect_strings(item, f"{loc}.{key}", strings, keys)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            collect_strings(item, f"{loc}[{index}]", strings, keys)


def scan_text(label: str, value, reporter: Reporter, strings, keys) -> bool:
    before = reporter.fail_count
    for loc, text in strings:
        for word in BLAME_WORDS:
            if word in text:
                reporter.fail(f"{label}: {loc}: 命中责备式词表 {word!r}")
        if WIN_ABS_RE.search(text):
            reporter.fail(f"{label}: {loc}: 出现盘符绝对路径（只允许 res:// 或相对路径）")
        if UNC_RE.search(text):
            reporter.fail(f"{label}: {loc}: 出现 UNC 绝对路径")
        if UNIX_ABS_RE.search(text):
            reporter.fail(f"{label}: {loc}: 出现 Unix 绝对路径")
        if URL_RE.search(text):
            reporter.fail(f"{label}: {loc}: 出现网络地址，叙事数据不得依赖网络")
    for loc, key in keys:
        lowered = key.lower()
        for token in BANNED_KEY_TOKENS:
            if token in lowered:
                reporter.fail(f"{label}: {loc}: 字段名包含禁止的运行时依赖标记 {token!r}")
    return reporter.fail_count == before


def count_fact_type(facts, fact_type: str) -> int:
    return sum(1 for fact in facts if isinstance(fact, dict) and fact.get("type") == fact_type)


def ending_matches(ending, facts, counters) -> bool:
    if not isinstance(ending, dict):
        return False
    for require in ending.get("requires", []):
        if not isinstance(require, dict):
            return False
        kind = require.get("kind")
        if kind == "counter":
            value = counters.get(require.get("counter"))
            if not is_int(value):
                return False
            target = require.get("value")
            op = require.get("op")
            if op == "==" and not value == target:
                return False
            if op == "!=" and not value != target:
                return False
            if op == ">=" and not value >= target:
                return False
            if op == "<=" and not value <= target:
                return False
            if op == ">" and not value > target:
                return False
            if op == "<" and not value < target:
                return False
        elif kind == "fact":
            if count_fact_type(facts, require.get("fact_type")) < require.get("min_count", 1):
                return False
        elif kind == "fact_absent":
            if count_fact_type(facts, require.get("fact_type")) > 0:
                return False
        elif kind == "fact_field":
            matched = sum(
                1
                for fact in facts
                if isinstance(fact, dict)
                and fact.get("type") == require.get("fact_type")
                and fact.get(require.get("field")) == require.get("equals")
            )
            if matched < require.get("min_count", 1):
                return False
        else:
            return False
    return True


def validate_fixture(path: Path, fixture, schema, endings, root: Path, reporter: Reporter) -> None:
    label = display(path, root)
    before = reporter.fail_count
    if not check_schema_version(fixture, label, reporter):
        return

    notice = fixture.get("fixture_notice")
    if not isinstance(notice, str) or "虚构" not in notice or "仅用于" not in notice:
        reporter.fail(f"{label}: fixture_notice 必须明确写出'虚构'与'仅用于校验/预览'")
    if not isinstance(fixture.get("scenario"), str) or not fixture["scenario"].strip():
        reporter.fail(f"{label}: 缺少非空 scenario 描述")

    facts = fixture.get("facts")
    if not isinstance(facts, list):
        reporter.fail(f"{label}: facts 必须是列表")
        return
    seen_fact_ids = set()
    for index, fact in enumerate(facts):
        if validate_fact(fact, schema, f"{label}.facts[{index}]", reporter):
            fact_id = fact.get("fact_id")
            if fact_id in seen_fact_ids:
                reporter.fail(f"{label}.facts[{index}]: fact_id 重复 {fact_id!r}")
            else:
                seen_fact_ids.add(fact_id)

    counters = fixture.get("counters")
    if not isinstance(counters, dict):
        reporter.fail(f"{label}: counters 必须是对象")
        return
    counter_fields = schema.get("counters", {}).get("fields", {})
    required_counters = {
        name
        for name, spec in counter_fields.items()
        if isinstance(spec, dict) and spec.get("required_in_snapshot") is True
    }
    missing = sorted(required_counters - set(counters))
    if missing:
        reporter.fail(f"{label}: counters 缺少必需计数 {missing}")
    unknown = sorted(set(counters) - set(counter_fields))
    if unknown:
        reporter.fail(f"{label}: counters 存在未知计数 {unknown}")
    for name, value in counters.items():
        spec = counter_fields.get(name)
        if not isinstance(spec, dict):
            continue
        if spec.get("type") == "int":
            if not is_int(value):
                reporter.fail(f"{label}.counters.{name}: 必须是整数")
            elif value < spec.get("min", 0):
                reporter.fail(f"{label}.counters.{name}: {value} 小于 min {spec.get('min')}")

    derived = {
        "expedition_count": count_fact_type(facts, "expedition_departed"),
        "expedition_failure_count": count_fact_type(facts, "expedition_failed"),
        "starvation_month_count": count_fact_type(facts, "starvation"),
        "buildings_completed": count_fact_type(facts, "construction_completed"),
        "talents_recruited": count_fact_type(facts, "talent_recruited"),
        "talents_lost": count_fact_type(facts, "talent_died"),
        "strongholds_gained": count_fact_type(facts, "stronghold_gained"),
        "strongholds_lost": count_fact_type(facts, "stronghold_lost"),
        "milestone_count": count_fact_type(facts, "milestone_achieved"),
        "total_casualties": sum(
            fact.get("amount", 0)
            for fact in facts
            if isinstance(fact, dict) and fact.get("type") == "casualty" and is_int(fact.get("amount"))
        ),
    }
    fact_count = counters.get("fact_count")
    complete_sample = is_int(fact_count) and fact_count == len(facts)
    for name, sample_value in derived.items():
        if name not in counters or not is_int(counters[name]):
            continue
        if complete_sample:
            if counters[name] != sample_value:
                reporter.fail(
                    f"{label}: 计数 {name}={counters[name]} 与完整样例推导值 {sample_value} 不一致"
                )
        elif counters[name] < sample_value:
            reporter.fail(
                f"{label}: 计数 {name}={counters[name]} 小于样例中该事实推导值 {sample_value}"
            )
    if is_int(fact_count) and fact_count < len(facts):
        reporter.fail(f"{label}: fact_count={fact_count} 小于 facts 条数 {len(facts)}")
    months_played = counters.get("months_played")
    fact_months = [
        fact.get("game_month")
        for fact in facts
        if isinstance(fact, dict) and is_int(fact.get("game_month"))
    ]
    if fact_months and is_int(months_played):
        max_month = max(fact_months)
        if max_month >= months_played:
            reporter.fail(f"{label}: 事实 game_month={max_month} 不小于 months_played={months_played}")

    expected = fixture.get("expected")
    ending_by_id = {
        ending.get("id"): ending
        for ending in endings
        if isinstance(ending, dict) and isinstance(ending.get("id"), str)
    }
    if not isinstance(expected, dict):
        reporter.fail(f"{label}: expected 必须是对象")
    else:
        eligible = expected.get("eligible_ending_ids")
        if not isinstance(eligible, list) or not eligible:
            reporter.fail(f"{label}.expected: eligible_ending_ids 必须是非空列表")
        else:
            non_string = [item for item in eligible if not isinstance(item, str)]
            if non_string:
                reporter.fail(f"{label}.expected: eligible_ending_ids 只能包含字符串")
            eligible = [item for item in eligible if isinstance(item, str)]
            unknown_ids = [ending_id for ending_id in eligible if ending_id not in ending_by_id]
            if unknown_ids:
                reporter.fail(f"{label}.expected: 引用了未知结局 id {unknown_ids}")
            selected = expected.get("selected_ending_id")
            if not isinstance(selected, str) or selected not in ending_by_id:
                reporter.fail(f"{label}.expected: selected_ending_id {selected!r} 不存在")
            elif selected not in eligible:
                reporter.fail(f"{label}.expected: selected_ending_id 不在 eligible_ending_ids 内")
            if not isinstance(expected.get("evidence_sufficient"), bool):
                reporter.fail(f"{label}.expected: evidence_sufficient 必须是布尔值")

            evaluable = [
                ending
                for ending in ending_by_id.values()
                if ending.get("preview_only") is not True
            ]
            computed = sorted(
                (ending for ending in evaluable if ending_matches(ending, facts, counters)),
                key=lambda ending: ending.get("priority", 10**9),
            )
            computed_ids = [ending.get("id") for ending in computed]
            if set(computed_ids) != set(eligible):
                missing_ids = sorted(set(computed_ids) - set(eligible))
                extra_ids = sorted(set(eligible) - set(computed_ids))
                reporter.fail(
                    f"{label}.expected: 按 requires 推导的 eligible={computed_ids}，"
                    f"文件写的是 {sorted(eligible)}（多写 {extra_ids}，少写 {missing_ids}）"
                )
            elif computed_ids and computed_ids[0] != selected:
                reporter.fail(
                    f"{label}.expected: 按 priority 应选 {computed_ids[0]!r}，"
                    f"文件写的是 {selected!r}"
                )

    if reporter.fail_count == before:
        reporter.ok(f"{label}: 虚构标注、{len(facts)} 条事实、{len(counters)} 个计数与期望结局通过")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="T4-10 叙事数据静态校验器（不启动引擎）")
    parser.add_argument("--root", type=Path, default=None, help="仓库根目录，默认自动定位")
    args = parser.parse_args(argv)

    if args.root is not None:
        root = args.root.expanduser().resolve()
    else:
        here = Path(__file__).resolve()
        root = None
        for parent in here.parents:
            if (parent / "apps" / "desktop" / "data" / "narrative").is_dir():
                root = parent
                break
        if root is None:
            root = Path.cwd().resolve()

    reporter = Reporter()
    print(f"INFO: ROOT={root}")
    print("INFO: 静态校验，不启动 Godot，不读取真实存档")

    narrative = root / "apps" / "desktop" / "data" / "narrative"
    if not narrative.is_dir():
        reporter.fail(f"数据目录不存在: {narrative}")
        print(f"SUMMARY: OK={reporter.ok_count} FAIL={reporter.fail_count}")
        return 1

    schema = load_json(narrative / "facts_schema.json", root, reporter)
    endings_doc = load_json(narrative / "endings.json", root, reporter)
    handbook = load_json(narrative / "handbook.json", root, reporter)
    labels = ["facts_schema.json", "endings.json", "handbook.json"]
    for label, doc in zip(labels, [schema, endings_doc, handbook]):
        if doc is not None:
            reporter.ok(f"{label}: JSON 解析通过")

    all_strings = []
    all_keys = []
    if schema is not None:
        collect_strings(schema, "facts_schema", all_strings, all_keys)
        validate_schema(schema, root, reporter)
    if endings_doc is not None:
        collect_strings(endings_doc, "endings", all_strings, all_keys)
    endings = []
    if endings_doc is not None and schema is not None:
        endings = validate_endings(endings_doc, schema, root, reporter)
    if handbook is not None and schema is not None:
        collect_strings(handbook, "handbook", all_strings, all_keys)
        validate_handbook(handbook, schema, root, reporter)

    fixtures_dir = narrative / "fixtures"
    fixture_paths = sorted(fixtures_dir.glob("*.json")) if fixtures_dir.is_dir() else []
    if not (3 <= len(fixture_paths) <= 4):
        reporter.fail(f"fixtures: 需要 3~4 个样例事实集 JSON，实际 {len(fixture_paths)}")
    else:
        reporter.ok(f"fixtures: 找到 {len(fixture_paths)} 个样例文件")
    if schema is not None and endings:
        for path in fixture_paths:
            fixture = load_json(path, root, reporter)
            if fixture is None:
                continue
            collect_strings(fixture, display(path, root), all_strings, all_keys)
            validate_fixture(path, fixture, schema, endings, root, reporter)

    readme = narrative / "README.md"
    if not readme.is_file():
        reporter.fail("README.md: 文件不存在")
    else:
        try:
            readme_text = readme.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            reporter.fail(f"README.md: 无法按 UTF-8 读取（{exc}）")
        else:
            all_strings.append(("README.md", readme_text))
            reporter.ok("README.md: 已纳入文本扫描")

    if scan_text("text_scan", None, reporter, all_strings, all_keys):
        reporter.ok(
            f"text_scan: {len(all_strings)} 条字符串、{len(all_keys)} 个字段名通过"
            "（绝对路径/责备词表/网络地址/运行时依赖字段）"
        )

    print(f"SUMMARY: OK={reporter.ok_count} FAIL={reporter.fail_count}")
    return 0 if reporter.fail_count == 0 else 1


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass
    sys.exit(main())
