extends RefCounted

const ITEMS := ["Gold ring","Ruby","Sapphire"]
const VALUES := [180,320,450]
const SAVE := "user://jewelry.cfg"
var bag: Array = []
var trunks: Dictionary = {}
var taken: Dictionary = {}
var cash := 0
var solo := false
var displays: Dictionary = {}

func load_progress() -> void:
	var save:=ConfigFile.new()
	if save.load(SAVE)==OK:
		bag=save.get_value("inventory","bag",[])
		trunks=save.get_value("inventory","cars",{})
		taken=save.get_value("inventory","taken",{})
		cash=save.get_value("inventory","cash",0)

func save_progress() -> void:
	var save:=ConfigFile.new()
	for entry in [["bag",bag],["cars",trunks],["taken",taken],["cash",cash]]:
		save.set_value("inventory",entry[0],entry[1])
	save.save(SAVE)

func add_shop(world: Node, shop: Node3D, id: String) -> void:
	var stand:=StandardMaterial3D.new()
	stand.albedo_color=Color("263035")
	world.label_at(shop,"JEWELRY",Vector3(0,2.7,5.6),Color("ffe09a"))
	for i in 3:
		var key:="%s/%d" % [id,i]
		var base:=Vector3(-2.8+i*2.8,0,1.4)
		world.mesh_box(shop,base+Vector3.UP*.46,Vector3(.95,.92,.82),stand)
		var piece:=MeshInstance3D.new()
		if i==0:
			var ring:=TorusMesh.new()
			ring.inner_radius=.13
			ring.outer_radius=.22
			piece.mesh=ring
			piece.rotation.x=.85
		else:
			var gem:=CylinderMesh.new()
			gem.radial_segments=8
			gem.top_radius=.13
			gem.bottom_radius=.23
			gem.height=.30
			piece.mesh=gem
		var mat:=StandardMaterial3D.new()
		mat.albedo_color=[Color("ffc341"),Color("d82559"),Color("236deb")][i]
		mat.metallic=.55
		mat.roughness=.18
		piece.material_override=mat
		shop.add_child(piece)
		piece.position=base+Vector3.UP*1.12
		piece.visible=solo and not taken.has(key)
		displays[key]=piece
		piece.tree_exiting.connect(func(): if displays.get(key)==piece: displays.erase(key))

func refresh() -> void:
	for key in displays:
		displays[key].visible=solo and not taken.has(key)

func context(pos: Vector3,world: Node) -> Dictionary:
	var nearest:=""
	var distance:=1.8
	for key in displays:
		var piece: Node3D=displays[key]
		if not piece.visible:
			continue
		var at:=piece.global_position
		var d:=Vector2(pos.x-at.x,pos.z-at.z).length()
		if d<distance:
			nearest=key
			distance=d
	if nearest!="":
		var i:=nearest.get_slice("/",1).to_int()
		return {"kind":"take","key":nearest,"item":i,"text":"TAKE "+ITEMS[i] if bag.size()<4 else "BAG FULL"}
	if not bag.is_empty() and pos.distance_to(world.stations.fence.position)<3:
		return {"kind":"sell","text":"SELL JEWELRY"}
	for id in world.vehicles:
		var car: Node3D=world.vehicles[id]
		if pos.distance_to(car.to_global(Vector3(0,0,2.9)))>1.6:
			continue
		var cargo: Array=trunks.get(id,[])
		if not bag.is_empty() and cargo.size()<12:
			return {"kind":"store","key":id,"text":"STORE IN TRUNK"}
		if not cargo.is_empty() and bag.size()<4:
			return {"kind":"unload","key":id,"text":"UNLOAD TRUNK"}
		return {"kind":"","text":"TRUNK %d/12" % cargo.size()}
	return {}

func interact(action: Dictionary) -> void:
	match action.get("kind",""):
		"take":
			if bag.size()>=4 or taken.has(action.key):
				return
			taken[action.key]=true
			bag.append(action.item)
			displays[action.key].hide()
		"store","unload":
			var cargo: Array=trunks.get(action.key,[])
			if action.kind=="store":
				while not bag.is_empty() and cargo.size()<12:
					cargo.append(bag.pop_back())
			else:
				while not cargo.is_empty() and bag.size()<4:
					bag.append(cargo.pop_back())
			trunks[action.key]=cargo
		"sell":
			for item in bag:
				cash+=VALUES[item]
			bag.clear()
		_:
			return
	save_progress()
