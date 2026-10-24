extends Node2D
## Afterward - "One Shift" prototype.
## Everything is built and drawn in code so the project has no asset dependencies.
## Loop: Dawn -> Hero's passage (watch / hide) -> Shift (clean, loot, change) -> Inspection -> Dream/reset.

enum Phase { DAWN, PASSAGE, SHIFT, INSPECTION, DREAM, ENDING }

const ROOM := Rect2(20, 60, 840, 640)
const PANEL_X := 885.0
const SHIFT_ACTIONS := 8
const MAX_LOOPS := 10
const FRAGMENTS_NEEDED := 3
const PELL_SPEED := 230.0
const HERO_SPEED := 170.0
const REACH := 56.0
const PELL_R := 13.0
const DOORWAY_X := 680.0
const SIGHT := 300.0
const GRUB_SPAWN := Vector2(650, 480)
const HERO_START := Vector2(14, 400)
const ACT_NAMES := ["Village", "Forest", "Mines", "Capital", "Tower"]

## [name, kind, power] per Hero act. Better act = better leftovers.
const LOOT := {
	1: [["Rusty Sword", "gear", 3], ["Cloth Armour", "gear", 3], ["Stale Bread", "gift", 1], ["Minor Potion", "consumable", 1]],
	2: [["Short Bow", "gear", 5], ["Leather Armour", "gear", 6], ["Herb Kit", "consumable", 2], ["Wildflowers", "gift", 2]],
	3: [["Iron Sword", "gear", 8], ["Steel Helm", "gear", 8], ["Lantern", "tool", 3], ["Old Relic", "curio", 4]],
	4: [["Fine Cloak", "gear", 10], ["Forged Papers", "tool", 5], ["Enchanted Ring", "gear", 12], ["Gold Chocolate", "gift", 4]],
	5: [["Legendary Plate", "gear", 16], ["Dark Lord's Charm", "gear", 18], ["Hero's Spare Blade", "gear", 15], ["Rose of the Tower", "gift", 6]],
}

# ---- Persistent across resets (the "memory" side of the game) ----
var phase: int = Phase.DAWN
var loop_no: int = 1
var journal: Dictionary = {}   # id -> {text, loop}
var fragments: int = 0
var found: Dictionary = {}     # fragment sources already used
var stash: Array = []
var lean: Dictionary = {"control": 0, "defiance": 0, "compassion": 0, "charm": 0}
var hero: Dictionary = {"greed": 60, "violence": 50, "mercy": 20, "awareness": 0.0}
var suspicion: int = 20

# ---- Reset every loop ----
var objs: Dictionary = {}
var floor_items: Array = []
var satchel: Array = []
var coin: int = 0
var actions: int = 0
var orders: Dictionary = {}
var pell: Vector2 = Vector2.ZERO
var in_cart: bool = false
var cur_room: String = "inn"
var hero_room: String = "inn"
var hero_pos: Vector2 = Vector2(-100, -100)
var hero_steps: Array = []
var hero_i: int = 0
var hero_t: float = 0.0
var hero_started: bool = false
var bark_text: String = ""
var bark_time: float = 0.0
var msgs: Array = []
var learned_this_loop: Array = []
var report: Array = []
var dream_lines: Array = []
var bribed: bool = false

# ---- UI state ----
var menu: String = ""
var show_journal: bool = false
var show_debug: bool = false
var font: Font = ThemeDB.fallback_font
var cv: CanvasItem
var shapes_on: bool = true
var text_on: bool = true
var ui_overlay: Node2D
const PIXEL_SIZE := 4.0


func _ready() -> void:
	randomize()
	cv = self
	setup_pixel_layers()
	reset_world()
	say("I wake up. Again. This time I remember yesterday.")


# =========================================================== setup

func setup_pixel_layers() -> void:
	# Layer 1: pixelate everything drawn by this node (the world), left of the side panel.
	var pix_layer: CanvasLayer = CanvasLayer.new()
	pix_layer.layer = 1
	add_child(pix_layer)
	var shader: Shader = Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float px = 3.0;
uniform float levels = 7.0;
void fragment() {
	vec2 logical = vec2(1280.0, 720.0);
	vec2 uv = (floor(SCREEN_UV * logical / px) + 0.5) * px / logical;
	vec3 c = texture(screen_tex, uv).rgb;
	COLOR = vec4(floor(c * levels + 0.5) / levels, 1.0);
}
"""
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("px", PIXEL_SIZE)
	var rect: ColorRect = ColorRect.new()
	rect.position = Vector2.ZERO
	rect.size = Vector2(PANEL_X - 13.0, 720.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	pix_layer.add_child(rect)
	# Layer 2: crisp text/UI on top.
	var ui_layer: CanvasLayer = CanvasLayer.new()
	ui_layer.layer = 2
	add_child(ui_layer)
	ui_overlay = Node2D.new()
	ui_overlay.set_script(load("res://scripts/overlay.gd"))
	ui_overlay.main = self
	ui_layer.add_child(ui_overlay)


func tier() -> int:
	return mini(5, 1 + floori((loop_no - 1) / 2.0))


func make_item(data: Array, guild: bool = false) -> Dictionary:
	return {"name": data[0], "kind": data[1], "power": data[2], "guild": guild}


func random_loot(kind_filter: String = "") -> Dictionary:
	var pool: Array = LOOT[tier()]
	if kind_filter != "":
		var filtered: Array = pool.filter(func(d: Array) -> bool: return d[1] == kind_filter)
		if not filtered.is_empty():
			pool = filtered
	return make_item(pool.pick_random())


func junk_item() -> Dictionary:
	return {"name": "Scrap of Cloth", "kind": "junk", "power": 0, "guild": false}


func solid_size(type: String) -> Vector2:
	match type:
		"pot":
			return Vector2(36, 36)
		"chest":
			return Vector2(56, 36)
		"barrel":
			return Vector2(40, 52)
		"table":
			return Vector2(68, 44)
		"board":
			return Vector2(40, 80)
		"cart":
			return Vector2(60, 36)
		"grub":
			return Vector2(30, 30)
	return Vector2.ZERO


func add_obj(id: String, type: String, pos: Vector2, state: String, room: String = "inn", size: Vector2 = Vector2.ZERO) -> void:
	objs[id] = {"id": id, "type": type, "pos": pos, "spawn": pos, "state": state, "item": null, "took": false, "gap": false, "room": room, "size": size if size != Vector2.ZERO else solid_size(type)}


func reset_world() -> void:
	objs = {}
	floor_items = []
	orders = {}
	satchel = []
	coin = 0
	bribed = false
	learned_this_loop = []
	in_cart = false
	cur_room = "inn"
	hero_room = "inn"
	hero_pos = Vector2(-100, -100)
	pell = Vector2(110, 650)
	var xs: Array = [230, 380, 540, 700]
	for i in 4:
		add_obj("pot%d" % i, "pot", Vector2(xs[i], 110), "full")
	add_obj("chestA", "chest", Vector2(120, 560), "closed")
	add_obj("chestB", "chest", Vector2(780, 590), "closed")
	objs["chestA"].item = random_loot("consumable")
	objs["chestB"].item = random_loot("gear")
	objs["chestB"].item.guild = true
	add_obj("door", "door", Vector2(36, 400), "ok")
	add_obj("grub", "grub", GRUB_SPAWN, "ok")
	add_obj("board", "board", Vector2(60, 220), "empty")
	add_obj("barrel", "barrel", Vector2(825, 200), "ok")
	add_obj("table", "table", Vector2(430, 340), "empty")
	add_obj("seam", "seam", Vector2(450, 684), "ok")
	add_obj("cart", "cart", Vector2(400, 520), "ok")
	# Kitchen
	add_obj("kpot0", "pot", Vector2(200, 130), "full", "kitchen")
	add_obj("kpot1", "pot", Vector2(330, 130), "full", "kitchen")
	add_obj("chestC", "chest", Vector2(140, 520), "closed", "kitchen")
	objs["chestC"].item = random_loot("gift")
	objs["chestC"].item.guild = true
	add_obj("counter", "counter", Vector2(520, 220), "ok", "kitchen", Vector2(280, 36))
	add_obj("stove", "stove", Vector2(790, 130), "ok", "kitchen", Vector2(90, 70))
	add_obj("ktable", "ktable", Vector2(480, 440), "ok", "kitchen", Vector2(170, 90))


func stash_power() -> int:
	var p: int = 0
	for it in stash:
		if it.kind == "gear":
			p += int(it.power)
	return p


func satchel_size() -> int:
	return 4 + mini(4, floori(stash_power() / 6.0))


func stash_capacity() -> int:
	return 2 + memory_depth()


func memory_depth() -> int:
	return 1 + fragments


func awareness_state() -> String:
	var a: float = hero.awareness
	if a < 25.0:
		return "Oblivious"
	if a < 60.0:
		return "Curious"
	if a < 100.0:
		return "Suspicious"
	return "Engaged"


func suspicion_state() -> String:
	if suspicion >= 80:
		return "RAIDED"
	if suspicion >= 40:
		return "Watched"
	return "Fine"


# =========================================================== helpers

func say(t: String) -> void:
	msgs.append(t)
	while msgs.size() > 7:
		msgs.pop_front()


func bark(t: String) -> void:
	bark_text = t
	bark_time = 2.2


func add_fact(id: String, text: String) -> void:
	if journal.has(id):
		return
	journal[id] = {"text": text, "loop": loop_no}
	learned_this_loop.append(text)
	say("Journal: " + text)


func witness(id: String, text: String) -> void:
	if hero_room == cur_room and pell.distance_to(hero_pos) <= SIGHT:
		add_fact(id, text)


func gain_fragment(source: String, fact_id: String, text: String) -> void:
	found[source] = true
	fragments += 1
	add_fact(fact_id, text)
	say("MEMORY FRAGMENT! Memory Depth is now %d." % memory_depth())


func lean_up(k: String, n: int) -> void:
	lean[k] = mini(100, lean[k] + n)


func drop_item(item: Dictionary, pos: Vector2, room: String) -> void:
	floor_items.append({"item": item, "pos": pos, "room": room})


func spend(n: int) -> bool:
	if actions < n:
		say("No time left for that. Bramm is coming.")
		return false
	actions -= n
	return true


func complete_order(id: String) -> void:
	if orders.has(id):
		orders[id].done = true


func add_to_satchel(item: Dictionary) -> bool:
	if satchel.size() >= satchel_size():
		say("Satchel is full. Stash something or let it go.")
		return false
	satchel.append(item)
	return true


func dominant_lean(skip: String = "") -> String:
	var best: String = ""
	var best_v: int = -1
	for k in lean:
		if k != skip and lean[k] > best_v:
			best = k
			best_v = lean[k]
	return best


# =========================================================== phase flow

func begin_passage() -> void:
	phase = Phase.PASSAGE
	hero_pos = HERO_START
	hero_room = "inn"
	hero_steps = build_hero_script()
	hero_i = 0
	hero_t = 0.0
	hero_started = false
	say("The Hero is coming. Stay close enough to learn, far enough not to be seen.")


func end_passage() -> void:
	phase = Phase.SHIFT
	hero_pos = Vector2(-100, -100)
	hero_room = "inn"
	in_cart = false
	actions = SHIFT_ACTIONS
	if suspicion >= 40:
		actions -= 2
		say("Watched: a Supervisor shadows you. Fewer actions this shift.")
	if hero.awareness >= 60.0:
		actions -= 1
		say("The Hero is suspicious of you. You feel eyes on your back.")
	actions = maxi(4, actions)
	orders = {}
	for id in objs:
		var o: Dictionary = objs[id]
		match o.type:
			"pot":
				if o.state == "broken":
					orders[id] = {"label": "Restock pot", "done": false}
			"chest":
				if o.state == "open":
					orders[id] = {"label": "Restock chest", "done": false}
			"door":
				if o.state == "broken":
					orders[id] = {"label": "Repair front door", "done": false}
			"grub":
				if o.state == "out":
					orders[id] = {"label": "Return Grub to spawn", "done": false}
			"board":
				orders[id] = {"label": "Pin tomorrow's quest", "done": false}
	say("Shift begins. %d work orders, %d actions. Something has to give." % [orders.size(), actions])


func end_shift() -> void:
	phase = Phase.INSPECTION
	menu = ""
	var done: int = 0
	for id in orders:
		if orders[id].done:
			done += 1
	var total: int = orders.size()
	var dil: float = 1.0 if total == 0 else float(done) / float(total)
	var gaps: int = 0
	for id in objs:
		if objs[id].type == "chest" and objs[id].gap:
			gaps += 1
	report = []
	report.append("Supervisor Bramm inspects your areas.")
	report.append("Work orders done: %d / %d  (Diligence %d%%)" % [done, total, int(dil * 100.0)])
	var delta: int = 0
	if dil < 0.5:
		delta += 25
		report.append("Half the room is still a mess.  Suspicion +25")
	elif dil < 0.8:
		delta += 10
		report.append("\"Could be tidier.\"  Suspicion +10")
	else:
		delta -= 8
		report.append("\"Good work, Pell.\"  Suspicion -8")
	if gaps > 0:
		delta += 15 * gaps
		report.append("Bramm frowns at an empty chest.  Suspicion +%d" % (15 * gaps))
	var wage: int = int(round(dil * 30.0))
	coin += wage
	report.append("Wage: %d coin. (Coin is lost on reset - spend it, or it's gone.)" % wage)
	suspicion = clampi(suspicion + delta, 0, 100)
	if suspicion >= 80:
		report.append("RAID! Inquisitors search the Seam.")
		if stash.size() > 0:
			var names: Array = stash.map(func(it: Dictionary) -> String: return it.name)
			report.append("Confiscated: " + ", ".join(names))
			stash = []
		else:
			report.append("They find nothing. Your stash was empty.")
		suspicion = 40
	report.append("")
	report.append("[B] Bribe Bramm (20 coin, Suspicion -15)     [Enter] Sleep")


func bribe() -> void:
	if bribed:
		return
	if coin < 20:
		say("Not enough coin.")
		return
	coin -= 20
	bribed = true
	suspicion = maxi(0, suspicion - 15)
	lean_up("control", 5)
	report.append("You slip Bramm 20 coin. Suspicion -15. (Control rises.)")


func begin_dream() -> void:
	phase = Phase.DREAM
	dream_lines = []
	dream_lines.append("The world rewinds.")
	dream_lines.append("")
	var lost: Array = []
	for it in satchel:
		lost.append(it.name)
	if coin > 0:
		lost.append("%d coin" % coin)
	if lost.is_empty():
		dream_lines.append("Nothing on your person to lose.")
	else:
		dream_lines.append("Lost in the reset: " + ", ".join(lost))
	if stash.is_empty():
		dream_lines.append("Your stash is empty. Hint: whatever is in the Seam survives.")
	else:
		var kept: Array = stash.map(func(it: Dictionary) -> String: return it.name)
		dream_lines.append("Kept in the Seam: " + ", ".join(kept))
	dream_lines.append("")
	if learned_this_loop.is_empty():
		dream_lines.append("No new memories settle this time.")
	else:
		dream_lines.append("New memories settle:")
		for t in learned_this_loop:
			dream_lines.append("  - " + t)
	dream_lines.append("")
	dream_lines.append("[Enter] Wake up")


func finish_dream() -> void:
	hero.awareness = maxf(0.0, hero.awareness - 15.0)
	if fragments >= FRAGMENTS_NEEDED or loop_no >= MAX_LOOPS:
		phase = Phase.ENDING
		return
	loop_no += 1
	reset_world()
	phase = Phase.DAWN
	msgs = []
	say("Dawn. Loop %d. The inn smells of last night's stew." % loop_no)


# =========================================================== Hero script + AI

func step_move(p: Vector2) -> Dictionary:
	return {"k": "move", "p": p}


func step_act(a: String, id: String, t: float) -> Dictionary:
	return {"k": "act", "a": a, "o": id, "t": t}


func build_hero_script() -> Array:
	var s: Array = []
	s.append(step_move(Vector2(90, 400)))
	s.append(step_act("kick_door", "door", 0.9))
	if objs["table"].state == "gift":
		s.append(step_move(Vector2(430, 400)))
		s.append(step_act("eat_gift", "table", 1.4))
	if objs["board"].state == "kind" or objs["board"].state == "quest":
		s.append(step_move(Vector2(115, 230)))
		s.append(step_act("read_note", "board", 1.4))
	var order: Array = [0, 1, 2, 3]
	order.shuffle()
	for i in order:
		var o: Dictionary = objs["pot%d" % i]
		s.append(step_move(o.pos + Vector2(0, 55)))
		s.append(step_act("pot", o.id, 0.7))
	s.append(step_move(Vector2(775, 205)))
	s.append(step_act("barrel", "barrel", 1.0))
	s.append(step_move(Vector2(DOORWAY_X, 690)))
	s.append({"k": "warp", "room": "kitchen", "p": Vector2(DOORWAY_X, 95)})
	for kid in ["kpot0", "kpot1"]:
		s.append(step_move(objs[kid].pos + Vector2(0, 55)))
		s.append(step_act("pot", kid, 0.7))
	s.append(step_move(Vector2(200, 520)))
	s.append(step_act("chestC", "chestC", 1.2))
	s.append(step_move(Vector2(DOORWAY_X, 70)))
	s.append({"k": "warp", "room": "inn", "p": Vector2(DOORWAY_X, 665)})
	s.append(step_move(Vector2(165, 560)))
	s.append(step_act("chestA", "chestA", 1.2))
	s.append(step_move(Vector2(735, 590)))
	s.append(step_act("chestB", "chestB", 1.2))
	s.append(step_move(GRUB_SPAWN + Vector2(-40, 0)))
	s.append(step_act("grub", "grub", 1.0))
	s.append(step_move(Vector2(920, 420)))
	return s


func update_hero(dt: float) -> void:
	if hero_i >= hero_steps.size():
		end_passage()
		return
	var st: Dictionary = hero_steps[hero_i]
	if st.k == "warp":
		hero_room = st.room
		hero_pos = st.p
		hero_i += 1
		return
	if st.k == "move":
		var d: Vector2 = st.p - hero_pos
		var stp: float = HERO_SPEED * dt
		if d.length() <= stp:
			hero_pos = st.p
			hero_i += 1
		else:
			hero_pos += d.normalized() * stp
	else:
		if not hero_started:
			hero_started = true
			hero_do(st.a, objs[st.o])
		hero_t += dt
		if hero_t >= st.t:
			hero_t = 0.0
			hero_started = false
			hero_i += 1
	# Being near the Hero in plain sight raises Awareness.
	if not in_cart and hero_room == cur_room and pell.distance_to(hero_pos) < 110.0:
		hero.awareness = minf(100.0, hero.awareness + 14.0 * dt)


func hero_do(a: String, o: Dictionary) -> void:
	match a:
		"kick_door":
			o.state = "broken"
			bark("Locked? Pfft. *CRASH*")
			witness("hero_door", "The Hero kicks down doors that were never locked. (I unlocked it.)")
		"eat_gift":
			o.state = "eaten"
			hero.mercy = mini(100, hero.mercy + 4)
			hero.greed = maxi(0, hero.greed - 3)
			hero.awareness = minf(100.0, hero.awareness + 8.0)
			bark("Bread? Who left this here?")
			witness("hero_gift", "The Hero is a sucker for free bread. A gift softens him.")
		"read_note":
			if objs["board"].state == "kind":
				hero.mercy = mini(100, hero.mercy + 6)
				hero.greed = maxi(0, hero.greed - 5)
				bark("'Please be gentle with the pots.' ...Huh. Fine.")
			else:
				bark("A new quest! Obviously I'll do it.")
			witness("hero_board", "The Hero always reads the notice board, and does what it says.")
		"pot":
			var chance: float = clampf(0.35 + (hero.greed - hero.mercy * 0.5) / 100.0, 0.15, 0.95)
			if randf() < chance:
				o.state = "broken"
				bark("*SMASH*  Loot?")
				witness("hero_pots", "The Hero smashes every pot he walks past.")
				if randf() < 0.5:
					drop_item({"name": "Coin", "kind": "coin", "power": 5, "guild": false}, o.pos + Vector2(randi_range(-25, 25), 35), o.room)
				elif randf() < 0.5:
					drop_item(random_loot("gift" if randf() < 0.5 else "consumable"), o.pos + Vector2(randi_range(-25, 25), 35), o.room)
			else:
				bark("Nah. Leave it.")
		"barrel":
			o.state = "kicked"
			bark("Hm. Looks like there's something behind it. *KICK*")
			witness("hero_barrel", "Every Cycle the Hero kicks the corner barrel. A hairline crack glows behind it.")
		"chestA":
			o.state = "open"
			var taken: Dictionary = o.item
			o.item = null
			bark("Ooh, a %s! Time to upgrade." % taken.name)
			witness("hero_chest", "The Hero empties the first chest and dumps his old gear on the floor.")
			drop_item(random_loot("gear"), o.pos + Vector2(55, -35), o.room)
			drop_item(junk_item(), o.pos + Vector2(70, 10), o.room)
			if loop_no >= 3 and not found.has("letter"):
				drop_item({"name": "Hero's Crumpled Letter", "kind": "knowledge", "power": 0, "guild": false}, o.pos + Vector2(20, -60), o.room)
		"chestC":
			o.state = "open"
			bark("Not hungry. Pantry food is for NPCs.")
			witness("hero_pantry", "The Hero skips the pantry chest in the kitchen. Food is for people without quests.")
		"chestB":
			o.state = "open"
			bark("Bag's full. I'll come back. (He never does.)")
			witness("hero_chest_skip", "The Hero's bag is full by the second chest. He always leaves it unlooted.")
		"grub":
			if objs["board"].state == "kind" or randf() * 100.0 < hero.mercy:
				bark("Sorry, little guy. Off you go.")
			else:
				o.state = "out"
				o.pos = o.spawn + Vector2(-70, -70)
				bark("Goblin! *WHACK*")
				witness("hero_grub", "The Hero clobbers Grub on sight. Grub is out cold until someone drags him back.")
				drop_item({"name": "Coin", "kind": "coin", "power": 5, "guild": false}, o.pos + Vector2(30, 20), o.room)


# =========================================================== interaction

func reach_list() -> Array:
	## Everything Pell can currently interact with, nearest first.
	var out: Array = []
	for id in objs:
		var o: Dictionary = objs[id]
		if o.room != cur_room or o.type in ["counter", "stove", "ktable"]:
			continue
		var d: float = pell.distance_to(o.pos)
		if d <= REACH + (30.0 if o.type == "board" else 0.0):
			out.append({"d": d, "kind": "obj", "ref": o})
	for fi in floor_items:
		if fi.room != cur_room:
			continue
		var d2: float = pell.distance_to(fi.pos)
		if d2 <= REACH:
			out.append({"d": d2 - 20.0, "kind": "floor", "ref": fi})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	return out


func labels(t: Dictionary) -> Array:
	## [E label, F label] for the thing at hand; "" = not available.
	if t.kind == "floor":
		return ["Pick up " + t.ref.item.name, ""]
	var o: Dictionary = t.ref
	if phase == Phase.PASSAGE:
		return [("Leave the cart" if in_cart else "Hide in the cart"), ""] if o.type == "cart" else ["", ""]
	match o.type:
		"pot":
			return ["Restock pot (1 action)", ""] if o.state == "broken" else ["", ""]
		"chest":
			if o.state == "open" and o.item != null:
				return ["Take %s (free - but leaves a gap)" % o.item.name, "Close chest as-is (1 action)"]
			if o.state == "open":
				return ["Close and restock chest (1 action)", ""]
			return ["", ""]
		"door":
			return ["Repair door (1 action)", ""] if o.state == "broken" else ["", ""]
		"grub":
			if o.state == "out":
				return ["Drag Grub back to spawn (1 action)", "Talk to groggy Grub (1 action)"]
			return ["", ""]
		"board":
			return ["Pin standard quest (1 action)", "Write your own note (1 action)"]
		"table":
			return ["Leave a gift for the Hero (1 action)", ""] if o.state == "empty" else ["", ""]
		"barrel":
			return ["Search behind barrel (1 action)", ""] if o.state == "kicked" else ["", ""]
		"seam":
			return ["Open the Seam (stash)", ""]
	return ["", ""]


func interact(alt: bool) -> void:
	var list: Array = reach_list()
	if list.is_empty():
		return
	for t in list:
		var lb: Array = labels(t)
		if lb[1 if alt else 0] == "":
			continue
		do_interact(t, alt)
		return


func do_interact(t: Dictionary, alt: bool) -> void:
	if t.kind == "floor":
		var fi: Dictionary = t.ref
		var it: Dictionary = fi.item
		if it.kind == "coin":
			coin += int(it.power)
			floor_items.erase(fi)
			say("+%d coin." % int(it.power))
		elif add_to_satchel(it):
			floor_items.erase(fi)
			say("Picked up %s." % it.name)
		return
	var o: Dictionary = t.ref
	if phase == Phase.PASSAGE:
		if o.type == "cart":
			in_cart = not in_cart
			if in_cart:
				pell = o.pos + Vector2(0, 42)
				say("You duck into the cart. Nobody looks at a cleaning cart.")
		return
	match o.type:
		"pot":
			if spend(1):
				o.state = "full"
				complete_order(o.id)
				say("Pot restocked.")
		"chest":
			if not alt and o.item != null:
				if add_to_satchel(o.item):
					say("Pocketed the %s. The chest looks suspiciously empty." % o.item.name)
					o.item = null
					o.took = true
					lean_up("defiance", 5)
			elif alt or o.item == null:
				if spend(1):
					o.state = "closed"
					complete_order(o.id)
					if o.took:
						var idx: int = -1
						for i in satchel.size():
							if satchel[i].kind == "junk":
								idx = i
								break
						if idx >= 0:
							satchel.remove_at(idx)
							say("You slip a Scrap of Cloth in as a 'fake'. Bramm won't notice. Probably.")
							lean_up("defiance", 3)
						else:
							o.gap = true
							say("Closed an empty chest. Bramm will notice that.")
					else:
						say("Chest restocked by the Guild.")
		"door":
			if spend(1):
				o.state = "ok"
				complete_order(o.id)
				lean_up("compassion", 3)
				say("Door repaired. The Innkeeper will never know it was broken.")
		"grub":
			if not alt:
				if spend(1):
					o.state = "ok"
					o.pos = o.spawn
					complete_order(o.id)
					lean_up("compassion", 2)
					say("Grub dragged home. He doesn't remember a thing. Probably.")
			else:
				if spend(1):
					talk_to_grub()
		"board":
			if not alt:
				if spend(1):
					o.state = "standard"
					complete_order(o.id)
					say("Pinned: 'Wanted: 10 wolf pelts.' The usual.")
			else:
				menu = "note"
		"table":
			var idx2: int = -1
			for i in satchel.size():
				if satchel[i].kind == "gift":
					idx2 = i
					break
			if idx2 < 0:
				say("I have nothing to give. (Gifts: bread, flowers, chocolate - the Hero's own leftovers, polished.)")
			elif spend(1):
				var g: Dictionary = satchel[idx2]
				satchel.remove_at(idx2)
				o.state = "gift"
				lean_up("charm", 6)
				say("You leave the %s on the table with a tidy little bow." % g.name)
		"barrel":
			if found.has("barrel"):
				say("Nothing more behind the barrel.")
			elif journal.has("hero_barrel"):
				if spend(1):
					gain_fragment("barrel", "frag_barrel", "Behind the barrel: scratched into the wall, in my own handwriting - 'Don't trust the Founder.'")
			else:
				say("A dusty crack. If only I knew why he keeps kicking this thing...")
		"seam":
			menu = "stash"


func talk_to_grub() -> void:
	lean_up("compassion", 4)
	if not journal.has("grub_memory"):
		add_fact("grub_memory", "Grub: 'Every morning I wake up, and every morning I forget a bad dream.' Revived monsters keep a trace of memory.")
		say("Grub mumbles something odd. He looks sad. Come back and ask again.")
	elif journal[("grub_memory")].loop < loop_no and not found.has("grub"):
		gain_fragment("grub", "frag_grub", "Grub: 'A mad old woman, Wenna, used to count the resets on the wall. Like you.'")
	else:
		say("Grub snores softly.")


func use_item(i: int) -> void:
	if i >= satchel.size():
		return
	var it: Dictionary = satchel[i]
	match it.kind:
		"knowledge":
			satchel.remove_at(i)
			gain_fragment("letter", "frag_letter", "The Hero's letter: 'Dear Hero, the Cycle was never your fault. Find the one who sweeps.'")
		"consumable":
			satchel.remove_at(i)
			actions += 1
			say("Ate/used the %s. +1 action." % it.name)
		_:
			say("%s: not much I can do with that here. Stash it?" % it.name)


# =========================================================== input

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.keycode
	if k == KEY_TAB:
		show_journal = not show_journal
		return
	if k == KEY_F1:
		show_debug = not show_debug
		return
	if show_journal:
		if k == KEY_ESCAPE:
			show_journal = false
		return
	if menu == "stash":
		handle_stash_key(k)
		return
	if menu == "note":
		handle_note_key(k)
		return
	var enter: bool = (k == KEY_ENTER or k == KEY_KP_ENTER)
	match phase:
		Phase.DAWN:
			if enter:
				begin_passage()
			elif k == KEY_E:
				menu = ""
		Phase.PASSAGE:
			if k == KEY_E:
				interact(false)
		Phase.SHIFT:
			if enter:
				end_shift()
			elif k == KEY_E:
				interact(false)
			elif k == KEY_F:
				interact(true)
			elif k >= KEY_1 and k <= KEY_8:
				use_item(k - KEY_1)
		Phase.INSPECTION:
			if enter:
				begin_dream()
			elif k == KEY_B:
				bribe()
		Phase.DREAM:
			if enter:
				finish_dream()
		Phase.ENDING:
			if enter:
				get_tree().reload_current_scene()


func handle_stash_key(k: int) -> void:
	if k == KEY_ESCAPE or k == KEY_ENTER:
		menu = ""
		return
	if k >= KEY_1 and k <= KEY_8:
		var i: int = k - KEY_1
		if i < satchel.size():
			if stash.size() >= stash_capacity():
				say("The Seam is full (%d). Take something out first." % stash_capacity())
			else:
				var it: Dictionary = satchel[i]
				satchel.remove_at(i)
				stash.append(it)
				say("%s tucked into the Seam. It will survive the reset." % it.name)
		return
	var keys: Array = [KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_Y]
	var j: int = keys.find(k)
	if j >= 0 and j < stash.size():
		if satchel.size() >= satchel_size():
			say("Satchel is full.")
		else:
			var it2: Dictionary = stash[j]
			stash.remove_at(j)
			satchel.append(it2)
			say("Took %s out of the Seam." % it2.name)


func handle_note_key(k: int) -> void:
	if k == KEY_ESCAPE:
		menu = ""
		return
	var b: Dictionary = objs["board"]
	if k == KEY_1 or k == KEY_2:
		if not spend(1):
			menu = ""
			return
		if k == KEY_1:
			b.state = "kind"
			lean_up("compassion", 6)
			say("You pin: 'Please be gentle with the pots. They have feelings.'")
		else:
			b.state = "quest"
			lean_up("control", 6)
			say("You pin: 'URGENT: A wolf in the forest. Go now.' Quest forged.")
		complete_order("board")
		menu = ""


func blocked(p: Vector2) -> bool:
	## Solid furniture, chests, pots etc. cannot be walked over.
	for id in objs:
		var o: Dictionary = objs[id]
		if o.room == cur_room and o.size.x > 0.0:
			if Rect2(o.pos - o.size / 2.0, o.size).grow(PELL_R).has_point(p):
				return true
	return false


func move_pell(step: Vector2) -> void:
	var stuck: bool = blocked(pell)  # never trap Pell if something moved onto them
	var np: Vector2 = pell + Vector2(step.x, 0)
	np.x = clampf(np.x, ROOM.position.x + 12.0, ROOM.end.x - 12.0)
	if stuck or not blocked(np):
		pell = np
	np = pell + Vector2(0, step.y)
	np.y = clampf(np.y, ROOM.position.y + 12.0, ROOM.end.y - 12.0)
	if stuck or not blocked(np):
		pell = np


func check_doorways() -> void:
	if cur_room == "inn" and pell.y >= ROOM.end.y - 16.0 and absf(pell.x - DOORWAY_X) < 45.0:
		cur_room = "kitchen"
		pell = Vector2(DOORWAY_X, ROOM.position.y + 45.0)
	elif cur_room == "kitchen" and pell.y <= ROOM.position.y + 16.0 and absf(pell.x - DOORWAY_X) < 45.0:
		cur_room = "inn"
		pell = Vector2(DOORWAY_X, ROOM.end.y - 45.0)


func _process(delta: float) -> void:
	if phase == Phase.PASSAGE or phase == Phase.SHIFT or phase == Phase.DAWN:
		if menu == "" and not show_journal and not in_cart:
			var v: Vector2 = Vector2.ZERO
			if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
				v.y -= 1
			if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
				v.y += 1
			if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
				v.x -= 1
			if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
				v.x += 1
			if phase != Phase.DAWN:
				move_pell(v.normalized() * PELL_SPEED * delta)
				check_doorways()
	if phase == Phase.PASSAGE and menu == "" and not show_journal:
		var hdt: float = delta * (3.0 if Input.is_physical_key_pressed(KEY_SPACE) else 1.0)
		update_hero(hdt)
	if bark_time > 0.0:
		bark_time -= delta
	queue_redraw()
	if ui_overlay != null:
		ui_overlay.queue_redraw()


# =========================================================== drawing

func d_rect(r: Rect2, c: Color, filled: bool = true, w: float = -1.0) -> void:
	if shapes_on:
		cv.draw_rect(r, c, filled, w)


func d_circle(p: Vector2, r: float, c: Color, filled: bool = true, w: float = -1.0) -> void:
	if shapes_on:
		cv.draw_circle(p, r, c, filled, w)


func d_line(a: Vector2, b: Vector2, c: Color, w: float = -1.0) -> void:
	if shapes_on:
		cv.draw_line(a, b, c, w)


func txt(pos: Vector2, s: String, size: int = 15, col: Color = Color(0.93, 0.9, 0.82)) -> void:
	if text_on:
		cv.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func para(pos: Vector2, s: String, width: float, size: int = 15, col: Color = Color(0.93, 0.9, 0.82)) -> void:
	if text_on:
		cv.draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, -1, col)


func box(r: Rect2, col: Color, border: Color = Color(0, 0, 0, 0)) -> void:
	d_rect(r, col, true)
	if border.a > 0.0:
		d_rect(r, border, false, 2.0)


func bar(pos: Vector2, w: float, frac: float, col: Color) -> void:
	box(Rect2(pos, Vector2(w, 12)), Color(0.18, 0.17, 0.2))
	box(Rect2(pos, Vector2(w * clampf(frac, 0.0, 1.0), 12)), col)


func _draw() -> void:
	## Pass 1 (this node): world shapes only. A shader on the layer above pixelates them.
	cv = self
	shapes_on = true
	text_on = false
	draw_world()


func draw_overlay(c: CanvasItem) -> void:
	## Pass 2 (crisp layer on top): world labels, HUD, panel and all screens.
	cv = c
	shapes_on = false
	text_on = true
	draw_world()
	shapes_on = true
	draw_world_hud()
	draw_panel()
	match phase:
		Phase.DAWN:
			draw_dawn()
		Phase.INSPECTION:
			draw_lines_screen("INSPECTION", report)
		Phase.DREAM:
			draw_lines_screen("REBIRTH", dream_lines)
		Phase.ENDING:
			draw_ending()
	if menu == "stash":
		draw_stash()
	elif menu == "note":
		draw_note_menu()
	if show_journal:
		draw_journal()


func draw_world() -> void:
	var inn: bool = cur_room == "inn"
	box(ROOM, Color(0.36, 0.27, 0.19) if inn else Color(0.42, 0.42, 0.45), Color(0.15, 0.1, 0.07))
	for i in range(1, 8):
		d_line(Vector2(ROOM.position.x, ROOM.position.y + i * 80), Vector2(ROOM.end.x, ROOM.position.y + i * 80), Color(0.3, 0.22, 0.15) if inn else Color(0.33, 0.33, 0.36), 1.0)
	txt(Vector2(30, 82), "THE SLEEPING STAG - INN" if inn else "INN KITCHEN", 13, Color(0.7, 0.6, 0.45))
	if inn:
		d_circle(GRUB_SPAWN, 26.0, Color(0.3, 0.22, 0.15))
		txt(GRUB_SPAWN + Vector2(-22, 44), "(spawn)", 11, Color(0.55, 0.45, 0.35))
		box(Rect2(ROOM.end.x - 8, 380, 10, 80), Color(0.2, 0.3, 0.2))
		txt(Vector2(ROOM.end.x - 52, 475), "to Forest", 11, Color(0.55, 0.7, 0.5))
		box(Rect2(DOORWAY_X - 45, ROOM.end.y - 6, 90, 8), Color(0.2, 0.3, 0.2))
		txt(Vector2(DOORWAY_X - 32, ROOM.end.y - 12), "Kitchen v", 11, Color(0.6, 0.8, 0.55))
	else:
		box(Rect2(DOORWAY_X - 45, ROOM.position.y - 2, 90, 8), Color(0.2, 0.3, 0.2))
		txt(Vector2(DOORWAY_X - 22, ROOM.position.y + 20), "Inn ^", 11, Color(0.6, 0.8, 0.55))
	for id in objs:
		if objs[id].room == cur_room:
			draw_obj(objs[id])
	for fi in floor_items:
		if fi.room == cur_room:
			draw_floor_item(fi)
	if phase == Phase.PASSAGE and hero_room == cur_room:
		d_circle(hero_pos, 17.0, Color(0.95, 0.8, 0.2))
		d_circle(hero_pos + Vector2(0, -22), 9.0, Color(0.98, 0.88, 0.7))
		txt(hero_pos + Vector2(-16, 36), "HERO", 11, Color(1, 0.9, 0.4))
	if not in_cart:
		d_circle(pell, 13.0, Color(0.3, 0.55, 0.85))
		d_line(pell + Vector2(10, 12), pell + Vector2(26, -14), Color(0.8, 0.65, 0.3), 3.0)
		txt(pell + Vector2(-9, 30), "Pell", 11, Color(0.6, 0.8, 1))


func draw_world_hud() -> void:
	## Crisp (non-pixelated) bits that sit on top of the world.
	if phase == Phase.PASSAGE and hero_room == cur_room and bark_time > 0.0:
		box(Rect2(hero_pos + Vector2(-8, -78), Vector2(font.get_string_size(bark_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 14, 24)), Color(1, 1, 1, 0.92))
		txt(hero_pos + Vector2(-1, -61), bark_text, 13, Color(0.1, 0.1, 0.1))
	if phase == Phase.SHIFT or phase == Phase.PASSAGE:
		var list: Array = reach_list()
		for t in list:
			var lb: Array = labels(t)
			if lb[0] != "" or lb[1] != "":
				var s: String = ""
				if lb[0] != "":
					s += "[E] " + lb[0]
				if lb[1] != "":
					s += "    [F] " + lb[1]
				box(Rect2(Vector2(30, 668), Vector2(820, 26)), Color(0, 0, 0, 0.7))
				txt(Vector2(38, 687), s, 15, Color(1, 0.95, 0.6))
				break
	if phase == Phase.PASSAGE:
		box(Rect2(Vector2(240, 66), Vector2(470, 24)), Color(0, 0, 0, 0.6))
		var where: String = "" if hero_room == cur_room else "  (Hero is in the %s)" % hero_room
		txt(Vector2(248, 84), "HERO'S PASSAGE - watch, hide. [Space] fast-forward" + where, 13)


func draw_obj(o: Dictionary) -> void:
	var p: Vector2 = o.pos
	match o.type:
		"pot":
			if o.state == "full":
				d_circle(p, 18.0, Color(0.65, 0.4, 0.25))
				d_circle(p + Vector2(0, -12), 10.0, Color(0.5, 0.3, 0.2))
			else:
				d_circle(p, 18.0, Color(0.25, 0.17, 0.12), false, 2.0)
				txt(p + Vector2(-14, 4), "x_x", 12, Color(0.7, 0.4, 0.3))
				if phase == Phase.SHIFT:
					txt(p + Vector2(-20, -24), "broken", 11, Color(0.9, 0.5, 0.4))
		"chest":
			var open: bool = o.state == "open"
			box(Rect2(p - Vector2(28, 18), Vector2(56, 36)), Color(0.5, 0.35, 0.15) if not open else Color(0.35, 0.25, 0.12), Color(0.2, 0.12, 0.05))
			if open:
				txt(p + Vector2(-26, -24), "open", 11, Color(0.9, 0.8, 0.5))
				if o.item != null:
					txt(p + Vector2(-34, 38), String(o.item.name), 11, Color(1, 0.9, 0.5))
			elif phase != Phase.SHIFT:
				txt(p + Vector2(-8, 5), "[]", 12)
			if o.gap:
				txt(p + Vector2(-20, 38), "GAP!", 12, Color(1, 0.4, 0.4))
		"door":
			box(Rect2(p - Vector2(8, 40), Vector2(16, 80)), Color(0.45, 0.3, 0.15) if o.state == "ok" else Color(0.25, 0.15, 0.1), Color(0.1, 0.06, 0.03))
			if o.state == "broken":
				txt(p + Vector2(-8, 58), "broken", 11, Color(0.9, 0.5, 0.4))
		"grub":
			var gc: Color = Color(0.4, 0.7, 0.3) if o.state == "ok" else Color(0.3, 0.45, 0.25)
			d_circle(p, 16.0, gc)
			txt(p + Vector2(-12, 5), "ò_ó" if o.state == "ok" else "x_x", 12, Color(0.1, 0.2, 0.05))
			txt(p + Vector2(-14, -22), "Grub" + (" (out cold)" if o.state == "out" else ""), 11, Color(0.7, 0.9, 0.6))
		"board":
			box(Rect2(p - Vector2(20, 40), Vector2(40, 80)), Color(0.5, 0.38, 0.22), Color(0.2, 0.13, 0.07))
			txt(p + Vector2(-17, -46), "NOTICES", 10, Color(0.8, 0.7, 0.5))
			if o.state != "empty":
				box(Rect2(p - Vector2(12, 20), Vector2(24, 30)), Color(0.95, 0.92, 0.8))
		"barrel":
			box(Rect2(p - Vector2(20, 26), Vector2(40, 52)), Color(0.45, 0.3, 0.15), Color(0.15, 0.1, 0.05))
			if o.state == "kicked":
				d_line(p + Vector2(34, -30), p + Vector2(30, 30), Color(0.6, 0.85, 1.0), 3.0)
				txt(p + Vector2(-30, 44), "crack", 11, Color(0.6, 0.85, 1.0))
		"table":
			box(Rect2(p - Vector2(34, 22), Vector2(68, 44)), Color(0.5, 0.35, 0.2), Color(0.2, 0.12, 0.05))
			txt(p + Vector2(-26, 5), "gift table" if o.state == "empty" else "gift!", 11, Color(0.9, 0.8, 0.6))
		"seam":
			d_line(p + Vector2(-60, 0), p + Vector2(60, 0), Color(0.6, 0.85, 1.0), 2.0)
			txt(p + Vector2(-26, -8), "THE SEAM", 11, Color(0.6, 0.85, 1.0))
		"counter", "stove", "ktable":
			box(Rect2(p - o.size / 2.0, o.size), Color(0.3, 0.3, 0.34), Color(0.12, 0.12, 0.14))
			txt(p + Vector2(-24, 4), String(o.type).to_upper(), 11, Color(0.75, 0.75, 0.8))
		"cart":
			box(Rect2(p - Vector2(30, 18), Vector2(60, 36)), Color(0.35, 0.4, 0.45), Color(0.15, 0.17, 0.2))
			txt(p + Vector2(-24, 5), "CART" if not in_cart else "(you)", 11, Color(0.8, 0.85, 0.9))


func draw_floor_item(fi: Dictionary) -> void:
	var it: Dictionary = fi.item
	var col: Color = Color(1, 0.85, 0.2) if it.kind == "coin" else Color(0.9, 0.9, 1.0)
	if it.kind == "knowledge":
		col = Color(0.7, 1.0, 0.8)
	d_rect(Rect2(fi.pos - Vector2(7, 7), Vector2(14, 14)), col, true)
	if pell.distance_to(fi.pos) < 120.0:
		txt(fi.pos + Vector2(-30, -12), String(it.name), 11, Color(1, 1, 1))


func draw_panel() -> void:
	box(Rect2(PANEL_X - 12, 0, 1280 - PANEL_X + 12, 720), Color(0.13, 0.12, 0.15))
	var x: float = PANEL_X
	var y: float = 30.0
	txt(Vector2(x, y), "AFTERWARD", 22, Color(0.95, 0.85, 0.5))
	y += 26.0
	var act_i: int = tier() - 1
	txt(Vector2(x, y), "Loop %d/%d   Hero Act %d: %s" % [loop_no, MAX_LOOPS, tier(), ACT_NAMES[act_i]], 14)
	y += 22.0
	txt(Vector2(x, y), "Memory Depth %d   Fragments %d/%d" % [memory_depth(), fragments, FRAGMENTS_NEEDED], 14, Color(0.6, 0.85, 1.0))
	y += 22.0
	txt(Vector2(x, y), "Actions left: %d     Coin: %d" % [actions, coin], 14)
	y += 24.0
	txt(Vector2(x, y), "Guild Suspicion: %d (%s)" % [suspicion, suspicion_state()], 13)
	y += 6.0
	bar(Vector2(x, y), 360.0, suspicion / 100.0, Color(0.85, 0.35, 0.3))
	y += 30.0
	if tier() >= 4 or show_debug:
		txt(Vector2(x, y), "Hero Awareness: %d (%s)" % [int(hero.awareness), awareness_state()], 13)
		y += 6.0
		bar(Vector2(x, y), 360.0, hero.awareness / 100.0, Color(0.9, 0.7, 0.25))
	else:
		txt(Vector2(x, y), "Hero Awareness: ??? (hidden until Act 4)", 13, Color(0.6, 0.6, 0.65))
		y += 6.0
		bar(Vector2(x, y), 360.0, 0.0, Color(0.9, 0.7, 0.25))
	y += 32.0
	txt(Vector2(x, y), "SATCHEL (%d/%d)   [1-8] use item" % [satchel.size(), satchel_size()], 14, Color(0.95, 0.85, 0.5))
	y += 20.0
	for i in satchel.size():
		var it: Dictionary = satchel[i]
		var tag: String = " (Guild property)" if it.guild else ""
		txt(Vector2(x + 6, y), "%d. %s [%s]%s" % [i + 1, it.name, it.kind, tag], 13)
		y += 18.0
	if satchel.is_empty():
		txt(Vector2(x + 6, y), "(empty)", 13, Color(0.6, 0.6, 0.65))
		y += 18.0
	y += 8.0
	txt(Vector2(x, y), "STASH (%d/%d) - survives reset" % [stash.size(), stash_capacity()], 14, Color(0.6, 0.85, 1.0))
	y += 20.0
	for it in stash:
		txt(Vector2(x + 6, y), "- %s" % it.name, 13, Color(0.7, 0.9, 1.0))
		y += 18.0
	y += 8.0
	txt(Vector2(x, y), "WORK ORDERS", 14, Color(0.95, 0.85, 0.5))
	y += 20.0
	if orders.is_empty():
		txt(Vector2(x + 6, y), "(issued when the Hero has passed)", 13, Color(0.6, 0.6, 0.65))
		y += 18.0
	for id in orders:
		var od: Dictionary = orders[id]
		txt(Vector2(x + 6, y), ("[x] " if od.done else "[ ] ") + od.label, 13, Color(0.5, 0.8, 0.5) if od.done else Color(0.93, 0.9, 0.82))
		y += 18.0
	y += 10.0
	var start: int = maxi(0, msgs.size() - 6)
	for i in range(start, msgs.size()):
		para(Vector2(x, y), String(msgs[i]), 365.0, 12, Color(0.75, 0.75, 0.8))
		y += 32.0 if String(msgs[i]).length() > 52 else 17.0
	txt(Vector2(x, 700), "WASD move  E/F act  Tab journal  Enter finish shift", 11, Color(0.55, 0.55, 0.6))
	if show_debug:
		txt(Vector2(x, 686), "Lean C%d D%d P%d L%d  Hero g%d v%d m%d" % [lean.control, lean.defiance, lean.compassion, lean.charm, hero.greed, hero.violence, hero.mercy], 11, Color(1, 0.6, 0.6))


func overlay(title: String) -> Rect2:
	var r: Rect2 = Rect2(150, 110, 600, 480)
	box(r, Color(0.08, 0.07, 0.1, 0.96), Color(0.8, 0.7, 0.4))
	txt(r.position + Vector2(24, 40), title, 24, Color(0.95, 0.85, 0.5))
	return r


func draw_lines_screen(title: String, lines: Array) -> void:
	var r: Rect2 = overlay(title)
	var y: float = r.position.y + 80.0
	for l in lines:
		para(Vector2(r.position.x + 24, y), String(l), 550.0, 15)
		y += 24.0 if String(l).length() < 62 else 42.0


func draw_dawn() -> void:
	var r: Rect2 = overlay("DAWN - Loop %d" % loop_no)
	var y: float = r.position.y + 80.0
	var lines: Array = [
		"The Guild dormitory. A broom, a bucket, a very low opinion of adventurers.",
		"",
		"Today the Hero is on Act %d (%s). Better act = better leftovers." % [tier(), ACT_NAMES[tier() - 1]],
		"",
		"PLAN:",
		"  1. Watch the Hero's passage. What he does is knowledge. [Tab] opens your Journal.",
		"  2. Then clean up the mess - there is never enough time for everything.",
		"  3. Hide anything worth keeping in the Seam (the glowing crack in the south wall).",
		"     Whatever is on your person is LOST at the reset. Coin too.",
		"  4. Collect %d Memory Fragments to remember everything." % FRAGMENTS_NEEDED,
		"",
		"Journal entries so far: %d     Stash: %d item(s)" % [journal.size(), stash.size()],
		"",
		"[Enter] Follow the Hero",
	]
	for l in lines:
		para(Vector2(r.position.x + 24, y), String(l), 550.0, 15)
		y += 26.0


func draw_stash() -> void:
	var r: Rect2 = overlay("THE SEAM")
	var y: float = r.position.y + 80.0
	txt(Vector2(r.position.x + 24, y), "Satchel - press number to stash   (%d/%d)" % [satchel.size(), satchel_size()], 15, Color(0.95, 0.85, 0.5))
	y += 26.0
	for i in satchel.size():
		txt(Vector2(r.position.x + 36, y), "%d. %s [%s]" % [i + 1, satchel[i].name, satchel[i].kind], 15)
		y += 22.0
	y += 14.0
	txt(Vector2(r.position.x + 24, y), "Seam - Q W E R T Y to take out   (%d/%d)" % [stash.size(), stash_capacity()], 15, Color(0.6, 0.85, 1.0))
	y += 26.0
	var keys: Array = ["Q", "W", "E", "R", "T", "Y"]
	for i in stash.size():
		txt(Vector2(r.position.x + 36, y), "%s. %s [%s, power %d]" % [keys[i], stash[i].name, stash[i].kind, stash[i].power], 15, Color(0.7, 0.9, 1.0))
		y += 22.0
	y += 14.0
	txt(Vector2(r.position.x + 24, y), "Gear in the Seam makes your satchel bigger (+1 slot per 6 power).", 13, Color(0.75, 0.75, 0.8))
	txt(Vector2(r.position.x + 24, r.end.y - 20), "[Esc] close", 13, Color(0.6, 0.6, 0.65))


func draw_note_menu() -> void:
	var r: Rect2 = overlay("WRITE A NOTE")
	var y: float = r.position.y + 90.0
	txt(Vector2(r.position.x + 24, y), "The Hero always reads the notice board.", 15)
	y += 40.0
	txt(Vector2(r.position.x + 24, y), "[1] 'Please be gentle with the pots. They have feelings.'   (Compassion)", 15, Color(0.6, 0.9, 0.6))
	y += 30.0
	txt(Vector2(r.position.x + 24, y), "[2] 'URGENT: wolf in the forest. Go now.'   (Control)", 15, Color(0.9, 0.7, 0.5))
	txt(Vector2(r.position.x + 24, r.end.y - 20), "[Esc] cancel   (costs 1 action; replaces the standard notice)", 13, Color(0.6, 0.6, 0.65))


func draw_journal() -> void:
	var r: Rect2 = overlay("PELL'S MEMORY JOURNAL")
	var y: float = r.position.y + 76.0
	txt(Vector2(r.position.x + 24, y), "Memory Depth %d - Fragments %d/%d" % [memory_depth(), fragments, FRAGMENTS_NEEDED], 14, Color(0.6, 0.85, 1.0))
	y += 28.0
	if journal.is_empty():
		txt(Vector2(r.position.x + 24, y), "Nothing yet. Watch the Hero. Everything he does is knowledge.", 14, Color(0.7, 0.7, 0.75))
	for id in journal:
		var e: Dictionary = journal[id]
		var is_frag: bool = String(id).begins_with("frag_")
		para(Vector2(r.position.x + 24, y), "(L%d) %s" % [e.loop, e.text], 550.0, 13, Color(0.6, 0.85, 1.0) if is_frag else Color(0.93, 0.9, 0.82))
		y += 40.0 if String(e.text).length() > 70 else 22.0
	txt(Vector2(r.position.x + 24, r.end.y - 20), "[Tab] close    Hints: the Hero's habits are keys. Fragments hide where habits lead.", 12, Color(0.6, 0.6, 0.65))


func draw_ending() -> void:
	var r: Rect2 = overlay("THE END (of the demo)")
	var y: float = r.position.y + 80.0
	var path: String = dominant_lean()
	var names: Dictionary = {"control": "The Puppet King", "defiance": "The Last Boss", "compassion": "The Kind Hero", "charm": "Happily Ever Afterward"}
	var blurbs: Dictionary = {
		"control": "Every quest the Hero takes is one you wrote. You rule from the shadows.",
		"defiance": "You stopped sweeping. You took the Dark Lord's tower - and his role.",
		"compassion": "The Hero looked up, saw what he was breaking, and chose mercy.",
		"charm": "He still looks at you like a stranger. But he stayed for breakfast.",
	}
	var lines: Array = []
	if fragments >= FRAGMENTS_NEEDED:
		lines.append("You remember everything now. The Cycle has nowhere left to hide.")
	else:
		lines.append("The Hero reached the Tower. You never learned enough. The Cycle goes on.")
	lines.append("")
	lines.append("Dominant leaning: %s  ->  \"%s\"" % [path, names[path]])
	lines.append(blurbs[path])
	var second: String = dominant_lean(path)
	lines.append("Blend: your second leaning (%s) would colour the epilogue." % second)
	lines.append("")
	lines.append("Loops: %d   Fragments: %d   Journal entries: %d" % [loop_no, fragments, journal.size()])
	lines.append("")
	lines.append("[Enter] Play again (New Game)")
	for l in lines:
		para(Vector2(r.position.x + 24, y), String(l), 550.0, 16)
		y += 28.0 if String(l).length() < 62 else 46.0
