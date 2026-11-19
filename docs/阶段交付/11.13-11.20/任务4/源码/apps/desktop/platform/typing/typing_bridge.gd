extends Node
## 后台输入桥（任务4 T4-05）。把 Windows 助手的**整数计数**接进游戏，除此之外什么都不做。
##
## 公开接口（与 docs/四机接口约定.md B 节一致）：
##   start(helper_path) -> {ok, message}   显式开启；默认关闭；重复调用不创建第二个进程
##   stop() -> void                        幂等关闭；清空计数；结束进程；节点销毁时自动调用
##   drain_count() -> int                  取出未消费汇总并清零（同一批只返回一次）
##   status() -> {enabled, helper_running, last_error}
##
## 4.6.3 的传输方式（重要实现说明）：
##   Godot 4.6.3 **没有**读取子进程 stdout 的 API（OS.execute 会阻塞主线程，OS.create_process 不给管道）。
##   因此这里用"助手把同样的协议行写到会话文件、桥接每 250ms 增量读文件"的方式；
##   协议内容、校验规则、序号/上限语义与 stdout 版完全一致，助手用 `--out` 参数切换。
##   若将来引擎提供非阻塞管道，只需替换 `_read_new_lines()`，公开接口不变。
##
## 不做的事：不推进时间、不改粮食/人口/加速倍率、不写存档、不发网络请求。
## 暂停/满田/关闭时应由调用方 stop()，恢复时 start() 新会话——旧会话残留不会补发。

const PROTOCOL_VERSION := 1
const MAX_LINE_BYTES := 512
const MAX_COUNT_PER_FRAME := 1000
const MAX_PENDING := 10000          ## 累积上限：超出后丢弃并记错误，避免内存里堆一个假额度
const POLL_INTERVAL_SEC := 0.25
const SESSION_PREFIX := "user://typing-session-"

var _enabled := false
var _pid := -1
var _session_path := ""
var _offset := 0
var _tail := ""
var _last_seq := 0
var _pending := 0
var _last_error := ""
var _timer: Timer

func _init() -> void:
	_timer = Timer.new()
	_timer.wait_time = POLL_INTERVAL_SEC
	_timer.one_shot = false
	_timer.autostart = false
	_timer.timeout.connect(_poll)
	add_child(_timer)

func _notification(what: int) -> void:
	# 节点销毁/退出场景树时必须清理，防止助手残留。
	if what == NOTIFICATION_PREDELETE:
		stop()

func _exit_tree() -> void:
	stop()

## 显式开启。helper_path 指向 TypingCounter.exe；不存在就报错，不假装成功。
func start(helper_path: String) -> Dictionary:
	if _enabled:
		return {"ok": true, "message": "后台输入已在运行，未重复启动。"}
	if not FileAccess.file_exists(helper_path):
		_last_error = "helper-missing"
		return {"ok": false, "message": "助手不存在：%s" % helper_path}
	var absolute_helper := ProjectSettings.globalize_path(helper_path)
	if not DirAccess.dir_exists_absolute(absolute_helper.get_base_dir()):
		_last_error = "helper-dir-missing"
		return {"ok": false, "message": "助手目录不存在。"}
	var session := "%s%s-%d.log" % [SESSION_PREFIX, str(OS.get_process_id()), Time.get_ticks_usec()]
	var absolute_session := ProjectSettings.globalize_path(session)
	if FileAccess.file_exists(absolute_session):
		DirAccess.remove_absolute(absolute_session)
	var pid := OS.create_process(absolute_helper, PackedStringArray(["--out", absolute_session]))
	if pid <= 0:
		_last_error = "spawn-failed"
		return {"ok": false, "message": "无法启动助手进程（系统拒绝或路径不可执行）。"}
	_reset_session_state()
	_enabled = true
	_pid = pid
	_session_path = absolute_session
	_last_error = ""
	_timer.start()
	return {"ok": true, "message": "后台输入已开启（进程 %d）。" % pid}

## 幂等关闭：结束进程、删会话文件、清空缓存。调用两次结果一样。
func stop() -> void:
	_timer.stop()
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	if not _session_path.is_empty() and FileAccess.file_exists(_session_path):
		DirAccess.remove_absolute(_session_path)
	_reset_session_state()
	_enabled = false
	_last_error = ""

## 取出当前汇总并清零。没有任何计数时返回 0（不是错误）。
func drain_count() -> int:
	var value := _pending
	_pending = 0
	return value

func status() -> Dictionary:
	return {
		"enabled": _enabled,
		"helper_running": _pid > 0 and OS.is_process_running(_pid),
		"last_error": _last_error,
	}

## 供测试/诊断：最近的序号，便于断言"新会话重新开始"。
func last_seq() -> int:
	return _last_seq

func _reset_session_state() -> void:
	_offset = 0
	_tail = ""
	_last_seq = 0
	_pending = 0
	_session_path = ""

func _poll() -> void:
	if not _enabled:
		return
	if _pid > 0 and not OS.is_process_running(_pid):
		# 助手崩溃：不拖死游戏，只标记并停止轮询；计数留在 _pending 里由调用方决定是否使用。
		_last_error = "helper-exited"
		_timer.stop()
		return
	for line: String in _read_new_lines():
		_ingest_line(line)

## 增量读取会话文件中尚未消费的完整行；不完整的一行留到下次。
func _read_new_lines() -> Array[String]:
	var lines: Array[String] = []
	if _session_path.is_empty() or not FileAccess.file_exists(_session_path):
		return lines
	var file := FileAccess.open(_session_path, FileAccess.READ)
	if file == null:
		_last_error = "session-unreadable"
		return lines
	var length := file.get_length()
	if length <= _offset:
		file.close()
		return lines
	file.seek(_offset)
	var chunk := file.get_buffer(length - _offset)
	_offset = length
	file.close()
	var text := _tail + chunk.get_string_from_utf8()
	_tail = ""
	var parts := text.split("\n")
	# 最后一段没有换行符 = 半行，保留到下次
	if not text.ends_with("\n"):
		_tail = parts[parts.size() - 1]
		parts.remove_at(parts.size() - 1)
	for part: String in parts:
		var line := part.strip_edges()
		if not line.is_empty():
			lines.append(line)
	if _tail.to_utf8_buffer().size() > MAX_LINE_BYTES:
		_last_error = "line-too-long"
		_tail = ""
	return lines

## 校验一行协议并累加。任何不合规的行都丢弃并记录错误，不猜测、不计入。
func _ingest_line(line: String) -> void:
	if line.to_utf8_buffer().size() > MAX_LINE_BYTES:
		_last_error = "line-too-long"
		return
	var parsed: Variant = JSON.parse_string(line)
	if typeof(parsed) != TYPE_DICTIONARY:
		_last_error = "bad-json"
		return
	var frame: Dictionary = parsed
	if not frame.has("v") or not (typeof(frame["v"]) in [TYPE_INT, TYPE_FLOAT]) or int(frame["v"]) != PROTOCOL_VERSION:
		_last_error = "bad-version"
		return
	if not frame.has("seq") or not (typeof(frame["seq"]) in [TYPE_INT, TYPE_FLOAT]):
		_last_error = "bad-seq"
		return
	if not frame.has("count") or not (typeof(frame["count"]) in [TYPE_INT, TYPE_FLOAT]):
		_last_error = "bad-count"
		return
	var seq := int(frame["seq"])
	var count := int(frame["count"])
	if count < 0 or count > MAX_COUNT_PER_FRAME:
		_last_error = "count-out-of-range"
		return
	if seq <= _last_seq:
		# 重复或倒退序号：同一批不能消费两次。
		_last_error = "seq-not-increasing"
		return
	_last_seq = seq
	if _pending + count > MAX_PENDING:
		_pending = MAX_PENDING
		_last_error = "pending-capped"
		return
	_pending += count

## 由 tick 时钟派生的"是否允许提交"判断只属于调用方；桥接不碰助耕倍率。
func is_running() -> bool:
	return _enabled and _pid > 0 and OS.is_process_running(_pid)
