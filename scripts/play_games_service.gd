class_name PlayGamesService
extends Node

signal authentication_changed(authenticated: bool, player_name: String)
signal leaderboard_unavailable(message: String)

const NATIVE_SINGLETON := "HandballPlayGames"
var authenticated := false
var player_name := "GUEST"
var pending_rank_score := 0
var diagnostic_status := "Play Games has not initialized"
var _open_after_sign_in := false

func _ready() -> void:
	var saved := ConfigFile.new()
	if saved.load("user://play_games.cfg") == OK:
		pending_rank_score = int(saved.get_value("scores", "highest_court", 0))
	if is_available():
		var bridge = Engine.get_singleton(NATIVE_SINGLETON)
		bridge.authentication_changed.connect(_on_authentication_changed)
		bridge.player_changed.connect(_on_player_changed)
		bridge.service_error.connect(_on_service_error)
		authenticate_silently()
	else:
		diagnostic_status = "Play Games Android component is missing from this build"

func is_available() -> bool:
	return Engine.has_singleton(NATIVE_SINGLETON)

func authenticate_silently() -> void:
	if is_available():
		Engine.get_singleton(NATIVE_SINGLETON).authenticate(false)

func request_sign_in() -> void:
	if not is_available():
		_on_service_error("PLAY GAMES UNAVAILABLE IN THIS BUILD")
		return
	Engine.get_singleton(NATIVE_SINGLETON).authenticate(true)

func submit_progress(court: int, _targets: int, _score: int) -> void:
	# The leaderboard displays completed courts, not an encoded million-point score.
	var completed := maxi(0, court - 1)
	if completed <= pending_rank_score:
		return
	pending_rank_score = completed
	var saved := ConfigFile.new()
	saved.set_value("scores", "highest_court", pending_rank_score)
	saved.save("user://play_games.cfg")
	if authenticated and is_available():
		Engine.get_singleton(NATIVE_SINGLETON).submit_highest_court(pending_rank_score)

func show_highest_court_leaderboard() -> void:
	if not is_available():
		_on_service_error("PLAY GAMES UNAVAILABLE IN THIS BUILD")
		return
	if not authenticated:
		_open_after_sign_in = true
		request_sign_in()
	else:
		Engine.get_singleton(NATIVE_SINGLETON).show_highest_court_leaderboard()

func _on_authentication_changed(value: bool) -> void:
	authenticated = value
	diagnostic_status = "Connected to Play Games" if value else "Not connected to Play Games"
	if authenticated and pending_rank_score > 0:
		Engine.get_singleton(NATIVE_SINGLETON).submit_highest_court(pending_rank_score)
	if authenticated and _open_after_sign_in:
		Engine.get_singleton(NATIVE_SINGLETON).show_highest_court_leaderboard()
	_open_after_sign_in = false
	authentication_changed.emit(authenticated, player_name)

func _on_player_changed(value: String) -> void:
	player_name = value if not value.is_empty() else "PLAYER"
	authentication_changed.emit(authenticated, player_name)

func _on_service_error(message: String) -> void:
	diagnostic_status = message
	_open_after_sign_in = false
	push_warning(message)
	leaderboard_unavailable.emit(message)
