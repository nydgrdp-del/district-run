extends Node3D

var data: Dictionary
var chunks := {}
var models := {}
var vehicles := {}
var pickups := {}
var stations := {}
var last_chunk := Vector2i(9999,9999)
var home: Node3D
var road_material := StandardMaterial3D.new()
var sand_material := StandardMaterial3D.new()
var pavement_material := StandardMaterial3D.new()
var line_material := StandardMaterial3D.new()

func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	for key in ["shop","house","apartment","police","sedan","runner","palm","crate","terminal"]:
		models[key] = load("res://assets/%s.glb" % key)
	road_material.albedo_color = Color("343e40")
	sand_material.albedo_color = Color("bbae83")
	pavement_material.albedo_color = Color("a9a798")
	line_material.albedo_color = Color("d8cb89")
	for mat in [road_material,sand_material,pavement_material,line_material]:
		mat.roughness = .95
	mesh_box(self, Vector3(0,-.11,0), Vector3(data.extent*2+20,.2,data.extent*2+20), sand_material)
	for s in data.stations:
		var obj: Node3D = models.terminal.instantiate()
		obj.position = Vector3(s.x,0,s.z)
		add_child(obj)
		stations[s.id] = obj
		label_at(obj, str(s.title), Vector3(0,2.2,0), Color("69e5d0"))
	for v in data.vehicles:
		var car: Node3D = models.sedan.instantiate()
		car.position = Vector3(v.x,0,v.z)
		add_child(car)
		vehicles[v.id] = car
	for loot in data.loot:
		var crate: Node3D = models.crate.instantiate()
		crate.position = Vector3(loot.x,.05,loot.z)
		add_child(crate)
		pickups[loot.id] = crate
		label_at(crate, "LOOT", Vector3(0,1.5,0), Color("f6c25d"))
	update_chunks(Vector3.ZERO)

func mesh_box(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var obj := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	obj.mesh = mesh
	obj.material_override = mat
	obj.position = at
	parent.add_child(obj)
	return obj

func label_at(parent: Node3D, text: String, at: Vector3, tint: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = 40
	label.pixel_size = .009
	label.modulate = tint
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	parent.add_child(label)
	return label

func update_chunks(at: Vector3) -> void:
	var center := Vector2i(roundi(at.x/60),roundi(at.z/60))
	if center == last_chunk:
		return
	last_chunk = center
	var wanted := {}
	for x in range(center.x-1,center.x+2):
		for z in range(center.y-1,center.y+2):
			var key := Vector2i(x,z)
			wanted[key] = true
			if absi(x) <= 8 and absi(z) <= 8 and not chunks.has(key):
				build_chunk(key)
	for key in chunks.keys():
		if not wanted.has(key):
			chunks[key].queue_free()
			chunks.erase(key)

func build_chunk(key: Vector2i) -> void:
	var root := Node3D.new()
	root.name = "Chunk_%s_%s" % [key.x,key.y]
	add_child(root)
	chunks[key] = root
	var cx := key.x * 60.0
	var cz := key.y * 60.0
	mesh_box(root,Vector3(cx,.005,cz),Vector3(12,.02,60),road_material)
	mesh_box(root,Vector3(cx,.006,cz+20),Vector3(60,.02,10),road_material)
	if key.x == 0 or key.y == 0:
		for stripe in range(-4,5):
			mesh_box(root,Vector3(cx+stripe*1.1,.035,cz+13),Vector3(.52,.02,3),line_material)
	for side in [-1,1]:
		mesh_box(root,Vector3(cx+side*8,.06,cz-7.5),Vector3(4,.12,45),pavement_material)
		for j in range(3):
			var palm: Node3D = models.palm.instantiate()
			palm.position = Vector3(cx+side*7.5,0,cz-25+j*15)
			palm.rotation.y = j*1.7+key.x
			root.add_child(palm)
	for j in range(10):
		mesh_box(root,Vector3(cx,.025,cz-28+j*6),Vector3(.12,.02,2.8),line_material)
	for b in data.buildings:
		if roundi(float(b.x)/60) == key.x and roundi(float(b.z)/60) == key.y:
			var building: Node3D = models[b.style].instantiate()
			building.position = Vector3(b.x,0,b.z)
			root.add_child(building)
	# Shared authoritative wall rectangles also stop camera clipping on the client.
	for wall in data.obstacles:
		if roundi(float(wall[0])/60) == key.x and roundi(float(wall[1])/60) == key.y:
			var body := StaticBody3D.new()
			body.position = Vector3(wall[0],2,wall[1])
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(wall[2],4,wall[3])
			shape.shape = box
			body.add_child(shape)
			root.add_child(body)

func apply_snapshot(s: Dictionary) -> void:
	for v in s.vehicles:
		if vehicles.has(v.id):
			vehicles[v.id].set_meta("target",Vector3(v.x,0,v.z))
			vehicles[v.id].set_meta("yaw",float(v.yaw))
	for loot in s.loot:
		if pickups.has(loot.id):
			pickups[loot.id].visible = loot.ready
	var alive := {}
	for drop in s.drops:
		var key: String = "drop_"+drop.id
		alive[key] = true
		if not pickups.has(key):
			var node: Node3D = models.crate.instantiate()
			node.position = Vector3(drop.x,0,drop.z)
			add_child(node)
			pickups[key] = node
			label_at(node,"DROPPED BAG",Vector3(0,1.5,0),Color("ef8158"))
	for key in pickups.keys():
		if str(key).begins_with("drop_") and not alive.has(key):
			pickups[key].queue_free()
			pickups.erase(key)
	if s.you.house and not is_instance_valid(home):
		home = models.house.instantiate()
		home.position = Vector3(-18,0,43)
		home.rotation.y = PI
		add_child(home)
		label_at(home,"YOUR HOME",Vector3(0,7,0),Color("69e5d0"))
	elif not s.you.house and is_instance_valid(home):
		home.queue_free()
		home = null

func _process(delta: float) -> void:
	for car in vehicles.values():
		if car.has_meta("target"):
			car.position = car.position.lerp(car.get_meta("target"),minf(1,delta*15))
			car.rotation.y = lerp_angle(car.rotation.y,car.get_meta("yaw"),minf(1,delta*15))
