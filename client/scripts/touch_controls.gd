extends Control

signal look_changed(delta: Vector2)
signal loot_pressed
var loot_caption := ""
var bag_caption := ""
const LOOT_RECT := Rect2(920,565,315,70)
signal vehicle_pressed
var vehicle_caption := ""
const CAR_RECT := Rect2(995,480,235,70)
var move := Vector2.ZERO
var stick_id := -1
var look_id := -1
var origin := Vector2(160,570)
var finger := Vector2(160,570)
var enabled := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _input(event: InputEvent) -> void:
	if not enabled:
		return
	var scale_factor := get_viewport().get_visible_rect().size / Vector2(1280,720)
	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position / scale_factor
		if event.pressed and not event.canceled:
			if not loot_caption.is_empty() and LOOT_RECT.has_point(pos):
				loot_pressed.emit()
				get_viewport().set_input_as_handled()
				return
			if not vehicle_caption.is_empty() and CAR_RECT.has_point(pos):
				vehicle_pressed.emit()
				get_viewport().set_input_as_handled()
				return
			if pos.x < 360 and pos.y > 380 and pos.y < 655 and stick_id < 0:
				stick_id = event.index
				origin = pos
				finger = pos
			elif pos.x > 450 and pos.y > 120 and pos.y < 480 and look_id < 0:
				look_id = event.index
		else:
			if event.index == stick_id:
				stick_id = -1
				move = Vector2.ZERO
			if event.index == look_id:
				look_id = -1
	elif event is InputEventScreenDrag:
		if event.index == stick_id:
			finger = event.position / scale_factor
			var offset := ((finger-origin)/65).limit_length()
			var strength := clampf((offset.length()-.12)/.88, 0, 1)
			move = offset.normalized()*strength
		elif event.index == look_id:
			look_changed.emit(event.relative / scale_factor)
	queue_redraw()

func _draw() -> void:
	if not enabled:
		return
	if not bag_caption.is_empty():
		draw_rect(Rect2(690,95,544,38),Color(.04,.12,.14,.9))
		draw_string(ThemeDB.fallback_font,Vector2(700,122),bag_caption,HORIZONTAL_ALIGNMENT_LEFT,-1,22)
	if not loot_caption.is_empty():
		draw_rect(LOOT_RECT,Color(.22,.15,.05,.96))
		draw_string(ThemeDB.fallback_font,LOOT_RECT.position+Vector2(0,44),loot_caption,HORIZONTAL_ALIGNMENT_CENTER,LOOT_RECT.size.x,24,Color.WHITE)
	if not vehicle_caption.is_empty():
		draw_rect(CAR_RECT,Color(.04,.16,.18,.94))
		draw_rect(CAR_RECT,Color(.55,.92,.82),false,3)
		draw_string(ThemeDB.fallback_font,CAR_RECT.position+Vector2(0,44),vehicle_caption,HORIZONTAL_ALIGNMENT_CENTER,CAR_RECT.size.x,24,Color.WHITE)
	var center := origin if stick_id >= 0 else Vector2(160,570)
	draw_circle(center,72,Color(0.04,.12,.16,.32))
	draw_arc(center,72,0,TAU,64,Color(.7,.88,.85,.5),2,true)
	draw_circle(center+move*55,28,Color(.45,.83,.76,.68))

func reset() -> void:
	move = Vector2.ZERO
	stick_id = -1
	look_id = -1
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset()
