extends RigidBody2D

class_name Room

var size

func make_room(_pos: Vector2, _size: Vector2):
	position = _pos
	size = _size
	var s = RectangleShape2D.new()
	s.extents = size
	s.custom_solver_bias = 0.75  # 初期値は0。コリジョンの重なりを解決する速度。負の数になると、解決しなくなる
	$CollisionShape2D.shape = s
	
