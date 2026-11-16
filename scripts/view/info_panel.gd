class_name InfoPanel
extends PanelContainer
## A small info window: a title, lines of text, and an optional rename field. It knows nothing
## about people or rooms, so the person window (#121) and the room window (#120) share it. The
## owner fills it with show_info and listens for rename_submitted. View only.

signal rename_submitted(text: String)

var _title: Label
var _body: Label
var _edit: LineEdit
var _button: Button
var _rename_row: HBoxContainer


func _init() -> void:
	name = "InfoPanel"
	custom_minimum_size = Vector2(240, 0)
	var column := VBoxContainer.new()
	add_child(column)
	_title = Label.new()
	_title.name = "Title"
	column.add_child(_title)
	_body = Label.new()
	_body.name = "Body"
	column.add_child(_body)
	_rename_row = HBoxContainer.new()
	_rename_row.name = "RenameRow"
	column.add_child(_rename_row)
	_edit = LineEdit.new()
	_edit.name = "RenameField"
	_edit.placeholder_text = "Rename"
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.text_submitted.connect(_on_submit)
	_rename_row.add_child(_edit)
	_button = Button.new()
	_button.name = "RenameButton"
	_button.text = "Rename"
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(func() -> void: _on_submit(_edit.text))
	_rename_row.add_child(_button)
	visible = false


## Fills the title and lines. The rename field shows only when rename_text is not null; it is
## reset to that text only when reset_field is true, so a refresh does not wipe what is being typed.
func show_info(title: String, lines: Array[String], rename_text: Variant = null, reset_field: bool = true) -> void:
	_title.text = title
	_body.text = "\n".join(lines)
	_rename_row.visible = rename_text != null
	if rename_text != null and reset_field:
		_edit.text = rename_text as String
	visible = true


func title_text() -> String:
	return _title.text


func body_text() -> String:
	return _body.text


func field_text() -> String:
	return _edit.text


func has_rename_field() -> bool:
	return _rename_row.visible


## Types into the field and submits, as the player pressing Enter would.
func submit_rename(text: String) -> void:
	_edit.text = text
	_on_submit(text)


## True if a screen point is over the visible panel.
func contains_point(point: Vector2) -> bool:
	return visible and get_global_rect().has_point(point)


func _on_submit(text: String) -> void:
	rename_submitted.emit(text)
	_edit.release_focus()
