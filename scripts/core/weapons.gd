class_name Weapons
extends RefCounted

## 武器表。所有数值都是设计定的（2026-11-17）。
## - range：攻击范围，单位 1 = 40 像素（回旋镖是飞多远）
## - damage：伤害。所有武器必须落在 34–49 → 任意组合都是 3 下杀（测试锁住）
## - speed：移速，100 = 基准
## - cooldown：攻击间隔，秒（回旋镖是「接住后到能再丢」的间隔，真正的节奏由飞行来回决定）
## - arc：挥击扇形角度；360 = 打一圈（长棍）
## - knockback：被打中往外推多远，单位同 range；负数 = 往自己这边拉（镰刀）
## - projectile：飞行道具武器（回旋镖），proj_speed 像素/秒，proj_r 判定半径像素
const TABLE: Dictionary = {
	"dagger": {
		"name": "匕首", "range": 1.0, "damage": 45, "speed": 150,
		"cooldown": 0.5, "arc": 90.0, "knockback": 0.25, "color": Color(0.85, 0.88, 0.95),
	},
	"spear": {
		"name": "长枪", "range": 2.0, "damage": 40, "speed": 100,
		"cooldown": 1.0, "arc": 45.0, "knockback": 1.0, "color": Color(0.80, 0.62, 0.38),
	},
	"staff": {
		"name": "长棍", "range": 2.5, "damage": 36, "speed": 100,
		"cooldown": 1.2, "arc": 360.0, "knockback": 0.75, "color": Color(0.62, 0.45, 0.28),
	},
	"scythe": {
		"name": "镰刀", "range": 3.0, "damage": 38, "speed": 85,
		"cooldown": 0.8, "arc": 100.0, "knockback": -1.0, "color": Color(0.72, 0.75, 0.80),
	},
	"boomerang": {
		"name": "回旋镖", "range": 3.5, "damage": 35, "speed": 110,
		"cooldown": 0.1, "arc": 0.0, "knockback": 0.25, "color": Color(0.85, 0.65, 0.30),
		"projectile": true, "proj_speed": 400.0, "proj_r": 8.0,
	},
	"whip": {
		"name": "铁鞭", "range": 4.0, "damage": 34, "speed": 70,
		"cooldown": 0.8, "arc": 120.0, "knockback": 0.5, "color": Color(0.55, 0.58, 0.62),
	},
}

## 轮抽时能刷出来的武器（手枪、盾牌之后加）
const POOL: Array[String] = ["dagger", "spear", "staff", "scythe", "boomerang", "whip"]


static func get_def(id: String) -> Dictionary:
	return TABLE[id]


## 刷出 count 把武器。池子够大就不重复；不够（人多）就允许重复。
static func roll(count: int, rng: RandomNumberGenerator) -> Array[String]:
	var bag: Array[String] = POOL.duplicate()
	_shuffle(bag, rng)
	var out: Array[String] = []
	for i in count:
		if i < bag.size():
			out.append(bag[i])
		else:
			out.append(POOL[rng.randi_range(0, POOL.size() - 1)])
	_shuffle(out, rng)
	return out


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t
