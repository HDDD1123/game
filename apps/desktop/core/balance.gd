extends RefCounted
## 本轮试验数值。保持规则与窗口独立，DSH 不在 UI 中复制结算公式。
const INITIAL = {
	"months": 0, "population": 10, "housing": 14,
	"food": 30, "wood": 20, "ore": 0, "agriculture": 1, "forge": 0,
}
const EARLY_REFUGEES = {1: 4, 3: 6, 5: 8, 8: 4, 11: 5, 15: 6, 20: 4}
const RECURRING_REFUGEE_START = 23
const RECURRING_REFUGEE_INTERVAL = 3
const RECURRING_REFUGEE_SIZE = 6
const FOOD_BASE = 12
const FOOD_PER_FARM_LEVEL = 6
const WOOD_PER_PERSON = 0.6
const HOUSING_COST = 12
const HOUSING_GAIN = 6
const FARM_COST_BASE = 18
const FORGE_WOOD_BASE = 24
const FORGE_ORE_BASE = 5
const FORGE_MAX_LEVEL = 3
const DROUGHT_FROM = 6
const DROUGHT_UNTIL = 9
const DROUGHT_FACTOR = 0.6
const MAX_RECORDS = 40
const MAX_BATTLE_RECORDS = 12
const SITES = {
	"ruins": {"name": "林间废墟", "rooms": [
		{"name": "藤蔓入口", "threat": 9, "loot": {"food": 5, "wood": 4, "ore": 3}},
		{"name": "倒塌回廊", "threat": 15, "loot": {"food": 8, "wood": 6, "ore": 4}},
		{"name": "守门魔物", "threat": 22, "loot": {"food": 12, "wood": 8, "ore": 7}},
	]},
	"mine": {"name": "荒废矿井", "rooms": [
		{"name": "废弃矿道", "threat": 20, "loot": {"food": 5, "wood": 0, "ore": 6}},
		{"name": "地底巢穴", "threat": 30, "loot": {"food": 8, "wood": 3, "ore": 9}},
		{"name": "矿脉守卫", "threat": 42, "loot": {"food": 15, "wood": 5, "ore": 15}},
	]},
}
const ACHIEVEMENTS = {
	"housing": "为来者留一盏灯：首次扩建住房。",
	"agriculture": "在荒地上播种：首次改善农业。",
	"first-victory": "首战告捷：远征队第一次赢得战斗。",
	"ruins-clear": "废墟深处：通过林间废墟三层。",
	"forge": "炉火初燃：首次建成铁匠铺。",
	"mine-clear": "矿脉重见天日：通过荒废矿井三层。",
	"drought-survived": "旱季之后：王国度过一场旱季。",
}
