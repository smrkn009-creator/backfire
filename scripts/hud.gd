extends CanvasLayer
# ============================================================
#  all of the on screen stuff.
#
#  the panel is the only thing i drew by hand (see _draw at the
#  bottom): hearts, score, wave, combo and a live "score to beat"
#  bar. the words live in plain Labels on top of it.
#
#  game.gd calls hud.refresh(self) once a frame and this file
#  works out what should be on screen. speech bubbles float over
#  the 3D world, so they are put in a Control that follows the
#  camera projection of a 3D point.
# ============================================================

var game_root = null

var panel = null
var hearts_lbl = null
var score_lbl = null
var wave_lbl = null
var combo_lbl = null
var target_lbl = null
var hint_lbl = null
var toasts = null

var menu = null
var menu_text = null
var debug_lbl = null
var show_debug = false     # F3 turns the fps strip back on if you ever need it

var bubbles = []          # speech bubbles floating in the world
var last_menu = ""

const CYAN = Color("#4df0ff")
const AMBER = Color("#ffb454")
const RED = Color("#ff5a6e")
const ICE = Color("#bff8ff")
const INK = Color("#e8ecff")
const DIM = Color("#8494bf")
const PINK = Color("#ff4fd8")
const GREEN = Color("#7cff9b")


func setup(root):
	game_root = root
	layer = 10

	# a full screen "surface" that owns the anchors, so the panel and the
	# menu always fill the window even if a Control tries to size to
	# its contents
	var surface = Control.new()
	surface.name = "Surface"
	surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(surface)

	panel = HudPanel.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(panel)

	hearts_lbl = label(Vector2(0, 0), 15, RED)
	place(hearts_lbl, Control.PRESET_TOP_LEFT, Rect2(30, 20, 300, 24))
	score_lbl = label(Vector2(0, 0), 40, Color.WHITE)
	place(score_lbl, Control.PRESET_TOP_RIGHT, Rect2(-380, 12, 350, 52))
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	wave_lbl = label(Vector2(0, 0), 14, CYAN)
	place(wave_lbl, Control.PRESET_CENTER_TOP, Rect2(-110, 20, 220, 22))
	wave_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	combo_lbl = label(Vector2(0, 0), 26, AMBER)
	place(combo_lbl, Control.PRESET_TOP_RIGHT, Rect2(-380, 72, 350, 34))
	combo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	target_lbl = label(Vector2(0, 0), 12, AMBER)
	place(target_lbl, Control.PRESET_TOP_RIGHT, Rect2(-380, 110, 350, 18))
	target_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	hint_lbl = label(Vector2(0, 0), 13, DIM)
	place(hint_lbl, Control.PRESET_CENTER_BOTTOM, Rect2(-460, -44, 920, 20))
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	debug_lbl = label(Vector2(0, 0), 14, Color("#9fd4ff"))
	place(debug_lbl, Control.PRESET_BOTTOM_LEFT, Rect2(20, -30, 1100, 22))
	debug_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	debug_lbl.add_theme_constant_override("outline_size", 5)

	toasts = VBoxContainer.new()
	toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	toasts.offset_left = -220
	toasts.offset_top = 150
	toasts.offset_right = 220
	toasts.offset_bottom = 350
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toasts)

	# ---- the big menu screen ----
	menu = ColorRect.new()
	menu.name = "Menu"
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.anchor_right = 1.0
	menu.anchor_bottom = 1.0
	# only slightly dark, so the demo game behind the menu is still
	# visible. it used to be 0.88 which hid everything
	menu.color = Color(0.02, 0.03, 0.06, 0.55)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var centre = CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(centre)
	menu_text = RichTextLabel.new()
	menu_text.bbcode_enabled = true
	menu_text.fit_content = true
	menu_text.scroll_active = false
	menu_text.custom_minimum_size = Vector2(880, 0)
	menu_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_text.add_theme_font_size_override("normal_font_size", 18)
	menu_text.add_theme_font_size_override("bold_font_size", 22)
	centre.add_child(menu_text)
	surface.add_child(menu)
	menu.visible = false


func label(pos, size, colour):
	var l = Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 7)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


# pin a label to part of the screen and give it an exact box.
# set_anchors_preset on its own keeps the old offsets, which left the
# labels off screen. this sets the corners and the box together.
func place(l, preset, box):
	l.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	l.offset_left = box.position.x
	l.offset_top = box.position.y
	l.offset_right = box.position.x + box.size.x
	l.offset_bottom = box.position.y + box.size.y


# ------------------------------------------------------------
#  speech bubbles
# ------------------------------------------------------------
func add_bubble(world_pos, words, colour):
	var box = PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.05, 0.11, 0.95)
	bg.border_width_bottom = 2
	bg.border_width_top = 2
	bg.border_width_left = 2
	bg.border_width_right = 2
	bg.border_color = colour
	bg.corner_radius_top_left = 9
	bg.corner_radius_top_right = 9
	bg.corner_radius_bottom_left = 9
	bg.corner_radius_bottom_right = 9
	bg.content_margin_left = 9
	bg.content_margin_right = 9
	bg.content_margin_top = 3
	bg.content_margin_bottom = 3
	box.add_theme_stylebox_override("panel", bg)

	var text = Label.new()
	text.text = words
	text.add_theme_font_size_override("font_size", 15)
	text.add_theme_color_override("font_color", colour)
	text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	text.add_theme_constant_override("outline_size", 5)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(text)

	add_child(box)
	bubbles.append({ "box": box, "pos": world_pos, "life": 1.5, "age": 0.0 })


func update_bubbles(dt):
	var cam = game_root.cam
	for i in range(bubbles.size() - 1, -1, -1):
		var b = bubbles[i]
		b["age"] = b["age"] + dt
		if b["age"] >= b["life"] or cam == null:
			b["box"].queue_free()
			bubbles.remove_at(i)
			continue
		var screen = cam.unproject_position(b["pos"])
		var size = b["box"].size
		# pop in during the first fifth of a second
		var t = b["age"] / b["life"]
		var drop = 0.0
		if t < 0.2:
			drop = (1.0 - t / 0.2) * 8.0
		b["box"].position = screen - Vector2(size.x * 0.5, size.y + 14.0 + drop - b["age"] * 16.0)
		var alpha = 1.0
		if t > 0.75:
			alpha = (1.0 - t) / 0.25
		b["box"].modulate = Color(1, 1, 1, alpha)


# ------------------------------------------------------------
#  little messages that slide in and fade out
# ------------------------------------------------------------
func toast(words, colour):
	var l = Label.new()
	l.text = words
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_child(l)
	var t = create_tween()
	t.tween_interval(1.3)
	t.tween_property(l, "modulate:a", 0.0, 0.5)
	t.tween_callback(l.queue_free)


# ------------------------------------------------------------
#  called every frame by game.gd
# ------------------------------------------------------------
# shows fps, state and what the game thinks is going on.
# press F3 in game to hide it again
func debug_line(game):
	var size = get_viewport().get_visible_rect().size
	var text = "FPS " + str(Engine.get_frames_per_second())
	text = text + "  (" + str(int(1000.0 / max(1.0, Engine.get_frames_per_second()))) + "ms)"
	text = text + "   state " + game.state
	text = text + "   wave " + str(game.wave)
	text = text + "   enemies " + str(game.enemies.size())
	text = text + "   window " + str(int(size.x)) + "x" + str(int(size.y))
	text = text + "   menu " + str(menu.visible)
	if game.paused:
		text = text + "   PAUSED"
	if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		text = text + "   mouse hidden"
	else:
		text = text + "   mouse visible"
	return text


func refresh(game):
	update_bubbles(get_process_delta_time())

	# while the title screen demo is running we do not want the real
	# score, wave or hearts on top of it
	var playing = game.state == "play"
	hearts_lbl.visible = playing
	score_lbl.visible = playing
	wave_lbl.visible = playing
	combo_lbl.visible = playing and game.combo > 1
	target_lbl.visible = playing
	hint_lbl.visible = playing and game.elapsed < 12.0

	if playing:
		# the diamonds on the panel show your lives now. the old "<3 <3 <3"
		# text sat on top of them saying the same thing twice
		hearts_lbl.text = ""
		score_lbl.text = str(game.score)
		wave_lbl.text = "WAVE " + str(game.wave)
		target_lbl.text = target_text(game)
		hint_lbl.text = "WASD move   ·   mouse aim   ·   SPACE / CLICK parry   ·   you have no attack"
		if game.combo > 1:
			combo_lbl.text = "x" + str(game.combo) + "  " + game.combo_name(game.combo)

	# tell the panel what to draw
	panel.score = game.score
	panel.wave = game.wave
	panel.hp = game.player.hp
	panel.combo = game.combo
	panel.combo_frac = clamp(game.comboT / 3.0, 0.0, 1.0)
	panel.beat = target_score(game)
	panel.beat_frac = 0.0
	if panel.beat > 0:
		# the goal moves up the board as i pass people, so the bar fills
		# the gap between the last score i beat and the next one. without
		# this it snapped back to empty every time the target changed
		var floor_score = 0
		for row in game.board:
			var their_score = int(row["score"])
			if their_score <= game.score and their_score > floor_score:
				floor_score = their_score
		var span = float(panel.beat - floor_score)
		if span < 1.0:
			span = 1.0
		panel.beat_frac = clamp(float(game.score - floor_score) / span, 0.0, 1.0)
	panel.playing = playing
	panel.queue_redraw()

	debug_lbl.visible = show_debug
	if show_debug:
		debug_lbl.text = debug_line(game)

	show_menu(game)


func target_score(game):
	# the number to beat, which game.gd works out by looking for the
	# closest score above mine. it goes up the board as i pass people
	if game.board.size() == 0:
		return 0
	return game.record_target


func target_text(game):
	var beat = target_score(game)
	if beat > 0:
		for row in game.board:
			if int(row["score"]) == beat:
				return str(row["name"]) + "  ·  " + str(beat) + " to beat"
	if game.score > 0 and game.board.size() > 0:
		# nothing left above me, so i am top of the board
		return "TOP OF THE BOARD"
	return ""


# ------------------------------------------------------------
#  the menu screens
# ------------------------------------------------------------
func show_menu(game):
	var html = ""
	if game.state == "title":
		html = title_screen(game)
	elif game.state == "initials":
		html = initials_screen(game)
	elif game.state == "over":
		html = over_screen(game)
	elif game.state == "play" and game.paused:
		html = "[center][font_size=44][b]PAUSED[/b][/font_size]\n\n[color=#8494bf]press P to keep playing[/color][/center]"

	menu.visible = html != ""
	if html != "" and html != last_menu:
		last_menu = html
		menu_text.text = html


func board_lines(game, highlight):
	if game.board.size() == 0:
		return "[center][color=#5c6b9a]no scores yet — be the first name on the board[/color][/center]"
	var t = "[center]"
	for i in game.board.size():
		var row = game.board[i]
		var line = str(i + 1) + "      " + str(row["name"]) + "        " + str(row["score"]) + "   [color=#5c6b9a]wave " + str(row["wave"]) + "[/color]"
		if int(row["score"]) == highlight:
			t = t + "[color=#ffb454][b]" + line + "[/b][/color]\n"
		else:
			t = t + line + "\n"
	t = t + "[/center]"
	return t


func title_screen(game):
	var t = "[center]"
	t = t + "[font_size=76][b]BACKFIRE[/b][/font_size]\n"
	t = t + "[font_size=22][color=#4df0ff][b]3 D  ·  ARENA[/b][/color][/font_size]\n\n"
	t = t + "[font_size=20][color=#e8ecff]You have no weapon.[/color] [color=#8494bf]Every shot you knock back flies home to whoever fired it.[/color][/font_size]\n\n\n"
	t = t + "[b]WASD[/b]  move          [b]MOUSE[/b]  aim          [b]SPACE / CLICK[/b]  parry\n"
	t = t + "[color=#8494bf]parry right at the start of the flash and it is PERFECT — it goes through two of them[/color]\n\n\n"
	t = t + "[color=#4df0ff][b]— ARENA RECORDS —[/b][/color]\n"
	t = t + board_lines(game, -1) + "\n"
	t = t + "[font_size=24][b]PRESS SPACE TO START[/b][/font_size]"
	t = t + "[/center]"
	return t


func initials_screen(game):
	var slots = "     "
	var i = 0
	while i < 3:
		if i < game.initials.length():
			slots = slots + "[font_size=52][b]" + game.initials.substr(i, 1) + "[/b][/font_size]   "
		elif i == game.initials.length():
			slots = slots + "[font_size=52][color=#4df0ff][b]_[/b][/color][/font_size]   "
		else:
			slots = slots + "[font_size=52][color=#33406b][b]_[/b][/color][/font_size]   "
		i = i + 1

	var t = "[center]"
	t = t + "[font_size=28][color=#4df0ff][b]NEW RECORD[/b][/color][/font_size]\n\n"
	t = t + "[font_size=70][b]" + str(game.pending_score) + "[/b][/font_size]\n\n"
	t = t + "[color=#8494bf]put your name up. this is what your friends have to beat.[/color]\n\n"
	t = t + slots + "\n\n"
	t = t + "[color=#8494bf]A-Z or 0-9    ·    BACKSPACE to fix    ·    ENTER to save[/color]"
	t = t + "[/center]"
	return t


func over_screen(game):
	var ratio = 0
	if game.deflects > 0:
		ratio = int(round(100.0 * game.perfects / game.deflects))
	var t = "[center]"
	t = t + "[font_size=34][b]YOU DID NOT BOUNCE BACK[/b][/font_size]\n\n"
	t = t + "[font_size=72][b]" + str(game.score) + "[/b][/font_size]\n"
	t = t + "[color=#8494bf]style[/color]  [font_size=38][b][color=#ffb454]" + game.rank + "[/color][/b][/font_size]\n\n"
	t = t + "[color=#e8ecff]wave " + str(game.wave) + "[/color]   ·   " + str(game.deflects) + " deflected   ·   " + str(game.kills) + " sent back\n"
	t = t + str(game.perfects) + " perfect (" + str(ratio) + "%)   ·   best combo x" + str(game.bestCombo) + "   ·   " + str(game.wrongGuy) + " wrong guy\n\n"
	t = t + "[color=#4df0ff][b]— ARENA RECORDS —[/b][/color]\n"
	t = t + board_lines(game, game.score) + "\n"
	t = t + "[font_size=24][b]PRESS R TO PLAY AGAIN[/b][/font_size]"
	t = t + "[/center]"
	return t


# ============================================================
#  the hand drawn HUD panel
#  every frame this paints: the two corner brackets, the score
#  underline, the wave name, the combo bar and the live "score to
#  beat" bar underneath the score
# ============================================================
class HudPanel extends Control:
	var score = 0
	var wave = 0
	var hp = 3
	var combo = 0
	var combo_frac = 0.0
	var beat = 0
	var beat_frac = 0.0
	var playing = false

	func _draw():
		var size = get_rect().size
		if not playing:
			return

		var edge = Color(0.30, 0.94, 1.0, 0.75)

		# corner brackets
		var len = 46.0
		var pad = 18.0
		_line(Vector2(pad, pad), Vector2(pad + len, pad), edge, 2.0)
		_line(Vector2(pad, pad), Vector2(pad, pad + len), edge, 2.0)
		_line(Vector2(size.x - pad, pad), Vector2(size.x - pad - len, pad), edge, 2.0)
		_line(Vector2(size.x - pad, pad), Vector2(size.x - pad, pad + len), edge, 2.0)
		_line(Vector2(pad, size.y - pad), Vector2(pad + len, size.y - pad), edge, 2.0)
		_line(Vector2(pad, size.y - pad), Vector2(pad, size.y - pad - len), edge, 2.0)
		_line(Vector2(size.x - pad, size.y - pad), Vector2(size.x - pad - len, size.y - pad), edge, 2.0)
		_line(Vector2(size.x - pad, size.y - pad), Vector2(size.x - pad, size.y - pad - len), edge, 2.0)

		# underline above the score
		var right = size.x - 30.0
		_line(Vector2(right - 350.0, 66.0), Vector2(right, 66.0), Color(1, 1, 1, 0.18), 2.0)

		# combo timer bar, under the combo text
		if combo > 1:
			var w = 350.0 * combo_frac
			draw_rect(Rect2(right - 350.0, 118.0, 350.0, 4.0), Color(1, 1, 1, 0.12))
			draw_rect(Rect2(right - w, 118.0, w, 4.0), Color("#ffb454"))

		# "score to beat" bar, sits right under your score. once it is full
		# the bar goes solid gold and stops moving, because you have
		# already beaten the number and there is nothing left to fill
		if beat > 0:
			var y = 112.0
			draw_rect(Rect2(right - 350.0, y, 350.0, 5.0), Color(1, 1, 1, 0.10))
			var filled = 350.0 * beat_frac
			var bar_colour = Color("#ffb454")
			if beat_frac >= 1.0:
				bar_colour = Color("#ffd84d")
			draw_rect(Rect2(right - filled, y, filled, 5.0), bar_colour)

		# heart pips as small diamonds, in case the font has no <3
		var x = 30.0
		var i = 0
		while i < max(3, hp):
			var c = Vector2(x + i * 20.0, 52.0)
			var col = Color(1, 0.35, 0.43)
			if i >= hp:
				col = Color(1, 1, 1, 0.15)
			_diamond(c, 6.0, col)
			i = i + 1

	func _diamond(c, r, col):
		var pts = PackedVector2Array([
			Vector2(c.x, c.y - r), Vector2(c.x + r, c.y),
			Vector2(c.x, c.y + r), Vector2(c.x - r, c.y), Vector2(c.x, c.y - r)
		])
		draw_polyline(pts, col, 2.0)

	func _line(a, b, col, w):
		draw_line(a, b, col, w)
