extends Node2D

## 战场：画草地、角色、武器挥击；采集本地玩家的 WASD + 鼠标输入写进 Net.local_input。
## 全部用 _draw 画像素块，先不用美术资源。

const PLAYER_COLORS: Array[Color] = [
	Color(0.90, 0.30, 0.30), Color(0.30, 0.55, 0.95), Color(0.95, 0.80, 0.25), Color(0.65, 0.40, 0.90),
	Color(0.30, 0.85, 0.85), Color(0.95, 0.55, 0.20), Color(0.95, 0.50, 0.75), Color(0.30, 0.28, 0.32),  # 第 8 色别用白，跟受击闪白撞
]

## 分队模式脚下圈的颜色：0 = 红队，1 = 蓝队
const TEAM_COLORS: Array[Color] = [Color(1.0, 0.35, 0.3), Color(0.35, 0.6, 1.0)]

var grass: ImageTexture
## 显示位置（在快照之间平滑一下，客户端 30Hz 快照不会一顿一顿）
var display_pos: Dictionary = {}
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	grass = _make_grass()


func _make_grass() -> ImageTexture:
	var w: int = int(BattleSim.ARENA.x)
	var h: int = int(BattleSim.ARENA.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = 8
	var base := Color(0.36, 0.62, 0.30)
	img.fill(base)
	for i in 5200:
		var x: int = r.randi_range(0, w - 1)
		var y: int = r.randi_range(0, h - 2)
		var c: Color = base.darkened(r.randf_range(0.08, 0.22)) if r.randf() < 0.6 else base.lightened(r.randf_range(0.06, 0.16))
		img.set_pixel(x, y, c)
		if r.randf() < 0.35:
			img.set_pixel(x, y + 1, c)  # 竖着的小草
	for i in 90:  # 小花
		var fc: Color = [Color(0.95, 0.9, 0.4), Color(0.95, 0.95, 0.95), Color(0.9, 0.5, 0.6)][r.randi_range(0, 2)]
		img.set_pixel(r.randi_range(0, w - 1), r.randi_range(0, h - 1), fc)
	return ImageTexture.create_from_image(img)


func _process(dt: float) -> void:
	if Net.sim == null or Net.phase < Net.Phase.BATTLE:
		display_pos.clear()
		return
	for f: BattleSim.Fighter in Net.sim.fighters.values():
		var cur: Vector2 = display_pos.get(f.id, f.pos)
		display_pos[f.id] = f.pos if Net.is_server() else cur.lerp(f.pos, minf(1.0, dt * 20.0))
	if Net.phase == Net.Phase.BATTLE and not Net.autoplay:
		_collect_input()
	queue_redraw()


func _collect_input() -> void:
	var me: BattleSim.Fighter = Net.sim.fighters.get(Net.my_id())
	if me == null:
		return
	Net.local_input["move"] = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dp: Vector2 = display_pos.get(me.id, me.pos)
	Net.local_input["aim"] = (get_global_mouse_position() - dp).angle()
	Net.local_input["held"] = Input.is_action_pressed("attack")
	if Input.is_action_just_pressed("attack"):
		Net.local_input["seq"] += 1


func _draw() -> void:
	draw_texture(grass, Vector2.ZERO)
	if Net.sim == null or Net.phase < Net.Phase.BATTLE:
		return
	var fs: Array = Net.sim.fighters.values()
	# 死的先画，活的盖在上面
	fs.sort_custom(func(a: BattleSim.Fighter, b: BattleSim.Fighter) -> bool: return int(a.alive) < int(b.alive))
	for f: BattleSim.Fighter in fs:
		_draw_fighter(f)


## 各自为战：每人一个颜色。分队：身体按队伍上色（红队一片红、蓝队一片蓝），队友之间用深浅区分。
## 不然会出现「蓝色身体的人在红队」这种一眼看错的情况。
func _body_color(f: BattleSim.Fighter) -> Color:
	if Net.match_mode.get("k", 0) == 0:
		return PLAYER_COLORS[f.color_idx % PLAYER_COLORS.size()]
	var nth: int = 0
	for o: BattleSim.Fighter in Net.sim.fighters.values():
		if o.team == f.team and o.color_idx < f.color_idx:
			nth += 1
	var base: Color = TEAM_COLORS[f.team % 2]
	return [base, base.darkened(0.3), base.lightened(0.3)][nth % 3]


func _draw_fighter(f: BattleSim.Fighter) -> void:
	var p: Vector2 = (display_pos.get(f.id, f.pos) as Vector2).round()
	var col: Color = _body_color(f)
	var w: Dictionary = Weapons.get_def(f.weapon)
	var is_me: bool = f.id == Net.my_id()

	# 角色精灵按 12x12 的像素图来画，再整体放大 S 倍（S = 2 时每个「像素」是 2x2）。
	# 这样人物大小只跟 BattleSim.BODY_R 挂钩，改那一个常数就行。
	var S: float = BattleSim.BODY_R / 6.0

	if not f.alive:
		# 倒地：灰色扁块 + 叉
		draw_set_transform(p, 0.0, Vector2(S, S))
		draw_rect(Rect2(Vector2(-6, -2), Vector2(12, 5)), col.darkened(0.5))
		draw_line(Vector2(-3, -3), Vector2(3, 3), Color(0.15, 0.1, 0.1), 1.0)
		draw_line(Vector2(3, -3), Vector2(-3, 3), Color(0.15, 0.1, 0.1), 1.0)
		draw_set_transform(Vector2.ZERO)
		return

	var reach: float = Net.sim.hit_dist(f)
	# 自己的攻击范围提示（淡）
	if is_me:
		draw_arc(p, reach, 0, TAU, 64, Color(1, 1, 1, 0.12), 1.0)
	# 挥击扇形
	if f.swing > 0.0:
		var half: float = deg_to_rad(float(w["arc"])) / 2.0
		var a: float = f.swing / BattleSim.SWING_SHOW
		var pts := PackedVector2Array([p])
		for i in 13:
			pts.append(p + Vector2.from_angle(f.aim - half + 2.0 * half * i / 12.0) * reach)
		draw_colored_polygon(pts, Color(1, 1, 0.85, 0.45 * a))

	# 分队模式：脚下画队伍色的圈
	if Net.match_mode.get("k", 0) > 0:
		draw_arc(p + Vector2(0, BattleSim.BODY_R * 0.6), BattleSim.BODY_R * 1.1, 0, TAU, 32, TEAM_COLORS[f.team % 2], 2.0)

	draw_set_transform(p, 0.0, Vector2(S, S))
	# 影子
	draw_rect(Rect2(Vector2(-5, 5), Vector2(10, 2)), Color(0, 0, 0, 0.25))
	# 身体：12x12 像素块，带描边；受击闪白
	var body: Color = Color.WHITE if f.hurt > 0.0 else col
	draw_rect(Rect2(Vector2(-6, -6), Vector2(12, 12)), body.darkened(0.55))
	draw_rect(Rect2(Vector2(-5, -5), Vector2(10, 10)), body)
	draw_rect(Rect2(Vector2(-5, -5), Vector2(10, 2)), body.lightened(0.25))
	# 眼睛看向瞄准方向
	var look: Vector2 = (Vector2.from_angle(f.aim) * 2.0).round()
	draw_rect(Rect2(look + Vector2(-3, -2), Vector2(2, 2)), Color(0.1, 0.1, 0.12))
	draw_rect(Rect2(look + Vector2(1, -2), Vector2(2, 2)), Color(0.1, 0.1, 0.12))
	# 武器：从身体伸出去的线，长度跟 range 挂钩
	var wlen: float = 4.0 + float(w["range"]) * 4.0
	var dir: Vector2 = Vector2.from_angle(f.aim)
	var st: Vector2 = dir * 7.0
	draw_line(st, st + dir * wlen, w["color"], 2.0)
	draw_set_transform(Vector2.ZERO)

	# 血条和名字不跟着放大，只跟着身体高度挪位置
	var top: float = -BattleSim.BODY_R
	var hp_w: float = 24.0
	var hp_r: float = float(f.hp) / float(BattleSim.BASE_HP)
	draw_rect(Rect2(p + Vector2(-hp_w / 2.0, top - 6), Vector2(hp_w, 3)), Color(0.15, 0.05, 0.05))
	draw_rect(Rect2(p + Vector2(-hp_w / 2.0, top - 6), Vector2(hp_w * hp_r, 3)), Color(0.35, 0.9, 0.35) if hp_r > 0.3 else Color(0.95, 0.3, 0.25))
	# 名字
	var label: String = ("▼ " if is_me else "") + f.name
	var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	draw_string(font, p + Vector2(-tw / 2.0, top - 9), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.9))
