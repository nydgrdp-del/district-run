extends Node

signal snapshot(data: Dictionary)
signal notice(message: String)
signal connected
signal disconnected

var socket := WebSocketPeer.new()
var active := false
var welcomed := false
var hello_sent := false
var endpoint := ""
var nickname := "Runner"
var player_id := ""
var last_packet := 0
var seq := 0
var config := ConfigFile.new()
var ping_ms := 0
var ping_clock := 0.0

func _ready() -> void:
	config.load("user://device.cfg")

func join(url: String, display_name: String) -> void:
	leave(false)
	endpoint = url.strip_edges()
	nickname = display_name.strip_edges()
	# Raw WS is limited to explicit development builds. Use WSS when shipping.
	if not endpoint.begins_with("wss://") and not (OS.is_debug_build() and endpoint.begins_with("ws://")):
		notice.emit("Use wss:// for a release build")
		return
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 262144
	var err := socket.connect_to_url(endpoint)
	if err != OK:
		notice.emit("Could not start connection: %s" % err)
		return
	active = true
	last_packet = Time.get_ticks_msec()
	notice.emit("Connecting to district…")

func leave(emit_event: bool = true) -> void:
	if active:
		socket.close()
	active = false
	welcomed = false
	hello_sent = false
	seq = 0
	if emit_event:
		disconnected.emit()

func send(data: Dictionary) -> void:
	if active and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(data))

func act(kind: String, target: String = "") -> void:
	var request := Crypto.new().generate_random_bytes(16).hex_encode()
	send({"type":"action", "request":request, "kind":kind, "target":target})

func movement(direction: Vector2, yaw: float, sprint: bool) -> void:
	seq += 1
	send({"type":"input", "seq":seq, "x":direction.x, "z":direction.y, "yaw":yaw, "sprint":sprint})

func _process(delta: float) -> void:
	if not active:
		return
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not hello_sent:
			hello_sent = true
			send({"type":"hello", "protocol":1, "name":nickname,
				"token":config.get_value("keys", endpoint.sha256_text(), "")})
		while socket.get_available_packet_count() > 0:
			last_packet = Time.get_ticks_msec()
			var value: Variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if not value is Dictionary:
				continue
			match value.get("type", ""):
				"welcome":
					player_id = value.id
					config.set_value("keys", endpoint.sha256_text(), value.token)
					config.set_value("connection", "url", endpoint)
					config.set_value("connection", "name", nickname)
					if config.save("user://device.cfg") != OK:
						notice.emit("Device key could not be saved; progress recovery is at risk")
					welcomed = true
					connected.emit()
				"snapshot":
					snapshot.emit(value)
				"result", "error":
					notice.emit(str(value.get("message", "")))
				"pong":
					ping_ms = Time.get_ticks_msec() - int(value.get("stamp", Time.get_ticks_msec()))
		ping_clock += delta
		if ping_clock > 2.0:
			ping_clock = 0
			send({"type":"ping", "stamp":Time.get_ticks_msec()})
	elif state == WebSocketPeer.STATE_CLOSED:
		leave()
		notice.emit("Disconnected. Your server-saved progress is retained.")
	if active and Time.get_ticks_msec()-last_packet > 10000:
		leave()
		notice.emit("Connection timed out. Check the server address and network.")
