extends RefCounted
## Pure deterministic ASCII generation; no nodes, global RNG or filesystem.
const DIRS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const WIDTH := 19
const HEIGHT := 15

static func generate(run_seed: int, floor_number: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed + floor_number * 104729
	var cells: Array = []
	for y in HEIGHT:
		var row: Array = []
		row.resize(WIDTH)
		row.fill("#")
		cells.append(row)
	var centers: Array[Vector2i] = [Vector2i(3, 3)]
	for i in 5:
		centers.append(Vector2i(rng.randi_range(3, WIDTH - 4), rng.randi_range(3, HEIGHT - 4)))
	for i in centers.size():
		var c := centers[i]
		for y in range(c.y - 2, c.y + 3):
			for x in range(c.x - 2, c.x + 3):
				cells[y][x] = " "
		if i > 0:
			var previous := centers[i - 1]
			for x in range(mini(c.x, previous.x), maxi(c.x, previous.x) + 1):
				cells[c.y][x] = " "
			for y in range(mini(c.y, previous.y), maxi(c.y, previous.y) + 1):
				cells[y][previous.x] = " "
	var map := _strings(cells)
	var distance := flood(map, Vector2i(3, 3))
	var candidates: Array = distance.keys()
	# Explicit RNG shuffle: independent of the engine/global seed.
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Vector2i = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = swap
	var exit_cell := Vector2i(3, 3)
	for cell: Vector2i in candidates:
		if int(distance[cell]) > int(distance[exit_cell]):
			exit_cell = cell
	cells[3][3] = "@"
	cells[exit_cell.y][exit_cell.x] = ">"
	var remaining := 5 + floor_number * 3
	for cell: Vector2i in candidates:
		if remaining > 0 and int(distance[cell]) >= 6 and cells[cell.y][cell.x] == " ":
			cells[cell.y][cell.x] = "T" if remaining % 4 == 0 else "E"
			remaining -= 1
	for cell: Vector2i in candidates:
		if cells[cell.y][cell.x] == " " and int(distance[cell]) >= 3:
			cells[cell.y][cell.x] = "+"
			break
	map = _strings(cells)
	if remaining > 0 or not validate(map).get("valid", false):
		return {"map": fallback(floor_number), "fallback": true, "seed": run_seed}
	return {"map": map, "fallback": false, "seed": run_seed}

static func _strings(cells: Array) -> Array:
	var map: Array = []
	for row: Array in cells:
		var line := ""
		for tile: String in row:
			line += tile
		map.append(line)
	return map

static func flood(map: Array, start: Vector2i) -> Dictionary:
	var distance: Dictionary = {start: 0}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		for direction: Vector2i in DIRS:
			var next := cell + direction
			if next.y < 0 or next.y >= map.size() or next.x < 0 or next.x >= String(map[next.y]).length():
				continue
			if map[next.y][next.x] == "#" or distance.has(next):
				continue
			distance[next] = int(distance[cell]) + 1
			queue.append(next)
	return distance

static func validate(map: Array) -> Dictionary:
	if map.size() < 5:
		return {"valid": false}
	var start := Vector2i(-1, -1)
	var exits: Array[Vector2i] = []
	var enemies: Array[Vector2i] = []
	var open_count := 0
	var starts := 0
	var width := String(map[0]).length()
	for y in map.size():
		if String(map[y]).length() != width:
			return {"valid": false}
		for x in width:
			var tile: String = map[y][x]
			if (x == 0 or y == 0 or x == width - 1 or y == map.size() - 1) and tile != "#":
				return {"valid": false}
			if tile != "#":
				open_count += 1
			if tile == "@":
				start = Vector2i(x, y)
				starts += 1
			elif tile == ">":
				exits.append(Vector2i(x, y))
			elif tile in ["E", "T"]:
				enemies.append(Vector2i(x, y))
	if starts != 1 or exits.size() != 1 or enemies.is_empty():
		return {"valid": false}
	var reached := flood(map, start)
	if reached.size() != open_count or not reached.has(exits[0]):
		return {"valid": false}
	for cell in enemies:
		if int(reached.get(cell, 0)) < 6:
			return {"valid": false}
	return {"valid": true, "reachable": reached.size(), "enemies": enemies.size(), "spawn": start, "exit": exits[0]}

static func fallback(floor_number: int) -> Array:
	var map: Array = [
		"###############",
		"#@            #",
		"#             #",
		"#      E      #",
		"#             #",
		"#   +     T   #",
		"#             #",
		"#      E     >#",
		"###############",
	]
	if floor_number > 1:
		map[2] = "#         E   #"
	if floor_number > 2:
		map[6] = "#          T  #"
	return map
