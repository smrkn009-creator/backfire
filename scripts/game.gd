extends Node3D
# ============================================================
#  BACKFIRE 3D
#  You have no attack button. You can only parry, and every
#  bullet you knock back flies home to the thing that fired it.
#
#  this is the main script. it keeps the score, spawns the waves
#  and glues the other scripts together:
#      player.gd   - the little glowing guy
#      enemy.gd    - turret / spreader / rusher
#      bullet.gd   - the shots
#      effects.gd  - sparks, rings and floating text
#      hud.gd      - the on screen text
#      sounds.gd   - the beeps
# ============================================================

# player, hud, effects and sounds are attached to nodes in main.tscn
# now, so i only need these two here
const EnemyScript = preload("res://scripts/enemy.gd")
const BulletScript = preload("res://scripts/bullet.gd")

# the arena is measured like a 2d map (x to the right, y down)
# and the 3d floor is just that map laid flat
const W = 1080.0
const H = 620.0
const PAD = 26.0

# QUALITY: "low" turns off the expensive stuff (glow, shadows, smooth edges).
# my laptop is a 2015 Intel one, and with everything on it ran at about
# 4 frames a second, which looks like the game has frozen. low mode is
# what i actually play on and it still looks good.
# change to "high" if you are on a gaming pc
const QUALITY = "low"

# all the numbers i kept changing by hand
const PLAYER_SPEED = 265.0
const PARRY_RADIUS = 46.0
const PARRY_ARC = 1.45
const PARRY_TIME = 0.16
const PARRY_COOLDOWN = 0.38
const PERFECT_WINDOW = 0.07
const REFLECT_SPEED = 640.0
const COMBO_TIME = 3.0

var state = "title"          # title / play / over / initials
var demo = false             # true while the title screen is showing a fake game
var ghost = null             # the fake player the demo enemies shoot at


# the fake player. it is never drawn, it is only something for the demo
# enemies to aim at, so it just needs the same three numbers a real
# player has and nothing else
class GhostTarget extends Node3D:
	var sx = 540.0
	var sy = 310.0
	var hp = 99
var paused = false
var muted = false

var player = null
var bullets = []
var enemies = []
var spawns = []              # things waiting to appear
var fx = null
var hud = null
var snd = null
var cam = null

var score = 0
var combo = 0
var comboT = 0.0
var wave = 0
var waveT = 0.0
var waveState = "break"
var elapsed = 0.0
var kills = 0
var deflects = 0
var perfects = 0
var wrongGuy = 0
var bestCombo = 0
var shake = 0.0
var hitstop = 0.0
var slowmo = 0.0
var flash = 0.0

var aim_point = Vector3.ZERO
var cam_home = Vector3(0, 660, 530)

# the game's own crosshair, drawn on the floor under the mouse
var crosshair = null
var crosshair_ring = null

# the low blocks standing in the middle of the arena. you can hide
# behind them: enemy bullets hit them and die. your own parried shots
# are too fast to be stopped, so you can always still kill something
var cover_list = []

# leaderboard: 5 little rows, saved to the disk
var board = []
const BOARD_PATH = "user://backfire3d_board.save"
var initials = ""
var pending_score = 0
var rank = "D"


func _ready():
	randomize()
	setup_actions()

	# these four now live in main.tscn, so i can see them in the scene
	# tab and click on them instead of hunting through code
	player = $Player
	fx = $Effects
	snd = $Sounds
	hud = $HUD

	# the shield animation needs to know how long a parry lasts, other
	# wise it animates on its own numbers and drifts out of sync
	player.parry_length = PARRY_TIME
	player.parry_cooldown = PARRY_COOLDOWN

	# the lights, camera and floor are still made by code below
	build_world()

	# the thing the enemies aim at on the title screen. it is not drawn,
	# it just walks in a slow circle so the demo looks like somebody is
	# actually playing
	ghost = GhostTarget.new()
	ghost.name = "DemoTarget"
	add_child(ghost)
	ghost.sx = W / 2.0
	ghost.sy = H / 2.0
	ghost.hp = 99
	hud.setup(self)
	build_crosshair()
	load_board()
	reset_game()
	player.place()
	aim_point = sim_to_world(W / 2.0, H / 2.0 - 120.0)
	start_demo()
	if not OS.has_feature("server"):
		fit_window_to_screen()
	hud.refresh(self)


# ------------------------------------------------------------
#  the crosshair: i hide the normal windows mouse pointer and draw
#  my own glowing target on the floor where the mouse is pointing.
#  the dots are markers at 40, 80 and 120 units so you can judge
#  distance to an enemy at a glance
# ------------------------------------------------------------
func build_crosshair():
	crosshair = Node3D.new()
	crosshair.name = "Crosshair"
	add_child(crosshair)

	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 8.0
	torus.outer_radius = 10.5
	torus.rings = 16
	torus.ring_segments = 4
	ring.mesh = torus
	ring.material_override = flat_glow(Color("#4df0ff"))
	crosshair.add_child(ring)
	crosshair_ring = ring

	# four little ticks around the ring
	var i = 0
	while i < 4:
		var tick = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(1.6, 0.4, 7.0)
		tick.mesh = box
		tick.material_override = flat_glow(Color("#4df0ff"))
		tick.position = Vector3(0, 0, 13.0)
		tick.rotation_degrees.y = 90.0 * i
		var holder = Node3D.new()
		holder.add_child(tick)
		tick.position = Vector3(0, 0, 13.0)
		crosshair.add_child(holder)
		holder.rotation_degrees.y = 90.0 * i
		tick.rotation_degrees.y = 0.0
		i = i + 1

func flat_glow(colour):
	var mat = StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func update_crosshair():
	if crosshair == null:
		return
	var showing = state == "play" and not paused
	crosshair.visible = showing
	if not showing:
		return
	var p = Vector3(aim_point.x, 1.5, aim_point.z)
	crosshair.position = p
	# gentle spin so it feels alive
	crosshair.rotation.y = crosshair.rotation.y + 0.8 * get_process_delta_time()
	# turn red when a bullet is coming at you - a free warning
	var danger = false
	for b in bullets:
		if b.mine:
			continue
		var dx = b.sx - player.sx
		var dy = b.sy - player.sy
		if sqrt(dx * dx + dy * dy) < 150.0:
			danger = true
	var c = Color("#4df0ff")
	if danger:
		c = Color("#ff5a6e")
	for n in crosshair.get_children():
		if n is MeshInstance3D:
			var m = n.material_override
			m.albedo_color = c
			m.emission = c


# ------------------------------------------------------------
#  the keys. i set them up in code so i could not forget to
#  fill in the input map in the editor
# ------------------------------------------------------------
func setup_actions():
	if InputMap.has_action("move_left"):
		return
	var keys = {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
	}
	for action in keys:
		InputMap.add_action(action)
		for code in keys[action]:
			var ev = InputEventKey.new()
			ev.physical_keycode = code
			InputMap.action_add_event(action, ev)


# ------------------------------------------------------------
#  turning map numbers into 3d numbers
# ------------------------------------------------------------
func sim_to_world(sx, sy, height = 0.0):
	return Vector3(sx - W / 2.0, height, sy - H / 2.0)


# ------------------------------------------------------------
#  the world: lights, camera, floor
# ------------------------------------------------------------
func build_world():
	# dark background with a bit of glow so the neon pops
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#070912")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#35507f")
	env.ambient_light_energy = 0.75
	if QUALITY == "high":
		env.glow_enabled = true
		env.glow_intensity = 0.85
		env.glow_bloom = 0.15
		env.glow_hdr_threshold = 0.9
	else:
		env.glow_enabled = false
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# the camera comes from the scene file now (Main/Camera3D).
	# one fixed angle: if it moved around, the player could not tell
	# where a bullet is on the floor
	cam = $Camera3D
	cam.look_at(Vector3(0, 0, 20), Vector3.UP)
	cam.current = true

	# main light (the only one that makes shadows)
	var light = DirectionalLight3D.new()
	light.light_color = Color("#bcd4ff")
	light.light_energy = 1.2
	if QUALITY == "high":
		light.shadow_enabled = true
		light.directional_shadow_max_distance = 1600.0
	else:
		light.shadow_enabled = false
	add_child(light)
	light.position = Vector3(-260, 620, 320)
	light.look_at(Vector3.ZERO)

	# red light from behind, just for the arcade look
	var rim = DirectionalLight3D.new()
	rim.light_color = Color("#ec3750")
	rim.light_energy = 0.45
	add_child(rim)
	rim.position = Vector3(300, 220, -420)
	rim.look_at(Vector3.ZERO)

	# floor slab
	var floor_mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(W, H)
	floor_mesh.mesh = plane
	var floor_mat = StandardMaterial3D.new()
	floor_mat.albedo_color = Color("#0b0f1e")
	floor_mat.metallic = 0.35
	floor_mat.roughness = 0.55
	floor_mesh.material_override = floor_mat
	add_child(floor_mesh)

	# the walls around the arena. four low neon walls so the floor
	# reads as a room instead of a floating slab in the dark. they sit
	# just outside the play area, so they never block a shot. the
	# player and the bullets are clamped inside anyway, this is looks
	build_walls()
	build_cover()

	# the grid lines, made out of thin boxes
	var grid_mat = StandardMaterial3D.new()
	grid_mat.albedo_color = Color("#12203c")
	grid_mat.emission_enabled = true
	grid_mat.emission = Color("#2f6bff")
	grid_mat.emission_energy_multiplier = 0.55
	var x = -W / 2.0
	while x <= W / 2.0:
		var line = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(1.2, 0.2, H)
		line.mesh = box
		line.material_override = grid_mat
		line.position = Vector3(x, 0.8, 0)
		add_child(line)
		x = x + 60.0
	var z = -H / 2.0
	while z <= H / 2.0:
		var line2 = MeshInstance3D.new()
		var box2 = BoxMesh.new()
		box2.size = Vector3(W, 0.2, 1.2)
		line2.mesh = box2
		line2.material_override = grid_mat
		line2.position = Vector3(0, 0.8, z)
		add_child(line2)
		z = z + 60.0


# ------------------------------------------------------------
#  the walls. four boxes, one per side, with a glowing strip on top
#  so you can see where the arena ends at a glance
# ------------------------------------------------------------
func build_walls():
	# low walls. tall ones looked like a stadium and the one nearest the
	# camera covered the bottom of the arena, so all four are the same
	# short height and the near one is shorter still
	var wall_h = 20.0
	var near_h = 12.0
	var half_w = W / 2.0
	var half_h = H / 2.0

	# [Length, Height, Depth, x, z]  for each of the four sides
	var sides = [
		[W + 40.0, wall_h, 14.0, 0.0, -half_h - 7.0],      # back
		[W + 40.0, near_h, 14.0, 0.0, half_h + 7.0],       # front (nearest the camera)
		[14.0, wall_h, H + 40.0, -half_w - 7.0, 0.0],      # left
		[14.0, wall_h, H + 40.0, half_w + 7.0, 0.0],       # right
	]

	var body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = Color("#131b33")
	body_mat.metallic = 0.4
	body_mat.roughness = 0.45

	var strip_mat = StandardMaterial3D.new()
	strip_mat.albedo_color = Color("#4df0ff")
	strip_mat.emission_enabled = true
	strip_mat.emission = Color("#4df0ff")
	strip_mat.emission_energy_multiplier = 1.5

	for side in sides:
		var wall = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(side[0], side[1], side[2])
		wall.mesh = box
		wall.material_override = body_mat
		wall.position = Vector3(side[3], side[1] / 2.0, side[4])
		add_child(wall)

		# the bright strip along the top edge
		var strip = MeshInstance3D.new()
		var strip_box = BoxMesh.new()
		strip_box.size = Vector3(side[0] + 3.0, 2.0, side[2] + 3.0)
		strip.mesh = strip_box
		strip.material_override = strip_mat
		strip.position = Vector3(side[3], side[1] + 1.0, side[4])
		add_child(strip)


# ------------------------------------------------------------
#  cover. four low blocks in the middle of the arena, short enough to
#  see over but tall enough that an enemy bullet runs into them. this
#  is what makes the middle of the arena worth using instead of just
#  running round the outside edge
# ------------------------------------------------------------
func build_cover():
	var spots = [
		[-260.0, -170.0],
		[260.0, -170.0],
		[-260.0, 170.0],
		[260.0, 170.0],
	]
	# small and low. the first ones i made were 78 wide and 26 tall with a
	# big glowing top, and they read as huge yellow slabs rather than
	# something you duck behind
	var block_w = 62.0
	var block_d = 62.0
	var block_h = 18.0

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color("#26304f")
	mat.roughness = 0.75

	# dark blue with an amber edge. the edge is the only bright part, so
	# you can see where the block ends without it glowing in your face
	var top_mat = StandardMaterial3D.new()
	top_mat.albedo_color = Color("#101a33")
	top_mat.roughness = 0.8
	top_mat.emission_enabled = true
	top_mat.emission = Color("#ffb454")
	top_mat.emission_energy_multiplier = 0.35

	for spot in spots:
		var block = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(block_w, block_h, block_d)
		block.mesh = box
		block.material_override = mat
		block.position = Vector3(spot[0], block_h / 2.0, spot[1])
		add_child(block)

		# a thin lit stripe along the top edge, so you can see the block
		# against the dark floor without it shouting
		var rim = MeshInstance3D.new()
		var rim_box = BoxMesh.new()
		rim_box.size = Vector3(block_w + 2.0, 1.2, block_d + 2.0)
		rim.mesh = rim_box
		rim.material_override = top_mat
		rim.position = Vector3(spot[0], block_h + 0.2, spot[1])
		add_child(rim)

		# the numbers are stored in arena space, not 3d space, so the
		# collision code below does not have to think about the camera
		cover_list.append({
			"x": spot[0] + W / 2.0,
			"y": spot[1] + H / 2.0,
			"hw": block_w / 2.0,
			"hh": block_d / 2.0,
		})


# is this point inside a block?
func inside_cover(x, y, r = 0.0):
	for c in cover_list:
		if abs(x - c["x"]) < c["hw"] + r and abs(y - c["y"]) < c["hh"] + r:
			return true
	return false


# shove a round thing out of a block. returns the new position.
# this is only ever called for the player, so the blocks feel solid to
# you and to nothing else
func push_out_of_cover(x, y, r):
	for c in cover_list:
		var dx = x - c["x"]
		var dy = y - c["y"]
		var overlap_x = c["hw"] + r - abs(dx)
		var overlap_y = c["hh"] + r - abs(dy)
		if overlap_x > 0.0 and overlap_y > 0.0:
			# push out the short way, so you slide along the edge
			if overlap_x < overlap_y:
				var dir = 1.0
				if dx < 0.0:
					dir = -1.0
				x = c["x"] + dir * (c["hw"] + r)
			else:
				var dir2 = 1.0
				if dy < 0.0:
					dir2 = -1.0
				y = c["y"] + dir2 * (c["hh"] + r)
	return Vector2(x, y)


# ------------------------------------------------------------
#  where is the mouse pointing on the floor?
#  i shoot a line out of the camera through the mouse and see
#  where it hits the floor. this is why aiming works in 3d
# ------------------------------------------------------------
func mouse_on_floor(screen_pos):
	var from = cam.project_ray_origin(screen_pos)
	var dir = cam.project_ray_normal(screen_pos)
	if abs(dir.y) < 0.0001:
		return Vector3.ZERO
	var t = -from.y / dir.y
	return from + dir * t


# ------------------------------------------------------------
#  starting and resetting
# ------------------------------------------------------------
func reset_game():
	score = 0
	combo = 0
	comboT = 0.0
	wave = 0
	waveT = 1.2
	waveState = "break"
	elapsed = 0.0
	kills = 0
	deflects = 0
	perfects = 0
	wrongGuy = 0
	bestCombo = 0
	shake = 0.0
	hitstop = 0.0
	slowmo = 0.0
	flash = 0.0
	initials = ""
	passed_record = false
	# throw away every bullet and enemy
	for b in bullets:
		b.queue_free()
	bullets = []
	for e in enemies:
		e.queue_free()
	enemies = []
	spawns = []
	if player != null:
		player.sx = W / 2.0
		player.sy = H / 2.0
		player.vx = 0.0
		player.vy = 0.0
		player.hp = 3
		player.parry_time = 0.0
		player.cooldown = 0.0
		player.inv = 0.0
		player.aim = -PI / 2.0


# ------------------------------------------------------------
#  the demo behind the title screen
#  it is the real game running with the volume down: enemies spawn,
#  walk about and shoot at a fake player, and the bullets get deleted
#  before they reach him. nothing here touches the score, the waves
#  or the board, so it can never mess up a real run.
# ------------------------------------------------------------
func start_demo():
	demo = true
	stop_demo_quietly()
	var kinds = ["turret", "turret", "spreader", "rusher"]
	var i = 0
	while i < 5:
		var kind = kinds[randi() % kinds.size()]
		# spread them around the middle so the whole arena is busy
		var ang = TAU * float(i) / 5.0 + randf_range(-0.3, 0.3)
		var dist = randf_range(210.0, 330.0)
		var ex = clamp(W / 2.0 + cos(ang) * dist, 90.0, W - 90.0)
		var ey = clamp(H / 2.0 + sin(ang) * dist, 80.0, H - 80.0)
		var e = EnemyScript.new()
		e.kind = kind
		e.sx = ex
		e.sy = ey
		e.wave = 3
		# shoot at the ghost, not at the player
		e.target = ghost
		add_child(e)
		e.place()
		enemies.append(e)
		# stagger the first shot so they do not all fire on frame one
		e.fire_timer = randf_range(0.3, 2.2)
		i = i + 1


func stop_demo_quietly():
	for e in enemies:
		e.queue_free()
	enemies = []
	for b in bullets:
		b.queue_free()
	bullets = []
	spawns = []


func stop_demo():
	if demo:
		demo = false
		stop_demo_quietly()


# the fake player walks a slow circle so the demo is not static
func step_ghost(dt, t):
	var ang = t * 0.55
	ghost.sx = W / 2.0 + cos(ang) * 170.0
	ghost.sy = H / 2.0 + sin(ang * 1.3) * 110.0


# ------------------------------------------------------------
#  the window. my laptop is 1366 wide, so a 1280 window with a
#  title bar hangs off the bottom of the screen. start at whatever
#  fits on the actual monitor, and F11 is fullscreen if you want it
#  bigger. the game is drawn at 1280x720 and scaled, so the layout
#  is the same at every size.
# ------------------------------------------------------------
func fit_window_to_screen():
	var usable = DisplayServer.screen_get_usable_rect()
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	# leave a little room for the title bar and the taskbar
	var scale = min(1.0, min(usable.size.x * 0.92 / 1280.0, usable.size.y * 0.88 / 720.0))
	var w = int(1280 * scale)
	var h = int(720 * scale)
	get_window().size = Vector2i(w, h)
	# and put it in the middle of the screen
	get_window().position = usable.position + (usable.size - Vector2i(w, h)) / 2


func toggle_fullscreen():
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		fit_window_to_screen()
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func go_to_title():
	state = "title"
	paused = false
	reset_game()
	start_demo()


func start_game():
	stop_demo()
	reset_game()
	# starts empty. check_passing_record() works out who is next to beat,
	# and keeps moving up the board as the score climbs
	record_target = 0
	state = "play"
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	next_wave()


# ------------------------------------------------------------
#  input
# ------------------------------------------------------------
func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		var key = event as InputEventKey
		if state == "initials":
			type_letter(key)
			return
		if key.keycode == KEY_SPACE:
			if state == "play":
				player.try_parry()
			else:
				start_game()
		elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			if state != "play":
				start_game()
		elif key.keycode == KEY_R:
			if state == "over":
				start_game()
		elif key.keycode == KEY_P:
			if state == "play":
				paused = not paused
		elif key.keycode == KEY_M:
			muted = not muted
			snd.muted = muted
		elif key.keycode == KEY_F11:
			toggle_fullscreen()
		elif key.keycode == KEY_F2:
			# flip quality without editing the file
			if QUALITY == "low":
				hud.toast("glow + shadows need a restart to change", Color("#ffb454"))
			else:
				hud.toast("high quality mode", Color("#ffb454"))
		elif key.keycode == KEY_F3:
			hud.show_debug = not hud.show_debug
		elif key.keycode == KEY_ESCAPE:
			# escape always gets you out. in a game it takes you back to
			# the menu, on the menu it closes the window, so a stuck
			# window can never trap you again
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if state == "title":
				get_tree().quit()
			else:
				go_to_title()
	elif event is InputEventMouseMotion:
		aim_point = mouse_on_floor(event.position)
	elif event is InputEventMouseButton and event.pressed:
		aim_point = mouse_on_floor(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if state == "play":
				player.try_parry()
			else:
				start_game()


# ------------------------------------------------------------
#  the frame
# ------------------------------------------------------------
func _process(delta):
	var dt = min(delta, 0.05)
	if state == "play" and not paused:
		if hitstop > 0.0:
			hitstop = hitstop - dt
		else:
			var scale = 1.0
			if slowmo > 0.0:
				slowmo = slowmo - dt
				scale = 0.35
			step_world(dt * scale)
	else:
		elapsed = elapsed + dt
		if demo and state == "title":
			step_demo(dt)

	if demo and state == "title":
		# keep the glowing ring on the floor while the menu is up, it
		# makes the arena look alive behind the words
		crosshair.visible = true
		crosshair.position = Vector3(ghost.sx - W / 2.0, 1.5, ghost.sy - H / 2.0)

	shake = max(0.0, shake - dt * 46.0)
	flash = max(0.0, flash - dt * 2.6)
	update_camera(dt)
	update_crosshair()
	hud.refresh(self)


func update_camera(dt):
	# follow the player a tiny bit, then shake. that's the whole camera
	var fx_off = (player.sx - W / 2.0) * 0.10
	var fz_off = (player.sy - H / 2.0) * 0.07
	var target = cam_home + Vector3(fx_off, 0, fz_off)
	cam.position = cam.position.lerp(target, min(1.0, dt * 3.0))
	if shake > 0.0:
		cam.position.x = cam.position.x + randf_range(-shake, shake) * 0.8
		cam.position.y = cam_home.y + randf_range(-shake, shake) * 0.6
	cam.look_at(Vector3(fx_off * 0.4, 0, 20 + fz_off * 0.4), Vector3.UP)


# ------------------------------------------------------------
#  one step of the whole game
# ------------------------------------------------------------
# a one shot flag so the passing message only fires once a run
var passed_record = false
var record_target = 0        # the number i am chasing this run


func check_passing_record():
	# who am i chasing? whoever is sitting just above me. this has to be
	# worked out fresh, because it moves up the board as i pass people.
	# the old version picked one name at the start of the run and never
	# looked again, so beating 5th place still told me to beat 5th place
	# for the rest of the game
	var higher = 0
	var found = false
	for row in board:
		var their_score = int(row["score"])
		if their_score > score:
			if not found or their_score < higher:
				higher = their_score
				found = true
	if found:
		record_target = higher
	else:
		record_target = 0

	# the banner only fires once per run, and only after i have scored
	# something worth announcing
	if passed_record or score <= 0:
		return
	if board.size() > 0 and record_target == 0:
		passed_record = true
		fx.text(W / 2.0, H / 2.0 - 110, "RECORD BROKEN", Color("#ffd84d"), 40)
		say(player, "keep up", Color("#4df0ff"))
		snd.play("clear")
		shake = max(shake, 10.0)


func step_world(dt):
	elapsed = elapsed + dt

	if state == "play":
		player.step(dt, self)
		player.place()

	if comboT > 0.0:
		comboT = comboT - dt
		if comboT <= 0.0:
			combo = 0

	check_passing_record()
	step_cowards(dt)
	step_spawns(dt)
	step_enemies(dt)
	step_bullets(dt)
	check_wave(dt)


# the last one alive, on its last hit point, loses its nerve for a
# second. i had it running forever at first, which was a real bug: the
# last enemy would never come back, so the wave could never be finished.
# now he panics, says something, shoots again, and you can knock his own
# bullet back into him. one panic per wave, so it keeps being funny.
var coward_done = false

func step_cowards(dt):
	if wave < 2 or enemies.size() != 1:
		return
	if coward_done:
		return
	var e = enemies[0]
	if e.hp != 1 or e.age < 1.0:
		return
	e.running = true
	e.run_timer = 1.0
	coward_done = true
	say(e, pick_taunt_coward(), Color("#7cff9b"))


# one frame of the title screen demo
func step_demo(dt):
	step_ghost(dt, elapsed)
	for i in range(enemies.size() - 1, -1, -1):
		var e = enemies[i]
		e.step(dt, self)
		e.place()

	# move the bullets, and quietly drop the ones heading for the ghost
	for i in range(bullets.size() - 1, -1, -1):
		var b = bullets[i]
		var alive = b.step(dt, self)
		b.place()
		if not alive:
			bullets.remove_at(i)
			b.queue_free()
			continue
		# the ghost "parries": near enough is good enough for a menu
		var dx = b.sx - ghost.sx
		var dy = b.sy - ghost.sy
		if not b.mine and inside_cover(b.sx, b.sy, b.radius):
			bullets.remove_at(i)
			b.queue_free()
			fx.burst(b.sx, b.sy, Color("#ffb454"), 5)
		elif not b.mine and sqrt(dx * dx + dy * dy) < 42.0:
			bullets.remove_at(i)
			b.queue_free()
			fx.burst(b.sx, b.sy, Color("#4df0ff"), 6)
		elif b.mine:
			# a demo bullet that comes home kills the shooter, so the
			# demo keeps refreshing itself instead of getting quiet
			for j in range(enemies.size() - 1, -1, -1):
				var e2 = enemies[j]
				var ex = b.sx - e2.sx
				var ey = b.sy - e2.sy
				if sqrt(ex * ex + ey * ey) < e2.radius + b.radius:
					fx.burst(e2.sx, e2.sy, Color("#ffb454"), 14)
					enemies.remove_at(j)
					e2.queue_free()
					bullets.remove_at(i)
					b.queue_free()
					break

	# keep the demo populated: if it thins out, quietly add somebody
	if enemies.size() < 4 and randf() < dt * 0.9:
		var kinds = ["turret", "spreader", "rusher"]
		var kind = kinds[randi() % kinds.size()]
		var ang = randf_range(0.0, TAU)
		var dist = randf_range(210.0, 330.0)
		var e = EnemyScript.new()
		e.kind = kind
		e.sx = clamp(W / 2.0 + cos(ang) * dist, 90.0, W - 90.0)
		e.sy = clamp(H / 2.0 + sin(ang) * dist, 80.0, H - 80.0)
		e.wave = 3
		e.target = ghost
		e.fire_timer = randf_range(0.4, 1.6)
		add_child(e)
		e.place()
		enemies.append(e)


func step_spawns(dt):
	for i in range(spawns.size() - 1, -1, -1):
		var s = spawns[i]
		s["t"] = s["t"] - dt
		if s["t"] <= 0.0:
			make_enemy(s["kind"], s["x"], s["y"])
			spawns.remove_at(i)


func step_enemies(dt):
	for i in range(enemies.size() - 1, -1, -1):
		var e = enemies[i]
		e.step(dt, self)
		e.place()


func step_bullets(dt):
	for i in range(bullets.size() - 1, -1, -1):
		# something this bullet does might clear the whole list (dying
		# does that), so check the index is still real before using it
		if i >= bullets.size():
			continue
		var b = bullets[i]
		var alive = b.step(dt, self)
		b.place()
		if not alive:
			bullets.remove_at(i)
			b.queue_free()
			continue

		if not b.mine:
			var dx = b.sx - player.sx
			var dy = b.sy - player.sy
			var dist = sqrt(dx * dx + dy * dy)

			# --- the parry. this is the whole game in one if ---
			if player.parry_time > 0.0 and dist < PARRY_RADIUS + b.radius:
				var ang = atan2(dy, dx)
				if abs(angle_difference(player.aim, ang)) < PARRY_ARC / 2.0:
					reflect_bullet(b)
					continue

			# --- or it hits a block ---
			if inside_cover(b.sx, b.sy, b.radius):
				bullets.remove_at(i)
				b.queue_free()
				fx.burst(b.sx, b.sy, Color("#ffb454"), 5)
				snd.play("cover")
				continue

			# --- or it hits me ---
			if player.inv <= 0.0 and dist < 12.0 + b.radius:
				bullets.remove_at(i)
				b.queue_free()
				hurt_player(b.src)
		else:
			# my bullet: does it hit an enemy?
			# (kill_enemy can free the bullet for me, so i check that it
			# is still in the list before removing it again. removing
			# index i twice was a crash waiting to happen)
			for j in range(enemies.size() - 1, -1, -1):
				var e = enemies[j]
				var ex = b.sx - e.sx
				var ey = b.sy - e.sy
				if sqrt(ex * ex + ey * ey) < e.radius + b.radius:
					e.hp = e.hp - 1
					e.flash = 0.12
					if e.hp <= 0:
						kill_enemy(j, b)
					else:
						shake = max(shake, 4.0)
					if not b.mine:
						# kill_enemy already took it out of the list
						break
					b.pierce = b.pierce - 1
					if b.pierce <= 0:
						bullets.remove_at(i)
						b.queue_free()
					break


# ------------------------------------------------------------
#  parry!
# ------------------------------------------------------------
func reflect_bullet(b):
	var perfect = (PARRY_TIME - player.parry_time) <= PERFECT_WINDOW
	var speed = REFLECT_SPEED
	if perfect:
		speed = REFLECT_SPEED * 1.22
	b.vx = cos(player.aim) * speed
	b.vy = sin(player.aim) * speed
	b.mine = true
	# paint() is what actually turns it from red to cyan. setting mine
	# alone only changes the numbers, not the mesh, so a parried bullet
	# stayed red and looked like it was still coming for you
	b.paint()
	b.pierce = 1
	if perfect:
		b.pierce = 2
	b.life = 4.0
	deflects = deflects + 1
	if perfect:
		perfects = perfects + 1
		score = score + 50
		fx.text(b.sx, b.sy - 25, "PERFECT", Color.WHITE, 22)
		shake = max(shake, 11.0)
		hitstop = max(hitstop, 0.075)
		slowmo = max(slowmo, 0.12)
		snd.play("perfect")
		if b.src != null and b.src.is_inside_tree() and b.src.hp > 0 and randf() < 0.55:
			say(b.src, pick_taunt_scared(), Color("#ffd84d"))
	else:
		score = score + 10
		shake = max(shake, 6.0)
		hitstop = max(hitstop, 0.045)
		snd.play("parry")
	fx.burst(b.sx, b.sy, Color("#4df0ff"), 12)
	fx.ring(b.sx, b.sy, Color("#4df0ff"), 46)


# ------------------------------------------------------------
#  damage
# ------------------------------------------------------------
func hurt_player(from_who):
	if player.inv > 0.0:
		return
	player.hp = player.hp - 1
	player.inv = 1.15
	shake = max(shake, 16.0)
	flash = 1.0
	combo = 0
	comboT = 0.0
	fx.burst(player.sx, player.sy, Color("#ec3750"), 26)
	fx.ring(player.sx, player.sy, Color("#ec3750"), 110)
	snd.play("hurt")
	if from_who != null and from_who.is_inside_tree() and from_who.hp > 0:
		if randf() < 0.85:
			say(from_who, pick_taunt_hit(), Color("#ff5a6e"))
	if player.hp <= 0:
		game_over()


func kill_enemy(index, by_bullet):
	var e = enemies[index]
	enemies.remove_at(index)
	kills = kills + 1
	combo = combo + 1
	comboT = COMBO_TIME
	if combo > bestCombo:
		bestCombo = combo
	# every ten kills, he says something. tiny thing, but it makes the
	# little ball feel like he is enjoying himself
	if kills > 0 and kills % 10 == 0:
		say(player, pick_player_line(), Color("#4df0ff"))

	var gain = 100 * combo
	score = score + gain
	fx.text(e.sx, e.sy - 20, "+" + str(gain), Color("#ffb454"), 22)
	if combo > 1:
		fx.text(e.sx, e.sy - 46, "x" + str(combo), Color("#ffb454"), 16)
	if combo >= 3:
		fx.text(e.sx, e.sy - 70, combo_name(combo), Color("#ff4fd8"), 22)
	fx.burst(e.sx, e.sy, Color("#ffb454"), 24)
	fx.ring(e.sx, e.sy, Color("#ffb454"), 80)
	if combo == 5:
		hud.toast("SICK", Color("#ff4fd8"))
	elif combo == 8:
		hud.toast("FILTHY", Color("#ff4fd8"))
	elif combo == 12:
		hud.toast("INSANE", Color("#ff4fd8"))
	elif combo == 20:
		hud.toast("UNREAL", Color("#ff4fd8"))
	shake = max(shake, 9.0)
	hitstop = max(hitstop, 0.055)
	slowmo = max(slowmo, 0.16)
	snd.play("kill")
	e.queue_free()

	# if my bullet kills somebody it did not belong to, that is a wrong guy
	if by_bullet != null and by_bullet.src != null and by_bullet.src != e:
		wrongGuy = wrongGuy + 1
		score = score + 50
		fx.text(e.sx, e.sy - 94, "WRONG GUY +50", Color("#ff4fd8"), 16)
		if by_bullet.src.is_inside_tree() and by_bullet.src.hp > 0:
			if randf() < 0.8:
				say(by_bullet.src, pick_taunt_wrong(), Color("#ff4fd8"))


# a speech bubble above whatever just said something
func say(who, words, colour):
	if who == null or not who.is_inside_tree():
		return
	hud.add_bubble(sim_to_world(who.sx, who.sy, 58.0), words, colour)


func combo_name(c):
	if c >= 20:
		return "UNREAL"
	if c >= 12:
		return "INSANE"
	if c >= 8:
		return "FILTHY"
	if c >= 5:
		return "SICK"
	return "NICE"


# ------------------------------------------------------------
#  enemies and waves
# ------------------------------------------------------------
func make_enemy(kind, sx, sy):
	var e = EnemyScript.new()
	e.kind = kind
	e.sx = sx
	e.sy = sy
	e.wave = wave
	add_child(e)
	e.place()
	enemies.append(e)
	return e


func fire_bullet(from_enemy, angle, speed):
	var b = BulletScript.new()
	b.sx = from_enemy.sx + cos(angle) * (from_enemy.radius + 6.0)
	b.sy = from_enemy.sy + sin(angle) * (from_enemy.radius + 6.0)
	b.vx = cos(angle) * speed
	b.vy = sin(angle) * speed
	b.src = from_enemy
	add_child(b)
	b.place()
	bullets.append(b)
	snd.play("shoot")


# put one bullet at an exact spot, instead of working out an angle from
# an enemy. the wave code does not use these, but they are handy when i
# want a shot in a particular place
func spawn_bullet_at(from_enemy, sx, sy, vx, vy):
	var b = BulletScript.new()
	b.sx = sx
	b.sy = sy
	b.vx = vx
	b.vy = vy
	b.src = from_enemy
	add_child(b)
	b.place()
	bullets.append(b)
	return b


func spawn_my_bullet_at(from_enemy, sx, sy, vx, vy):
	var b = spawn_bullet_at(from_enemy, sx, sy, vx, vy)
	b.mine = true
	b.paint()
	return b


func next_wave():
	wave = wave + 1
	waveState = "fight"
	# wave 1 is two turrets, not three. three is too many: the parry only
	# covers 83 degrees, so shots arriving from behind you cannot be
	# blocked at all and a first timer just loses without understanding
	# why. two looks scarier than it sounds because they now walk at you
	# the wave curve. with fewer they piled up slowly and the middle of a
	# run had nothing happening in it
	var turrets = clamp(2 + int(wave * 0.75), 2, 9)
	var spreaders = clamp(int(wave / 1.6), 0, 5)
	var rushers = clamp(int((wave - 1) / 1.2), 0, 6)

	coward_done = false

	var list = []
	for i in turrets:
		list.append("turret")
	for i in spreaders:
		list.append("spreader")
	for i in rushers:
		list.append("rusher")

	var n = 0
	for kind in list:
		# put them near the walls, never right on top of the player
		var sx = 0.0
		var sy = 0.0
		var tries = 0
		while tries < 24:
			var edge = randi() % 4
			if edge == 0:
				sx = randf_range(60, W - 60)
				sy = randf_range(50, 110)
			elif edge == 1:
				sx = randf_range(W - 140, W - 60)
				sy = randf_range(60, H - 60)
			elif edge == 2:
				sx = randf_range(60, W - 60)
				sy = randf_range(H - 110, H - 50)
			else:
				sx = randf_range(60, 140)
				sy = randf_range(60, H - 60)
			tries = tries + 1
			var dx = sx - player.sx
			var dy = sy - player.sy
			var gap = sqrt(dx * dx + dy * dy)
			# not on top of the player, but not hiding at the far wall
			# either. between 170 and 560 units away
			if gap > 170.0 and gap < 560.0:
				break
		spawns.append({ "kind": kind, "x": sx, "y": sy, "t": 0.55 + n * 0.16 })
		n = n + 1

	fx.text(W / 2.0, H / 2.0 - 70, "WAVE " + str(wave), Color("#4df0ff"), 44)
	if wave >= 2:
		hud.toast(wave_line(), Color("#8494bf"))
	snd.play("wave")


func check_wave(dt):
	if waveState == "fight" and enemies.is_empty() and spawns.is_empty():
		waveState = "break"
		waveT = 2.0
		var bonus = 250 * wave
		score = score + bonus
		fx.text(W / 2.0, H / 2.0 - 30, "WAVE CLEAR  +" + str(bonus), Color("#4df0ff"), 26)
		snd.play("clear")
		# every third wave you get one hp back
		if wave % 3 == 0 and player.hp < 5:
			player.hp = player.hp + 1
			fx.text(W / 2.0, H / 2.0 + 10, "PATCHED UP  +1 HP", Color("#7cff9b"), 20)
			hud.toast("+1 LIFE", Color("#7cff9b"))
	elif waveState == "break":
		waveT = waveT - dt
		if waveT <= 0.0:
			next_wave()


# ------------------------------------------------------------
#  game over + leaderboard
# ------------------------------------------------------------
func game_over():
	state = "over"
	# the demo comes back behind the game over screen, but not right now:
	# we are inside step_bullets and emptying the bullet list here would
	# pull the floor out from under the loop. one frame later is fine.
	call_deferred("start_demo")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	rank = work_out_rank()
	pending_score = score
	shake = 26.0
	hitstop = 0.12
	fx.burst(player.sx, player.sy, Color("#ec3750"), 60)
	snd.play("over")
	if can_enter_board(score):
		state = "initials"
		initials = ""


func work_out_rank():
	var ratio = 0.0
	if deflects > 0:
		ratio = float(perfects) / float(deflects)
	if score > 14000 and ratio > 0.45:
		return "S"
	if score > 9000 or ratio > 0.5:
		return "A"
	if score > 5000 or ratio > 0.3:
		return "B"
	if score > 2000:
		return "C"
	return "D"


func can_enter_board(s):
	if s <= 0:
		return false
	if board.size() < 5:
		return true
	var last = board[board.size() - 1]
	return s > int(last["score"])


# is this name already on the board? used to show "your best" on the
# game over screen instead of asking for the initials again
func best_for_name(letters):
	var clean = str(letters).to_upper().substr(0, 3)
	for row in board:
		if str(row["name"]) == clean:
			return int(row["score"])
	return -1


func type_letter(key):
	var code = key.keycode
	if code == KEY_BACKSPACE:
		if initials.length() > 0:
			initials = initials.substr(0, initials.length() - 1)
		snd.play("type")
		return
	if code == KEY_ENTER or code == KEY_KP_ENTER:
		if initials.length() > 0:
			submit_initials(initials)
		return
	if code == KEY_ESCAPE:
		state = "over"
		return
	var letter = char(code)
	if letter.length() == 1 and letter >= "A" and letter <= "Z":
		if initials.length() < 3:
			initials = initials + letter
			snd.play("type")
	elif letter.length() == 1 and letter >= "0" and letter <= "9":
		if initials.length() < 3:
			initials = initials + letter
			snd.play("type")


func submit_initials(name):
	var clean = ""
	for i in name.length():
		var c = name.substr(i, 1).to_upper()
		if (c >= "A" and c <= "Z") or (c >= "0" and c <= "9"):
			clean = clean + c
	if clean == "":
		clean = "AAA"
	if clean.length() > 3:
		clean = clean.substr(0, 3)
	# a name only ever gets one row on the board. if the same name comes
	# back with a bigger score i replace the old row, and if it comes back
	# with a smaller one i do not touch it. before this i appended a new
	# row every time, so AAA AAA AAA could fill the whole board.
	var found = -1
	for i in board.size():
		if str(board[i]["name"]).to_upper() == clean:
			found = i
	if found >= 0:
		if pending_score > int(board[found]["score"]):
			board[found]["score"] = pending_score
			board[found]["wave"] = wave
	else:
		board.append({ "name": clean, "score": pending_score, "wave": wave })

	build_board()
	save_board()
	state = "over"


# sort the board best first, clean up anything silly, and keep 5 rows
func build_board():
	var cleaned = []
	for row in board:
		if not (row is Dictionary):
			continue
		if not row.has("name") or not row.has("score"):
			continue
		cleaned.append({
			"name": str(row["name"]).to_upper().substr(0, 3),
			"score": int(row["score"]),
			"wave": int(row["wave"]) if row.has("wave") else 1,
		})

	# throw away duplicate names in old save files, keeping the best one
	var unique = []
	for row in cleaned:
		var seen = -1
		for i in unique.size():
			if unique[i]["name"] == row["name"]:
				seen = i
		if seen >= 0:
			if row["score"] > unique[seen]["score"]:
				unique[seen] = row
		else:
			unique.append(row)

	# sort best first. a plain bubble sort, biggest score to the top.
	# the board only ever holds five rows so this is plenty fast
	var i = 0
	while i < unique.size():
		var j = i + 1
		while j < unique.size():
			if unique[j]["score"] > unique[i]["score"]:
				var swap = unique[i]
				unique[i] = unique[j]
				unique[j] = swap
			j = j + 1
		i = i + 1

	board = []
	var k = 0
	while k < unique.size() and k < 5:
		board.append(unique[k])
		k = k + 1


func save_board():
	var f = FileAccess.open(BOARD_PATH, FileAccess.WRITE)
	if f != null:
		f.store_var(board)
		f.close()


# the board a fresh install starts with, so there is always a number to
# chase. without this the score-to-beat bar is invisible until you have
# played once, which is a bad first ten seconds
func starter_board():
	return [
		{"name": "ZED", "score": 1200, "wave": 4},
		{"name": "KAI", "score": 850, "wave": 3},
		{"name": "MO", "score": 500, "wave": 2},
	]


func load_board():
	board = []
	if not FileAccess.file_exists(BOARD_PATH):
		board = starter_board()
		build_board()
		return
	if FileAccess.file_exists(BOARD_PATH):
		var f = FileAccess.open(BOARD_PATH, FileAccess.READ)
		if f != null:
			var data = f.get_var()
			f.close()
			if data is Array:
				board = data
	# older save files can have the same name twice, so tidy it up on load
	build_board()


# ------------------------------------------------------------
#  the stupid things the enemies say
# ------------------------------------------------------------
const TAUNTS_HIT = ["skill issue", "got 'em", "lol", "too slow", "that's on you", "ez", "nice try"]
const TAUNTS_WRONG = ["wrong guy!", "friendly fire!", "oops", "not me!!"]
const TAUNTS_SCARED = ["how?!", "no fair", "cheater", "wait what", "impossible"]
const TAUNTS_COWARD = ["mom pick me up", "i quit", "not paid enough", "brb", "he's cheating",
	"i have a family", "nope nope nope", "you're hacking"]

func pick_taunt_hit():
	return TAUNTS_HIT[randi() % TAUNTS_HIT.size()]

func pick_taunt_wrong():
	return TAUNTS_WRONG[randi() % TAUNTS_WRONG.size()]

func pick_taunt_scared():
	return TAUNTS_SCARED[randi() % TAUNTS_SCARED.size()]


# a line under each wave number, so the game has a bit of mouth on it
const WAVE_LINES = [
	"they are warming up",
	"more of them this time",
	"they brought friends",
	"ok this is getting silly",
	"who keeps hiring these guys",
	"they are not even aiming",
	"somebody call an adult",
	"this is a lot of turrets",
]

const PLAYER_LINES = ["next", "too easy", "come on then", "is that it", "warm up over"]

func pick_player_line():
	return PLAYER_LINES[randi() % PLAYER_LINES.size()]


func wave_line():
	var i = wave - 2
	if i < 0:
		i = 0
	if i >= WAVE_LINES.size():
		i = WAVE_LINES.size() - 1
	return WAVE_LINES[i]


func pick_taunt_coward():
	return TAUNTS_COWARD[randi() % TAUNTS_COWARD.size()]
