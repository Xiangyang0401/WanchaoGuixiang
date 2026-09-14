class_name LevelEntry
extends Marker2D
## 关卡入口点。玩家从别的关卡进来时，会被放到对应 id 的入口点上。
##
## 用法：在关卡里放若干个 LevelEntry，各起一个 id（如 "west"、"east"、"default"）。
## 另一关卡的 LevelExit 指定 target_entry = "west"，玩家就会出现在这里。
##
## 每个关卡至少要有一个 id 为 "default" 的入口，作为兜底和默认复活点。

@export var entry_id: StringName = &"default"

## 从此入口进入时玩家的朝向。
@export_enum("右:1", "左:-1") var facing: int = 1

## 是否同时作为本关的默认复活点。
## 按策划要求：每个区域有默认复活点，检查点优先级高于它。
@export var is_default_respawn: bool = false


func _ready() -> void:
	add_to_group(&"level_entry")
	if is_default_respawn:
		add_to_group(&"default_respawn")
