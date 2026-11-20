extends RefCounted
## 存档桥接层（格式5）。写入临时文件成功后才替换，保留上一份 .bak。
## 读取优先级：5 -> 4 -> 3；只有较新文件不存在才试较旧文件。
## 较新文件存在但损坏必须报错，不能静默回退旧档。
const VERSION = 5
const MAX_BYTES = 2097152
const PATH_V5 = "user://kingdom-save-v5.json"
const PATH_V4 = "user://kingdom-save-v4.json"
const PATH_V3 = "user://kingdom-save-v3.json"
var primary_path := PATH_V5
var legacy_path := PATH_V4
var ancient_path := PATH_V3

func save_game(game: RefCounted, path: String = "") -> Dictionary:
	if path.is_empty():
		path = primary_path
	var raw: String = JSON.stringify({"version": VERSION, "state": game.snapshot()}, "\t")
	var temporary: String = path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "无法创建临时存档：" + str(FileAccess.get_open_error())}
	file.store_string(raw)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return {"ok": false, "message": "写入失败，原存档未替换。"}
	var backup: String = path + ".bak"
	var had_original: bool = FileAccess.file_exists(path)
	if had_original:
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
			return {"ok": false, "message": "无法更新备份，原存档未替换。"}
		if DirAccess.rename_absolute(path, backup) != OK:
			return {"ok": false, "message": "无法备份原存档，保存中止。"}
	if DirAccess.rename_absolute(temporary, path) != OK:
		if had_original:
			var restore_error: Error = DirAccess.rename_absolute(backup, path)
			if restore_error != OK:
				return {"ok": false, "message": "替换及恢复失败，原存档保留在 .bak，请勿删除。"}
		return {"ok": false, "message": "替换存档失败，原文件已恢复。"}
	return {"ok": true, "message": "已手动保存（格式5）。下次打开点击读取，不补算离线时间。"}

func load_game(game: RefCounted, path: String = "") -> Dictionary:
	if not path.is_empty():
		return _load_any(game, path)
	if FileAccess.file_exists(primary_path):
		return _load_any(game, primary_path)
	if FileAccess.file_exists(legacy_path):
		return _load_any(game, legacy_path)
	if FileAccess.file_exists(ancient_path):
		return _load_any(game, ancient_path)
	return {"ok": false, "message": "没有可读取的存档，或文件无法打开。"}

func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_length() > MAX_BYTES:
		file.close()
		return {}
	var content: String = file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(content) != OK:
		return {}
	var parsed = parser.data
	return parsed if parsed is Dictionary else {}

func _load_any(game: RefCounted, path: String) -> Dictionary:
	var parsed: Dictionary = _read_json(path)
	if parsed.is_empty():
		return {"ok": false, "message": "存档无法解析或过大，当前进度未改变。"}
	var version: Variant = parsed.get("version")
	if typeof(version) != TYPE_INT and typeof(version) != TYPE_FLOAT:
		return {"ok": false, "message": "存档版本必须为数字。"}
	if version == VERSION:
		if not game.import_snapshot(parsed.get("state")):
			return {"ok": false, "message": "存档数据校验失败，当前进度未改变。"}
		return {"ok": true, "message": "已恢复资源、事件、远征、农田、技能与时钟，未推进月份。"}
	if version == 4:
		if not game.import_v4(parsed.get("state")):
			return {"ok": false, "message": "格式4存档校验失败，当前进度未改变。"}
		return {"ok": true, "message": "已从格式4迁移（旧文件保留）；时钟置0，不追补产出。"}
	if version == 3:
		if not game.import_v3(parsed.get("state")):
			return {"ok": false, "message": "格式3存档校验失败，当前进度未改变。"}
		return {"ok": true, "message": "已从格式3迁移（旧文件保留）；不追补历史产出。"}
	return {"ok": false, "message": "存档格式或版本不符，当前进度未改变。"}
