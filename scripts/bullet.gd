extends Node3D
# ============================================================

const GlowDisc = preload("res://scripts/glow_disc.gd")

# ============================================================
#  a bullet. it starts red (dangerous, coming at you) and turns
#  cyan the moment you parry it (mine now, going home).
#  step() returns false when the bullet should be deleted.
# ============================================================

var sx = 0.0
var sy = 0.0
var vx = 0.0
var vy = 0.0
var radius = 6.0
var mine = false       # true = i parried it, it is coming for you now
var pierce = 1         # how many enemies it can go through
var life = 6.0     # seconds. 6s at 260 units/s is further than the arena is long
var src = null         # the enemy that fired it

var mesh = null
var mat = null
var glow_hit = null


func _ready():
	# the bullet is a small stretched capsule with a ball inside it, so
	# it reads as something moving fast rather than a floating dot
	mesh = MeshInstance3D.new()
	var capsule = CapsuleMesh.new()
	capsule.radius = 4.5
	capsule.height = 16.0
	capsule.radial_segments = 8
	capsule.rings = 3
	mesh.mesh = capsule
	mat = StandardMaterial3D.new()
	mat.emission_enabled = true
	mesh.material_override = mat
	add_child(mesh)

	# the body is bigger than it used to be. at the camera distance a
	# small bullet was nearly invisible, and the bullet colour is the
	# whole warning system: red means it is coming for you
	capsule.radius = 6.0
	capsule.height = 22.0

	# a soft glow so it stands out against the dark floor
	glow_hit = GlowDisc.new()
	glow_hit.colour = Color("#ff5a6e")
	glow_hit.size = 34.0
	glow_hit.strength = 0.45
	add_child(glow_hit)

	paint()


func paint():
	var colour = Color("#ff5a6e")
	if mine:
		colour = Color("#4df0ff")
	mat.albedo_color = colour
	mat.emission = colour
	# 3.2 was so bright it clipped to pure white on screen. the colour of
	# the bullet is how you know whether it is coming for you or going
	# away, so it has to stay red and cyan
	mat.emission_energy_multiplier = 1.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if mine:
		mesh.scale = Vector3.ONE * 1.35
	else:
		mesh.scale = Vector3.ONE

	# and the glow follows the body colour, or a parried shot would keep
	# a red halo and still look dangerous
	if glow_hit != null:
		glow_hit.set_colour(colour)


# returns false when the bullet is finished
func step(dt, game):
	life = life - dt

	if mine:
		# a parried bullet chases the closest enemy
		var target = null
		var best = 999999.0
		for e in game.enemies:
			var dx = e.sx - sx
			var dy = e.sy - sy
			var d = sqrt(dx * dx + dy * dy)
			# prefer the one that fired it
			if e == src:
				d = d * 0.45
			if d < best:
				best = d
				target = e
		if target != null:
			var current = atan2(vy, vx)
			var want = atan2(target.sy - sy, target.sx - sx)
			var turn = clamp(angle_difference(current, want), -2.4 * dt, 2.4 * dt)
			var speed = sqrt(vx * vx + vy * vy)
			vx = cos(current + turn) * speed
			vy = sin(current + turn) * speed

	sx = sx + vx * dt
	sy = sy + vy * dt

	if life <= 0.0:
		return false
	# the margins are 30 units past the walls. these numbers have to
	# follow the arena size, they were still set for the old smaller one
	# and bullets were disappearing in mid air
	if sx < -30.0 or sx > game.W + 30.0 or sy < -30.0 or sy > game.H + 30.0:
		return false
	return true


func place():
	position = Vector3(sx - 540.0, 14.0, sy - 310.0)
	# point the dart along its own velocity
	if abs(vx) + abs(vy) > 1.0:
		rotation.y = -atan2(vy, vx) - PI / 2.0
