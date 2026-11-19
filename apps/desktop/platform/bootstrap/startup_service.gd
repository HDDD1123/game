extends RefCounted
## 启动诊断服务（任务4 T4-02）。只读：检查资源与存档"能不能用"，不改任何状态。
##
## 边界（见 docs/四机接口约定.md D 节）：
##   * `inspect_saves()` 只报告文件存在性、大小、可解析版本与错误分类；
##     **不**把存档灌进 Kingdom，也**不**因为文件存在就宣称"可读"。
##     真正载入仍由任务2的 SaveStore 完成，且校验通过后才替换状态。
##   * 新建/重试/退出由任务1的首屏调用本服务的结论；本服务不删除、不覆盖任何存档。
##   * 本服务不创建窗口、不改变时间、不写偏好。

## 存档检查状态（稳定字符串，UI 可据此显示文案）。
const STATUS_MISSING := "missing"
const STATUS_READABLE := "readable"
const STATUS_CORRUPT := "corrupt"
const STATUS_INCOMPATIBLE := "incompatible"
const STATUS_PERMISSION := "permission_denied"
const STATUS_TOO_LARGE := "too_large"

const MAX_SAVE_BYTES := 2097152
## 启动时必须可读的资源。缺哪个就报哪个，不用"应该没问题"糊过去。
const REQUIRED_RESOURCES := [
	"res://project.godot",
	"res://ui/main.tscn",
	"res://data/building_slots.json",
]

## 存档路径按任务2的格式5/4/3优先级给出（本服务只读，不改写）。
const SAVE_CANDIDATES := [
	{"path": "user://kingdom-save-v5.json", "version": 5},
	{"path": "user://kingdom-save-v4.json", "version": 4},
	{"path": "user://kingdom-save-v3.json", "version": 3},
]

func inspect_saves(candidates: Array = SAVE_CANDIDATES) -> Dictionary:
	var primary: Dictionary = {}
	var legacy: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		var inspected := inspect_file(candidate.path, candidate.version)
		if primary.is_empty():
			primary = inspected
		else:
			legacy.append(inspected)
	var recommendation := _recommend(primary)
	return {
		"primary": primary,
		"legacy": legacy,
		"can_continue": primary.status == STATUS_READABLE,
		"can_start_new": true,
		"can_retry": primary.status != STATUS_MISSING,
		"recommendation": recommendation,
		"message": recommendation,
	}

## 单个文件的只读检查。version 是该文件**声称**的格式版本，用于判断"版本不符"与"内容损坏"。
func inspect_file(path: String, expected_version: int) -> Dictionary:
	var result := {
		"path": path,
		"exists": false,
		"bytes": 0,
		"version": -1,
		"status": STATUS_MISSING,
		"message": "没有找到存档。",
	}
	if not FileAccess.file_exists(path):
		return result
	result.exists = true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.status = STATUS_PERMISSION
		result.message = "存档存在但无法打开（%s）：可能是权限或文件被占用。" % error_string(FileAccess.get_open_error())
		return result
	result.bytes = file.get_length()
	if result.bytes <= 0:
		file.close()
		result.status = STATUS_CORRUPT
		result.message = "存档是空文件。"
		return result
	if result.bytes > MAX_SAVE_BYTES:
		file.close()
		result.status = STATUS_TOO_LARGE
		result.message = "存档超过 %d 字节上限，拒绝读取。" % MAX_SAVE_BYTES
		return result
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		result.status = STATUS_CORRUPT
		result.message = "存档不是合法 JSON，无法继续；原文件保持不变。"
		return result
	var record: Dictionary = parsed
	var version: Variant = record.get("version")
	# Godot 的 JSON.parse_string 把数字统一解析成 float（4 -> 4.0），所以不能只认 TYPE_INT，
	# 否则真实存档会被误判成"缺整数版本号"。这里接受"整数值的 float"，其余仍算损坏。
	var int_like: bool = typeof(version) == TYPE_INT \
		or (typeof(version) == TYPE_FLOAT and is_equal_approx(float(version), round(float(version))))
	if not int_like:
		result.status = STATUS_CORRUPT
		result.message = "存档缺少整数版本号，视为损坏（不会当成旧版本自动修复）。"
		return result
	result.version = int(version)
	if int(version) != expected_version:
		result.status = STATUS_INCOMPATIBLE
		result.message = "存档版本为 %d，此处需要 %d。" % [int(version), expected_version]
		return result
	if typeof(record.get("state")) != TYPE_DICTIONARY:
		result.status = STATUS_CORRUPT
		result.message = "存档缺少 state 对象，校验不能通过。"
		return result
	# 到这里只证明"结构与版本匹配"；字段级校验仍归任务2的 SaveStore。
	result.status = STATUS_READABLE
	result.message = "结构与版本匹配，可交给存档层做完整校验。"
	return result

## 启动依赖检查：返回 {ok, missing, message}。
func check_resources() -> Dictionary:
	var missing: Array[String] = []
	for path: String in REQUIRED_RESOURCES:
		if not FileAccess.file_exists(path):
			missing.append(path)
	var message := "启动依赖齐全。" if missing.is_empty() else "缺少 %d 个必需资源：%s" % [missing.size(), ", ".join(missing)]
	return {"ok": missing.is_empty(), "missing": missing, "message": message}

## 环境摘要，写进交付/日志时用它，避免各处自己拼。
func environment_summary() -> Dictionary:
	return {
		"engine": Engine.get_version_info().get("string", "unknown"),
		"os": OS.get_name(),
		"user_data_dir": OS.get_user_data_dir(),
		"headless": DisplayServer.get_name() == "headless",
	}

func _recommend(primary: Dictionary) -> String:
	match primary.status:
		STATUS_MISSING:
			return "没有存档：可以新建。旧文件不会被本服务创建或删除。"
		STATUS_READABLE:
			return "已有可继续的存档；继续后由存档层完整校验，再决定是否替换当前状态。"
		STATUS_INCOMPATIBLE:
			return "存档版本不匹配：可以新建，或先备份后在明确任务里迁移；不会静默用旧档顶替。"
		STATUS_CORRUPT:
			return "存档损坏：建议保留原文件并新建；不使用 .bak 自动恢复（该策略未在本任务授权）。"
		STATUS_PERMISSION:
			return "存档无法打开：检查权限/占用后重试；重试不会改写文件。"
		STATUS_TOO_LARGE:
			return "存档异常大：拒绝读取，请人工确认文件来源。"
		_:
			return "存档状态未知。"
