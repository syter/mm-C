extends Node

## 联机 + 对局流程（autoload: Net）。
##
## 架构：主机即服务器（listen server），服务器权威。
## - 客户端只上传输入（移动方向 / 朝向 / 攻击），服务器跑 BattleSim，再广播快照。
## - 大厅 → 轮抽 → 战斗 → 结算 的状态机全在服务器，客户端只负责显示。
##
## 现在用 ENet（局域网 / 直连 IP）。接 Steam 时只需要把 host()/join() 里的
## ENetMultiplayerPeer 换成 GodotSteam 的 SteamMultiplayerPeer，其余 RPC 都不用动。

signal phase_changed(phase: int)
signal lobby_changed
signal draft_changed
signal mode_changed
signal battle_started
signal battle_ended(winner_id: int)
signal net_error(msg: String)
## 战斗特效/音效事件：swings = [出手者 id]，hits = [{attacker, target, damage, killed}]，catches = [接住回旋镖的人]
signal fx(swings: Array, hits: Array, catches: Array)

enum Phase { MENU, LOBBY, DRAFT, MODE, BATTLE, RESULT }

const DEFAULT_PORT: int = 24680
## 一局最多几人（真人 + 机器人一起算）。2026-11-17 定为 5
const MAX_PLAYERS: int = 5
const DRAFT_TIME: float = 20.0
const RESULT_TIME: float = 5.0
const MODE_TIME: float = 30.0
## 每几个物理帧广播一次快照（60fps / 2 = 30Hz）
const SNAP_EVERY: int = 2

var phase: int = Phase.MENU
var my_name: String = "玩家"
## id -> {name: String, bot: bool}，服务器同步给所有人
var players: Dictionary = {}
## {order: [id], weapons: [wid], taken: [id 或 0], turn: int, time_left: float}
var draft: Dictionary = {}
## 模式选择：{chooser: id, time_left: float}。最后一个选武器的人决定模式和分队
var mode_pick: Dictionary = {}
## 本局模式：{k: 0 = 各自为战 / k = 少的一边几个人, side_a: [id]}（side_a 是 A 队成员）
var match_mode: Dictionary = {"k": 0, "side_a": []}
## 测试用：机器人 / autoplay 当选模式的人时强制选这个 k（-1 = 随机）
var force_mode: int = -1
var sim: BattleSim = null
var last_winner: int = 0
## 本地玩家输入，由 Arena 每帧写入
var local_input: Dictionary = {"move": Vector2.ZERO, "aim": 0.0, "held": false, "seq": 0}
## 测试用：让本地玩家也由机器人操作
var autoplay: bool = false

var rng := RandomNumberGenerator.new()

# —— 以下只在服务器上用 ——
var _inputs: Dictionary = {}  # id -> {move, aim, held, seq}
var _last_seq: Dictionary = {}  # id -> 上次处理过的攻击序号
var _next_bot_id: int = -1
var _frame: int = 0
var _timer: float = 0.0
var _auto_sent: String = ""  # 客户端 autoplay 防止同一个回合重复发请求


func _ready() -> void:
	rng.randomize()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: _fail("连接失败"))
	multiplayer.server_disconnected.connect(func() -> void: _fail("主机断开了"))


func is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0


# ============ 建立 / 断开连接 ============

func host(port: int = DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_PLAYERS - 1)  # 参数是「客户端」上限，主机自己不算
	if err != OK:
		net_error.emit("开主机失败（端口 %d 被占用？）" % port)
		return false
	multiplayer.multiplayer_peer = peer
	players = {1: {"name": my_name, "bot": false}}
	_set_phase_local(Phase.LOBBY)
	lobby_changed.emit()
	return true


func join(ip: String, port: int = DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(ip, port)
	if err != OK:
		net_error.emit("连接失败")
		return false
	multiplayer.multiplayer_peer = peer
	return true


func leave() -> void:
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	sim = null
	_set_phase_local(Phase.MENU)


func _fail(msg: String) -> void:
	leave()
	net_error.emit(msg)


func _on_connected() -> void:
	_register.rpc_id(1, my_name)


func _on_peer_connected(_id: int) -> void:
	pass  # 等对方调用 _register 再加入大厅


func _on_peer_disconnected(id: int) -> void:
	if not is_server():
		return
	players.erase(id)
	_inputs.erase(id)
	match phase:
		Phase.DRAFT:
			_draft_remove(id)
		Phase.MODE:
			if players.size() < 2:
				_back_to_lobby()
			elif id == mode_pick.get("chooser", 0):
				_start_battle_server({"k": 0, "side_a": []})  # 决定的人跑了，直接各自为战
			else:
				_sync_mode.rpc(mode_pick)
		Phase.BATTLE:
			sim.kill(id)
	_sync_lobby.rpc(players)


# ============ 大厅 ============

@rpc("any_peer", "reliable")
func _register(pname: String) -> void:
	if not is_server():
		return
	var sid: int = multiplayer.get_remote_sender_id()
	if phase != Phase.LOBBY or players.size() >= MAX_PLAYERS:
		_rejected.rpc_id(sid, "对局已开始或房间已满")
		return
	players[sid] = {"name": pname.substr(0, 12), "bot": false}
	_set_phase.rpc_id(sid, phase)
	_sync_lobby.rpc(players)


@rpc("authority", "reliable")
func _rejected(reason: String) -> void:
	_fail(reason)


@rpc("authority", "call_local", "reliable")
func _sync_lobby(p: Dictionary) -> void:
	players = p
	lobby_changed.emit()


@rpc("authority", "call_local", "reliable")
func _set_phase(ph: int) -> void:
	_set_phase_local(ph)


func _set_phase_local(ph: int) -> void:
	phase = ph
	phase_changed.emit(ph)


func add_bot() -> void:
	if not is_server() or phase != Phase.LOBBY or players.size() >= MAX_PLAYERS:
		return
	var id: int = _next_bot_id
	_next_bot_id -= 1
	players[id] = {"name": "机器人%d" % -id, "bot": true}
	_sync_lobby.rpc(players)


func remove_bots() -> void:
	if not is_server() or phase != Phase.LOBBY:
		return
	for id: int in players.keys():
		if players[id]["bot"]:
			players.erase(id)
	_sync_lobby.rpc(players)


# ============ 轮抽 ============

func start_game() -> void:
	if not is_server() or phase != Phase.LOBBY or players.size() < 2:
		return
	var order: Array = players.keys()
	Weapons._shuffle(order, rng)
	var weapons: Array = Array(Weapons.roll(order.size() + 1, rng))
	var taken: Array = []
	taken.resize(weapons.size())
	taken.fill(0)
	draft = {"order": order, "weapons": weapons, "taken": taken, "turn": 0, "time_left": DRAFT_TIME}
	_timer = DRAFT_TIME
	_set_phase.rpc(Phase.DRAFT)
	_sync_draft.rpc(draft)


@rpc("authority", "call_local", "reliable")
func _sync_draft(d: Dictionary) -> void:
	draft = d
	draft_changed.emit()


func current_picker() -> int:
	if draft.is_empty() or draft["turn"] >= draft["order"].size():
		return 0
	return draft["order"][draft["turn"]]


## 本地玩家选第 slot 把武器
func pick(slot: int) -> void:
	if is_server():
		_do_pick(1, slot)
	else:
		_request_pick.rpc_id(1, slot)


@rpc("any_peer", "reliable")
func _request_pick(slot: int) -> void:
	if is_server():
		_do_pick(multiplayer.get_remote_sender_id(), slot)


func _do_pick(pid: int, slot: int) -> void:
	if phase != Phase.DRAFT or pid != current_picker():
		return
	if slot < 0 or slot >= draft["weapons"].size() or draft["taken"][slot] != 0:
		return
	draft["taken"][slot] = pid
	_advance_draft()


func _advance_draft() -> void:
	draft["turn"] += 1
	_timer = DRAFT_TIME
	draft["time_left"] = _timer
	_sync_draft.rpc(draft)
	if current_picker() == 0:
		_enter_mode_phase()


func _draft_remove(id: int) -> void:
	var idx: int = draft["order"].find(id)
	if idx < 0:
		return
	# 已经选过的就让武器空出来（反正人走了）
	var tslot: int = draft["taken"].find(id)
	if tslot >= 0:
		draft["taken"][tslot] = 0
	var was_current: bool = idx == draft["turn"]
	draft["order"].remove_at(idx)
	if idx < draft["turn"]:
		draft["turn"] -= 1
	if draft["order"].size() < 2:
		_back_to_lobby()
		return
	if was_current:
		draft["turn"] -= 1
		_advance_draft()
	else:
		_sync_draft.rpc(draft)


func _auto_pick(pid: int) -> void:
	var free: Array[int] = []
	for i in draft["taken"].size():
		if draft["taken"][i] == 0:
			free.append(i)
	_do_pick(pid, free[rng.randi_range(0, free.size() - 1)])


# ============ 战斗 ============

# ============ 模式选择 ============
## 最后一个选武器的人，在所有人选完之后决定：各自为战，或 k v 其余（k = 1 .. 人数/2），并且自己分队。

## 本局参战的人（选到了武器、还在线）
func fighters_in_draft() -> Array:
	var out: Array = []
	for i in draft["taken"].size():
		var pid: int = draft["taken"][i]
		if pid != 0 and players.has(pid):
			out.append(pid)
	return out


## 可选的 k：0 = 各自为战，1..n/2 = k v (n-k)
func mode_options() -> Array[int]:
	var n: int = fighters_in_draft().size()
	var out: Array[int] = [0]
	for k in range(1, n / 2 + 1):
		if not (n == 2 and k == 1):  # 两个人的 1v1 就是各自为战
			out.append(k)
	return out


func mode_name(k: int, n: int) -> String:
	return "各自为战" if k == 0 else "%dv%d" % [k, n - k]


func _enter_mode_phase() -> void:
	if mode_options().size() <= 1:
		_start_battle_server({"k": 0, "side_a": []})  # 只有两个人，没得选
		return
	mode_pick = {"chooser": draft["order"].back(), "time_left": MODE_TIME}
	_timer = MODE_TIME
	_sync_mode.rpc(mode_pick)
	_set_phase.rpc(Phase.MODE)


@rpc("authority", "call_local", "reliable")
func _sync_mode(d: Dictionary) -> void:
	mode_pick = d
	mode_changed.emit()


## 本地玩家（必须是决定的人）提交模式和 A 队名单
func choose_mode(k: int, side_a: Array) -> void:
	if is_server():
		_do_choose_mode(1, k, side_a)
	else:
		_request_mode.rpc_id(1, k, side_a)


@rpc("any_peer", "reliable")
func _request_mode(k: int, side_a: Array) -> void:
	if is_server():
		_do_choose_mode(multiplayer.get_remote_sender_id(), k, side_a)


func _do_choose_mode(pid: int, k: int, side_a: Array) -> void:
	if phase != Phase.MODE or pid != mode_pick.get("chooser", 0):
		return
	if not mode_options().has(k):
		return
	var alive: Array = fighters_in_draft()
	var clean: Array = []
	for id: int in side_a:
		if alive.has(id) and not clean.has(id):
			clean.append(id)
	if k > 0 and clean.size() != k:
		return
	_start_battle_server({"k": k, "side_a": clean if k > 0 else []})


## 机器人 / 超时：随机模式 + 随机分队（超时的真人默认各自为战）
func _auto_mode(random_mode: bool) -> Dictionary:
	var opts: Array[int] = mode_options()
	var k: int = 0
	if force_mode >= 0 and opts.has(force_mode):
		k = force_mode
	elif random_mode:
		k = opts[rng.randi_range(0, opts.size() - 1)]
	var ids: Array = fighters_in_draft()
	Weapons._shuffle(ids, rng)
	return {"k": k, "side_a": ids.slice(0, k)}


# ============ 战斗 ============

func _start_battle_server(mode: Dictionary) -> void:
	match_mode = mode
	var k: int = mode["k"]
	var entries: Array = []
	for i in draft["taken"].size():
		var pid: int = draft["taken"][i]
		if pid != 0 and players.has(pid):
			var e: Dictionary = {"id": pid, "name": players[pid]["name"], "weapon": draft["weapons"][i]}
			if k > 0:
				e["team"] = 0 if mode["side_a"].has(pid) else 1
			entries.append(e)
	_inputs.clear()
	_last_seq.clear()
	_start_battle.rpc(entries, rng.randi(), mode)


@rpc("authority", "call_local", "reliable")
func _start_battle(entries: Array, seed_v: int, mode: Dictionary) -> void:
	match_mode = mode
	_auto_sent = ""
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	sim = BattleSim.new()
	sim.setup(entries, r)
	local_input["seq"] = 0
	_set_phase_local(Phase.BATTLE)
	battle_started.emit()


@rpc("any_peer", "unreliable_ordered")
func _client_input(mv: Vector2, aim: float, held: bool, seq: int) -> void:
	if not is_server():
		return
	_inputs[multiplayer.get_remote_sender_id()] = {"move": mv, "aim": aim, "held": held, "seq": seq}


@rpc("authority", "unreliable_ordered")
func _snapshot(arr: Array) -> void:
	if sim != null and phase == Phase.BATTLE:
		sim.apply_snapshot(arr)


@rpc("authority", "call_local", "reliable")
func _fx(swings: Array, hits: Array, catches: Array) -> void:
	fx.emit(swings, hits, catches)


@rpc("authority", "call_local", "reliable")
func _end_battle(winner: int, final_snap: Array) -> void:
	if sim != null:
		sim.apply_snapshot(final_snap)
	last_winner = winner
	_set_phase_local(Phase.RESULT)
	battle_ended.emit(winner)


func _back_to_lobby() -> void:
	draft = {}
	_set_phase.rpc(Phase.LOBBY)
	_sync_lobby.rpc(players)


func _physics_process(dt: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if autoplay and phase == Phase.BATTLE and sim != null:
		var b: Dictionary = Bot.think(sim, my_id(), rng)
		if not b.is_empty():
			local_input["move"] = b["move"]
			local_input["aim"] = b["aim"]
			local_input["held"] = b["attack"]

	if autoplay and not is_server():
		_client_autoplay_choices()

	if not is_server():
		if phase == Phase.BATTLE:
			_client_input.rpc_id(1, local_input["move"], local_input["aim"], local_input["held"], local_input["seq"])
		return

	_frame += 1
	match phase:
		Phase.DRAFT:
			var cur: int = current_picker()
			if cur != 0 and (players.get(cur, {}).get("bot", false) or (cur == 1 and autoplay)):
				_auto_pick(cur)  # 机器人秒选
			else:
				_timer -= dt
				if _timer <= 0.0 and cur != 0:
					_auto_pick(cur)  # 超时随机选
		Phase.MODE:
			var ch: int = mode_pick.get("chooser", 0)
			if players.get(ch, {}).get("bot", false) or (ch == 1 and autoplay):
				_start_battle_server(_auto_mode(true))
			else:
				_timer -= dt
				if _timer <= 0.0:
					_start_battle_server({"k": 0, "side_a": []})  # 超时：各自为战
		Phase.BATTLE:
			_tick_battle(dt)
		Phase.RESULT:
			_timer -= dt
			if _timer <= 0.0:
				_back_to_lobby()


## 客户端 autoplay（测试用）：轮到自己就立刻选武器 / 选模式
func _client_autoplay_choices() -> void:
	if phase == Phase.DRAFT and current_picker() == my_id():
		var key: String = "d%d" % draft["turn"]
		if _auto_sent != key:
			_auto_sent = key
			var free: Array[int] = []
			for i in draft["taken"].size():
				if draft["taken"][i] == 0:
					free.append(i)
			pick(free[rng.randi_range(0, free.size() - 1)])
	elif phase == Phase.MODE and mode_pick.get("chooser", 0) == my_id() and _auto_sent != "m":
		_auto_sent = "m"
		var m: Dictionary = _auto_mode(true)
		choose_mode(m["k"], m["side_a"])


func _tick_battle(dt: float) -> void:
	var inputs: Dictionary = {}
	for id: int in sim.fighters.keys():
		if players.get(id, {}).get("bot", false):
			inputs[id] = Bot.think(sim, id, rng)
			continue
		var raw: Dictionary = local_input if id == 1 else _inputs.get(id, {})
		if raw.is_empty():
			continue
		# 攻击 = 按住 或 有新的点击（序号变了）。点击用序号，丢包也不会吞掉
		var seq: int = raw["seq"]
		var clicked: bool = seq != _last_seq.get(id, 0)
		_last_seq[id] = seq
		inputs[id] = {"move": raw["move"], "aim": raw["aim"], "attack": raw["held"] or clicked}
	sim.step(dt, inputs)
	if not sim.swings.is_empty() or not sim.events.is_empty() or not sim.catches.is_empty():
		# 音效事件走可靠通道：一秒顶多几次，丢了会很明显（砍到人没声音）
		_fx.rpc(Array(sim.swings), Array(sim.events), Array(sim.catches))
	if _frame % SNAP_EVERY == 0:
		_snapshot.rpc(sim.snapshot())
	if sim.is_over():
		_timer = RESULT_TIME
		_end_battle.rpc(sim.winner_id(), sim.snapshot())
