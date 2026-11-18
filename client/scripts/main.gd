extends Node3D

const Network = preload("res://scripts/network.gd")
const WorldView = preload("res://scripts/world_view.gd")
const Actor = preload("res://scripts/actor.gd")
const TouchControls = preload("res://scripts/touch_controls.gd")
const MiniMap = preload("res://scripts/minimap.gd")

var net: Node
var world: Node3D
var camera: Camera3D
var actors := {}
var you := {}
var latest := {}
var yaw := 0.0
var pitch := .23
var playing := false
var input_clock := 0.0
var step_clock := 0.0
var elapsed := 0.0
var preview_time := 0.0
var menu: Control
var hud: Control
var inventory: Panel
var touch: Control
var nickname: LineEdit
var address: LineEdit
var status: Label
var toast: Label
var stats: Label
var objective: Label
var location_label: Label
var ammo_label: Label
var interact_button: Button
var map: Control
var bag_grid: Control
var sprint_button: Button
var toast_until := 0.0
var nearest := {}
var screen_capture := ""
var capture_done := false
var capture_after := 5.0
var auto_url := ""
var smoke := false
var smoke_ok := false

func _ready() -> void:
	DisplayServer.window_set_title("District Run | Mobile development build 0.1")
	_setup_inputs()
	net = Network.new()
	add_child(net)
	net.snapshot.connect(_on_snapshot)
	net.notice.connect(_notice)
	net.connected.connect(_connected)
	net.disconnected.connect(_disconnected)
	_setup_environment()
	world = WorldView.new()
	add_child(world)
	camera = Camera3D.new()
	camera.fov = 64
	camera.far = 230
	camera.current = true
	add_child(camera)
	_make_ui()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--connect="):
			auto_url = arg.trim_prefix("--connect=")
		if arg.begins_with("--capture="):
			screen_capture = arg.trim_prefix("--capture=")
		if arg == "--smoke":
			smoke = true
	if not auto_url.is_empty():
		net.join(auto_url,"Build tester")

func _setup_inputs() -> void:
	var keys := {"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"sprint":KEY_SHIFT,
		"interact":KEY_E,"mask":KEY_M,"bag":KEY_TAB,"reload":KEY_R,"vehicle":KEY_F}
	for action in keys:
		InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = keys[action]
		InputMap.action_add_event(action,key)

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("408a9c")
	sky_mat.sky_horizon_color = Color("e3d6b1")
	sky_mat.ground_horizon_color = Color("dbcaa8")
	sky_mat.ground_bottom_color = Color("7e8877")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c4d9dc")
	env.ambient_light_energy = .65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var environment := WorldEnvironment.new()
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-44,-28,0)
	sun.light_color = Color("ffe0ac")
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 75
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)

func _style(color: Color, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	box.content_margin_left = 16
	box.content_margin_right = 16
	return box

func _panel(parent: Control, at: Vector2, dim: Vector2, color: Color) -> Panel:
	var p := Panel.new()
	p.position = at
	p.size = dim
	p.add_theme_stylebox_override("panel",_style(color,Color(.4,.65,.6,.24)))
	parent.add_child(p)
	return p

func _label(parent: Control, text: String, at: Vector2, dim: Vector2, font_size: int, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = dim
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Control, text: String, at: Vector2, dim: Vector2, fn: Callable, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.position = at
	b.size = dim
	b.add_theme_font_size_override("font_size",18)
	b.add_theme_color_override("font_color",Color("112e30") if accent else Color("e4efe9"))
	b.add_theme_stylebox_override("normal",_style(Color("e9b557") if accent else Color(.035,.12,.14,.88),Color(.38,.64,.6,.65)))
	b.add_theme_stylebox_override("hover",_style(Color("80c5ae"),Color("c2ecd5")))
	b.add_theme_stylebox_override("pressed",_style(Color("52a994"),Color("d6f3d3")))
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(fn)
	parent.add_child(b)
	return b

func _make_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	menu = Control.new()
	root.add_child(menu)
	var pane := _panel(menu,Vector2(36,36),Vector2(460,648),Color(.025,.075,.09,.95))
	_label(pane,"OPEN DISTRICT  /  DEVELOPMENT 0.1",Vector2(30,26),Vector2(400,30),15,Color("72cfbb"))
	_label(pane,"DISTRICT\nRUN",Vector2(26,68),Vector2(405,150),66,Color("f2e8ca"))
	_label(pane,"Build your name. Risk your haul.",Vector2(30,223),Vector2(400,32),21,Color("c0d3c8"))
	_label(pane,"PLAYER NAME",Vector2(30,285),Vector2(400,22),13,Color("85b6aa"))
	nickname = LineEdit.new()
	nickname.position=Vector2(30,315)
	nickname.size=Vector2(400,45)
	nickname.text=net.config.get_value("connection","name","Runner")
	nickname.max_length=20
	pane.add_child(nickname)
	_label(pane,"SERVER ADDRESS",Vector2(30,380),Vector2(400,22),13,Color("85b6aa"))
	address=LineEdit.new()
	address.position=Vector2(30,410)
	address.size=Vector2(400,45)
	address.text=net.config.get_value("connection","url","ws://127.0.0.1:8765")
	pane.add_child(address)
	_button(pane,"ENTER DISTRICT  →",Vector2(30,480),Vector2(400,54),func(): net.join(address.text,nickname.text),true)
	status = _label(pane,"Run the included server to play.\nAn early build, not the finished game.",Vector2(30,550),Vector2(400,80),15,Color("b4c6bc"))
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_label(menu,"LOOT  •  DRIVE  •  BUILD",Vector2(775,610),Vector2(450,40),24,Color("f5ebce"))
	_label(menu,"Original assets and world • Mobile-first controls",Vector2(775,653),Vector2(470,24),15,Color("ccdbce"))
	hud = Control.new()
	hud.visible=false
	root.add_child(hud)
	map=MiniMap.new()
	map.position=Vector2(24,24)
	map.size=Vector2(188,172)
	map.world_data=world.data
	hud.add_child(map)
	location_label=_label(hud,"SUNSET DISTRICT",Vector2(27,202),Vector2(500,32),16,Color("fff0c6"))
	var top := _panel(hud,Vector2(245,24),Vector2(720,64),Color(.025,.08,.09,.88))
	stats=_label(top,"",Vector2(18,12),Vector2(690,40),19)
	_button(hud,"BAG",Vector2(1090,24),Vector2(76,48),_toggle_bag)
	_button(hud,"EXIT",Vector2(1176,24),Vector2(80,48),func(): net.leave())
	var task := _panel(hud,Vector2(24,260),Vector2(330,94),Color(.025,.08,.09,.82))
	_label(task,"YOUR NEXT MOVE",Vector2(14,9),Vector2(310,22),12,Color("e8bb64"))
	objective=_label(task,"",Vector2(14,31),Vector2(303,56),17)
	objective.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	touch=TouchControls.new()
	root.add_child(touch)
	touch.look_changed.connect(func(delta: Vector2): yaw-=delta.x*.005; pitch=clampf(pitch+delta.y*.003,-.08,.9))
	sprint_button=_button(hud,"SPRINT",Vector2(74,664),Vector2(173,40),func(): pass)
	sprint_button.toggle_mode=true
	_button(hud,"MASK",Vector2(1006,652),Vector2(110,46),func(): net.act("mask"))
	_button(hud,"RELOAD",Vector2(1126,652),Vector2(130,46),func(): net.act("reload"))
	_button(hud,"FIRE",Vector2(1126,538),Vector2(130,100),func(): net.send({"type":"shoot"}),true)
	interact_button=_button(hud,"INTERACT",Vector2(912,566),Vector2(200,70),_interact)
	_button(hud,"CAR",Vector2(1006,508),Vector2(106,46),_vehicle)
	ammo_label=_label(hud,"",Vector2(1090,477),Vector2(180,30),19,Color("f5dfa0"))
	_label(hud,"+",Vector2(628,338),Vector2(30,38),28,Color(.95,.95,.85,.8))
	toast=_label(root,"",Vector2(360,644),Vector2(620,48),19,Color("ffdd97"))
	toast.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_color_override("font_shadow_color",Color.BLACK)
	toast.add_theme_constant_override("shadow_offset_x",2)
	toast.add_theme_constant_override("shadow_offset_y",2)
	inventory=_panel(root,Vector2(360,133),Vector2(560,464),Color(.02,.07,.085,.98))
	inventory.visible=false
	_label(inventory,"YOUR BAG  /  6 × 4",Vector2(24,20),Vector2(440,40),26,Color("f0d79b"))
	_button(inventory,"×",Vector2(488,18),Vector2(48,42),_toggle_bag)
	bag_grid=Control.new()
	bag_grid.position=Vector2(28,84)
	inventory.add_child(bag_grid)
	_label(inventory,"Stolen goods are lost on death while wanted.\nSell at the teal terminal near the market.",Vector2(28,370),Vector2(500,60),17,Color("b9ccc3"))

func _connected() -> void:
	playing=true
	menu.hide()
	hud.show()
	touch.enabled=true
	touch.queue_redraw()
	_notice("Connected. Explore the market on your left.")

func _disconnected() -> void:
	playing=false
	hud.hide()
	menu.show()
	inventory.hide()
	touch.enabled=false
	touch.reset()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	for actor in actors.values():
		actor.queue_free()
	actors.clear()
	you={}

func _notice(message: String) -> void:
	status.text=message
	toast.text=message
	toast_until=elapsed+4

func _on_snapshot(data: Dictionary) -> void:
	latest=data
	you=data.you
	var alive := {}
	var all: Array = data.players.duplicate()
	all.append(you)
	for p in all:
		alive[p.id]=true
		if not actors.has(p.id):
			var actor := Actor.new()
			add_child(actor)
			actor.setup(world.models.runner,p.name)
			actor.position=Vector3(p.x,0,p.z)
			actor.name_label.visible=p.id!=net.player_id
			actors[p.id]=actor
		actors[p.id].state(p)
	for id in actors.keys():
		if not alive.has(id):
			actors[id].queue_free()
			actors.erase(id)
	world.apply_snapshot(data)
	map.player=Vector2(you.x,you.z)
	map.yaw=yaw
	map.others=data.players
	map.queue_redraw()
	stats.text="HP %s     CASH $%s     BANK $%s     HEAT %s/5" % [you.hp,you.cash,you.bank,you.heat]
	ammo_label.text="%s / %s" % [you.ammo,you.reserve]
	location_label.text="SUNSET  •  %s ONLINE  •  %sms" % [data.population,net.ping_ms]
	if you.reloading:
		ammo_label.text="RELOADING…"
	if not you.bag.is_empty():
		objective.text="Bring your haul to SALES CENTER."
	elif int(you.cash)>0:
		objective.text="Turn dirty cash into bank funds at LAUNDRY."
	elif not you.laundry.is_empty():
		objective.text="Collect your clean funds when the timer finishes."
	elif you.heat:
		objective.text="Surrender at POLICE to clear your wanted status."
	elif not you.masked:
		objective.text="Enter NIGHT MARKET and equip your mask."
	else:
		objective.text="Approach a crate inside the market."
	if inventory.visible:
		_draw_bag()
	for event in data.get("events",[]):
		_shot(event)
	if smoke and not smoke_ok:
		smoke_ok=true
		print("CLIENT_SMOKE_OK authenticated snapshot: ",data.population," player(s)")

func _toggle_bag() -> void:
	inventory.visible=not inventory.visible
	touch.enabled=playing and not inventory.visible
	touch.reset()
	if inventory.visible:
		_draw_bag()

func _draw_bag() -> void:
	for child in bag_grid.get_children():
		child.queue_free()
	for y in range(4):
		for x in range(6):
			_panel(bag_grid,Vector2(x*82,y*66),Vector2(77,61),Color("1d3336"))
	for item in you.get("bag",[]):
		var card := _panel(bag_grid,Vector2(item.gx*82,item.gy*66),Vector2(item.w*82-5,item.h*66-5),Color("42685d"))
		var text := _label(card,"%s\n$%s" % [item.title,item.value],Vector2(7,4),card.size-Vector2(14,8),15,Color("ffdfa0"))
		text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func _find_nearest() -> void:
	nearest={}
	if you.is_empty():
		return
	if not str(you.vehicle).is_empty():
		nearest={"kind":"vehicle","id":"","title":"EXIT CAR"}
	else:
		var pos := Vector2(you.x,you.z)
		var distance := 3.0
		var options: Array = []
		for station in world.data.stations:
			var s: Dictionary=station.duplicate()
			if s.kind=="police" and you.heat:
				s.kind="surrender"
				s.title="SURRENDER"
			options.append(s)
		for loot in world.data.loot:
			if world.pickups[loot.id].visible:
				var l: Dictionary=loot.duplicate()
				l.kind="loot"
				l.title="TAKE LOOT"
				options.append(l)
		for drop in latest.get("drops",[]):
			var d: Dictionary=drop.duplicate()
			d.kind="pickup"
			d.title="TAKE BAG"
			options.append(d)
		for s in options:
			var dist := pos.distance_to(Vector2(s.x,s.z))
			if dist<distance:
				nearest=s
				distance=dist
	interact_button.text=str(nearest.get("title","INTERACT"))
	interact_button.disabled=nearest.is_empty()

func _interact() -> void:
	if not nearest.is_empty():
		net.act(nearest.kind,nearest.id)

func _vehicle() -> void:
	if you.is_empty():
		return
	if not str(you.vehicle).is_empty():
		net.act("vehicle")
		return
	for v in latest.get("vehicles",[]):
		if Vector2(v.x,v.z).distance_to(Vector2(you.x,you.z)) < 4:
			net.act("vehicle",v.id)
			return
	_notice("Move closer to a car")

func _unhandled_input(event: InputEvent) -> void:
	if not playing:
		return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		yaw-=event.relative.x*.004
		pitch=clampf(pitch+event.relative.y*.003,-.08,.9)
	if event.is_action_pressed("bag"):
		_toggle_bag()
	if inventory.visible:
		return
	if event.is_action_pressed("interact"):
		_interact()
	if event.is_action_pressed("mask"):
		net.act("mask")
	if event.is_action_pressed("reload"):
		net.act("reload")
	if event.is_action_pressed("vehicle"):
		_vehicle()
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		net.send({"type":"shoot"})

func _physics_process(delta: float) -> void:
	if not playing or you.is_empty():
		return
	input_clock+=delta
	if input_clock>=.05:
		input_clock=0
		var dir: Vector2 = Input.get_vector("left","right","forward","back") + touch.move
		if inventory.visible:
			dir=Vector2.ZERO
		dir=dir.limit_length()
		if str(you.vehicle).is_empty():
			var v := Vector3(dir.x,0,dir.y).rotated(Vector3.UP,yaw)
			dir=Vector2(v.x,v.z)
		net.movement(dir,yaw,Input.is_action_pressed("sprint") or sprint_button.button_pressed)
	_find_nearest()
	var actor: Node3D=actors.get(net.player_id)
	if actor:
		var target := actor.position+Vector3(0,1.5,0)
		if not str(you.vehicle).is_empty():
			target=Vector3(you.x,1.5,you.z)
		var offset := Vector3(.6,2.4+pitch*4,6.2).rotated(Vector3.UP,yaw)
		var desired := target+offset
		var query := PhysicsRayQueryParameters3D.create(target,desired)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			desired=hit.position+(target-hit.position).normalized()*.3
		camera.position=camera.position.lerp(desired,minf(1,delta*12))
		camera.look_at(target+Vector3(-sin(yaw),0,-cos(yaw))*2)
		world.update_chunks(actor.position)
	step_clock+=delta
	if step_clock>.38 and absf(float(you.speed))>.3 and str(you.vehicle).is_empty():
		step_clock=0
		_sound("step",Vector3(you.x,.1,you.z),-14)

func _process(delta: float) -> void:
	elapsed+=delta
	if elapsed>toast_until:
		toast.text=""
	if not playing:
		preview_time+=delta*.08
		camera.position=Vector3(-2+sin(preview_time)*5,8,23)
		camera.look_at(Vector3(-14,2,-6))
	if not screen_capture.is_empty() and not capture_done and elapsed>capture_after:
		capture_done=true
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(screen_capture)
			print("CAPTURE_SAVED ",screen_capture)
		get_tree().quit(0 if not smoke or smoke_ok else 1)
	if smoke and elapsed>6 and screen_capture.is_empty():
		get_tree().quit(0 if smoke_ok else 1)

func _sound(key: String, at: Vector3, volume: float) -> void:
	var path := "res://assets/%s.wav" % key
	if not ResourceLoader.exists(path):
		return
	var audio := AudioStreamPlayer3D.new()
	audio.stream=load(path)
	audio.position=at
	audio.volume_db=volume
	audio.max_distance=70
	add_child(audio)
	audio.finished.connect(audio.queue_free)
	audio.play()

func _shot(event: Dictionary) -> void:
	_sound("shot",Vector3(event.x,1.3,event.z),-6)
	var tracer := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color=Color("ffe0a0")
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,mat)
	var start := Vector3(event.x,1.3,event.z)
	mesh.surface_add_vertex(start)
	mesh.surface_add_vertex(start+Vector3(-sin(event.yaw),0,-cos(event.yaw))*24)
	mesh.surface_end()
	tracer.mesh=mesh
	add_child(tracer)
	get_tree().create_timer(.06).timeout.connect(tracer.queue_free)
