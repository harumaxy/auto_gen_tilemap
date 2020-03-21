extends Node2D

# https://ja.wikipedia.org/wiki/%E3%83%97%E3%83%AA%E3%83%A0%E6%B3%95
# プリム法を使ったダンジョン生成

var Room = preload("res://Room.tscn")
onready var map = $TileMap

var tile_size = 32
var num_rooms = 50
var min_size = 4
var max_size = 10
var hspread = 400
var cull = 0.5  # 部屋が残る確立

# AStar(A*) : https://docs.godotengine.org/en/3.2/classes/class_astar.html
# 空間内の接続されたポイント感の最短パスを見つけるA*グラフ探索アルゴリズムの実装オブジェクト
# A*: https://ja.wikipedia.org/wiki/A*
var path: AStar2D # AStarr pathfinding object : 
	
# payler	

var Player = preload("res://Charactor.tscn")
var start_room = null
var end_room = null
var play_mode = false
var player: Charactor = null

func find_start_room():
	var min_x = INF
	for room in $Rooms.get_children():
		if room.position.x < min_x:
			start_room = room
			min_x = room.position.x

func find_end_room():
	var max_x = -INF
	for room in $Rooms.get_children():
		if room.position.x > max_x:
			end_room = room
			max_x = room.position.x



func _ready():
	randomize()
	make_rooms()
	
func make_rooms():
	for i in range(num_rooms):
		var pos = Vector2(rand_range(-hspread, hspread), 0)
		var r = Room.instance()
		var w = min_size + randi() % (max_size - min_size)
		var h = min_size + randi() % (max_size - min_size)
		r.make_room(pos, Vector2(w, h) * tile_size)
		$Rooms.add_child(r)
	# 動きが止まるまで待つ。
	yield(get_tree().create_timer(1.1), "timeout")
	# cull rooms : cull = 選び出す。選り抜く
	# ついでに、作った部屋の位置を配列に保存
	var room_positions = []
	for r in $Rooms.get_children():
		if randf() < cull:
			(r as Room).queue_free()
		else:
			(r as Room).mode = RigidBody2D.MODE_STATIC
			room_positions.append(r.position)
	yield(get_tree(), "idle_frame")
	path = find_mst(room_positions)

func find_mst(nodes: Array):
	# Prim法アルゴリズム
	var path = AStar2D.new()
	print(nodes)
	path.add_point(path.get_available_point_id(), nodes.pop_front())
	
	# repeat untile no more nodes remain:
	while not nodes.empty():
		var min_dist = INF
		var min_p = null
		var p = null   # current pos
		for p1 in path.get_points():
			p1 = path.get_point_position(p1)
			# Loop through the remaining nodes
			for p2 in nodes:
				if p1.distance_to(p2) < min_dist:
					min_dist = p1.distance_to(p2)
					min_p = p2
					p = p1
		var n = path.get_available_point_id()
		path.add_point(n, min_p)
		path.connect_points(path.get_closest_point(p), n)
		nodes.erase(min_p)
	return path
		

func _process(delta):
	update()		

func _draw():
	for room in $Rooms.get_children():
		draw_rect(Rect2(room.position - room.size, room.size * 2), Color(32, 228, 0), false)
	if path:
		for p in path.get_points():
			for c in path.get_point_connections(p):
				var pp = path.get_point_position(p) # point pos
				var cp = path.get_point_position(c) # connection pos
				draw_line(pp, cp, Color.green, 15, true)

	
	
func _input(event):
	if event.is_action_pressed("ui_select"):
		if play_mode:
			player.queue_free()
			play_mode = false
		map.clear()
		for n in $Rooms.get_children():
			(n as Node).queue_free()
		path = null
		start_room = null
		end_room = null
		make_rooms()
	if event.is_action_pressed("ui_focus_next"):
		make_map()
	if event.is_action_pressed("ui_cancel"):
		player = Player.instance()
		add_child(player)
		player.position = start_room.position
		play_mode = true
		
		


func make_map():
	# Tilemapを、作成されたrooms, path から作る
	map.clear()
	find_start_room()
	find_end_room()
	# Tilemapを壁で埋める。(部屋のない壁だけの洞窟)
	var full_rect = Rect2()
	for room in $Rooms.get_children():
		var r = Rect2(
			room.position - room.size, 
			room.get_node("CollisionShape2D").shape.extents * 2)
		full_rect = full_rect.merge(r)
	var top_left = map.world_to_map(full_rect.position)
	var bottom_right = map.world_to_map(full_rect.end)
	for x in range(top_left.x, bottom_right.x):
		for y in range(top_left.y, bottom_right.y):
			map.set_cell(x, y, 1)
			
	# roomsの範囲をタイルマップで部屋を作る。
	var corridors = [] # 1つの接続に付き、1つのコリジョン
	for room in $Rooms.get_children():
		var s = (room.size / tile_size).floor()  # 単位長のSize
		var pos = map.world_to_map(room.position)
		var ul = (room.position / tile_size).floor() - s  # unit length
		for x in range(2, s.x * 2 - 1):
			for y in range(2, s.y * 2 - 1):
				map.set_cell(ul.x + x, ul.y + y, 0)
		
		# 部屋を接続する。
		var p = path.get_closest_point(room.position)
		var pp = path.get_point_position(p)
		for conn_id in path.get_point_connections(p):
			if not conn_id in corridors:
				var start = map.world_to_map(pp)
				var end = map.world_to_map(path.get_point_position(conn_id))
				carve_path(start, end)
		corridors.append(p)

func carve_path(pos1: Vector2, pos2: Vector2):
	# Carve a path between two points
	# 2点の間を掘る
	var x_diff = sign(pos2.x - pos1.x)
	var y_diff = sign(pos2.y - pos1.y)
	if x_diff == 0: x_diff = pow(-1.0, randi() % 2)
	if y_diff == 0: y_diff = pow(-1.0, randi() % 2)
	# Carve either x/y or y/x
	var x_y = pos1
	var y_x = pos2
	if (randi() % 2) > 0:
		x_y = pos2
		y_x = pos1
	for x in range(pos1.x, pos2.x, x_diff):
		map.set_cell(x, x_y.y, 0)
		map.set_cell(x, x_y.y+y_diff, 0)  # widen the corridor
	for y in range(pos1.y, pos2.y, y_diff):
		map.set_cell(y_x.x, y, 0)
		map.set_cell(y_x.x+x_diff, y, 0)  # widen the corridor
	
