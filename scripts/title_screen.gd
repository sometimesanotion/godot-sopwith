extends CanvasLayer

signal start_game
signal start_vs_computer

const KEY_ASSIGNMENT_SCENE := preload("res://scenes/key_assignment.tscn")

enum MenuState { MAIN, OPTIONS }
var current_state: MenuState = MenuState.MAIN
var selected_index: int = 0

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var menu_container: VBoxContainer = $MenuContainer
@onready var controls_container: VBoxContainer = $ControlsContainer

func _ready() -> void:
	_create_menu()

func _create_menu() -> void:
	menu_container.clear()
	
	var items = ["Single Player", "Single Player vs. Computer", "Game Options", "Quit Game"]
	for i in range(items.size()):
		var label = Label.new()
		label.text = items[i]
		label.add_theme_font_size_override("font_size", 20)
		menu_container.add_child(label)
	
	_update_selection()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pull_down"):
		selected_index = (selected_index + 1) % 4
		_update_selection()
	elif Input.is_action_just_pressed("pull_up"):
		selected_index = (selected_index - 1 + 4) % 4
		_update_selection()
	elif Input.is_action_just_pressed("fire"):
		_handle_selection()
	elif Input.is_key_pressed(KEY_S):
		selected_index = 0
		_handle_selection()
	elif Input.is_key_pressed(KEY_C):
		selected_index = 1
		_handle_selection()
	elif Input.is_key_pressed(KEY_O):
		selected_index = 2
		_handle_selection()
	elif Input.is_key_pressed(KEY_Q):
		get_tree().quit()
	elif Input.is_key_pressed(KEY_K):
		_show_key_assignment()

func _update_selection() -> void:
	for i in range(menu_container.get_child_count()):
		var label = menu_container.get_child(i)
		if i == selected_index:
			label.text = "> " + _get_menu_item(i)
		else:
			label.text = "  " + _get_menu_item(i)

func _get_menu_item(index: int) -> String:
	var items = ["Single Player", "Single Player vs. Computer", "Game Options", "Quit Game"]
	return items[index]

func _handle_selection() -> void:
	match selected_index:
		0:
			start_game.emit()
			queue_free()
		1:
			start_vs_computer.emit()
			queue_free()
		2:
			_show_key_assignment()
		3:
			get_tree().quit()

func _show_key_assignment() -> void:
	var key_screen := KEY_ASSIGNMENT_SCENE.instantiate()
	get_parent().add_child(key_screen)
	queue_free()

func _on_key_settings_pressed() -> void:
	_show_key_assignment()