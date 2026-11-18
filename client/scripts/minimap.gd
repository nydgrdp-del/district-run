extends Control
var player := Vector2.ZERO
var yaw := 0.0
var world_data := {}
var others: Array = []

func _draw() -> void:
	var center := size/2
	draw_style_box(_style(),Rect2(Vector2.ZERO,size))
	for b in world_data.get("buildings",[]):
		var at := center+(Vector2(b.x,b.z)-player)*1.1
		if Rect2(Vector2(9,9),size-Vector2(18,18)).has_point(at):
			draw_rect(Rect2(at-Vector2(6,5),Vector2(12,10)),Color("557775"))
	for s in world_data.get("stations",[]):
		var at := center+(Vector2(s.x,s.z)-player)*1.1
		if Rect2(Vector2(7,7),size-Vector2(14,14)).has_point(at):
			draw_circle(at,4,Color("f2c15f"))
	for p in others:
		var at := center+(Vector2(p.x,p.z)-player)*1.1
		if Rect2(Vector2(7,7),size-Vector2(14,14)).has_point(at):
			draw_circle(at,3,Color("ef805e") if p.masked else Color("8eb8ed"))
	var forward := Vector2(-sin(yaw),-cos(yaw))
	var side := Vector2(forward.y,-forward.x)
	draw_colored_polygon(PackedVector2Array([center+forward*10,center-forward*6+side*6,center-forward*6-side*6]),Color("6cf2d3"))

func _style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color=Color(.025,.09,.10,.91)
	s.border_color=Color(.3,.6,.56,.6)
	s.set_border_width_all(1)
	s.set_corner_radius_all(16)
	return s
