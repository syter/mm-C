class_name Weapons
extends RefCounted

## 武器表。
## range / damage / speed 是设计定的数值；
## cooldown（攻击间隔，秒）也是设计定的；arc（挥击扇形角度）还是占位值 —— 见 DESIGN.md「待定项」。
## knockback：被打中时往后推多远，单位跟 range 一样（1 = 40 像素）。2026-11-17 定。
const TABLE: Dictionary = {
	"dagger": {
		"name": "匕首", "range": 1.0, "damage": 45, "speed": 150,
		"cooldown": 0.5, "arc": 90.0, "knockback": 0.25, "color": Color(0.85, 0.88, 0.95),
	},
	"spear": {
		"name": "长枪", "range": 2.0, "damage": 40, "speed": 100,
		"cooldown": 1.0, "arc": 30.0, "knockback": 1.0, "color": Color(0.80, 0.62, 0.38),
	},
	"whip": {
		"name": "铁鞭", "range": 4.0, "damage": 34, "speed": 70,
		"cooldown": 0.8, "arc": 120.0, "knockback": 0.5, "color": Color(0.55, 0.58, 0.62),
	},
}

## 轮抽时能刷出来的武器（手枪、盾牌之后加）
const POOL: Array[String] = ["dagger", "spear", "whip"]


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
