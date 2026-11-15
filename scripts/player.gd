extends Node3D
# ============================================================

const GlowDisc = preload("res://scripts/glow_disc.gd")

# ============================================================
#  the player: a little glowing capsule with a nose, a shield
#  arc and a ring under the feet that shows the cooldown.
#  it does not know about enemies or score, it just moves,
#  aims and reports when it parried.
# ============================================================

var sx = 540.0        # position on the flat map
var sy = 310.0
var vx = 0.0
var vy = 0.0
var hp = 3
var aim = -PI / 2.0
var parry_time = 0.0   # how long the shield stays up
var cooldown = 0.0

# how long a parry lasts, written down in one place. game.gd sets these
# from its own settings at startup so the shield animation always matches
# the real window
var parry_length = 0.18
var parry_cooldown = 0.34
var inv = 0.0          # invincible time after getting hit

var body = null
var nose = null
var shield = null
var ring = null
var ring_mat = null
var shield_mat = null
var body_mat = null


func _ready():
	# ring on the floor: "here i am" + parry cooldown meter
	ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 26.0
	torus.outer_radius = 31.0
	ring.mesh = torus
	# a torus already lies flat on the floor, so no rotation here
	ring_mat = glow_material(Color("#4df0ff"), 2.0)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = ring_mat
	ring.position.y = 1.0
	add_child(ring)

	# the body: a round white ball tinted cyan, like the web build.
	# simple, and it reads instantly against the dark floor
	body = MeshInstance3D.new()
	var head_ball = SphereMesh.new()
	head_ball.radius = 12.0
	head_ball.height = 24.0
	head_ball.radial_segments = 24
	head_ball.rings = 14
	body.mesh = head_ball
	body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = Color("#ffffff")
	body_mat.emission_enabled = true
	body_mat.emission = Color("#9fe9ff")
	body_mat.emission_energy_multiplier = 1.1
	body_mat.roughness = 0.25
	body.material_override = body_mat
	body.position.y = 15.0
	add_child(body)

	# the glow around him
	var halo = GlowDisc.new()
	halo.colour = Color("#4df0ff")
	halo.size = 78.0
	halo.strength = 0.6
	halo.position.y = 15.0
	add_child(halo)

	# a visor slit, so you can tell which way he is looking
	var visor = MeshInstance3D.new()
	var visor_mesh = BoxMesh.new()
	visor_mesh.size = Vector3(13.0, 2.5, 2.0)
	visor.mesh = visor_mesh
	visor.material_override = glow_material(Color("#0a1020"), 0.2)
	visor.position = Vector3(0, 18.0, -10.5)
	add_child(visor)

	# little light so the player lights up the floor around him
	var lamp = OmniLight3D.new()
	lamp.light_color = Color("#4df0ff")
	lamp.light_energy = 2.2
	lamp.omni_range = 240.0
	lamp.position.y = 26.0
	add_child(lamp)

	# the nose. it points along the aim so you always know
	# which way your shield is facing
	nose = MeshInstance3D.new()
	var cone = CylinderMesh.new()
	cone.top_radius = 0.0        # the pointy end
	cone.bottom_radius = 6.0
	cone.height = 20.0
	nose.mesh = cone
	nose.material_override = glow_material(Color("#ffffff"), 3.0)
	# a cone points up by default, so lay it on its side pointing forward.
	# "forward" for the player is local -Z, because that is the direction
	# we rotate the whole body to face
	nose.rotation_degrees.x = -90.0
	nose.position = Vector3(0, 17.0, -20.0)
	add_child(nose)

	# the shield: a round buckler that floats in front of you and
	# always faces the way you are aiming. it is built on a small
	# "face" node that is tipped upright, so everything i add to it
	# can be drawn as if it were flat on a table
	shield = Node3D.new()
	shield.name = "Shield"
	shield.position = Vector3(0, 0, 0)
	shield.rotation_degrees.x = -18.0     # lean it back so you see into the curve
	shield.position = Vector3(0, 8.0, 0)  # lift it clear of the floor
	add_child(shield)

	# everything for the shield hangs off this, so i can clear it out or
	# measure it in one place. it is not tipped any more, the slats stand
	# up on their own
	var face = Node3D.new()
	face.name = "Face"
	shield.add_child(face)

	# ---- the buckler ----
	# this is the third go at making it curved, so here is what the first
	# two got wrong: i kept building a flat disc and standing it on edge,
	# and from a camera that looks down at the arena you cannot tell a
	# disc from a circle whether it is curved or not. it just looked like
	# a ring lying around the player.
	# this one is a wall of slats on an arc, so it wraps around you. from
	# above it is a crescent, which is a shape your eye knows is curved
	# without having to be told
	var arc = 1.9           # total spread, in radians. a bit wider than the parry
	var radius = 34.0
	var slats = 9
	var slat_h = 26.0

	var si = 0
	while si < slats:
		# -half .. +half across the arc, with 0 being dead ahead
		var f = float(si) / float(slats - 1)
		var a = -arc / 2.0 + arc * f

		# a holder node turned to this angle, so i can place the slat
		# straight ahead of it and let the rotation do the curving
		var holder = Node3D.new()
		holder.rotation.y = a
		face.add_child(holder)

		# taller in the middle, shorter at the ends, which makes the wall
		# look like it is leaning around you
		var tall = slat_h - abs(a) * 5.0
		var slat = MeshInstance3D.new()
		var slab = BoxMesh.new()
		slab.size = Vector3(10.5, tall, 3.5)
		slat.mesh = slab
		slat.material_override = glow_material(Color("#4df0ff"), 2.2)
		slat.position = Vector3(0, tall / 2.0, -radius)
		holder.add_child(slat)

		# a brighter cap on every other slat, so the top edge reads
		if si % 2 == 0:
			var cap = MeshInstance3D.new()
			var capm = BoxMesh.new()
			capm.size = Vector3(11.0, 2.4, 4.2)
			cap.mesh = capm
			cap.material_override = glow_material(Color("#bff8ff"), 3.0)
			cap.position = Vector3(0, tall - 1.0, -radius)
			holder.add_child(cap)

		# a little rib across the middle of each slat
		var rib = MeshInstance3D.new()
		var ribm = BoxMesh.new()
		ribm.size = Vector3(11.0, 2.0, 4.4)
		rib.mesh = ribm
		rib.material_override = glow_material(Color("#bff8ff"), 1.6)
		rib.position = Vector3(0, tall * 0.45, -radius)
		holder.add_child(rib)

		si = si + 1

	# the keel down the middle of the wall, which is where a buckler would
	# have its boss. it sits proud of the slats so it catches the light
	var keel = MeshInstance3D.new()
	var keelm = BoxMesh.new()
	keelm.size = Vector3(3.5, 28.0, 5.0)
	keel.mesh = keelm
	keel.material_override = glow_material(Color("#ffffff"), 3.0)
	keel.position = Vector3(0, 14.0, -radius - 1.5)
	face.add_child(keel)

	# one material i can brighten while a parry is up
	shield_mat = glow_material(Color("#4df0ff"), 2.2)

	shield.visible = false


func glow_material(colour, power):
	var mat = StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = power
	return mat


# ------------------------------------------------------------
#  called by the mouse: shoot the shield up
# ------------------------------------------------------------
func try_parry():
	if cooldown <= 0.0:
		parry_time = parry_length
		cooldown = parry_cooldown


func step(dt, game):
	# --- walking ---
	var ix = 0.0
	var iy = 0.0
	if Input.is_action_pressed("move_left"):
		ix = ix - 1.0
	if Input.is_action_pressed("move_right"):
		ix = ix + 1.0
	if Input.is_action_pressed("move_up"):
		iy = iy - 1.0
	if Input.is_action_pressed("move_down"):
		iy = iy + 1.0
	var len = sqrt(ix * ix + iy * iy)
	if len > 0.0:
		ix = ix / len
		iy = iy / len

	vx = lerp(vx, ix * 265.0, min(1.0, dt * 18.0))
	vy = lerp(vy, iy * 265.0, min(1.0, dt * 18.0))
	sx = sx + vx * dt
	sy = sy + vy * dt
	var half_w = game.W / 2.0
	var half_h = game.H / 2.0
	sx = clamp(sx, 26.0, game.W - 26.0)
	sy = clamp(sy, 26.0, game.H - 26.0)

	# the cover blocks are solid for me, so walk out of any i am in
	var pushed = game.push_out_of_cover(sx, sy, 13.0)
	sx = clamp(pushed.x, 26.0, game.W - 26.0)
	sy = clamp(pushed.y, 26.0, game.H - 26.0)

	# --- aiming at the floor point the mouse picked ---
	var dx = game.aim_point.x - (sx - 540.0)
	var dz = game.aim_point.z - (sy - 310.0)
	if abs(dx) + abs(dz) > 4.0:
		aim = atan2(dz, dx)

	# --- timers ---
	if parry_time > 0.0:
		parry_time = parry_time - dt
	if cooldown > 0.0:
		cooldown = cooldown - dt
	if inv > 0.0:
		inv = inv - dt


# ------------------------------------------------------------
#  move the meshes to match the numbers
# ------------------------------------------------------------
func place():
	position = Vector3(sx - 540.0, 0, sy - 310.0)

	# this is the one bit of maths in the whole game.
	# the aim angle points along (cos(aim), 0, sin(aim)) on the floor.
	# a mesh's "forward" is local -Z, and rotating by -(...) turns
	# local -Z onto that direction. it is aim + half a turn because
	# -Z already points backwards before we rotate anything
	rotation.y = -(aim + PI / 2.0)

	# ring: brighter when you can parry again
	var ready = 1.0 - clamp(cooldown / parry_cooldown, 0.0, 1.0)
	var ring_colour = Color("#4df0ff")
	ring_colour.a = 0.22 + 0.55 * ready
	ring_mat.albedo_color = ring_colour
	ring_mat.emission_energy_multiplier = 1.0 + 1.6 * ready

	# blink while invincible
	if inv > 0.0:
		var blink = int(inv * 22.0) % 2 == 0
		body.visible = not blink
	else:
		body.visible = true

	# the shield snaps out fast and shrinks away as the window closes.
	# it also spins while it is up, which just looks good
	var k = clamp(parry_time / parry_length, 0.0, 1.0)
	shield.visible = k > 0.0
	var pop = 0.60 + 0.60 * k
	shield.scale = Vector3.ONE * pop
	shield.rotation.z = (1.0 - k) * 0.10       # a little nudge as it fades
	shield_mat.emission_energy_multiplier = 2.0 + 4.0 * k
