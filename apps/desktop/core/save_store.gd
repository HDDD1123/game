extends RefCounted
## 存档桥接层。写入临时文件成功后才替换，保留上一份 .bak。
const VERSION = 3
const MAX_BYTES = 2097152

func save_game(game: RefCounted, path: String = "user://kingdom-save-v3.json") -> Dictionary:
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
	return {"ok": true, "message": "已手动保存。下次打开点击读取，不补算离线时间。"}

func load_game(game: RefCounted, path: String = "user://kingdom-save-v3.json") -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "message": "没有可读取的存档，或文件无法打开。"}
	if file.get_length() > MAX_BYTES:
		file.close()
		return {"ok": false, "message": "存档过大，当前进度未改变。"}
	var content: String = file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(content) != OK:
		return {"ok": false, "message": "存档不是有效JSON，当前进度未改变。"}
	var parsed = parser.data
	if not parsed is Dictionary or parsed.get("version") != VERSION:
		return {"ok": false, "message": "存档格式或版本不符，当前进度未改变。"}
	if not game.import_snapshot(parsed.get("state")):
		return {"ok": false, "message": "存档数据校验失败，当前进度未改变。"}
	return {"ok": true, "message": "已恢复资源、事件、远征和手记，未推进月份。"}
