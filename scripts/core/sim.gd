class_name BattleSim
extends RefCounted

## 纯逻辑的战斗模拟，不依赖任何节点，方便无头测试。
## 服务器跑 step()；客户端只用 apply_snapshot() 接收状态来渲染。

const ARENA: Vector2 = Vector2(640, 360)
## 武器 range 的 1 个单位 = 多少像素
const UNIT_PX: float = 20.0
## 移动速度 100 = 每秒 120 像素（横穿屏幕约 5 秒）
const SPEED_PX: float = 1.2
const BODY_R: float = 6.0
const BASE_HP: int = 100
const MARGIN: float = 12.0
const SWING_SHOW: float = 0.15
const HURT_SHOW: float = 0.2


class Fighter:
	var id: int = 0
	var name: String = ""
	var weapon: String = ""
	var pos: Vector2 = Vector2.ZERO
	var aim: float = 0.0
	var hp: int = BattleSim.BASE_HP
	var cd: float = 0.0
	var swing: float = 0.0
	var hurt: float = 0.0
	var alive: bool = true
	var kills: int = 0
	var color_idx: int = 0


var fighters: Dictionary = {}  # id -> Fighter
var time: float = 0.0
## 本帧发生的命中：{attacker, target, damage, killed}
var events: Array[Dictionary] = []


## entries: [{id, name, weapon}]，按顺序分配颜色和出生点
func setup(entries: Array, rng: RandomNumberGenerator) -> void:
	fighters.clear()
	time = 0.0
	var n: int = entries.size()
	var center: Vector2 = ARENA / 2.0
	var base_ang: float = rng.randf() * TAU
	for i in n:
		var e: Dictionary = entries[i]
		var f := Fighter.new()
		f.id = e["id"]
		f.name = e["name"]
		f.weapon = e["weapon"]
		f.color_idx = i
		var ang: float = base_ang + TAU * i / n
		# 椭圆分布，贴合 16:9 场地
		f.pos = center + Vector2(cos(ang) * 230.0, sin(ang) * 120.0)
		f.aim = (center - f.pos).angle()
		fighters[f.id] = f


func move_speed(f: Fighter) -> float:
	return float(Weapons.get_def(f.weapon)["speed"]) * SPEED_PX


## 攻击者中心到目标中心的最大命中距离
func hit_dist(f: Fighter) -> float:
	return BODY_R * 2.0 + float(Weapons.get_def(f.weapon)["range"]) * UNIT_PX


func can_hit(a: Fighter, t: Fighter) -> bool:
	var d: Vector2 = t.pos - a.pos
	var dist: float = d.length()
	if dist > hit_dist(a):
		return false
	if dist < BODY_R * 2.0:
		return true  # 贴脸了，不看角度
	var half: float = deg_to_rad(float(Weapons.get_def(a.weapon)["arc"])) / 2.0
	# 加上目标身体占的角度，擦边也算
	half += atan2(BODY_R, dist)
	return absf(angle_difference(a.aim, d.angle())) <= half


## inputs: id -> {move: Vector2, aim: float, attack: bool}
func step(dt: float, inputs: Dictionary) -> void:
	time += dt
	events.clear()
	var attackers: Array[Fighter] = []
	for f: Fighter in fighters.values():
		f.swing = maxf(f.swing - dt, 0.0)
		f.hurt = maxf(f.hurt - dt, 0.0)
		if not f.alive:
			continue
		f.cd = maxf(f.cd - dt, 0.0)
		var inp: Dictionary = inputs.get(f.id, {})
		var mv: Vector2 = inp.get("move", Vector2.ZERO)
		if mv.length() > 1.0:
			mv = mv.normalized()
		f.pos += mv * move_speed(f) * dt
		f.pos = f.pos.clamp(Vector2(MARGIN, MARGIN), ARENA - Vector2(MARGIN, MARGIN))
		f.aim = inp.get("aim", f.aim)
		if inp.get("attack", false) and f.cd <= 0.0:
			attackers.append(f)

	# 先判定所有命中再统一扣血，同一帧互砍两边都会中
	var pending: Array[Dictionary] = []
	for a in attackers:
		var w: Dictionary = Weapons.get_def(a.weapon)
		a.cd = float(w["cooldown"])
		a.swing = SWING_SHOW
		for t: Fighter in fighters.values():
			if t == a or not t.alive:
				continue
			if can_hit(a, t):
				pending.append({"attacker": a.id, "target": t.id, "damage": int(w["damage"])})
	for p in pending:
		var t: Fighter = fighters[p["target"]]
		if not t.alive:
			# 同帧被多人打死，后面的伤害照样记事件但不重复算击杀
			p["killed"] = false
			events.append(p)
			continue
		t.hp = maxi(t.hp - int(p["damage"]), 0)
		t.hurt = HURT_SHOW
		p["killed"] = false
		events.append(p)
	for p in events:
		var t: Fighter = fighters[p["target"]]
		if t.hp <= 0 and t.alive:
			t.alive = false
			p["killed"] = true
			(fighters[p["attacker"]] as Fighter).kills += 1


func kill(id: int) -> void:
	if fighters.has(id):
		var f: Fighter = fighters[id]
		f.alive = false
		f.hp = 0


func alive_count() -> int:
	var c: int = 0
	for f: Fighter in fighters.values():
		if f.alive:
			c += 1
	return c


func is_over() -> bool:
	return alive_count() <= 1


## 胜者 id；同归于尽返回 0（ENet 的 id 从 1 开始，机器人是负数，0 不会撞）
func winner_id() -> int:
	for f: Fighter in fighters.values():
		if f.alive:
			return f.id
	return 0


func snapshot() -> Array:
	var out: Array = []
	for f: Fighter in fighters.values():
		out.append([f.id, f.pos.x, f.pos.y, f.aim, f.hp, f.swing, f.hurt, f.alive, f.cd, f.kills])
	return out


func apply_snapshot(arr: Array) -> void:
	for row: Array in arr:
		if not fighters.has(row[0]):
			continue
		var f: Fighter = fighters[row[0]]
		f.pos = Vector2(row[1], row[2])
		f.aim = row[3]
		f.hp = row[4]
		f.swing = row[5]
		f.hurt = row[6]
		f.alive = row[7]
		f.cd = row[8]
		f.kills = row[9]
