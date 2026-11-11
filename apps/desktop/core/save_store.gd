extends RefCounted
## 存档桥接层（格式4）。写入临时文件成功后才替换，保留上一份 .bak。
## 格式3迁移：仅当尚无格式4文件时读取旧文件并迁移，旧文件保留。
const VERSION = 4
const MAX_BYTES = 2097152
const PATH_V4 = "user://kingdom-save-v4.json"
const PATH_V3 = "user://kingdom-save-v3.json"

func save_game(game: RefCounted, path: String = PATH_V4) -> Dictionary:
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
	return {"ok": true, "message": "已手动保存（格式4）。下次打开点击读取，不补算离线时间。"}

func load_game(game: RefCounted, path: String = PATH_V4) -> Dictionary:
	if FileAccess.file_exists(path):
		return _load_v4(game, path)
	if FileAccess.file_exists(PATH_V3):
		return _migrate_v3(game)
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

func _load_v4(game: RefCounted, path: String) -> Dictionary:
	var parsed: Dictionary = _read_json(path)
	if parsed.is_empty() or parsed.get("version") != VERSION:
		return {"ok": false, "message": "存档格式或版本不符，当前进度未改变。"}
	if not game.import_snapshot(parsed.get("state")):
		return {"ok": false, "message": "存档数据校验失败，当前进度未改变。"}
	return {"ok": true, "message": "已恢复资源、事件、远征、农田与技能，未推进月份。"}

func _migrate_v3(game: RefCounted) -> Dictionary:
	var parsed: Dictionary = _read_json(PATH_V3)
	if parsed.is_empty() or parsed.get("version") != 3:
		return {"ok": false, "message": "旧存档无法识别，当前进度未改变。"}
	if not game.import_v3(parsed.get("state")):
		return {"ok": false, "message": "旧存档校验失败，当前进度未改变。"}
	return {"ok": true, "message": "已从格式3迁移（旧文件保留）；本次不追补历史产出。"}
