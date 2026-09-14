class_name InputHints
extends RefCounted
## 把 InputMap 的动作解析成玩家看得懂的键名（中文）。
##
## 教学文案里写 {action:jump}，运行到这里换成"空格"。玩家改键后
## 显示自动跟随，不用改文案。这是文案与真实键位解耦的唯一方式——
## 硬编码"按空格"的话，玩家改键或加手柄支持，提示就骗人了。
##
## 用法：
##   InputHints.action_key_name("jump")       -> "空格"
##   InputHints.fill_text("跳跃：{action:jump}") -> "跳跃：空格"

## 物理键码 -> 中文名。只收本项目用得到的键。
## 物理键码不随键盘布局变（QWERTY 上按 A 的位置就是 65），
## 所以用 physical_keycode 而非 keycode 判断。
const _KEY_NAMES := {
	KEY_A: "A", KEY_B: "B", KEY_C: "C", KEY_D: "D",
	KEY_E: "E", KEY_F: "F", KEY_G: "G", KEY_H: "H",
	KEY_I: "I", KEY_J: "J", KEY_K: "K", KEY_L: "L",
	KEY_M: "M", KEY_N: "N", KEY_O: "O", KEY_P: "P",
	KEY_Q: "Q", KEY_R: "R", KEY_S: "S", KEY_T: "T",
	KEY_U: "U", KEY_V: "V", KEY_W: "W", KEY_X: "X",
	KEY_Y: "Y", KEY_Z: "Z",
	KEY_SPACE: "空格",
	KEY_SHIFT: "Shift",
	KEY_CTRL: "Ctrl",
	KEY_ALT: "Alt",
	KEY_TAB: "Tab",
	KEY_ENTER: "回车",
	KEY_ESCAPE: "Esc",
	KEY_LEFT: "←", KEY_RIGHT: "→", KEY_UP: "↑", KEY_DOWN: "↓",
	KEY_F1: "F1", KEY_F2: "F2", KEY_F3: "F3", KEY_F4: "F4",
	KEY_F5: "F5", KEY_F6: "F6", KEY_F7: "F7", KEY_F8: "F8",
}


## 取某动作当前绑定的主键名。
## 规则：字母键（A-Z）优先，其次鼠标/手柄，最后其它键。
## 原因：move_left 这类动作通常同时绑了方向键和 WASD，
## 教学提示显示"移动：A"比"移动：←"更符合当代玩家的习惯。
## 找不到返回空串，调用方应保留占位符原样或给个兜底。
static func action_key_name(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	var fallback := ""
	for e in InputMap.action_get_events(action):
		var n := _event_name(e)
		if n == "":
			continue
		if fallback == "":
			fallback = n
		if _is_letter(e):
			return n
	return fallback


static func _is_letter(e: InputEvent) -> bool:
	if e is InputEventKey:
		var k := e as InputEventKey
		var key := k.physical_keycode if k.physical_keycode != 0 else k.keycode
		return key >= KEY_A and key <= KEY_Z
	return false


static func _event_name(e: InputEvent) -> String:
	if e is InputEventKey:
		var k := e as InputEventKey
		var key := k.physical_keycode if k.physical_keycode != 0 else k.keycode
		if _KEY_NAMES.has(key):
			return _KEY_NAMES[key]
		return "键%d" % int(key)
	if e is InputEventMouseButton:
		var b := (e as InputEventMouseButton).button_index
		match b:
			MOUSE_BUTTON_LEFT: return "鼠标左键"
			MOUSE_BUTTON_RIGHT: return "鼠标右键"
			MOUSE_BUTTON_MIDDLE: return "鼠标中键"
			_: return "鼠标键%d" % int(b)
	if e is InputEventJoypadButton:
		return "手柄键%d" % int((e as InputEventJoypadButton).button_index)
	return ""


## 把文案里的 {action:名字} 占位符替换成真实键名。
## 未知动作保持占位符原样，方便策划排查写错的 action。
static func fill_text(text: String) -> String:
	var out := text
	for m in _action_pattern().search_all(text):
		var action := m.get_string(1)
		var name := action_key_name(action)
		if name == "":
			name = "?" + action  # 保留可读的提示，别静默吞掉
		out = out.replace(m.get_string(), name)
	return out


static var _pattern: RegEx = null


static func _action_pattern() -> RegEx:
	if _pattern == null:
		_pattern = RegEx.create_from_string(r"\{action:([a-zA-Z0-9_]+)\}")
	return _pattern
