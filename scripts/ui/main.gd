extends Node

## 主场景：战场 + 各阶段的 UI 面板（菜单 / 大厅 / 轮抽 / 战斗 HUD / 结算）。UI 全用代码搭。
##
## 命令行参数（测试用，跟在 -- 后面）：
##   --host            直接开主机
##   --join=IP         直接连接
##   --name=名字
##   --bots=N          开主机后加 N 个机器人，并自动开始
##   --autoplay        本地玩家也交给机器人
##   --quit-after=N    打完 N 局自动退出，打印结果（冒烟测试用）
##   --capture=DIR     非无头模式下，把轮抽和战斗画面截图存到 DIR

const Arena := preload("res://scripts/ui/arena.gd")

var arena: Node2D
var ui: CanvasLayer
var panels: Dictionary = {}
var status_label: Label

# 菜单
var name_edit: LineEdit
var ip_edit: LineEdit
# 大厅
var lobby_list: VBoxContainer
var lobby_host_box: HBoxContainer
var lobby_hint: Label
# 轮抽
var draft_title: Label
var draft_cards: HBoxContainer
var draft_order: Label
var draft_timer: Label
var draft_left: float = 0.0
# HUD / 结算
var hud_label: Label
var result_label: Label

var opts: Dictionary = {}
var matches_done: int = 0
var capture_dir: String = ""
var _cap_frame: int = 0
var _captured: Dictionary = {}


func _ready() -> void:
	_parse_args()
	arena = Arena.new()
	add_child(arena)
	ui = CanvasLayer.new()
	add_child(ui)
	_build_ui()
	Net.phase_changed.connect(_on_phase)
	Net.lobby_changed.connect(_refresh_lobby)
	Net.draft_changed.connect(_refresh_draft)
	Net.battle_ended.connect(_on_battle_ended)
	Net.net_error.connect(func(m: String) -> void: status_label.text = m)
	_on_phase(Net.phase)
	_auto_start()


func _parse_args() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if opts.has("name"):
		Net.my_name = opts["name"]
	Net.autoplay = opts.has("autoplay")
	capture_dir = opts.get("capture", "")


func _auto_start() -> void:
	if opts.has("host"):
		if Net.host():
			for i in int(opts.get("bots", "0")):
				Net.add_bot()
			if int(opts.get("bots", "0")) > 0:
				Net.start_game()
			elif opts.has("wait"):
				# --wait=N：等到大厅有 N 人自动开始（联机冒烟测试用）
				var need: int = int(opts["wait"])
				Net.lobby_changed.connect(func() -> void:
					if Net.phase == Net.Phase.LOBBY and Net.players.size() >= need:
						Net.start_game())
	elif opts.has("join"):
		Net.join(opts["join"])


# ============ UI 搭建 ============

func _build_ui() -> void:
	var theme := Theme.new()
	theme.default_font_size = 10
	var root := Control.new()
	root.theme = theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	# —— 菜单 ——
	var menu := _panel(root, "menu", true)
	var mv := _vbox(menu)
	_label(mv, "武器轮抽乱斗", 20)
	_label(mv, "WASD 移动 · 鼠标瞄准 · 左键攻击", 8).modulate = Color(1, 1, 1, 0.7)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "名字"
	name_edit.text = Net.my_name
	name_edit.max_length = 12
	mv.add_child(name_edit)
	_button(mv, "开主机", func() -> void:
		Net.my_name = _name()
		Net.host())
	var jb := HBoxContainer.new()
	mv.add_child(jb)
	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jb.add_child(ip_edit)
	_button(jb, "加入", func() -> void:
		Net.my_name = _name()
		status_label.text = "连接中…"
		Net.join(ip_edit.text.strip_edges()))
	status_label = _label(mv, "", 8)
	status_label.modulate = Color(1, 0.8, 0.6)

	# —— 大厅 ——
	var lobby := _panel(root, "lobby", true)
	var lv := _vbox(lobby)
	_label(lv, "大厅", 16)
	lobby_list = VBoxContainer.new()
	lv.add_child(lobby_list)
	lobby_hint = _label(lv, "", 8)
	lobby_hint.modulate = Color(1, 1, 1, 0.6)
	lobby_host_box = HBoxContainer.new()
	lv.add_child(lobby_host_box)
	_button(lobby_host_box, "加机器人", Net.add_bot)
	_button(lobby_host_box, "清机器人", Net.remove_bots)
	_button(lobby_host_box, "开始", Net.start_game)
	_button(lv, "离开", Net.leave)

	# —— 轮抽 ——
	var dr := _panel(root, "draft", true)
	var dv := _vbox(dr)
	draft_title = _label(dv, "", 14)
	draft_cards = HBoxContainer.new()
	draft_cards.add_theme_constant_override("separation", 6)
	draft_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	dv.add_child(draft_cards)
	draft_order = _label(dv, "", 8)
	draft_order.modulate = Color(1, 1, 1, 0.7)
	draft_timer = _label(dv, "", 8)
	draft_timer.modulate = Color(1, 0.8, 0.5)

	# —— 战斗 HUD ——
	var hud := Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	panels["battle"] = hud
	hud_label = Label.new()
	hud_label.position = Vector2(6, 4)
	hud_label.add_theme_font_size_override("font_size", 8)
	hud_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_label.add_theme_constant_override("outline_size", 3)
	hud.add_child(hud_label)

	# —— 结算 ——
	var res := _panel(root, "result", false)
	var rv := _vbox(res)
	result_label = _label(rv, "", 16)
	_label(rv, "几秒后回到大厅…", 8).modulate = Color(1, 1, 1, 0.6)


func _panel(root: Control, key: String, opaque: bool) -> PanelContainer:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(c)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.12, 0.92 if opaque else 0.75)
	sb.border_color = Color(0.9, 0.85, 0.6)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	c.add_child(p)
	panels[key] = c
	return p


func _vbox(parent: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.custom_minimum_size.x = 200
	parent.add_child(v)
	return v


func _label(parent: Control, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _name() -> String:
	var n: String = name_edit.text.strip_edges()
	return n if n != "" else "玩家"


# ============ 状态刷新 ============

func _on_phase(ph: int) -> void:
	var key: String = ["menu", "lobby", "draft", "battle", "result"][ph]
	for k: String in panels:
		panels[k].visible = (k == key) or (k == "battle" and ph == Net.Phase.RESULT)
	if ph == Net.Phase.LOBBY:
		_refresh_lobby()


func _refresh_lobby() -> void:
	for c in lobby_list.get_children():
		c.queue_free()
	for id: int in Net.players:
		var p: Dictionary = Net.players[id]
		var tag: String = " (主机)" if id == 1 else (" (你)" if id == Net.my_id() else "")
		_label(lobby_list, ("🤖 " if p["bot"] else "• ") + p["name"] + tag, 10)
	lobby_host_box.visible = Net.is_server()
	lobby_hint.text = "至少 2 人才能开始" if Net.is_server() else "等主机开始…"


func _refresh_draft() -> void:
	if Net.draft.is_empty():
		return
	draft_left = float(Net.draft.get("time_left", 0.0))
	var cur: int = Net.current_picker()
	var my_turn: bool = cur == Net.my_id()
	if cur == 0:
		draft_title.text = "选完了，准备开打！"
	elif my_turn:
		draft_title.text = "轮到你选了！"
	else:
		draft_title.text = "%s 正在选…" % Net.players.get(cur, {}).get("name", "?")
	for c in draft_cards.get_children():
		c.queue_free()
	var weapons: Array = Net.draft["weapons"]
	for i in weapons.size():
		var w: Dictionary = Weapons.get_def(weapons[i])
		var owner: int = Net.draft["taken"][i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(80, 72)
		var t: String = "%s\n\n范围 %s\n伤害 %d\n速度 %d" % [w["name"], str(w["range"]), w["damage"], w["speed"]]
		if owner != 0:
			t += "\n← " + Net.players.get(owner, {}).get("name", "?")
		b.text = t
		b.disabled = owner != 0 or not my_turn
		var slot: int = i
		b.pressed.connect(func() -> void: Net.pick(slot))
		draft_cards.add_child(b)
	var names: Array[String] = []
	for j in Net.draft["order"].size():
		var pid: int = Net.draft["order"][j]
		var n: String = Net.players.get(pid, {}).get("name", "?")
		names.append(("[%s]" % n) if j == Net.draft["turn"] else n)
	draft_order.text = "顺序：" + " → ".join(names)


func _on_battle_ended(winner: int) -> void:
	if winner == 0:
		result_label.text = "同归于尽！"
	elif winner == Net.my_id():
		result_label.text = "你赢了！"
	else:
		var n: String = Net.sim.fighters[winner].name if Net.sim.fighters.has(winner) else "?"
		result_label.text = "%s 获胜" % n
	matches_done += 1
	if opts.has("quit-after"):
		_print_result(winner)
		if matches_done >= int(opts["quit-after"]):
			# 等可靠消息发出去再退
			get_tree().create_timer(0.5).timeout.connect(func() -> void: get_tree().quit(0))


func _print_result(winner: int) -> void:
	var rows: Array[String] = []
	for f: BattleSim.Fighter in Net.sim.fighters.values():
		rows.append("%s[%s] hp=%d kills=%d" % [f.name, f.weapon, f.hp, f.kills])
	print("RESULT me=%d winner=%d time=%.1fs | %s" % [Net.my_id(), winner, Net.sim.time, " ; ".join(rows)])


func _process(_dt: float) -> void:
	if Net.phase == Net.Phase.DRAFT and Net.current_picker() != 0:
		draft_left = maxf(draft_left - _dt, 0.0)
		draft_timer.text = "%d 秒后随机选" % ceili(draft_left)
	if (Net.phase == Net.Phase.BATTLE or Net.phase == Net.Phase.RESULT) and Net.sim != null:
		var me: BattleSim.Fighter = Net.sim.fighters.get(Net.my_id())
		if me != null:
			var w: Dictionary = Weapons.get_def(me.weapon)
			hud_label.text = "%s  HP %d  存活 %d/%d" % [w["name"], me.hp, Net.sim.alive_count(), Net.sim.fighters.size()]
	_maybe_capture()


## 截图：root.get_texture() 拿到的是上一帧，所以状态到了之后再等几帧
func _maybe_capture() -> void:
	if capture_dir == "":
		return
	_cap_frame += 1
	var key: String = ""
	if Net.phase == Net.Phase.DRAFT and not _captured.has("draft"):
		key = "draft"
	elif Net.phase == Net.Phase.BATTLE and Net.sim != null and Net.sim.time > 2.5 and not _captured.has("battle"):
		key = "battle"
	elif Net.phase == Net.Phase.RESULT and not _captured.has("result"):
		key = "result"
	if key == "" or _captured.has(key):
		return
	if not _captured.has(key + "_wait"):
		_captured[key + "_wait"] = _cap_frame
		return
	if _cap_frame - int(_captured[key + "_wait"]) < 3:
		return
	_captured[key] = true
	var path: String = capture_dir.path_join("shot_%s.png" % key)
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ", path)
