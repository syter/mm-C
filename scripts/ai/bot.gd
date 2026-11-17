class_name Bot
extends RefCounted

## 很笨的机器人：找最近的敌人，手长就风筝、手短就贴上去，够得着就砍。
## 用途：一个人也能测试；联机冒烟测试里替代真人操作。不追求像人。


static func think(sim: BattleSim, id: int, rng: RandomNumberGenerator) -> Dictionary:
	var me: BattleSim.Fighter = sim.fighters.get(id)
	if me == null or not me.alive:
		return {}
	var target: BattleSim.Fighter = null
	var best: float = INF
	for f: BattleSim.Fighter in sim.fighters.values():
		if f.team == me.team or not f.alive:
			continue
		var d: float = me.pos.distance_to(f.pos)
		if d < best:
			best = d
			target = f
	if target == null:
		return {"move": Vector2.ZERO, "aim": me.aim, "attack": false}

	var to: Vector2 = target.pos - me.pos
	var my_reach: float = sim.hit_dist(me)
	var their_reach: float = sim.hit_dist(target)
	var dir: Vector2 = to.normalized()
	var mv: Vector2
	if my_reach > their_reach + BattleSim.BODY_R * 1.3 and best < their_reach + BattleSim.BODY_R * 2.3:
		mv = -dir  # 对面手短，拉开
	elif best > my_reach * 0.8:
		mv = dir
	else:
		mv = Vector2.ZERO
	# 加点横向晃动，免得两个机器人直线对冲
	var strafe: Vector2 = dir.orthogonal() * sin(sim.time * 2.0 + float(id)) * 0.6
	mv = (mv + strafe).limit_length(1.0)
	var aim: float = to.angle() + rng.randf_range(-0.15, 0.15)
	return {"move": mv, "aim": aim, "attack": sim.can_hit(me, target)}
