class_name PlayGamesService
extends Node

signal authentication_changed(authenticated: bool, player_name: String)
signal leaderboard_unavailable(message: String)

const NATIVE_SINGLETON := "HandballPlayGames"

var authenticated := false
var player_name := "GUEST"
var pending_rank_score := 0

func _ready() -> void:
	if Engine.has_singleton(NATIVE_SINGLETON):
		var bridge = Engine.get_singleton(NATIVE_SINGLETON)
		if bridge.has_signal("authentication_changed"):
			bridge.authentication_changed.connect(_on_authentication_changed)
		if bridge.has_signal("player_changed"):
			bridge.player_changed.connect(_on_player_changed)
		authenticate_silently()

func is_available() -> bool:
	return Engine.has_singleton(NATIVE_SINGLETON)

func authenticate_silently() -> void:
	if not is_available():
		authentication_changed.emit(false, "GUEST")
		return
	Engine.get_singleton(NATIVE_SINGLETON).authenticate(false)

func request_sign_in() -> void:
	if not is_available():
		leaderboard_unavailable.emit("PLAY GAMES AVAILABLE IN RELEASE BUILD")
		return
	Engine.get_singleton(NATIVE_SINGLETON).authenticate(true)

func submit_progress(court: int, targets: int, score: int) -> void:
	var encoded := int(court) * 1000000 + int(targets) * 10000 + mini(score, 9999)
	pending_rank_score = maxi(pending_rank_score, encoded)
	if authenticated and is_available():
		Engine.get_singleton(NATIVE_SINGLETON).submit_highest_court(pending_rank_score)

func show_highest_court_leaderboard() -> void:
	if not is_available():
		leaderboard_unavailable.emit("PLAY GAMES AVAILABLE IN RELEASE BUILD")
		return
	if not authenticated:
		request_sign_in()
		return
	Engine.get_singleton(NATIVE_SINGLETON).show_highest_court_leaderboard()

func _on_authentication_changed(value: bool) -> void:
	authenticated = value
	if authenticated and pending_rank_score > 0:
		Engine.get_singleton(NATIVE_SINGLETON).submit_highest_court(pending_rank_score)
	authentication_changed.emit(authenticated, player_name)

func _on_player_changed(value: String) -> void:
	player_name = value if not value.is_empty() else "PLAYER"
	authentication_changed.emit(authenticated, player_name)
