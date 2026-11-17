extends SceneTree

## 核心逻辑回归测试（无头）：godot --headless --path . --script res://tests/regression/test_core.gd
## 另外顺手跑一个机器人对战统计，看三把武器 1v1 的胜率 —— 只是参考，机器人不像人。

var fails: int = 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		fails += 1


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	print("[武器刷新]")
	var r2: Array[String] = Weapons.roll(3, rng)
	check(r2.size() == 3, "2 人刷 3 把")
	var uniq := {}
	for w in r2:
		uniq[w] = true
	check(uniq.size() == 3, "池子够时不重复")
	check(Weapons.roll(9, rng).size() == 9, "8 人刷 9 把（允许重复）")

	print("[移动速度]")
	var sim := BattleSim.new()
	sim.setup([{"id": 1, "name": "a", "weapon": "dagger"}, {"id": 2, "name": "b", "weapon": "whip"}], rng)
	var a: BattleSim.Fighter = sim.fighters[1]
	var b: BattleSim.Fighter = sim.fighters[2]
	check(is_equal_approx(sim.move_speed(a) / sim.move_speed(b), 150.0 / 70.0), "匕首 150 / 铁鞭 70 速度比")

	print("[命中判定]")
	a.pos = Vector2(100, 100)
	a.aim = 0.0
	b.pos = Vector2(100 + sim.hit_dist(a) - 1.0, 100)
	check(sim.can_hit(a, b), "射程内正前方能打中")
	b.pos = Vector2(100 + sim.hit_dist(a) + 2.0, 100)
	check(not sim.can_hit(a, b), "射程外打不中")
	b.pos = Vector2(100 - 20, 100)
	check(not sim.can_hit(a, b), "背后打不中")

	print("[伤害与击杀]")
	b.pos = Vector2(115, 100)
	sim.step(0.016, {1: {"move": Vector2.ZERO, "aim": 0.0, "attack": true}})
	check(b.hp == 30, "匕首一刀 70")
	sim.step(0.016, {1: {"move": Vector2.ZERO, "aim": 0.0, "attack": true}})
	check(b.hp == 30, "冷却中不能连砍")
	for i in 70:  # 匕首间隔 1 秒
		sim.step(0.016, {1: {"move": Vector2.ZERO, "aim": 0.0, "attack": true}})
	check(not b.alive and a.kills == 1, "第二刀击杀")
	check(sim.is_over() and sim.winner_id() == 1, "只剩一人时结束")

	print("[同帧互砍]")
	sim.setup([{"id": 1, "name": "a", "weapon": "dagger"}, {"id": 2, "name": "b", "weapon": "dagger"}], rng)
	a = sim.fighters[1]
	b = sim.fighters[2]
	a.pos = Vector2(100, 100)
	b.pos = Vector2(115, 100)
	a.hp = 50
	b.hp = 50
	sim.step(0.016, {1: {"aim": 0.0, "attack": true}, 2: {"aim": PI, "attack": true}})
	check(not a.alive and not b.alive and sim.winner_id() == 0, "同归于尽 → 平局")

	print("[快照往返]")
	var s2 := BattleSim.new()
	s2.setup([{"id": 1, "name": "a", "weapon": "dagger"}, {"id": 2, "name": "b", "weapon": "dagger"}], rng)
	s2.apply_snapshot(sim.snapshot())
	check((s2.fighters[1] as BattleSim.Fighter).pos == a.pos and not (s2.fighters[2] as BattleSim.Fighter).alive, "快照还原位置和存活")

	_bot_duels(rng)
	print("\n%s（%d 个失败）" % ["全部通过" if fails == 0 else "有失败", fails])
	quit(1 if fails > 0 else 0)


func _bot_duels(rng: RandomNumberGenerator) -> void:
	print("\n[参考] 机器人 1v1 胜率，各 200 局（机器人很笨，只看大概倾向）")
	var ids: Array[String] = Weapons.POOL
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var wins := {1: 0, 2: 0, 0: 0}
			var total_t: float = 0.0
			for g in 200:
				var sim := BattleSim.new()
				sim.setup([{"id": 1, "name": "a", "weapon": ids[i]}, {"id": 2, "name": "b", "weapon": ids[j]}], rng)
				while not sim.is_over() and sim.time < 60.0:
					sim.step(1.0 / 60.0, {1: Bot.think(sim, 1, rng), 2: Bot.think(sim, 2, rng)})
				wins[sim.winner_id() if sim.is_over() else 0] += 1
				total_t += sim.time
			print("  %s vs %s：%d : %d（平/超时 %d）平均 %.1fs" % [ids[i], ids[j], wins[1], wins[2], wins[0], total_t / 200.0])
