extends SceneTree
## Regenera res://sim/core/default_config.tres con los valores por defecto de SimConfig.
func _initialize() -> void:
	var err := ResourceSaver.save(SimConfig.new(), "res://sim/core/default_config.tres")
	print("saved default_config.tres err=", err)
	quit()
