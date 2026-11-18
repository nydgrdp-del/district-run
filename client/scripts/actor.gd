extends Node3D

var target := Vector3.ZERO
var yaw := 0.0
var moving := 0.0
var gait := 0.0
var parts := {}
var name_label: Label3D
var face_cover := MeshInstance3D.new()
var model: Node3D

func setup(scene: PackedScene, player_name: String) -> void:
	model = scene.instantiate()
	add_child(model)
	var fabric := StandardMaterial3D.new()
	fabric.albedo_color = Color("25343c")
	fabric.roughness = 1.0
	var cover := SphereMesh.new()
	cover.radius = .178
	cover.height = .20
	face_cover.mesh = cover
	face_cover.material_override = fabric
	face_cover.position = Vector3(0,1.69,-.026)
	face_cover.visible = false
	model.add_child(face_cover)
	for key in ["ArmL","ArmR","LegL","LegR"]:
		var part := model.find_child(key,true,false)
		if part:
			parts[key] = part
	name_label = Label3D.new()
	name_label.text = player_name
	name_label.position.y = 2.35
	name_label.font_size = 28
	name_label.pixel_size = .009
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(name_label)

func state(data: Dictionary) -> void:
	face_cover.visible = data.masked
	target = Vector3(data.x,0,data.z)
	yaw = float(data.yaw)
	moving = absf(float(data.speed))
	visible = str(data.vehicle).is_empty()
	name_label.modulate = Color("65b8ef") if data.role == "police" else (Color("ef9067") if data.masked else Color.WHITE)

func _process(delta: float) -> void:
	if position.distance_to(target)>8:
		position = target
	else:
		position = position.lerp(target,minf(1,delta*16))
	rotation.y = lerp_angle(rotation.y,yaw,minf(1,delta*12))
	gait += delta * maxf(0,moving) * 2.6
	var swing := sin(gait)*minf(moving/6,.8)
	for key in parts:
		var direction := 1.0 if key in ["ArmL","LegR"] else -1.0
		parts[key].rotation.x = swing*direction
