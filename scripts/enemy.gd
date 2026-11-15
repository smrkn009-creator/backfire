extends Node3D
# ============================================================

const GlowDisc = preload("res://scripts/glow_disc.gd")

# ============================================================
#  the three bad guys. they all live in this file because they
#  share 90% of the same code, only the shape and how they
#  move is different:
#      turret   - slowly floats about and fires one aimed shot
#      spreader - fires three shots in a fan
#      rusher   - walks at you, winds up, then dashes
# ============================================================

var kind = "turret"
var sx = 0.0
var sy = 0.0
var vx = 0.0
var vy = 0.0
var hp = 1
var radius = 14.0
var wave = 1

var fire_timer = 1.5
var rate = 1.8
var bullet_speed = 260.0
var flash = 0.0

# rusher only
var phase = "stalk"     # stalk / wind / dash / rest
var phase_timer = 0.0

# where the enemy is walking to
var walk_x = 0.0
var walk_y = 0.0
var walk_timer = 0.0

var mat = null
var shape = null
var age = 0.0            # how long this one has been alive
var running = false      # chicken: the last one alive runs away
var run_timer = 0.0
var float_y = 18.0       # how high off the floor it floats
var node_scale = 1.25    # how big the whole thing is drawn
var target = null        # who to aim at. null = the player
                         # the title screen demo points this at a fake player


func _ready():
	# these are the shapes from the web version, which everyone liked
	# better than the little machines i built after: one clean crystal
	# each, plus a soft glow stuck to it. Godot has no octahedron or
	# tetrahedron mesh, so i make them out of points by hand.
	if kind == "turret":
		# a red octahedron: two square pyramids joined at the base
		hp = 1
		radius = 15.0
		rate = max(0.70, 1.55 - wave * 0.07)
		bullet_speed = 262.0
		mat = glow(Color("#ff2d45"), 2.2)
		shape = make_crystal(8, 11.0, 30.0)
		shape.material_override = mat
		add_child(shape)

	elif kind == "spreader":
		# an orange tetrahedron, which is the pointy one
		hp = 2
		radius = 17.0
		rate = max(1.15, 2.30 - wave * 0.07)
		bullet_speed = 232.0
		mat = glow(Color("#ff8a3d"), 2.2)
		shape = make_crystal(4, 13.0, 28.0)
		shape.material_override = mat
		add_child(shape)

	else:
		# a pink cone lying on its side, pointing where it is going
		hp = 1
		radius = 13.0
		phase = "stalk"
		phase_timer = randf_range(0.6, 1.3)
		mat = glow(Color("#ff3ad0"), 2.4)
		shape = MeshInstance3D.new()
		var cone = CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 13.0
		cone.height = 30.0
		cone.radial_segments = 4          # four sides makes it a crystal
		shape.mesh = cone
		shape.material_override = mat
		# stand it on its side. a cone points up by default, so tip it
		# towards -Z, which is the direction the enemy faces
		shape.rotation_degrees.x = -90.0
		add_child(shape)

	# the glow. a soft disc stuck to the middle of every crystal, which
	# is what makes them read at a distance
	var halo = GlowDisc.new()
	halo.colour = mat.albedo_color
	halo.size = radius * 5.2
	halo.strength = 0.5
	halo.position.y = 0.0
	add_child(halo)

	# the base of every crystal sits a little above the floor, and each
	# one turns slowly so the facets catch the light
	position.y = 0.0

	# bigger, so their shape reads from the camera	# bigger, so their shape reads from the camera. the hit radius grows
	# with them, so they are still as easy (or hard) to hit as before
	radius = radius * 1.25

	# the crystal floats above the floor instead of sitting in it, and
	# every one of them is a bit bigger than the raw shape
	position.y = 0.0
	float_y = radius * 1.55
	node_scale = 1.5

	# wave 1 is easy on purpose: everybody who tries the game should
	# get a kill before it starts being mean
	if wave == 1:
		rate = rate / 0.86
		bullet_speed = bullet_speed * 0.86

	fire_timer = randf_range(0.9, 1.9)
	walk_x = sx
	walk_y = sy


func glow(colour, power):
	var m = StandardMaterial3D.new()
	m.albedo_color = colour
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = power
	# flat and bright. i tried making them shiny (metallic + rim light)
	# and they turned grey, because the shiny bits reflect the blue room
	# light instead of keeping their own colour. no metal, no shine
	m.roughness = 0.55
	m.metallic = 0.0
	return m


func step(dt, game):
	age = age + dt
	if flash > 0.0:
		flash = flash - dt

	# normally the player. the demo behind the menu sets target to a
	# fake player so the menu has something to shoot at
	var who = game.player
	if target != null:
		who = target
	var dx = who.sx - sx
	var dy = who.sy - sy
	var to_player = atan2(dy, dx)

	# the scared one runs for the wall and stops shooting, but only
	# for a second. then he remembers he has a gun and comes back,
	# otherwise the wave could never end
	if running:
		run_timer = run_timer - dt
		var away = to_player + PI
		sx = clamp(sx + cos(away) * 230.0 * dt, 40.0, 920.0)
		sy = clamp(sy + sin(away) * 230.0 * dt, 40.0, 500.0)
		if run_timer <= 0.0:
			running = false
			fire_timer = 0.35      # shoot again almost straight away
		return

	if kind == "rusher":
		step_rusher(dt, dx, dy, to_player)
	else:
		step_shooter(dt, dx, dy, to_player, game)

	# does it touch me? this must be checked for every kind of enemy. it
	# used to sit inside the shooting code, so a rusher could dash right
	# through me and nothing happened
	touch_player(game)

	# spinning for the turret, turning for the rest
	if kind == "turret":
		shape.rotation.y = shape.rotation.y + dt * 1.4
		shape.rotation.x = shape.rotation.x + dt * 0.6
	else:
		# same rule as the player: local -Z is "forward", so turning by
		# -90 degrees lines the spike up with the angle it is aiming at.
		rotation.y = -(to_player + PI / 2.0)


func step_shooter(dt, dx, dy, to_player, game):
	# walk about, but drift towards the player instead of picking
	# somewhere random. before this they wandered anywhere and spent half
	# the wave parked behind a block where you could not see them, and an
	# enemy you cannot see is not scary, it is just missing
	walk_timer = walk_timer + dt
	var wdx = walk_x - sx
	var wdy = walk_y - sy
	var wlen = sqrt(wdx * wdx + wdy * wdy)
	if wlen < 24.0 or walk_timer > 2.4:
		walk_timer = 0.0
		# aim the walk at a point near the player, a bit off centre so
		# they do not all stand in one pile
		var pull = randf_range(60.0, 180.0)
		var spread = randf_range(-120.0, 120.0)
		walk_x = clamp(game.player.sx + cos(to_player + PI + spread * 0.01) * pull, 60.0, game.W - 60.0)
		walk_y = clamp(game.player.sy + sin(to_player + PI + spread * 0.01) * pull, 60.0, game.H - 60.0)

		# never aim the walk into a block, they would get stuck behind it
		if game.inside_cover(walk_x, walk_y, 40.0):
			walk_x = clamp(walk_x + randf_range(-140.0, 140.0), 60.0, game.W - 60.0)
			walk_y = clamp(walk_y + randf_range(-140.0, 140.0), 60.0, game.H - 60.0)

		wdx = walk_x - sx
		wdy = walk_y - sy
		wlen = sqrt(wdx * wdx + wdy * wdy)

	if wlen > 1.0:
		sx = sx + (wdx / wlen) * 54.0 * dt
		sy = sy + (wdy / wlen) * 54.0 * dt

	# and if they are somehow standing inside a block, shove them out.
	# a bullet that spawns inside cover dies straight away, so this also
	# means they stop wasting their shots on the block they are stuck in
	var out = game.push_out_of_cover(sx, sy, radius)
	sx = out.x
	sy = out.y

	# bang
	fire_timer = fire_timer - dt
	if fire_timer <= 0.0:
		fire_timer = rate * randf_range(0.85, 1.15)
		if kind == "turret":
			game.fire_bullet(self, to_player, bullet_speed)
		else:
			game.fire_bullet(self, to_player - 0.22, bullet_speed)
			game.fire_bullet(self, to_player, bullet_speed)
			game.fire_bullet(self, to_player + 0.22, bullet_speed)


func step_rusher(dt, dx, dy, to_player):
	phase_timer = phase_timer - dt
	var dist = sqrt(dx * dx + dy * dy)
	if dist < 1.0:
		dist = 1.0

	if phase == "stalk":
		sx = sx + (dx / dist) * 105.0 * dt
		sy = sy + (dy / dist) * 105.0 * dt
		if phase_timer <= 0.0:
			phase = "wind"
			phase_timer = 0.42
	elif phase == "wind":
		# shaking = get out of the way
		if phase_timer <= 0.0:
			phase = "dash"
			phase_timer = 0.42
			# charge at the player. the spike points that way now, so the
			# shape and the movement agree
			vx = cos(to_player) * 560.0
			vy = sin(to_player) * 560.0
	elif phase == "dash":
		sx = sx + vx * dt
		sy = sy + vy * dt
		vx = vx * (1.0 - 1.6 * dt)
		vy = vy * (1.0 - 1.6 * dt)
		if phase_timer <= 0.0:
			phase = "rest"
			phase_timer = 0.45
	else:
		sx = sx + vx * dt * 0.3
		sy = sy + vy * dt * 0.3
		if phase_timer <= 0.0:
			phase = "stalk"
			phase_timer = randf_range(0.35, 0.7)

	sx = clamp(sx, 20.0, 1080.0 - 20.0)
	sy = clamp(sy, 20.0, 620.0 - 20.0)


func touch_player(game):
	var dx = game.player.sx - sx
	var dy = game.player.sy - sy
	var dist = sqrt(dx * dx + dy * dy)
	if dist < radius + 12.0:
		if game.player.parry_time > 0.0:
			# blocked with the shield: push them away
			var ang = atan2(-dy, -dx)
			sx = sx + cos(ang) * 26.0
			sy = sy + sin(ang) * 26.0
			if kind == "rusher":
				phase = "rest"
				phase_timer = 0.8
				vx = 0.0
				vy = 0.0
			game.shake = max(game.shake, 5.0)
		else:
			game.hurt_player(self)


func place():
	position = Vector3(sx - 540.0, 0, sy - 310.0)
	# bob a little so they feel alive, and stay up off the floor
	position.y = float_y + sin(Time.get_ticks_msec() / 300.0 + sx * 0.01) * 3.0

	if mat == null:
		return
	if flash > 0.0:
		mat.albedo_color = Color.WHITE
		mat.emission = Color.WHITE
		mat.emission_energy_multiplier = 4.0
	else:
		var base = Color("#ff2d45")
		if kind == "spreader":
			base = Color("#ff8a3d")
		elif kind == "rusher":
			base = Color("#ff3ad0")
		mat.albedo_color = base
		mat.emission = base
		if kind == "rusher" and phase == "wind":
			mat.emission_energy_multiplier = 3.4
		else:
			mat.emission_energy_multiplier = 2.2

	# rushers swell up just before they dash
	scale = Vector3.ONE * node_scale
	if kind == "rusher" and phase == "wind":
		scale = Vector3.ONE * (node_scale * 1.14)


# ------------------------------------------------------------
#  build an octahedron or a tetrahedron out of triangles.
#  an octahedron is 8 triangles: it is just two pyramids glued base
#  to base. a tetrahedron is 4. i could not find these as ready made
#  meshes in godot, so here is the geometry spelled out.
# ------------------------------------------------------------
func make_crystal(faces, size, height):
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# the points. top, bottom, and a ring of points round the waist
	var top = Vector3(0, height * 0.55, 0)
	var bottom = Vector3(0, -height * 0.55, 0)
	var ring = []
	var i = 0
	while i < 4:
		var ang = TAU * i / 4.0 + PI / 4.0
		ring.append(Vector3(cos(ang) * size, 0, sin(ang) * size))
		i = i + 1

	if faces == 8:
		# octahedron: 4 triangles up to the top, 4 down to the bottom
		var j = 0
		while j < 4:
			var a = ring[j]
			var b = ring[(j + 1) % 4]
			_tri(st, top, a, b)
			_tri(st, bottom, b, a)
			j = j + 1
	else:
		# tetrahedron: top point with three of the four ring points as
		# the base, then the last one closes the other side
		var k = 0
		while k < 3:
			_tri(st, top, ring[k], ring[k + 1])
			k = k + 1
		_tri(st, bottom, ring[1], ring[0])
		_tri(st, bottom, ring[2], ring[1])
		_tri(st, bottom, ring[3], ring[2])
		_tri(st, bottom, ring[0], ring[3])
		_tri(st, top, ring[3], ring[0])

	# every triangle gets a normal that points away from the middle, so
	# the facets light up separately. that is most of the crystal look
	st.generate_normals()

	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	return mesh_inst


func _tri(st, a, b, c):
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
