extends Node3D

enum GameState { READY, PLAYING, LOST, PAUSED }

const BALL_RADIUS := 0.18
const WALL_Z := -10.0
const HIT_PLANE_Z := 1.65
const FLOOR_Y := -1.55
const START_SPEED := 8.5
const MAX_SPEED := 14.0
const RETURN_ACCELERATION := 0.08

var state := GameState.READY
var score := 0
var best_score := 0
var rally_speed := START_SPEED
var ball_velocity := Vector3.ZERO
var spin := Vector3.ZERO
var last_ball_position := Vector3.ZERO
var touch_start := Vector2.ZERO
var touch_time_ms := 0
var missed := false
var buffered_strike_position := Vector2.ZERO
var buffered_strike_until_ms := 0

var ball: MeshInstance3D
var ball_shadow: Decal
var camera: Camera3D
var score_label: Label
var best_label: Label
var instruction_label: Label
var game_over_panel: Control
var final_score_label: Label
var reticle: Control
var impact_flash: OmniLight3D
var hand: Node3D
var wall_target: Node3D
var target_label: Label
var court_level := 1
var targets_hit := 0
var target_goal := 5
var target_position := Vector2(0.0, 1.0)
var ad_service: AdService
var play_games_service: PlayGamesService
var profile_button: Button
var leaderboard_button: Button

func _ready() -> void:
	best_score = int(_load_best())
	_build_background_plate()
	_build_environment()
	_build_target()
	_build_ball()
	_build_hand()
	_build_ui()
	_build_audio()
	play_games_service = PlayGamesService.new()
	add_child(play_games_service)
	play_games_service.authentication_changed.connect(_on_play_games_authentication_changed)
	play_games_service.leaderboard_unavailable.connect(_show_status_message)

	ad_service = AdService.new()
	add_child(ad_service)
	ad_service.interstitial_closed.connect(_restart_round)
	ad_service.initialize()
	_reset_ball(true)

func _physics_process(delta: float) -> void:
	if state != GameState.PLAYING:
		return
	last_ball_position = ball.position
	ball_velocity.y -= 0.85 * delta
	ball_velocity += spin.cross(ball_velocity.normalized()) * 0.025 * delta
	ball.position += ball_velocity * delta
	ball.rotate_x(ball_velocity.z * delta * 1.8)
	ball.rotate_y(-ball_velocity.x * delta * 1.8)
	_handle_wall_collision()
	_handle_side_bounds()
	_update_shadow()
	_update_reticle()
	_consume_buffered_strike()
	if ball.position.z > HIT_PLANE_Z + 0.65:
		_drop_ball()
	elif ball.position.y < FLOOR_Y - BALL_RADIUS:
		_drop_ball()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_start = event.position
			touch_time_ms = Time.get_ticks_msec()
			_try_strike(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_strike(event.position)
	elif event.is_action_pressed("pause"):
		_toggle_pause()

func _try_strike(screen_position: Vector2) -> void:
	if state == GameState.READY:
		state = GameState.PLAYING
		instruction_label.visible = false
		_launch_toward_wall(screen_position, 1.0)
		return
	if state == GameState.LOST or state == GameState.PAUSED:
		return
	var ball_screen := camera.unproject_position(ball.global_position)
	var apparent_radius := clampf(230.0 / maxf(0.8, absf(ball.position.z - camera.position.z)), 56.0, 180.0)
	var distance := screen_position.distance_to(ball_screen)
	var ball_is_returning := ball_velocity.z > 0.0
	var strike_zone := ball.position.z > -4.0
	var generous_contact := distance <= maxf(210.0, apparent_radius * 3.0)
	if ball_is_returning and strike_zone and generous_contact:
		var quality := clampf(1.0 - distance / maxf(260.0, apparent_radius * 3.0), 0.35, 1.0)
		_launch_toward_wall(screen_position, quality)
	else:
		buffered_strike_position = screen_position
		buffered_strike_until_ms = Time.get_ticks_msec() + 650

func _consume_buffered_strike() -> void:
	if buffered_strike_until_ms <= 0 or Time.get_ticks_msec() > buffered_strike_until_ms:
		buffered_strike_until_ms = 0
		return
	if ball_velocity.z > 0.0 and ball.position.z > -4.0:
		var screen_point := camera.unproject_position(ball.global_position)
		var distance := buffered_strike_position.distance_to(screen_point)
		if distance <= 280.0 or ball.position.z > -1.25:
			buffered_strike_until_ms = 0
			_launch_toward_wall(buffered_strike_position, 0.72)

func _launch_toward_wall(screen_position: Vector2, quality: float) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var ball_screen := camera.unproject_position(ball.global_position)
	var touch_offset := (screen_position - ball_screen) / 230.0
	rally_speed = minf(MAX_SPEED, START_SPEED + score * RETURN_ACCELERATION)
	var flight_time := maxf(0.8, (ball.position.z - WALL_Z) / rally_speed)
	var desired_x := clampf(target_position.x + touch_offset.x * 1.15, -3.5, 3.5)
	var desired_y := clampf(target_position.y - touch_offset.y * 1.0, -0.8, 2.8)
	ball_velocity = Vector3(
		(desired_x - ball.position.x) / flight_time,
		(desired_y - ball.position.y + 0.5 * 0.85 * flight_time * flight_time) / flight_time,
		-rally_speed
	)
	var aim_x := clampf(touch_offset.x, -1.0, 1.0)
	var aim_y := clampf(-touch_offset.y, -1.0, 1.0)
	spin = Vector3(-aim_y * 7.0, aim_x * 9.0, 0.0)
	missed = false
	_play_hand_animation(screen_position, quality)
	_play_impact(false, quality)
	_haptic(35 if quality > 0.72 else 22)

func _handle_wall_collision() -> void:
	if ball.position.z - BALL_RADIUS > WALL_Z:
		return
	ball.position.z = WALL_Z + BALL_RADIUS
	ball_velocity.z = absf(ball_velocity.z) * 0.78
	# Guide every return into a calm, reachable window near screen center.
	var return_time := maxf(0.8, (HIT_PLANE_Z - ball.position.z) / ball_velocity.z)
	var target_x := clampf(ball.position.x * 0.18, -0.75, 0.75)
	var target_y := -0.15
	ball_velocity.x = (target_x - ball.position.x) / return_time
	ball_velocity.y = (target_y - ball.position.y + 0.5 * 0.85 * return_time * return_time) / return_time
	spin *= 0.45
	var target_distance := Vector2(ball.position.x, ball.position.y).distance_to(target_position)
	var target_points := 0
	if target_distance <= 0.95:
		target_points = 3 if target_distance <= 0.32 else (2 if target_distance <= 0.62 else 1)
		targets_hit += 1
		_move_target()
		if targets_hit >= target_goal:
			play_games_service.submit_progress(court_level, targets_hit, score + target_points)
			court_level += 1
			targets_hit = 0
			target_goal = mini(10, 4 + court_level)
			instruction_label.text = "COURT %d CLEARED" % (court_level - 1)
			instruction_label.visible = true
			var clear_tween := create_tween()
			clear_tween.tween_interval(1.25)
			clear_tween.tween_callback(func(): instruction_label.visible = false)
	score += 1 + target_points
	score_label.text = str(score)
	_update_target_label()
	if score > best_score:
		best_score = score
		best_label.text = "BEST %d" % best_score
	_play_impact(true, minf(1.0, rally_speed / MAX_SPEED + 0.25))
	_haptic(12)

func _handle_side_bounds() -> void:
	if absf(ball.position.x) > 3.8:
		ball.position.x = signf(ball.position.x) * 3.8
		ball_velocity.x = -signf(ball.position.x) * absf(ball_velocity.x) * 0.55
	if ball.position.y > 3.65:
		ball.position.y = 3.65
		ball_velocity.y = -absf(ball_velocity.y) * 0.45

func _drop_ball() -> void:
	if state != GameState.PLAYING:
		return
	state = GameState.LOST
	missed = true
	play_games_service.submit_progress(court_level, targets_hit, score)
	ad_service.note_round_finished()
	if score >= best_score:
		_save_best(best_score)
	final_score_label.text = "RALLY  %d\nBEST  %d" % [score, best_score]
	game_over_panel.visible = true
	reticle.visible = false
	_haptic(90)

func _on_new_rally_pressed() -> void:
	game_over_panel.visible = false
	ad_service.show_interstitial_or_continue()

func _on_save_rally_pressed() -> void:
	ad_service.show_rewarded_continue()

func _restart_round() -> void:
	score = 0
	rally_speed = START_SPEED
	score_label.text = "0"
	game_over_panel.visible = false
	_reset_ball(true)
	state = GameState.READY
	instruction_label.visible = true
	ad_service.preload_ads()

func _reset_ball(serve: bool) -> void:
	ball.position = Vector3(0.0, -0.25, -2.25)
	ball_velocity = Vector3.ZERO
	spin = Vector3.ZERO
	buffered_strike_until_ms = 0
	ball.visible = true
	reticle.visible = serve
	_update_shadow()

func _toggle_pause() -> void:
	if state == GameState.PLAYING:
		state = GameState.PAUSED
	elif state == GameState.PAUSED:
		state = GameState.PLAYING

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	# Let the photographed background plate show through the 3D viewport.
	environment.background_mode = Environment.BG_CANVAS
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c4d6e5")
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.45
	env.environment = environment
	add_child(env)

	camera = Camera3D.new()
	camera.position = Vector3(0.0, 0.35, 2.7)
	camera.fov = 68.0
	camera.current = true
	add_child(camera)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("ffe0b2")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)


func _build_background_plate() -> void:
	var background_layer := CanvasLayer.new()
	background_layer.layer = -1
	add_child(background_layer)
	var background := TextureRect.new()
	background.name = "UrbanCourtBackground"
	background.texture = load("res://assets/urban_court_background.png")
	background.position = Vector2.ZERO
	background.size = Vector2(720, 1280)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_layer.add_child(background)

func _build_billboard() -> void:
	# The structure is real 3D scenery. The native Android ad bridge places an
	# adaptive banner over the inner face using the same reserved screen area.
	var billboard := Node3D.new()
	billboard.name = "SkyBillboard"
	add_child(billboard)
	var steel := _material(Color("26323a"), 0.38, 0.72)
	var face_material := _material(Color("132433"), 0.72, 0.05)

	var face := MeshInstance3D.new()
	var face_mesh := BoxMesh.new()
	face_mesh.size = Vector3(5.35, 1.48, 0.16)
	face_mesh.material = face_material
	face.mesh = face_mesh
	face.position = Vector3(0.0, 6.35, WALL_Z - 0.12)
	billboard.add_child(face)

	# Chunky frame rails make the banner read as part of the court instead of UI.
	for rail in [
		[Vector3(0.0, 7.14, WALL_Z + 0.01), Vector3(5.72, 0.12, 0.22)],
		[Vector3(0.0, 5.56, WALL_Z + 0.01), Vector3(5.72, 0.12, 0.22)],
		[Vector3(-2.80, 6.35, WALL_Z + 0.01), Vector3(0.12, 1.70, 0.22)],
		[Vector3(2.80, 6.35, WALL_Z + 0.01), Vector3(0.12, 1.70, 0.22)]
	]:
		var rail_mesh_instance := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = rail[1]
		rail_mesh.material = steel
		rail_mesh_instance.mesh = rail_mesh
		rail_mesh_instance.position = rail[0]
		billboard.add_child(rail_mesh_instance)

	for x in [-1.85, 1.85]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.14, 2.25, 0.18)
		post_mesh.material = steel
		post.mesh = post_mesh
		post.position = Vector3(x, 5.18, WALL_Z - 0.17)
		billboard.add_child(post)

	var ad_copy := Label3D.new()
	ad_copy.text = "HANDBALL\nTEST AD"
	ad_copy.font_size = 74
	ad_copy.outline_size = 10
	ad_copy.modulate = Color("f2f6f8")
	ad_copy.outline_modulate = Color("132433")
	ad_copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ad_copy.position = Vector3(0.0, 6.34, WALL_Z + 0.02)
	ad_copy.pixel_size = 0.0062
	ad_copy.no_depth_test = true
	billboard.add_child(ad_copy)

	var disclosure := Label3D.new()
	disclosure.text = "ADVERTISEMENT"
	disclosure.font_size = 34
	disclosure.modulate = Color(1, 1, 1, 0.72)
	disclosure.position = Vector3(0.0, 7.31, WALL_Z + 0.02)
	disclosure.pixel_size = 0.0062
	disclosure.no_depth_test = true
	billboard.add_child(disclosure)

func _build_floor() -> void:
	var floor := StaticBody3D.new()
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(12.0, 0.18, 18.0)
	mesh.material = _material(Color("34383a"), 0.92, 0.0)
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(0, FLOOR_Y - 0.09, -3.0)
	floor.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	collision.shape = shape
	collision.position = mesh_instance.position
	floor.add_child(collision)
	add_child(floor)

func _build_block_wall() -> void:
	var wall_root := Node3D.new()
	wall_root.name = "CinderBlockWall"
	var block_material := _material(Color("777a78"), 0.94, 0.0)
	var mortar_material := _material(Color("9a9a91"), 1.0, 0.0)
	var mortar := MeshInstance3D.new()
	var mortar_mesh := BoxMesh.new()
	mortar_mesh.size = Vector3(10.2, 7.0, 0.22)
	mortar_mesh.material = mortar_material
	mortar.mesh = mortar_mesh
	mortar.position = Vector3(0, 1.9, WALL_Z - 0.10)
	wall_root.add_child(mortar)
	var block_width := 0.96
	var block_height := 0.46
	for row in range(15):
		var offset := -0.49 if row % 2 else 0.0
		for column in range(12):
			var x := -5.28 + column * 0.97 + offset
			if x < -5.08 or x > 5.08:
				continue
			var block := MeshInstance3D.new()
			var block_mesh := BoxMesh.new()
			block_mesh.size = Vector3(block_width, block_height, 0.28)
			block_mesh.material = block_material
			block.mesh = block_mesh
			block.position = Vector3(x, -1.29 + row * 0.47, WALL_Z + 0.02)
			wall_root.add_child(block)
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(10.2, 7.0, 0.25)
	collision.shape = shape
	collision.position = Vector3(0, 1.9, WALL_Z)
	body.add_child(collision)
	wall_root.add_child(body)
	add_child(wall_root)

func _build_fences() -> void:
	var fence_material := _material(Color("32383b"), 0.55, 0.65)
	for side in [-1.0, 1.0]:
		for post_index in range(4):
			var post := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.055
			cylinder.bottom_radius = 0.055
			cylinder.height = 4.4
			cylinder.material = fence_material
			post.mesh = cylinder
			post.position = Vector3(side * 5.1, 0.55, -8.8 + post_index * 3.2)
			add_child(post)

func _build_target() -> void:
	wall_target = Node3D.new()
	wall_target.name = "WallTarget"
	wall_target.position = Vector3(target_position.x, target_position.y, WALL_Z + 0.19)
	wall_target.rotation_degrees.x = 90.0
	add_child(wall_target)
	var colors := [Color("f5a623"), Color("f7efe0"), Color("ed5a3a")]
	var radii := [0.92, 0.58, 0.25]
	for index in range(3):
		var disk := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = radii[index]
		mesh.bottom_radius = radii[index]
		mesh.height = 0.018 + float(index) * 0.006
		mesh.radial_segments = 48
		mesh.material = _material(colors[index], 0.55, 0.0)
		disk.mesh = mesh
		disk.position.y = float(index) * 0.014
		wall_target.add_child(disk)

func _move_target() -> void:
	target_position = Vector2(randf_range(-3.1, 3.1), randf_range(-0.65, 2.55))
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(wall_target, "position", Vector3(target_position.x, target_position.y, WALL_Z + 0.19), 0.28)

func _update_target_label() -> void:
	if target_label != null:
		target_label.text = "COURT %d   TARGETS %d/%d" % [court_level, targets_hit, target_goal]

func _build_ball() -> void:
	ball = MeshInstance3D.new()
	ball.name = "BlueRacquetball"
	var sphere := SphereMesh.new()
	sphere.radius = BALL_RADIUS
	sphere.height = BALL_RADIUS * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	var ball_material := _material(Color("0756d9"), 0.58, 0.0)
	ball_material.clearcoat_enabled = true
	ball_material.clearcoat = 0.32
	ball_material.clearcoat_roughness = 0.42
	sphere.material = ball_material
	ball.mesh = sphere
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(ball)

	ball_shadow = Decal.new()
	ball_shadow.size = Vector3(1.2, 1.2, 1.2)
	ball_shadow.upper_fade = 0.45
	ball_shadow.lower_fade = 0.45
	add_child(ball_shadow)

	impact_flash = OmniLight3D.new()
	impact_flash.light_color = Color("5b91ff")
	impact_flash.light_energy = 0.0
	impact_flash.omni_range = 1.5
	add_child(impact_flash)

func _build_hand() -> void:
	hand = Node3D.new()
	hand.name = "PlayerHand"
	hand.visible = false
	add_child(hand)
	var skin := _material(Color("8b5a3c"), 0.78, 0.0)

	var palm := MeshInstance3D.new()
	var palm_mesh := SphereMesh.new()
	palm_mesh.radius = 0.42
	palm_mesh.height = 0.82
	palm_mesh.radial_segments = 24
	palm_mesh.rings = 12
	palm_mesh.material = skin
	palm.mesh = palm_mesh
	palm.scale = Vector3(0.82, 1.0, 0.42)
	hand.add_child(palm)

	var finger_x := [-0.27, -0.09, 0.09, 0.27]
	var finger_length := [0.47, 0.58, 0.55, 0.43]
	for index in range(4):
		var finger := MeshInstance3D.new()
		var finger_mesh := CapsuleMesh.new()
		finger_mesh.radius = 0.075
		finger_mesh.height = finger_length[index]
		finger_mesh.radial_segments = 16
		finger_mesh.rings = 8
		finger_mesh.material = skin
		finger.mesh = finger_mesh
		finger.position = Vector3(finger_x[index], 0.43 + finger_length[index] * 0.38, -0.015)
		hand.add_child(finger)

	var thumb := MeshInstance3D.new()
	var thumb_mesh := CapsuleMesh.new()
	thumb_mesh.radius = 0.09
	thumb_mesh.height = 0.42
	thumb_mesh.radial_segments = 16
	thumb_mesh.rings = 8
	thumb_mesh.material = skin
	thumb.mesh = thumb_mesh
	thumb.position = Vector3(-0.39, 0.02, -0.015)
	thumb.rotation_degrees.z = -52.0
	hand.add_child(thumb)

	var wrist := MeshInstance3D.new()
	var wrist_mesh := CapsuleMesh.new()
	wrist_mesh.radius = 0.20
	wrist_mesh.height = 0.55
	wrist_mesh.material = skin
	wrist.mesh = wrist_mesh
	wrist.position = Vector3(0.0, -0.48, 0.02)
	hand.add_child(wrist)
	hand.position = Vector3(0.75, -1.7, 0.25)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	score_label = Label.new()
	score_label.text = "0"
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.add_theme_font_size_override("font_size", 54)
	score_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	score_label.position = Vector2(-100, 44)
	score_label.size = Vector2(200, 68)
	root.add_child(score_label)

	target_label = Label.new()
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_label.add_theme_font_size_override("font_size", 18)
	target_label.add_theme_color_override("font_color", Color("ffd78a"))
	target_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	target_label.position = Vector2(-190, 116)
	target_label.size = Vector2(380, 34)
	root.add_child(target_label)
	_update_target_label()

	profile_button = Button.new()
	profile_button.text = "GUEST  •  SIGN IN"
	profile_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	profile_button.position = Vector2(24, 30)
	profile_button.size = Vector2(190, 52)
	profile_button.pressed.connect(_on_profile_pressed)
	root.add_child(profile_button)

	leaderboard_button = Button.new()
	leaderboard_button.text = "🏆  GLOBAL"
	leaderboard_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	leaderboard_button.position = Vector2(-190, 30)
	leaderboard_button.size = Vector2(166, 52)
	leaderboard_button.pressed.connect(_on_leaderboard_pressed)
	root.add_child(leaderboard_button)

	best_label = Label.new()
	best_label.text = "BEST %d" % best_score
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	best_label.add_theme_font_size_override("font_size", 18)
	best_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
	best_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	best_label.position = Vector2(-100, 148)
	best_label.size = Vector2(200, 30)
	root.add_child(best_label)

	instruction_label = Label.new()
	instruction_label.text = "TAP THE BALL TO SERVE"
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.add_theme_font_size_override("font_size", 19)
	instruction_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	instruction_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	instruction_label.position = Vector2(-180, -185)
	instruction_label.size = Vector2(360, 42)
	root.add_child(instruction_label)

	reticle = _make_reticle()
	root.add_child(reticle)
	game_over_panel = _make_game_over_panel()
	root.add_child(game_over_panel)

func _make_reticle() -> Control:
	var ring := Panel.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.size = Vector2(116, 116)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(1, 1, 1, 0.56)
	style.set_border_width_all(2)
	style.set_corner_radius_all(58)
	ring.add_theme_stylebox_override("panel", style)
	return ring

func _make_game_over_panel() -> Control:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-210, -210)
	panel.size = Vector2(420, 420)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.035, 0.05, 0.94)
	panel_style.border_color = Color("286ef0")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(28)
	panel_style.content_margin_left = 34
	panel_style.content_margin_right = 34
	panel_style.content_margin_top = 30
	panel_style.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", panel_style)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)
	var title := Label.new()
	title.text = "BALL DROPPED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 31)
	column.add_child(title)
	final_score_label = Label.new()
	final_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final_score_label.add_theme_font_size_override("font_size", 21)
	column.add_child(final_score_label)
	var save_button := Button.new()
	save_button.text = "SAVE RALLY  ▶"
	save_button.custom_minimum_size.y = 64
	save_button.pressed.connect(_on_save_rally_pressed)
	column.add_child(save_button)
	var restart_button := Button.new()
	restart_button.text = "NEW RALLY"
	restart_button.custom_minimum_size.y = 64
	restart_button.pressed.connect(_on_new_rally_pressed)
	column.add_child(restart_button)
	return panel

func _build_audio() -> void:
	# Procedural impact sound avoids missing-asset failures in the first build.
	var player := AudioStreamPlayer.new()
	player.name = "ImpactAudio"
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 22050.0
	generator.buffer_length = 0.25
	player.stream = generator
	add_child(player)
	player.play()

func _play_impact(wall_hit: bool, strength: float) -> void:
	var player := get_node_or_null("ImpactAudio") as AudioStreamPlayer
	if player == null:
		return
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var frames := 800
	var frequency := 128.0 if wall_hit else 86.0
	for index in range(frames):
		var time := float(index) / 22050.0
		var envelope := exp(-time * (75.0 if wall_hit else 48.0))
		var tone := sin(TAU * frequency * time) * envelope
		var noise := randf_range(-1.0, 1.0) * envelope * 0.32
		var sample := (tone * 0.7 + noise) * strength * 0.62
		playback.push_frame(Vector2(sample, sample))
	impact_flash.position = ball.position
	impact_flash.light_energy = 1.5 * strength
	var tween := create_tween()
	tween.tween_property(impact_flash, "light_energy", 0.0, 0.09)

func _play_hand_animation(screen_position: Vector2, quality: float) -> void:
	hand.visible = true
	var viewport_size := get_viewport().get_visible_rect().size
	var x := lerpf(-0.85, 0.85, screen_position.x / viewport_size.x)
	hand.position = Vector3(x, -1.38, 0.2)
	hand.scale = Vector3.ONE * (0.9 + quality * 0.12)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(hand, "position:z", -0.6, 0.07)
	tween.tween_property(hand, "position:z", 0.42, 0.16)
	tween.tween_callback(func(): hand.visible = false)

func _update_shadow() -> void:
	if ball_shadow == null:
		return
	ball_shadow.position = Vector3(ball.position.x, FLOOR_Y + 0.02, ball.position.z)
	var height := maxf(0.1, ball.position.y - FLOOR_Y)
	ball_shadow.size = Vector3(0.65 + height * 0.1, 1.0, 0.65 + height * 0.1)

func _update_reticle() -> void:
	if camera.is_position_behind(ball.global_position):
		reticle.visible = false
		return
	reticle.visible = ball.position.z > -4.0
	var point := camera.unproject_position(ball.global_position)
	var scale_amount := clampf(5.8 / maxf(1.1, camera.position.distance_to(ball.position)), 0.8, 1.65)
	reticle.position = point - reticle.size * 0.5
	reticle.scale = Vector2.ONE * scale_amount

func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _haptic(duration_ms: int) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms)

func _load_best() -> int:
	var config := ConfigFile.new()
	if config.load("user://save.cfg") == OK:
		return int(config.get_value("scores", "best", 0))
	return 0

func _save_best(value: int) -> void:
	var config := ConfigFile.new()
	config.set_value("scores", "best", value)
	config.save("user://save.cfg")


func _on_profile_pressed() -> void:
	play_games_service.request_sign_in()

func _on_leaderboard_pressed() -> void:
	play_games_service.show_highest_court_leaderboard()

func _on_play_games_authentication_changed(authenticated: bool, player_name: String) -> void:
	profile_button.text = ("●  " + player_name.to_upper()) if authenticated else "GUEST  •  SIGN IN"

func _show_status_message(message: String) -> void:
	instruction_label.text = message
	instruction_label.visible = true
	var tween := create_tween()
	tween.tween_interval(1.8)
	tween.tween_callback(func():
		if state != GameState.READY:
			instruction_label.visible = false
	)
