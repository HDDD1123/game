extends RefCounted
## 玩家偏好服务（任务4 T4-03）。单一写入者：只写 `user://preferences-v1.json`。
##
## 边界（见 docs/四机接口约定.md D 节）：
##   * 只存"偏好"：音量、字号缩放、减少动画、引导是否已跳过。窗口位置/尺寸继续由主UI的
##     `user://window-config.json` 维护，本服务不复制一份同义字段。
##   * 自动运行（clock）与后台输入监听**不写入偏好**：每次启动都按安全默认关闭。
##   * 写入用临时文件+改名，失败不破坏旧文件；读失败回落到默认值并给出原因，不静默当作已保存。
##   * 纯服务，不依赖 Kingdom、不创建 UI、不改变窗口。

const VERSION := 1
const PATH := "user://preferences-v1.json"
const MAX_BYTES := 65536

## 这些键永远不进偏好文件：自动运行与监听必须每次启动重新显式开启。
const NOT_PERSISTED := ["auto_run", "auto_running", "typing_enabled", "window_rect", "window_position"]

const DEFAULTS := {
	"master_volume": 0.8,
	"music_volume": 0.7,
	"sfx_volume": 0.8,
	"font_scale": 1.0,
	"reduce_motion": false,
	"onboarding_skipped": false,
}

# 用数组而不是 Vector2：Vector2 的分量是 32 位浮点（1.6 -> 1.60000002），
# 会让"写成 1.6、读回却不等于 1.6"这种精度问题进入偏好比较。
const RANGES := {
	"master_volume": [0.0, 1.0],
	"music_volume": [0.0, 1.0],
	"sfx_volume": [0.0, 1.0],
	"font_scale": [0.8, 1.6],
}

var _path := PATH

func _init(path: String = "") -> void:
	if not path.is_empty():
		_path = path

func get_path() -> String:
	return _path

## 返回 {ok, preferences, message}。任何失败都返回**完整可用**的默认值，调用方可以直接拿去用。
func load_preferences() -> Dictionary:
	if not FileAccess.file_exists(_path):
		return {"ok": true, "preferences": DEFAULTS.duplicate(true), "message": "首次启动，使用默认偏好。"}
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"preferences": DEFAULTS.duplicate(true),
			"message": "偏好文件无法打开（%s），本次使用默认值，不覆盖原文件。" % error_string(FileAccess.get_open_error()),
		}
	if file.get_length() > MAX_BYTES:
		file.close()
		return {
			"ok": false,
			"preferences": DEFAULTS.duplicate(true),
			"message": "偏好文件过大，已忽略并保留原文件。",
		}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"preferences": DEFAULTS.duplicate(true),
			"message": "偏好文件不是合法 JSON 对象，本次使用默认值，原文件保留。",
		}
	var loaded: Dictionary = parsed
	var version: Variant = loaded.get("version")
	# Godot 的 JSON.parse_string 返回 float（1 -> 1.0），所以接受"整数值的 float"。
	var int_like: bool = typeof(version) == TYPE_INT \
		or (typeof(version) == TYPE_FLOAT and is_equal_approx(float(version), round(float(version))))
	if not int_like or int(version) != VERSION:
		return {
			"ok": false,
			"preferences": DEFAULTS.duplicate(true),
			"message": "偏好版本不兼容（读到 %s，需要 %d），本次使用默认值。" % [str(version), VERSION],
		}
	var raw: Variant = loaded.get("preferences")
	if typeof(raw) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"preferences": DEFAULTS.duplicate(true),
			"message": "偏好内容缺失，本次使用默认值。",
		}
	var sanitised := sanitise(raw)
	return {"ok": true, "preferences": sanitised.value, "message": sanitised.message}

## 把任意输入收敛成"完整、类型正确、范围合法"的偏好字典。
## 未知键丢弃（并计数）；类型不对的键回落默认值；数值超范围截断。
func sanitise(raw: Dictionary) -> Dictionary:
	var result := DEFAULTS.duplicate(true)
	var rejected: Array[String] = []
	for key: String in raw.keys():
		if String(key) in NOT_PERSISTED:
			rejected.append(String(key))
			continue
		if not DEFAULTS.has(key):
			rejected.append(String(key))
			continue
		var value: Variant = raw[key]
		var default_value: Variant = DEFAULTS[key]
		if typeof(default_value) == TYPE_BOOL:
			if typeof(value) != TYPE_BOOL:
				rejected.append(String(key))
				continue
			result[key] = value
		elif typeof(default_value) == TYPE_FLOAT:
			if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
				rejected.append(String(key))
				continue
			var number := float(value)
			if is_nan(number) or is_inf(number):
				rejected.append(String(key))
				continue
			if RANGES.has(key):
				var bounds: Array = RANGES[key]
				number = clampf(number, float(bounds[0]), float(bounds[1]))
			result[key] = number
	var message := "偏好已校验。"
	if not rejected.is_empty():
		message = "已忽略 %d 个无效偏好键：%s" % [rejected.size(), ", ".join(rejected)]
	return {"value": result, "message": message}

## 原子保存：先写 .tmp，成功后再改名；旧文件先转 .bak。
func save_preferences(preferences: Dictionary) -> Dictionary:
	var sanitised := sanitise(preferences)
	var payload := {"version": VERSION, "preferences": sanitised.value}
	var temporary := _path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "无法创建临时偏好文件（%s），原设置未改动。" % error_string(FileAccess.get_open_error())}
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "message": "写入偏好失败，原设置未改动。"}
	var backup := _path + ".bak"
	if FileAccess.file_exists(_path):
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(_path, backup) != OK:
			DirAccess.remove_absolute(temporary)
			return {"ok": false, "message": "无法备份旧偏好，保存中止。"}
	if DirAccess.rename_absolute(temporary, _path) != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, _path)
		return {"ok": false, "message": "替换偏好失败，旧设置已恢复。"}
	# 把 sanitise 的提示一并带回：被丢弃的键要让调用方能解释给玩家，而不是静默吞掉。
	return {"ok": true, "message": "偏好已保存。" + str(sanitised.message)}

## 单键更新：加载→改→保存，避免调用方自己拼整份文件。
func set_value(key: String, value: Variant) -> Dictionary:
	if not DEFAULTS.has(key):
		return {"ok": false, "message": "未知偏好键：%s" % key}
	# 注意：Dictionary 取值是 Variant，这里必须显式标注类型，不能用 := 让编译器推断。
	var loaded: Dictionary = load_preferences()
	var current: Dictionary = loaded["preferences"]
	current[key] = value
	var saved := save_preferences(current)
	if not saved["ok"]:
		return saved
	var applied: Dictionary = load_preferences()
	return {"ok": true, "message": saved["message"], "preferences": applied["preferences"]}

## 恢复默认值（写盘）——同时保留"引导已跳过"这类与偏好无关的状态由调用方决定是否传回。
func reset_to_defaults() -> Dictionary:
	return save_preferences(DEFAULTS)
