extends Node2D

## 武器音效播放。监听 Net.fx：出手放 <武器>_swing，命中放 <攻击者武器>_hit，击杀再叠一个 kill。
## 用 AudioStreamPlayer2D 按角色在屏幕上的位置做左右声像（左边砍的声音偏左耳）。
## 音效文件由 tools/gen_sfx.py 生成，换正式音效时替换同名 wav 即可。

const POOL_SIZE: int = 16
## 同一个音每次随机微调音高，连砍时不会像复读机
const PITCH_JITTER: float = 0.06

var streams: Dictionary = {}
var players: Array[AudioStreamPlayer2D] = []
var _next: int = 0
## 各音效播放次数（冒烟测试打印用）
var counts: Dictionary = {}
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	for wid: String in Weapons.TABLE:
		for kind: String in ["swing", "hit"]:
			_load("%s_%s" % [wid, kind])
	_load("kill")
	_load("boomerang_catch")
	for i in POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		# 屏幕就 640 宽，衰减要很弱，主要只要左右声像
		p.max_distance = 4000.0
		p.attenuation = 0.3
		p.panning_strength = 0.6
		add_child(p)
		players.append(p)
	Net.fx.connect(_on_fx)


func _load(sname: String) -> void:
	var path: String = "res://assets/sfx/%s.wav" % sname
	if ResourceLoader.exists(path):
		streams[sname] = load(path)
	else:
		push_warning("缺音效：" + path)


func play(sname: String, pos: Vector2, vol_db: float = 0.0) -> void:
	if not streams.has(sname):
		return
	counts[sname] = int(counts.get(sname, 0)) + 1
	var p: AudioStreamPlayer2D = players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = streams[sname]
	p.position = pos
	p.volume_db = vol_db
	p.pitch_scale = 1.0 + rng.randf_range(-PITCH_JITTER, PITCH_JITTER)
	p.play()


func _on_fx(swings: Array, hits: Array, catches: Array) -> void:
	var sim: BattleSim = Net.sim
	if sim == null:
		return
	for id: int in swings:
		var f: BattleSim.Fighter = sim.fighters.get(id)
		if f != null:
			# 自己出手稍微响一点，别人的稍微轻一点，混战里听得出哪下是自己的
			play(f.weapon + "_swing", f.pos, 0.0 if id == Net.my_id() else -4.0)
	for h: Dictionary in hits:
		var a: BattleSim.Fighter = sim.fighters.get(h["attacker"])
		var t: BattleSim.Fighter = sim.fighters.get(h["target"])
		if a == null or t == null:
			continue
		play(a.weapon + "_hit", t.pos)
		if h.get("killed", false):
			play("kill", t.pos, 2.0)
	for id: int in catches:
		var c: BattleSim.Fighter = sim.fighters.get(id)
		if c != null:
			play("boomerang_catch", c.pos, 0.0 if id == Net.my_id() else -6.0)


func stop_all() -> void:
	for p in players:
		p.stop()
		p.stream = null


func _exit_tree() -> void:
	stop_all()


func _notification(what: int) -> void:
	# 关窗口时先停声音；音频线程要过一帧才放手，否则 Godot 退出时会报泄漏
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop_all()
