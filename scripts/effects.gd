extends Node3D
# ============================================================
#  all the little bits: sparks when something explodes, rings
#  that spread out, and the floating "+100" text.
#  game.gd just says fx.burst(x, y, colour, 12) and forgets.
# ============================================================

var sparks = []     # list of little boxes flying around
var rings = []      # list of expanding rings
var labels = []     # list of floating text


# ------------------------------------------------------------
#  a small explosion
# ------------------------------------------------------------
func burst(sx, sy, colour, amount):
	var i = 0
	while i < amount:
		var spark = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(4, 4, 4)
		spark.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = colour
		mat.emission_enabled = true
		mat.emission = colour
		mat.emission_energy_multiplier = 3.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		spark.material_override = mat
		add_child(spark)

		# random direction, random speed
		var ang = randf_range(0, TAU)
		var spd = randf_range(120.0, 340.0)
		sparks.append({
			"node": spark,
			"x": sx - 540.0,
			"z": sy - 310.0,
			"y": 14.0,
			"vx": cos(ang) * spd,
			"vy": randf_range(40.0, 180.0),
			"vz": sin(ang) * spd,
			"life": randf_range(0.3, 0.7),
			"age": 0.0,
			"mat": mat,
		})
		i = i + 1


# ------------------------------------------------------------
#  a ring that spreads out on the floor
# ------------------------------------------------------------
func ring(sx, sy, colour, size):
	var node = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 4
	node.mesh = torus
	var mat = StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	node.material_override = mat
	node.position = Vector3(sx - 540.0, 2.0, sy - 310.0)
	add_child(node)
	rings.append({ "node": node, "mat": mat, "size": size, "life": 0.45, "age": 0.0 })


# ------------------------------------------------------------
#  floating text like "+100" or "PERFECT"
# ------------------------------------------------------------
func text(sx, sy, words, colour, size):
	var label = Label3D.new()
	label.text = words
	label.font_size = size
	label.modulate = colour
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 10
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.pixel_size = 0.0018
	label.position = Vector3(sx - 540.0, 46.0, sy - 310.0)
	add_child(label)
	labels.append({ "node": label, "life": 1.0, "age": 0.0 })


# ------------------------------------------------------------
#  move everything, and clean up what has finished
# ------------------------------------------------------------
func _process(delta):
	var dt = min(delta, 0.05)

	for i in range(sparks.size() - 1, -1, -1):
		var s = sparks[i]
		s["age"] = s["age"] + dt
		if s["age"] >= s["life"]:
			s["node"].queue_free()
			sparks.remove_at(i)
			continue
		s["x"] = s["x"] + s["vx"] * dt
		s["y"] = s["y"] + s["vy"] * dt
		s["z"] = s["z"] + s["vz"] * dt
		s["vy"] = s["vy"] - 260.0 * dt
		s["vx"] = s["vx"] * (1.0 - 2.2 * dt)
		s["vz"] = s["vz"] * (1.0 - 2.2 * dt)
		if s["y"] < 2.0:
			s["y"] = 2.0
			s["vy"] = abs(s["vy"]) * 0.35
		s["node"].position = Vector3(s["x"], s["y"], s["z"])
		var fade = 1.0 - s["age"] / s["life"]
		s["mat"].albedo_color.a = fade
		s["mat"].emission_energy_multiplier = 3.0 * fade

	for i in range(rings.size() - 1, -1, -1):
		var r = rings[i]
		r["age"] = r["age"] + dt
		if r["age"] >= r["life"]:
			r["node"].queue_free()
			rings.remove_at(i)
			continue
		var k = r["age"] / r["life"]
		r["node"].scale = Vector3.ONE * max(0.01, r["size"] * k)
		r["mat"].albedo_color.a = (1.0 - k) * 0.9
		r["mat"].emission_energy_multiplier = 3.0 * (1.0 - k)

	for i in range(labels.size() - 1, -1, -1):
		var l = labels[i]
		l["age"] = l["age"] + dt
		if l["age"] >= l["life"]:
			l["node"].queue_free()
			labels.remove_at(i)
			continue
		l["node"].position.y = l["node"].position.y + 40.0 * dt
		l["node"].modulate.a = 1.0 - l["age"] / l["life"]
