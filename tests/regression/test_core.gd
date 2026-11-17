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

	print("[尺寸三件套等比]")
	# 身体 / 范围单位 / 移速 必须一起缩放，比例变了平衡就变了（基准是 v0.1 的 6 / 20 / 1.2）
	check(is_equal_approx(BattleSim.UNIT_PX / BattleSim.BODY_R, 20.0 / 6.0), "范围单位 : 身体 比例不变")
	check(is_equal_approx(BattleSim.SPEED_PX / BattleSim.BODY_R, 1.2 / 6.0), "移速 : 身体 比例不变")
	check(BattleSim.MARGIN >= BattleSim.BODY_R, "边界留白 ≥ 身体半径")

	print("[命中判定]")
	a.pos = Vector2(100, 100)
	a.aim = 0.0
	b.pos = Vector2(100 + sim.hit_dist(a) - 1.0, 100)
	check(sim.can_hit(a, b), "射程内正前方能打中")
	b.pos = Vector2(100 + sim.hit_dist(a) + 2.0, 100)
	check(not sim.can_hit(a, b), "射程外打不中")
	b.pos = Vector2(100 - 40, 100)
	check(not sim.can_hit(a, b), "背后打不中")

	print("[伤害与击杀]")
	b.pos = Vector2(115, 100)
	sim.step(0.016, {1: {"move": Vector2.ZERO, "aim": 0.0, "attack": true}})
	check(b.hp == 55, "匕首一刀 45")
	sim.step(0.016, {1: {"move": Vector2.ZERO, "aim": 0.0, "attack": true}})
	check(b.hp == 55, "冷却中不能连砍")
	for i in 35:  # 匕首间隔 0.5 秒
		sim.step(0.016, {1: {"move": Vector2.ZERO, "aim": 0.0, "attack": true}})
	check(b.alive and b.hp == 10, "第二刀还活着（10 血）")
	for i in 35:
		sim.step(0.016, {1: {"move": Vector2.ZERO, "aim": 0.0, "attack": true}})
	check(not b.alive and a.kills == 1, "第三刀击杀")
	check(sim.is_over() and sim.winner_id() == 1, "只剩一人时结束")

	print("[同帧互砍]")
	sim.setup([{"id": 1, "name": "a", "weapon": "dagger"}, {"id": 2, "name": "b", "weapon": "dagger"}], rng)
	a = sim.fighters[1]
	b = sim.fighters[2]
	a.pos = Vector2(100, 100)
	b.pos = Vector2(115, 100)
	a.hp = 40
	b.hp = 40
	sim.step(0.016, {1: {"aim": 0.0, "attack": true}, 2: {"aim": PI, "attack": true}})
	check(not a.alive and not b.alive and sim.winner_id() == 0, "同归于尽 → 平局")

	print("[平衡约束：所有武器都是 3 下杀，混着打也一样]")
	var dmgs: Array[int] = []
	for wid: String in Weapons.POOL:
		dmgs.append(int(Weapons.get_def(wid)["damage"]))
	check(dmgs.max() * 2 < BattleSim.BASE_HP, "任意两下都杀不死（最大伤害 ×2 < 100）")
	check(dmgs.min() * 3 >= BattleSim.BASE_HP, "任意三下必杀（最小伤害 ×3 ≥ 100）")

	print("[分队：不打队友]")
	var ts := BattleSim.new()
	ts.setup([{"id": 1, "name": "a", "weapon": "whip", "team": 0}, {"id": 2, "name": "b", "weapon": "dagger", "team": 0},
		{"id": 3, "name": "c", "weapon": "spear", "team": 1}], rng)
	var t1: BattleSim.Fighter = ts.fighters[1]
	var t2: BattleSim.Fighter = ts.fighters[2]
	var t3: BattleSim.Fighter = ts.fighters[3]
	t1.pos = Vector2(200, 180)
	t2.pos = Vector2(250, 180)
	t3.pos = Vector2(260, 200)
	ts.step(0.016, {1: {"aim": 0.0, "attack": true}})
	check(t2.hp == 100 and t2.kb == Vector2.ZERO, "铁鞭扫到队友：不掉血、不被击退")
	check(t3.hp == 66, "同一下扫到敌人：照常掉血")
	check(not ts.is_over(), "两队都还有人：没结束")
	ts.kill(3)
	check(ts.is_over() and ts.fighters[ts.winner_id()].team == 0, "敌队全灭：我方队伍获胜（两人都活着也算结束）")

	print("[击退]")
	for wid: String in Weapons.POOL:
		var ks := BattleSim.new()
		ks.setup([{"id": 1, "name": "a", "weapon": wid}, {"id": 2, "name": "b", "weapon": "dagger"}], rng)
		var ka: BattleSim.Fighter = ks.fighters[1]
		var kt: BattleSim.Fighter = ks.fighters[2]
		ka.pos = Vector2(200, 180)
		ka.aim = 0.0
		kt.pos = Vector2(200 + BattleSim.BODY_R * 2.0 + 4.0, 180)
		var start_x: float = kt.pos.x
		ks.step(1.0 / 60.0, {1: {"aim": 0.0, "attack": true}})
		for i in 60:
			ks.step(1.0 / 60.0, {})
		var want: float = float(Weapons.get_def(wid)["knockback"]) * BattleSim.UNIT_PX
		var got: float = kt.pos.x - start_x
		check(absf(got - want) < 1.0 and absf(kt.pos.y - 180.0) < 0.01, "%s 击退 %.0f 像素（实际 %.1f），方向朝外" % [wid, want, got])
	var ws := BattleSim.new()
	ws.setup([{"id": 1, "name": "a", "weapon": "spear"}, {"id": 2, "name": "b", "weapon": "dagger"}], rng)
	(ws.fighters[1] as BattleSim.Fighter).pos = Vector2(BattleSim.ARENA.x - 60, 180)
	(ws.fighters[2] as BattleSim.Fighter).pos = Vector2(BattleSim.ARENA.x - 30, 180)
	ws.step(1.0 / 60.0, {1: {"aim": 0.0, "attack": true}})
	for i in 60:
		ws.step(1.0 / 60.0, {})
	check((ws.fighters[2] as BattleSim.Fighter).pos.x <= BattleSim.ARENA.x - BattleSim.MARGIN, "击退不会把人推出场地")

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
