extends RefCounted
## 纯窗口几何工具（任务4 T4-03）。只计算矩形，**不**设置窗口、不读配置、不写文件。
##
## 为什么单独存在：窗口位置的唯一写入者仍是任务1的主UI（`user://window-config.json`）。
## 任务4只提供"推荐工作区矩形/贴边/夹取"这类可被主UI调用的纯函数，避免两个脚本互相拉扯。
## 全部函数为 static，可在无窗口的 headless 测试里直接调用。

const MIN_WIDTH := 720
const MIN_HEIGHT := 360

## 把期望矩形夹进可用工作区（任务栏之外），并保证不小于最小尺寸。
## 可用区放不下最小尺寸时，以可用区的左上角为准并返回可用区大小（宁可靠边，也不越出任务栏）。
static func clamp_to_usable(desired: Rect2i, usable: Rect2i, min_size: Vector2i = Vector2i(MIN_WIDTH, MIN_HEIGHT)) -> Rect2i:
	if usable.size.x <= 0 or usable.size.y <= 0:
		return Rect2i(desired)
	var size := desired.size
	size.x = maxi(size.x, mini(min_size.x, usable.size.x))
	size.y = maxi(size.y, mini(min_size.y, usable.size.y))
	size.x = mini(size.x, usable.size.x)
	size.y = mini(size.y, usable.size.y)
	var position := desired.position
	position.x = clampi(position.x, usable.position.x, usable.position.x + usable.size.x - size.x)
	position.y = clampi(position.y, usable.position.y, usable.position.y + usable.size.y - size.y)
	return Rect2i(position, size)

## 推荐矩形：按锚点把 preferred 尺寸放进可用区（居中/右上/左下等），再夹一次。
static func recommended_rect(usable: Rect2i, preferred: Vector2i, anchor: String = "center") -> Rect2i:
	var size := Vector2i(mini(preferred.x, usable.size.x), mini(preferred.y, usable.size.y))
	var position := usable.position
	match anchor:
		"center":
			position = usable.position + (usable.size - size) / 2
		"top_left":
			position = usable.position
		"top_right":
			position = Vector2i(usable.position.x + usable.size.x - size.x, usable.position.y)
		"bottom_left":
			position = Vector2i(usable.position.x, usable.position.y + usable.size.y - size.y)
		"bottom_right":
			position = usable.position + usable.size - size
		_:
			position = usable.position + (usable.size - size) / 2
	return clamp_to_usable(Rect2i(position, size), usable)

## 贴底条（底部街景）矩形：工作区底部，占满宽度。
static func bottom_dock_rect(usable: Rect2i, height: int) -> Rect2i:
	var dock_height := clampi(height, 1, usable.size.y)
	var position := Vector2i(usable.position.x, usable.position.y + usable.size.y - dock_height)
	return clamp_to_usable(Rect2i(position, Vector2i(usable.size.x, dock_height)), usable)

## 是否完全位于可用区内（用于布局断言：只检查应可见区域）。
static func is_inside(rect: Rect2i, usable: Rect2i) -> bool:
	return rect.position.x >= usable.position.x \
		and rect.position.y >= usable.position.y \
		and rect.position.x + rect.size.x <= usable.position.x + usable.size.x \
		and rect.position.y + rect.size.y <= usable.position.y + usable.size.y

## 两个矩形是否相交（面板互相遮挡的廉价检查）。
static func overlaps(a: Rect2i, b: Rect2i) -> bool:
	return a.intersects(b)

## 纯几何：把 100% 逻辑像素的矩形按缩放换算，用于高 DPI 下预估实际占用。
static func scale_rect(rect: Rect2i, scale: float) -> Rect2i:
	if scale <= 0.0 or is_nan(scale):
		return Rect2i(rect)
	return Rect2i(
		Vector2i(roundi(rect.position.x * scale), roundi(rect.position.y * scale)),
		Vector2i(roundi(rect.size.x * scale), roundi(rect.size.y * scale))
	)
