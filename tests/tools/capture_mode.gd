extends SceneTree

## 截图工具：直接摆出「轮抽（6 把武器）」「模式选择（我是决定的人，选了 2v3）」「分队战斗」三个画面，不走联网。
## 跑法（不能加 --headless，无头不渲染）：
##   godot --path . --script res://tests/tools/capture_mode.gd -- <输出目录>
## 注意：root.get_texture() 拿到的是上一帧，所以每次摆好状态后都要等几帧再截。

var main: Node
var frame: int = 0
var out_dir: String = "user://"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)


func _process(_dt: float) -> bool:
	frame += 1
	var net: Node = root.get_node("Net")
	if frame == 3:
		# 离线时 Godot 默认挂着 OfflineMultiplayerPeer，my_id() = 1、is_server() = true。
		# 所以「我」用 id 1，并关掉 Net 的物理帧，免得它当服务器把机器人跑起来。
		net.set_physics_process(false)
		net.players = {1: {"name": "我", "bot": false}, -1: {"name": "阿强", "bot": true},
			-2: {"name": "小美", "bot": true}, -3: {"name": "老王", "bot": true}, -4: {"name": "豆豆", "bot": true}}
		net.draft = {"order": [-1, -2, 1, -3, -4], "weapons": ["scythe", "dagger", "boomerang", "staff", "whip", "spear"],
			"taken": [-1, -2, 0, 0, 0, 0], "turn": 2, "time_left": 20.0}
		net._set_phase_local(net.Phase.DRAFT)
		net._sync_draft(net.draft)
	elif frame == 15:
		_save("shot_draft.png")
		net.draft = {"order": [-1, -2, -3, -4, 1], "weapons": ["scythe", "dagger", "boomerang", "staff", "whip", "spear"],
			"taken": [-1, -2, 1, -3, -4, 0], "turn": 5, "time_left": 0.0}
		net._set_phase_local(net.Phase.MODE)
		net._sync_mode({"chooser": 1, "time_left": 30.0})
		main.sel_k = 2
		main.sel_a = [1, -2]
		main._refresh_mode()
	elif frame == 27:
		_save("shot_mode.png")
		# 分队战斗：我 + 小美 红队，其余蓝队
		var entries: Array = [
			{"id": 1, "name": "我", "weapon": "boomerang", "team": 0}, {"id": -2, "name": "小美", "weapon": "dagger", "team": 0},
			{"id": -1, "name": "阿强", "weapon": "scythe", "team": 1}, {"id": -3, "name": "老王", "weapon": "staff", "team": 1},
			{"id": -4, "name": "豆豆", "weapon": "whip", "team": 1}]
		net._start_battle(entries, 7, {"k": 2, "side_a": [1, -2]})
		var sim: BattleSim = net.sim
		var pos := {1: Vector2(250, 190), -2: Vector2(330, 160), -1: Vector2(400, 210), -3: Vector2(150, 110), -4: Vector2(470, 120)}
		for id: int in pos:
			var f: BattleSim.Fighter = sim.fighters[id]
			f.pos = pos[id]
			f.aim = (Vector2(330, 180) - f.pos).angle()
		(sim.fighters[-1] as BattleSim.Fighter).hp = 62
		(sim.fighters[-3] as BattleSim.Fighter).swing = 0.1  # 长棍转圈
		(sim.fighters[-1] as BattleSim.Fighter).swing = 0.1  # 镰刀挥
		# 我的回旋镖正在飞
		var pr := BattleSim.Proj.new()
		pr.owner = 1
		pr.pos = Vector2(320, 205)
		sim.projs.append(pr)
		(sim.fighters[1] as BattleSim.Fighter).proj_out = true
	elif frame == 42:
		_save("shot_team_battle.png")
		quit(0)
	return false


func _save(name: String) -> void:
	var path: String = out_dir.path_join(name)
	root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path)
