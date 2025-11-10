@tool
class_name Portal extends Area3D

@export var cull_layer = 20
@export var link: Portal
@export var portal_area_margin = Vector3(0.1, 0.1, 1.0) :
	set(val):
		portal_area_margin = val
		update_portal_area_size(portal_area_margin, size)
	get:
		return portal_area_margin
@export var size = Vector3(0.1, 0.1, 1.0) :
	set(val):
		size = val
		update_portal_area_size(portal_area_margin, size)
	get:
		return size

var visual: CSGBox3D:
	set(v):
		visual = v
		update_portal_area_size(portal_area_margin, size)
		visual.set_layer_mask_value(1, false)
		visual.set_layer_mask_value(cull_layer, true)
		update_configuration_warnings()
var subviewport: SubViewport:
	set(v):
		subviewport = v
		update_configuration_warnings()
var collision_shape: CollisionShape3D:
	set(v):
		collision_shape = v
		update_configuration_warnings()

class TrackedBody:
	var body: PhysicsBody3D
	var prev_position

var tracked_bodies: Array[TrackedBody]

func _get_configuration_warnings() -> PackedStringArray:
	var warnings = PackedStringArray()

	if visual == null:
		warnings.push("No CSGBox3D child.")

	if subviewport == null:
		warnings.push_back("No SubViewport child")
	else:
		var found = false
		for c in subviewport.get_children():
			if c is Camera3D:
				found = true
				break
		if found == false:
			warnings.push_back("SubViewport does not have a Camera3D child")

	return warnings


# Called when the node enters the scene tree for the first time.
# func _ready() -> void:
# 	subviewport = SubViewport.new()
# 	camera = Camera3D.new()
# 	visual = CSGBox3D.new()

# 	update_portal_area_size(portal_area_margin, size)

# 	visual.set_layer_mask_value(1, false)
# 	visual.set_layer_mask_value(cull_layer, true)
# 	camera.set_cull_mask_value(link.cull_layer, false)

# 	subviewport.add_child(camera)
# 	add_child(visual)
# 	add_child(subviewport)

# 	var mat = ShaderMaterial.new()
# 	mat.shader = load("res://portal.gdshader")
	# mat.set_shader_parameter("albedo", subviewport.get_texture())
	# visual.material = mat

func _ready() -> void:
	update_portal_area_size(portal_area_margin, size)

func _enter_tree() -> void:
	child_entered_tree.connect(on_child_entered_tree)
	child_exiting_tree.connect(on_child_exiting_tree)
	body_entered.connect(on_body_entered)
	body_exited.connect(on_body_exited)

func _process(delta: float) -> void:
	do_update()

func _physics_process(delta: float) -> void:
	do_update()

func do_update():
	update_pos()
	auto_thick()
	try_teleport()

func auto_thick():
	var portal_camera = get_portal_camera()
	if not portal_camera:
		return

	var halfHeight = portal_camera.near * tan(deg_to_rad(0.5 * portal_camera.fov))
	var halfWidth = halfHeight * (subviewport.size.x/subviewport.size.y)
	var dstToNearClipPlaneCorner = Vector3(halfWidth, halfHeight, portal_camera.near).length()

	var transform = visual.transform
	var cam_portal_same_dir = -transform.basis.z.dot(transform.origin - portal_camera.transform.origin) > 0
	visual.size = Vector3(visual.size.x, visual.size.y, dstToNearClipPlaneCorner)
	visual.position = Vector3.FORWARD * dstToNearClipPlaneCorner * (0.5 if cam_portal_same_dir else -0.5)

func update_pos():
	var cur_camera = get_viewport().get_camera_3d()
	if not cur_camera:
		return
	if not link:
		return
	var portal_camera = get_portal_camera()
	if not portal_camera:
		return

	var rel_pos_link = link.global_transform * self.global_transform.affine_inverse() * cur_camera.global_transform

	portal_camera.global_transform = rel_pos_link
	portal_camera.fov = cur_camera.fov
	portal_camera.cull_mask = cur_camera.cull_mask
	portal_camera.set_cull_mask_value(link.cull_layer, false)

	subviewport.size = get_viewport().get_visible_rect().size

func update_portal_area_size(portal_area_margin, size):
	if not visual:
		return

	visual.size.x = size.x
	visual.size.y = size.y

	if not collision_shape:
		return

	collision_shape.shape.size = Vector3(
		size.x + portal_area_margin.x * 2,
		size.y + portal_area_margin.y * 2,
		portal_area_margin.z * 2)

func get_portal_camera() -> Camera3D:
	if subviewport == null:
		return null
	else:
		for c in subviewport.get_children():
			if c is Camera3D:
				return c
		return null

func try_teleport():
	var passed_bodies = []
	for tb in tracked_bodies:
		var forward = self.global_transform.basis.z
		var offset_from_portal = tb.body.global_position - self.global_position
		var prev_offset_from_portal = tb.prev_position - self.global_position
		var side = _nonzero_sign(offset_from_portal.dot(forward))
		var prev_side = _nonzero_sign(prev_offset_from_portal.dot(forward))
		if side != prev_side:
			passed_bodies.push_back(tb.body)
		tb.prev_position = tb.body.global_position

	for b in passed_bodies:
		teleport(b)

func teleport(body: PhysicsBody3D):
	if not link:
		return

	print("moved to other portal")

	var transform_rel_to_this_portal = self.global_transform.affine_inverse() * body.global_transform
	var moved_to_link = link.global_transform * transform_rel_to_this_portal
	body.global_transform = moved_to_link

	var r = link.global_transform.basis.get_euler() - global_transform.basis.get_euler()
	body.velocity = body.velocity \
		.rotated(Vector3(1, 0, 0), r.x) \
		.rotated(Vector3(0, 1, 0), r.y) \
		.rotated(Vector3(0, 0, 1), r.z)

	remove_tracked_body(body)
	link.add_tracked_body(body)

func get_tracked_body_entry(b: PhysicsBody3D):
	for tb in tracked_bodies:
		if tb.body == b:
			return tb
	return null

func add_tracked_body(b: PhysicsBody3D):
	var entry = get_tracked_body_entry(b)
	if entry != null:
		return

	var tb = TrackedBody.new()
	tb.body = b
	tb.prev_position = b.global_position
	tracked_bodies.push_back(tb)

func remove_tracked_body(b: PhysicsBody3D):
	for i in len(tracked_bodies):
		if tracked_bodies[i].body == b:
			tracked_bodies.remove_at(i)

func on_child_entered_tree(n: Node) -> void:
	if visual == null && n is CSGBox3D:
		visual = n
	elif subviewport == null && n is SubViewport:
		subviewport = n
	elif collision_shape == null && n is CollisionShape3D:
		collision_shape = n

func on_child_exiting_tree(n: Node) -> void:
	if visual != null && n is CSGBox3D:
		visual = null
	elif visual != null && n is SubViewport:
		subviewport = null
	elif collision_shape != null && n is CollisionShape3D:
		collision_shape = null

func on_body_entered(b: Node3D):
	if b is PhysicsBody3D:
		add_tracked_body(b)

func on_body_exited(b: Node3D):
	if b is PhysicsBody3D:
		remove_tracked_body(b)

func _nonzero_sign(value):
	var s = sign(value)
	if s == 0:
		s = 1
	return s
