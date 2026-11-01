extends Node

# Global configuration.
# Chart data lives inside the project so the exported APK works offline.

const BASE_DIR := "res://new-my_type/"
const MANIFEST_FILE := "manifest.json"
const AUDIO_FILE := "audio.ogg"
const SETTINGS_PATH := "user://settings.cfg"

var player_name := "Player"
var last_song_folder := ""
var last_difficulty := ""

var scroll_speed_multiplier := 6.0
var track_width_ratio := 0.72
var audio_offset := 0.0


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		save_settings()
		return
	scroll_speed_multiplier = clampf(float(cfg.get_value("game", "scroll_speed", 6.0)), 0.0, 28.0)
	track_width_ratio = clampf(float(cfg.get_value("game", "track_width", 0.72)), 0.4, 1.0)
	audio_offset = clampf(float(cfg.get_value("game", "audio_offset", 0.0)), -0.2, 0.2)
	player_name = str(cfg.get_value("game", "player_name", player_name))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "scroll_speed", scroll_speed_multiplier)
	cfg.set_value("game", "track_width", track_width_ratio)
	cfg.set_value("game", "audio_offset", audio_offset)
	cfg.set_value("game", "player_name", player_name)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_error("Failed to save settings: " + str(err))


func manifest_path() -> String:
	return BASE_DIR + MANIFEST_FILE


func song_dir(folder: String) -> String:
	return BASE_DIR + folder + "/"


func chart_path(folder: String, diff: String) -> String:
	return song_dir(folder) + diff + ".json"


func audio_path(folder: String) -> String:
	return song_dir(folder) + AUDIO_FILE


func load_manifest() -> Array:
	var path := manifest_path()
	if not FileAccess.file_exists(path):
		push_error("Manifest not found: " + path)
		return []
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Manifest is empty: " + path)
		return []
	var data = JSON.parse_string(text)
	if data is Array:
		return data
	push_error("Manifest is not a JSON array: " + path)
	return []
