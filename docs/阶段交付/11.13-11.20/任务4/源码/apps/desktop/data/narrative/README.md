# 叙事数据：史书事实、结局与手记

本目录只放**数据契约与文案素材**，不放游戏状态，也不执行叙事生成。正式生成器（任务4）只读事实与计数，返回条目和结局描述，不写存档、不补造事实。

## 文件

| 文件 | 作用 |
|---|---|
| `facts_schema.json` | 结构化史书事实的字段契约、14 类事实、持久累计计数与日志截断规则 |
| `endings.json` | 9 类短结局模板（其中 1 类为 `preview_only` 预览）与确定性选择规则 |
| `handbook.json` | 可翻阅手记的 4 章骨架：月份区间、引用事实类型、空章节文案 |
| `fixtures/*.json` | 4 个虚构样例事实集，仅用于校验与预览 |
| `../../tests/task4/validate_narrative.py` | 纯标准库静态校验器 |

## 事实从哪来

- 任务2在存档 `extensions.history` 中提供事实；`fact_id` 来自持久计数，跨月份稳定。
- 每条事实有 `type`（判别字段）、`fact_id`、`game_month` 和该类型的必填字段；字段类型只允许 `int`/`string`/`bool`/`enum`。
- 事实类型：远征出发/返回/失败、伤亡、建设完成、人才招募/死亡、事件选择、据点得失、里程碑、结束、收成摘要、饥饿。
- **计数与明细分开**：明细日志最多 40 条，只用于叙述细节。`no_expedition` 这类“从未发生”的结论只能读 `expedition_count == 0`；最近 40 条里没有相关条目只能说明该窗口无记录，不能当作历史证据。
- 没有证据时使用 `neutral_fallback` 或手记的 `empty_text`；不得推断未记录的动机，也不做责备式归因。

## 结局怎么选

- 每个结局有稳定 `id`、唯一 `category`、`requires`、`priority`、`tone`、`paragraphs` 和 `neutral_fallback`。
- `requires` 是**全部满足**才成立的证据条件，支持四种条件：
  - `counter`：持久计数比较（`==`/`!=`/`>=`/`<=`/`>`/`<`）；
  - `fact`：某类事实至少 N 条；
  - `fact_absent`：某类事实为 0 条；
  - `fact_field`：某类事实的某字段等于指定值至少 N 条。
- 选择规则：排除 `preview_only` 后，取 `requires` 全部满足且 `priority` 数值最小的条目；一个都不满足时由调用方使用中性回退，并标注证据不足。
- `paragraphs` 每段含 2~4 条 `variants`；随机只在这些同义文案之间挑选，不能改变事实、计数或结局判定。
- `preview_only: true` 的条目（`ending_abdication_inheritance`）只用于 fixture 预览：本轮未实现主动隐退/跨局继承，正式界面不得出现对应的假入口，也不得借此改写继承规则。

结局类别覆盖：未出兵（`no_expedition`）、多次远征失败（`repeated_expedition_failure`）、饥饿（`starvation`）、战败（`defeat`）、主动结束（`player_ended`）、亡国（`kingdom_fallen`）、长治国（`long_reign`）、中途退出/无法判定（`exited_midway`），外加隐退继承预览。

## 手记怎么翻

`handbook.json` 的章节按 `month_range` 接收事实：同一章内按 `game_month`、`fact_id` 升序。章节只声明 `fact_types` 与 `empty_text`，不写死玩家名、建筑名或具体数值；没有事实时显示空章节文案。

## 如何扩展

1. 新事实类型：先在 `facts_schema.json` 的 `fact_types` 增加条目（必填/可选字段、类型、`evidence_of`），再在任务2的提交器里写入对应事实与计数；不要只加数据不加计数。
2. 新结局：在 `endings.json` 增加条目，`requires` 只引用已登记的事实类型与计数；`category` 不得与现有重复，`priority` 不得重复；每段 2~4 条同义文案。
3. 新手记章节：确认 `month_range` 与前一章不重叠，`fact_types` 全部已登记。
4. 新样例：放 `fixtures/`，必须带“虚构样例，仅用于校验/预览”字样，并写 `expected.eligible_ending_ids`、`selected_ending_id`、`evidence_sufficient`。

## 校验

在仓库根目录运行（请使用运行环境提供的 Python 3，不要依赖 PATH 里的占位程序）：

```
python apps/desktop/tests/task4/validate_narrative.py --root .
```

退出码 0 表示全部静态检查通过，1 表示存在 `FAIL:` 行。校验内容：

- 三个 JSON 可解析且含 `schema_version`；
- 14 类事实齐备，字段类型合法，结局类别不重复且至少 8 类；
- 每个结局的 `requires` 只引用已登记事实/计数，`paragraphs` 每段 2~4 条互不相同的 `variants`；
- `preview_only` 缺少 `note` 时报错；
- 手记的 `fact_types` 引用合法、月份区间不重叠；
- fixtures 的类型/字段符合 schema，计数与完整样例推导一致，并按 `requires` 与 `priority` 复算期望结局；
- 文本扫描：禁止盘符/UNC/Unix 绝对路径（`res://` 与相对路径允许）、责备式词表、网络地址、运行时外部依赖字段。

## 边界

校验器**只做静态检查**：它不启动 Godot、不读取真实存档、不验证引擎侧渲染、字体与布局，也不验证任务2是否真的写入了这些事实。真实存档事实注入、`render_history` 的引擎内表现、以及 UI 是否隐藏 `preview_only` 入口，都需要在集成环境另行验证。本目录数据不使用运行时大模型、网络或外部服务。
