extends Node2D
## Afterward - "One Shift" prototype.
## Everything is built and drawn in code so the project has no asset dependencies.
## Loop: Dawn -> Hero's passage (watch / hide) -> Shift (clean, loot, change) -> Inspection -> Dream/reset.

enum Phase { DAWN, PASSAGE, SHIFT, INSPECTION, DREAM, ENDING }

const ROOM := Rect2(20, 60, 840, 640)
const PANEL_X := 885.0
## Actions per shift = number of work orders (never fewer than MIN_ACTIONS).
## Chores AND story actions (talking, notes, gifts, fragment hunting) each cost 1,
## so every plot decision means a chore left undone - unless you buy Strong Tea.
const MIN_ACTIONS := 4
const MAX_LOOPS := 10
const FRAGMENTS_NEEDED := 3
const PELL_SPEED := 230.0
const HERO_SPEED := 170.0
const REACH := 56.0
## First loops are a free tutorial: the Guild doesn't raise Suspicion and the Hero doesn't pay attention.
const GRACE_LOOPS := 3
const HERO_R := 14.0
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
var coin: int = 0            # earned this loop
var carried_coin: int = 0    # kept from last loop (Memory Depth 2+), expires at the next reset
var shop_greeted: bool = false
var payslips: int = 0
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
var talked_to_hero: bool = false
var hero_skip_chest: bool = false
var fight: Dictionary = {}
var snap: Dictionary = {}
var dream_note: String = ""
var backlog: Dictionary = {}   # id -> true: work left undone, persists across resets until actually done
var mess_noticed: bool = false

# ---- UI state ----
var menu: String = ""
var show_journal: bool = false
var show_debug: bool = false
var font: Font = ThemeDB.fallback_font
var cv: CanvasItem
var shapes_on: bool = true
var text_on: bool = true
var ui_overlay: Node2D
var nav: AStarGrid2D
var hero_wait: float = 0.0
var dialogue: Array = []   # blocking story boxes: {who, text}
var toast_text: String = ""
var toast_time: float = 0.0
const PIXEL_SIZE := 4.0
## Sprites are already pixel art, so the whole-screen pixelation shader is off by default.
const PIXELATE_WORLD := false
const SpriteData := preload("res://scripts/sprite_data.gd")


func _ready() -> void:
	randomize()
	cv = self
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	setup_pixel_layers()
	reset_world()
	say("I wake up. Again. This time I remember yesterday.")
	story("Pell", "I woke up and I remember yesterday. Nobody else does. Not the Innkeeper. Not Grub. Not him.")
	story("Pell", "So. The Hero kicks the door, smashes the pots, and I put them back. That's the job. For now.")


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
	rect.visible = PIXELATE_WORLD
	pix_layer.add_child(rect)
	# Layer 2: crisp text/UI on top.
	var ui_layer: CanvasLayer = CanvasLayer.new()
	ui_layer.layer = 2
	add_child(ui_layer)
	ui_overlay = Node2D.new()
	ui_overlay.set_script(load("res://scripts/overlay.gd"))
	ui_overlay.main = self
	ui_layer.add_child(ui_overlay)


func in_grace() -> bool:
	return loop_no <= GRACE_LOOPS


func add_awareness(n: float) -> void:
	if in_grace() and n > 0.0:
		return
	hero.awareness = clampf(hero.awareness + n, 0.0, 100.0)


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
		"innkeeper":
			return Vector2(22, 22)
	return Vector2.ZERO


func add_obj(id: String, type: String, pos: Vector2, state: String, room: String = "inn", size: Vector2 = Vector2.ZERO) -> void:
	objs[id] = {"id": id, "type": type, "pos": pos, "spawn": pos, "state": state, "item": null, "took": false, "gap": false, "room": room, "size": size if size != Vector2.ZERO else solid_size(type)}


func reset_world() -> void:
	objs = {}
	floor_items = []
	orders = {}
	satchel = []
	coin = 0
	shop_greeted = false
	talked_to_hero = false
	hero_skip_chest = false
	fight = {}
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
	add_obj("bar", "bar", Vector2(640, 250), "ok", "inn", Vector2(168, 48))
	add_obj("innkeeper", "innkeeper", Vector2(756, 250), "ok")
	# Kitchen
	add_obj("kpot0", "pot", Vector2(200, 130), "full", "kitchen")
	add_obj("kpot1", "pot", Vector2(330, 130), "full", "kitchen")
	add_obj("chestC", "chest", Vector2(140, 520), "closed", "kitchen")
	objs["chestC"].item = random_loot("gift")
	objs["chestC"].item.guild = true
	add_obj("counter", "counter", Vector2(520, 220), "ok", "kitchen", Vector2(280, 36))
	add_obj("stove", "stove", Vector2(790, 130), "ok", "kitchen", Vector2(56, 56))
	add_obj("ktable", "ktable", Vector2(480, 440), "ok", "kitchen", Vector2(168, 84))
	apply_backlog()


func apply_backlog() -> void:
	## Unfinished work does not reset with the world: it stays undone until Pell does it.
	for id in backlog.keys():
		if not objs.has(id):
			continue
		var o: Dictionary = objs[id]
		match o.type:
			"pot":
				o.state = "broken"
			"chest":
				o.state = "open"
			"door":
				o.state = "broken"
			"grub":
				o.state = "out"
				o.pos = o.spawn + Vector2(-70, -70)


func backlog_names() -> Array:
	var out: Array = []
	for id in backlog:
		if objs.has(id):
			out.append({"pot": "broken pot", "chest": "open chest", "door": "broken door", "grub": "Grub out cold"}.get(objs[id].type, "a mess"))
	return out


func total_coin() -> int:
	return coin + carried_coin


func spend_coin(n: int) -> bool:
	if total_coin() < n:
		return false
	var from_old: int = mini(carried_coin, n)  # old coin goes first - it expires sooner
	carried_coin -= from_old
	coin -= n - from_old
	return true


func shop_stock() -> Array:
	## Prices follow the Hero's act. Your wage doesn't.
	var m: float = 1.0 + 0.25 * (tier() - 1)
	return [
		{"id": "tea", "name": "Strong Tea (+2 actions)", "price": int(round(8.0 * m))},
		{"id": "bread", "name": "Fresh Bread (gift for the Hero)", "price": int(round(5.0 * m))},
		{"id": "fake", "name": "Convincing Fake (swap for loot)", "price": int(round(7.0 * m))},
	]


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
	toast_text = "Journal updated: " + text
	toast_time = 5.0


func story(who: String, text: String) -> void:
	## Plot-moving line: logged in the side panel AND shown in a big on-screen box that pauses play.
	dialogue.append({"who": who, "text": text})
	say(who + ": " + text)


func awareness_story() -> void:
	match awareness_state():
		"Curious":
			story("Pell", "The Hero glanced at me. Just for a second. Nobody looks at the cleaner. Careful.")
		"Suspicious":
			story("Hero", "Hey. Weren't you here yesterday? ...Weird. I keep seeing you.")
		"Engaged":
			story("Hero", "Wait. I know you. Who are you?")


func witness(id: String, text: String) -> void:
	if hero_room == cur_room and pell.distance_to(hero_pos) <= SIGHT:
		add_fact(id, text)


func gain_fragment(source: String, fact_id: String, text: String) -> void:
	found[source] = true
	fragments += 1
	add_fact(fact_id, text)
	story("MEMORY FRAGMENT", text)
	story("Pell", "Memory Depth %d. I remember more than I did this morning. That should worry me." % memory_depth())


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
	backlog.erase(id)


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
	build_nav("inn")
	hero_steps = build_hero_script()
	hero_i = 0
	hero_t = 0.0
	hero_started = false
	snap = {"journal": journal.duplicate(true), "fragments": fragments, "found": found.duplicate(true)}
	say("The Hero is coming. Stay close enough to learn, far enough not to be seen.")
	if not backlog.is_empty() and not in_grace():
		# A mess that never gets cleaned makes the Hero wonder - without him knowing why.
		add_awareness(5.0 * backlog.size())
		bark("Huh. That's still broken? Didn't I do that yesterday?")
		if not mess_noticed:
			mess_noticed = true
			add_fact("mess_stays", "Work left undone stays undone. The Hero noticed a mess that never got cleaned. It made him curious.")
			story("Pell", "I left it. Nobody tidied it. And he noticed - a clean room is invisible, a mess that stays makes a person think.")


func end_passage() -> void:
	phase = Phase.SHIFT
	hero_pos = Vector2(-100, -100)
	hero_room = "inn"
	in_cart = false
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
	for oid in orders:
		if backlog.has(oid):
			orders[oid].label = "OVERDUE: " + orders[oid].label
	actions = maxi(MIN_ACTIONS, orders.size())
	if suspicion >= 40:
		actions -= 2
		say("Watched: a Supervisor shadows you. Two fewer actions this shift.")
	if hero.awareness >= 60.0:
		actions -= 1
		say("The Hero is suspicious of you. You feel eyes on your back. One fewer action.")
	actions = maxi(3, actions)
	say("Shift begins: %d work orders, %d actions. Plot choices cost an action too." % [orders.size(), actions])


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
	for oid in orders:
		if not orders[oid].done and objs[oid].type != "board":
			backlog[oid] = true
	report = []
	report.append("Supervisor Bramm inspects your areas.")
	report.append("Work orders done: %d / %d  (Diligence %d%%)" % [done, total, int(dil * 100.0)])
	if not backlog.is_empty():
		report.append("%d unfinished task(s) stay undone until someone does them." % backlog.size())
	# Suspicion moves in proportion to how much work is left, not in steps:
	# 100% done = -8, 70% = no change, 0% = +30 (linear in between).
	var delta: int = 0
	if dil >= 0.7:
		delta = -int(round((dil - 0.7) / 0.3 * 8.0))
	else:
		delta = int(round((0.7 - dil) / 0.7 * 30.0))
	var verdict: String = "Excellent." if dil >= 0.9 else ("Acceptable." if dil >= 0.7 else ("Sloppy." if dil >= 0.4 else "Disgraceful."))
	if in_grace() and delta > 0:
		delta = 0
		report.append("Bramm: \"%s\"  He only skims your work this early. Suspicion unchanged." % verdict)
	else:
		report.append("Bramm: \"%s\"  Suspicion %s%d" % [verdict, "+" if delta >= 0 else "", delta])
	if gaps > 0 and in_grace():
		report.append("Bramm doesn't look inside the chests. Yet.")
	elif gaps > 0:
		delta += 15 * gaps
		report.append("Bramm frowns at an empty chest.  Suspicion +%d" % (15 * gaps))
	payslips += 1
	var gross: int = int(round(dil * 40.0))
	var adj: int = randi_range(2, 6)
	var cuts: Array = [["Dormitory rent", 8], ["Broom rental", 4], ["Uniform laundering", 3], ["Misc. adjustment", adj]]
	var net: int = gross
	report.append("PAYSLIP   Gross pay: %d coin" % gross)
	for c in cuts:
		net -= int(c[1])
		report.append("   - %s: %d" % [c[0], c[1]])
	net = maxi(0, net)
	coin += net
	report.append("   Net pay: %d coin" % net)
	if memory_depth() >= 2:
		report.append("   You remember the contract: 40 coin per full shift. Received: %d%%." % int(100.0 * net / 40.0))
		if not journal.has("guild_cheat"):
			add_fact("guild_cheat", "The Guild's payslip: rent, rental, laundering and a 'misc. adjustment' that is never the same twice. I'm paid less than the Hero spends on one potion.")
			story("Pell", "Rent. Broom rental. Laundering. 'Misc.' ...I do the maths. They take most of it back, every cycle. And I only noticed because I remember.")
	else:
		report.append("   (Wages arrive at the end of the shift. Coin does not survive the reset.)")
	suspicion = clampi(suspicion + delta, 0, 100)
	if suspicion >= 80:
		report.append("RAID! Inquisitors search the Seam.")
		if stash.size() > 0:
			var names: Array = stash.map(func(it: Dictionary) -> String: return it.name)
			report.append("Confiscated: " + ", ".join(names))
			stash = []
		else:
			report.append("They find nothing. Your stash was empty.")
		if backlog.is_empty():
			suspicion = 40
			report.append("With the work all done, the Guild's suspicion cools to 40.")
		else:
			report.append("Work is still undone, so the Guild's suspicion does not cool.")
	report.append("")
	report.append("[B] Bribe Bramm (20 coin, Suspicion -15)     [Enter] Sleep")


func bribe() -> void:
	if bribed:
		return
	if not spend_coin(20):
		say("Not enough coin.")
		return
	bribed = true
	suspicion = maxi(0, suspicion - 15)
	lean_up("control", 5)
	report.append("You slip Bramm 20 coin. Suspicion -15. (Control rises.)")


func begin_dream() -> void:
	phase = Phase.DREAM
	dream_lines = []
	dream_lines.append("The world rewinds.")
	if dream_note != "":
		dream_lines.append(dream_note)
		dream_note = ""
	dream_lines.append("")
	var lost: Array = []
	for it in satchel:
		lost.append(it.name)
	if memory_depth() >= 2:
		if carried_coin > 0:
			lost.append("%d coin that you failed to spend in time" % carried_coin)
	elif coin > 0:
		lost.append("%d coin" % coin)
	if lost.is_empty():
		dream_lines.append("Nothing on your person to lose.")
	else:
		dream_lines.append("Lost in the reset: " + ", ".join(lost))
	if memory_depth() >= 2 and coin > 0:
		dream_lines.append("Carried into the next cycle: %d coin (spend it before the next reset or it vanishes)." % coin)
	if stash.is_empty():
		dream_lines.append("Your stash is empty. Hint: whatever is in the Seam survives.")
	else:
		var kept: Array = stash.map(func(it: Dictionary) -> String: return it.name)
		dream_lines.append("Kept in the Seam: " + ", ".join(kept))
	if not backlog.is_empty():
		dream_lines.append("Still undone next cycle: " + ", ".join(backlog_names()))
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
	var old_tier: int = tier()
	if loop_no == GRACE_LOOPS:
		story("Pell", "Bramm's started reading the paperwork properly. And the Hero looked right at me yesterday. The slack is over.")
	if memory_depth() >= 2:
		if carried_coin == 0 and coin > 0 and not journal.has("coin_kept"):
			add_fact("coin_kept", "With enough memory, a few coins stay in my pocket for one cycle. The Guild's wages were never meant to be kept.")
			story("Pell", "My pocket still jingles. One cycle's worth. The Guild never told me coins could survive this. Nobody ever tried to keep any.")
		carried_coin = coin
	else:
		carried_coin = 0
	coin = 0
	loop_no += 1
	reset_world()
	if loop_no == 2:
		story("Pell", "Same pots. Same door. Same him. Yesterday wasn't a dream - I remember every smash.")
	if tier() != old_tier:
		story("Pell", "The Hero's moved on to Act %d: %s. The leftovers will be better. So will the monsters." % [tier(), ACT_NAMES[tier() - 1]])
	phase = Phase.DAWN
	msgs = []
	say("Dawn. Loop %d. The inn smells of last night's stew." % loop_no)


# =========================================================== Hero script + AI

func step_move(p: Vector2, straight: bool = false) -> Dictionary:
	## straight = walk in a line (used outside the room, through the front door and the Forest exit)
	return {"k": "move", "p": p, "straight": straight}


func build_nav(room: String) -> void:
	## The Hero obeys the same solid-object rules as Pell: he paths around furniture on a grid.
	nav = AStarGrid2D.new()
	nav.region = Rect2i(0, 0, 48, 36)
	nav.cell_size = Vector2(20, 20)
	nav.offset = Vector2(10, 10)
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	var inside: Rect2 = ROOM.grow(-12.0)
	for cx in 48:
		for cy in 36:
			if not inside.has_point(Vector2(cx * 20 + 10, cy * 20 + 10)):
				nav.set_point_solid(Vector2i(cx, cy), true)
	for id in objs:
		var o: Dictionary = objs[id]
		if o.room != room or o.size.x <= 0.0 or o.type == "grub":
			continue
		var r: Rect2 = Rect2(o.pos - o.size / 2.0, o.size).grow(HERO_R)
		for cx in range(maxi(0, int(floor(r.position.x / 20.0))), mini(48, int(ceil(r.end.x / 20.0)) + 1)):
			for cy in range(maxi(0, int(floor(r.position.y / 20.0))), mini(36, int(ceil(r.end.y / 20.0)) + 1)):
				if r.has_point(Vector2(cx * 20 + 10, cy * 20 + 10)):
					nav.set_point_solid(Vector2i(cx, cy), true)


func shove_pell() -> void:
	## Out of patience, the Hero pushes Pell aside (he never walks through them).
	var best: Vector2 = pell
	var best_d: float = -1.0
	for i in 12:
		var cand: Vector2 = pell + Vector2.from_angle(TAU * float(i) / 12.0) * 52.0
		if ROOM.grow(-14.0).has_point(cand) and not blocked(cand) and cand.distance_to(hero_pos) > best_d:
			best = cand
			best_d = cand.distance_to(hero_pos)
	if best_d >= 0.0:
		pell = best
		say("The Hero shoves past you without a glance.")


func hero_hits_pell(next: Vector2) -> bool:
	## True if stepping to `next` would push the Hero into Pell (moving away is always fine).
	if in_cart or hero_room != cur_room:
		return false
	var lim: float = HERO_R + PELL_R + 4.0
	return next.distance_to(pell) < lim and next.distance_to(pell) < hero_pos.distance_to(pell)


func hero_path(a: Vector2, b: Vector2, straight: bool, avoid_pell: bool = false) -> Array:
	if straight or nav == null:
		return [b]
	var extra: Array = []
	if avoid_pell and not in_cart and hero_room == cur_room:
		for cx in range(maxi(0, int(pell.x / 20.0) - 3), mini(48, int(pell.x / 20.0) + 4)):
			for cy in range(maxi(0, int(pell.y / 20.0) - 3), mini(36, int(pell.y / 20.0) + 4)):
				var cid: Vector2i = Vector2i(cx, cy)
				if not nav.is_point_solid(cid) and Vector2(cx * 20 + 10, cy * 20 + 10).distance_to(pell) < 36.0:
					nav.set_point_solid(cid, true)
					extra.append(cid)
	var ia: Vector2i = Vector2i(clampi(int(a.x / 20.0), 0, 47), clampi(int(a.y / 20.0), 0, 35))
	var ib: Vector2i = Vector2i(clampi(int(b.x / 20.0), 0, 47), clampi(int(b.y / 20.0), 0, 35))
	var was_a: bool = nav.is_point_solid(ia)
	var was_b: bool = nav.is_point_solid(ib)
	nav.set_point_solid(ia, false)
	nav.set_point_solid(ib, false)
	var pts: PackedVector2Array = nav.get_point_path(ia, ib)
	nav.set_point_solid(ia, was_a)
	nav.set_point_solid(ib, was_b)
	for cid in extra:
		nav.set_point_solid(cid, false)
	var out: Array = []
	for i in range(1, pts.size()):
		out.append(pts[i])
	out.append(b)
	return out


func step_act(a: String, id: String, t: float) -> Dictionary:
	return {"k": "act", "a": a, "o": id, "t": t}


func build_hero_script() -> Array:
	var s: Array = []
	s.append(step_move(Vector2(90, 400), true))
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
	s.append(step_move(Vector2(845, 420)))
	s.append(step_move(Vector2(920, 420), true))
	return s


func update_hero(dt: float) -> void:
	if hero_i >= hero_steps.size():
		end_passage()
		return
	var st: Dictionary = hero_steps[hero_i]
	if st.k == "warp":
		hero_room = st.room
		hero_pos = st.p
		build_nav(hero_room)
		hero_i += 1
		return
	if st.k == "move":
		if not st.has("path"):
			st["path"] = hero_path(hero_pos, st.p, st.straight)
			st["pi"] = 0
		var path: Array = st.path
		if st.pi >= path.size():
			hero_i += 1
			return
		var tgt: Vector2 = path[st.pi]
		var d: Vector2 = tgt - hero_pos
		var stp: float = HERO_SPEED * dt
		if hero_hits_pell(hero_pos + d.normalized() * minf(stp, d.length())):
			# Pell is in the way: wait, then try another route, then lose patience.
			hero_wait += dt
			if hero_wait > 0.6 and not st.get("rerouted", false):
				st["rerouted"] = true
				st["path"] = hero_path(hero_pos, st.p, st.straight, true)
				st["pi"] = 0
			elif hero_wait > 3.5:
				bark("Out of the way, cleaner!")
				add_awareness(8.0)
				shove_pell()
				hero_wait = 0.0
			return
		hero_wait = 0.0
		if d.length() <= stp:
			hero_pos = tgt
			st["pi"] = st.pi + 1
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
		var before: String = awareness_state()
		add_awareness(14.0 * dt)
		if awareness_state() != before:
			awareness_story()


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
			add_awareness(8.0)
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
			if o.state == "broken":
				bark("Already smashed. ...Wasn't that yesterday?")
				return
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
			if hero_skip_chest:
				bark("Cursed? ...Pass.")
				witness("hero_listens", "The Hero skipped a chest because I told him it was cursed. He believes anything the cleaner says.")
				return
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
			if o.state == "out":
				bark("Still down? Huh.")
				return
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
		if o.room != cur_room or o.type in ["counter", "stove", "ktable", "bar"]:
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
	if phase == Phase.PASSAGE and not in_cart and hero_room == cur_room and pell.distance_to(hero_pos) <= 72.0:
		out.append({"d": pell.distance_to(hero_pos) - 30.0, "kind": "hero", "ref": {"pos": hero_pos}})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	return out


func labels(t: Dictionary) -> Array:
	## [E label, F label] for the thing at hand; "" = not available.
	if t.kind == "floor":
		return ["Pick up " + t.ref.item.name, ""]
	if t.kind == "hero":
		var w: Dictionary = best_weapon()
		return ["Talk to the Hero", ("Attack the Hero (%s)" % w.name) if not w.is_empty() else ""]
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
				return ["Drag Grub back to spawn (1 action)", "Talk to groggy Grub (story, 1 action)"]
			return ["", ""]
		"board":
			return ["Pin standard quest (1 action)", "Write your own note (story, 1 action)"]
		"table":
			return ["Leave a gift for the Hero (story, 1 action)", ""] if o.state == "empty" else ["", ""]
		"barrel":
			return ["Search behind barrel (story, 1 action)", ""] if o.state == "kicked" else ["", ""]
		"seam":
			return ["Open the Seam (stash)", ""]
		"innkeeper":
			return ["Talk to the Innkeeper / buy things (free)", ""]
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
	if t.kind == "hero":
		if alt:
			start_fight()
		else:
			menu = "hero_talk"
		return
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
					gain_fragment("barrel", "frag_barrel", "Behind the barrel, scratched into the wall in my own handwriting: 'Someone is deciding who plays which part. Watch who gets looked at.'")
			else:
				say("A dusty crack. If only I knew why he keeps kicking this thing...")
		"seam":
			menu = "stash"
		"innkeeper":
			menu = "shop"
			if not shop_greeted:
				shop_greeted = true
				story("Innkeeper", "Welcome to the Sleeping Stag! First time here, love? Prices are posted. They never change. (They do.)")
				if memory_depth() >= 2:
					story("Pell", "I've bought tea from her two hundred times. She has never once remembered my face. Her prices climb with every act of the Hero's quest. My pay doesn't.")


func talk_to_grub() -> void:
	lean_up("compassion", 4)
	if not journal.has("grub_memory"):
		add_fact("grub_memory", "Grub: 'Every morning I wake up, and every morning I forget a bad dream.' Revived monsters keep a trace of memory.")
		story("Grub", "...every morning I wake up on the same spot. And every morning someone tired drags me home.")
		story("Pell", "He remembers something. Guild charms leave a trace. I should ask again tomorrow, once he's had time to think.")
	elif journal[("grub_memory")].loop < loop_no and not found.has("grub"):
		gain_fragment("grub", "frag_grub", "Grub: 'A mad old woman, Wenna, says the story offered her a part once. She said no. Now nobody believes her.'")
	else:
		story("Grub", "Zzz... five more minutes...")


func is_weapon(it: Dictionary) -> bool:
	var n: String = String(it.name)
	return it.kind == "gear" and (n.contains("Sword") or n.contains("Bow") or n.contains("Blade"))


func best_weapon() -> Dictionary:
	var best: Dictionary = {}
	for it in satchel:
		if is_weapon(it) and (best.is_empty() or it.power > best.power):
			best = it
	return best


func armour_power() -> int:
	var a: int = 0
	for it in satchel:
		if it.kind == "gear" and not is_weapon(it):
			a += int(it.power)
	return a


func talk_to_hero(opt: int) -> void:
	var st: String = awareness_state()
	var repeat: bool = talked_to_hero
	talked_to_hero = true
	add_awareness(12.0 if repeat else 6.0)
	add_fact("hero_talk", "The Hero will answer if you speak to him. He treats anyone nearby like a quest-giver.")
	var table: Dictionary = {
		1: ["Morning. Lovely day for... all of this.", {"Oblivious": "Hm? Oh. Morning. Is there a quest?", "Curious": "Morning. ...Have we met?", "Suspicious": "You again. You're always around.", "Engaged": "I know your face. Who ARE you?"}],
		2: ["The pots are somebody's livelihood, you know.", {"Oblivious": "Pots? ...They're pots.", "Curious": "Huh. Never thought about whose they were.", "Suspicious": "Is that a threat?", "Engaged": "Stay out of my way, cleaner."}],
		3: ["Heard the chest by the cellar is cursed. I'd skip it.", {"Oblivious": "Cursed? Pfft. ...Fine, I'll skip it.", "Curious": "Cursed? ...Huh. Okay.", "Suspicious": "Cursed. Sure. How would YOU know?", "Engaged": "Nice try."}],
	}
	story("Pell", table[opt][0])
	story("Hero", ("...Again? We just talked." if repeat else table[opt][1][st]))
	match opt:
		1:
			lean_up("charm", 3)
			hero.mercy = mini(100, hero.mercy + 1)
		2:
			lean_up("compassion", 4)
			hero.mercy = mini(100, hero.mercy + 3)
			hero.greed = maxi(0, hero.greed - 2)
		3:
			lean_up("control", 4)
			if not repeat and (st == "Oblivious" or st == "Curious" or (st == "Suspicious" and randf() < 0.5)):
				hero_skip_chest = true


func handle_hero_talk_key(k: int) -> void:
	if k == KEY_ESCAPE:
		menu = ""
		return
	if k >= KEY_1 and k <= KEY_3:
		menu = ""
		talk_to_hero(k - KEY_1 + 1)


func start_fight() -> void:
	var w: Dictionary = best_weapon()
	if w.is_empty():
		return
	var hm: int = 8 + 6 * tier()
	var pm: int = 3 + floori(armour_power() / 5.0)
	fight = {"w": w, "hh": hm, "hm": hm, "ph": pm, "pm": pm, "round": 0, "log": ["You draw the %s. The Hero turns around." % w.name]}
	menu = "fight"
	lean_up("defiance", 3)


func hero_counter() -> void:
	if randf() < 0.55 + 0.03 * tier():
		var dmg: int = 1 + (1 if tier() >= 3 else 0)
		fight.ph -= dmg
		fight.log.append("The Hero hits you for %d." % dmg)
	else:
		fight.log.append("You dodge the Hero's swing.")
	if fight.ph <= 0:
		fight_lose()


func fight_attack() -> void:
	var w: int = int(fight.w.power)
	var surprise: bool = fight.round == 0 and hero.awareness < 60.0
	var p_hit: float = clampf(0.30 + 0.025 * w - 0.04 * tier() + (0.2 if surprise else 0.0), 0.10, 0.85)
	fight.round += 1
	if randf() < p_hit:
		var dmg: int = w + randi_range(0, 2)
		fight.hh -= dmg
		fight.log.append("You hit the Hero for %d%s." % [dmg, " (surprise!)" if surprise else ""])
	else:
		fight.log.append("You miss.")
	if fight.hh <= 0:
		fight_win()
		return
	hero_counter()


func fight_flee() -> void:
	if randf() < 0.5:
		fight = {}
		menu = ""
		hero.awareness = maxf(hero.awareness, 60.0)
		bark("Hey! Get back here, cleaner!")
		shove_pell()
		say("You bolt. The Hero will remember this loop - he just doesn't know why yet.")
	else:
		fight.log.append("You can't get away!")
		hero_counter()


func end_loop_early(note: String) -> void:
	menu = ""
	fight = {}
	in_cart = false
	hero_pos = Vector2(-100, -100)
	dream_note = note
	begin_dream()


func fight_win() -> void:
	lean_up("defiance", 10)
	story("Pell", "He's on the floor. I did that. ...The whole inn is holding its breath.")
	story("Pell", "Then the light goes flat, and everything starts to rewind. The Hero keeps his progress. I keep what I learned.")
	end_loop_early("The Hero fell. The story broke, and the world rewinds early.")


func fight_lose() -> void:
	var lost: int = 0
	for id in journal:
		if not snap.get("journal", {}).has(id):
			lost += 1
	journal = snap.get("journal", journal)
	fragments = snap.get("fragments", fragments)
	found = snap.get("found", found)
	learned_this_loop = []
	story("Pell", "Ow. That's... that's the floor. Everything is going dark.")
	end_loop_early("You died. The memories you hadn't banked this cycle are gone (%d Journal entries). Memory Depth and Leanings stay. Death is a setback, not a game over." % lost)


func handle_fight_key(k: int) -> void:
	if fight.is_empty():
		menu = ""
		return
	if k == KEY_1:
		fight_attack()
	elif k == KEY_2:
		fight_flee()


func use_item(i: int) -> void:
	if i >= satchel.size():
		return
	var it: Dictionary = satchel[i]
	match it.kind:
		"knowledge":
			if not spend(1):
				return
			satchel.remove_at(i)
			gain_fragment("letter", "frag_letter", "The Hero's letter, in a cleaner's handwriting: 'Before you were the Hero, you swept these floors. Your locker is still in the Guild Hall.'")
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
	if not dialogue.is_empty():
		if k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_E or k == KEY_SPACE or k == KEY_F:
			dialogue.pop_front()
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
	if menu == "shop":
		handle_shop_key(k)
		return
	if menu == "hero_talk":
		handle_hero_talk_key(k)
		return
	if menu == "fight":
		handle_fight_key(k)
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


func handle_shop_key(k: int) -> void:
	if k == KEY_ESCAPE or k == KEY_ENTER:
		menu = ""
		return
	if k < KEY_1 or k > KEY_3:
		return
	var item: Dictionary = shop_stock()[k - KEY_1]
	if total_coin() < int(item.price):
		say("Not enough coin for the %s." % item.name)
		return
	match item.id:
		"tea":
			spend_coin(int(item.price))
			actions += 2
			say("You gulp down the tea. +2 actions.")
		"bread":
			if add_to_satchel({"name": "Fresh Bread", "kind": "gift", "power": 2, "guild": false}):
				spend_coin(int(item.price))
				say("Bought bread. The Hero can't resist it.")
		"fake":
			if add_to_satchel({"name": "Convincing Fake", "kind": "junk", "power": 0, "guild": false}):
				spend_coin(int(item.price))
				say("Bought a convincing fake. Now a chest can look untouched.")


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
	## Solid furniture, chests, pots etc. - and the Hero - cannot be walked through.
	if phase == Phase.PASSAGE and hero_room == cur_room and p.distance_to(hero_pos) < PELL_R + HERO_R:
		return true
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
		if menu == "" and not show_journal and not in_cart and dialogue.is_empty():
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
				# keys are screen-relative in the isometric view: W = up-screen = (-1,-1) in room space
				var wd: Vector2 = Vector2(v.x + v.y, v.y - v.x)
				move_pell(wd.normalized() * PELL_SPEED * delta)
				check_doorways()
	if phase == Phase.PASSAGE and menu == "" and not show_journal and dialogue.is_empty():
		var hdt: float = delta * (3.0 if Input.is_physical_key_pressed(KEY_SPACE) else 1.0)
		update_hero(hdt)
	if bark_time > 0.0:
		bark_time -= delta
	if toast_time > 0.0:
		toast_time -= delta
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
	elif menu == "shop":
		draw_shop()
	elif menu == "hero_talk":
		draw_hero_talk()
	elif menu == "fight":
		draw_fight()
	if show_journal:
		draw_journal()
	draw_toast()
	draw_dialogue()


func draw_toast() -> void:
	if toast_time <= 0.0 or not dialogue.is_empty():
		return
	var w: float = 820.0
	box(Rect2(Vector2(30, 98), Vector2(w, 46)), Color(0.05, 0.1, 0.16, 0.9), Color(0.6, 0.85, 1.0))
	para(Vector2(42, 118), toast_text, w - 24.0, 13, Color(0.8, 0.93, 1.0))


func draw_dialogue() -> void:
	if dialogue.is_empty():
		return
	var d: Dictionary = dialogue[0]
	var r: Rect2 = Rect2(60, 500, 760, 170)
	var frag: bool = d.who == "MEMORY FRAGMENT"
	box(Rect2(0, 0, 872, 720), Color(0, 0, 0, 0.35))
	box(r, Color(0.07, 0.06, 0.1, 0.97), Color(0.6, 0.85, 1.0) if frag else Color(0.95, 0.85, 0.5))
	txt(r.position + Vector2(20, 32), String(d.who), 20, Color(0.6, 0.85, 1.0) if frag else Color(0.95, 0.85, 0.5))
	para(r.position + Vector2(20, 66), String(d.text), 720.0, 18)
	var more: String = "  (%d more)" % (dialogue.size() - 1) if dialogue.size() > 1 else ""
	txt(r.position + Vector2(20, 158), "[Enter] continue" + more, 13, Color(0.6, 0.6, 0.65))


# =========================================================== isometric drawing
## Gameplay (movement, collision, reach) stays in flat room coordinates.
## Only drawing projects them to a 2:1 isometric view.

const ISO_A := 0.56
const ISO_B := 0.28
const ISO_ORIGIN := Vector2(388.0, 140.0)  # screen position of the room's north corner
const WALL_H := 90.0


func iso(p: Vector2, h: float = 0.0) -> Vector2:
	var q: Vector2 = p - ROOM.position
	return ISO_ORIGIN + Vector2((q.x - q.y) * ISO_A, (q.x + q.y) * ISO_B - h)


func shade(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f, c.a)


func d_poly(pts: Array, c: Color) -> void:
	if shapes_on:
		cv.draw_colored_polygon(PackedVector2Array(pts), c)


func ellipse_pts(c: Vector2, rx: float, ry: float) -> Array:
	var pts: Array = []
	for i in 16:
		var a: float = TAU * float(i) / 16.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func cuboid(center: Vector2, size: Vector2, h: float, top: Color, z0: float = 0.0, outline: bool = true) -> void:
	var x0: float = center.x - size.x / 2.0
	var x1: float = center.x + size.x / 2.0
	var y0: float = center.y - size.y / 2.0
	var y1: float = center.y + size.y / 2.0
	d_poly([iso(Vector2(x0, y1), h), iso(Vector2(x1, y1), h), iso(Vector2(x1, y1), z0), iso(Vector2(x0, y1), z0)], shade(top, 0.74))
	d_poly([iso(Vector2(x1, y1), h), iso(Vector2(x1, y0), h), iso(Vector2(x1, y0), z0), iso(Vector2(x1, y1), z0)], shade(top, 0.52))
	var tp: Array = [iso(Vector2(x0, y0), h), iso(Vector2(x1, y0), h), iso(Vector2(x1, y1), h), iso(Vector2(x0, y1), h)]
	d_poly(tp, top)
	if outline and shapes_on:
		tp.append(tp[0])
		cv.draw_polyline(PackedVector2Array(tp), shade(top, 0.35), 1.0)


func cylinder(center: Vector2, r: float, h: float, top: Color) -> void:
	var c0: Vector2 = iso(center)
	var rx: float = r * ISO_A * 1.414
	var ry: float = r * ISO_B * 1.414
	var side: Color = shade(top, 0.65)
	d_poly(ellipse_pts(c0, rx, ry), side)
	d_poly([c0 + Vector2(-rx, 0), c0 + Vector2(rx, 0), c0 + Vector2(rx, -h), c0 + Vector2(-rx, -h)], side)
	d_poly(ellipse_pts(c0 + Vector2(0, -h), rx, ry), top)


var tex_cache: Dictionary = {}


func sprite(sname: String) -> Texture2D:
	if not tex_cache.has(sname):
		var path: String = "res://assets/sprites/%s.png" % sname
		tex_cache[sname] = load(path) if ResourceLoader.exists(path) else null
	return tex_cache[sname]


func d_sprite(sname: String, wpos: Vector2, z: float = 0.0) -> bool:
	## Draws a sprite anchored at a world position (its feet / footprint centre). False if the PNG is missing.
	var tex: Texture2D = sprite(sname)
	if tex == null:
		return false
	var a: Vector2 = SpriteData.ANCHORS.get(sname, Vector2(tex.get_width() / 2.0, tex.get_height()))
	if shapes_on:
		cv.draw_texture(tex, (iso(wpos, z) - a).round())
	return true


func obj_sprite(o: Dictionary) -> String:
	match o.type:
		"pot":
			return "pot_full" if o.state == "full" else "pot_broken"
		"chest":
			return "chest_open" if o.state == "open" else "chest_closed"
		"barrel":
			return "barrel"
		"table":
			return "table"
		"board":
			return "board_empty" if o.state == "empty" else "board_note"
		"cart":
			return "cart"
		"grub":
			return "grub_ok" if o.state == "ok" else "grub_out"
		"innkeeper":
			return "innkeeper"
	return ""


func item_sprite(it: Dictionary) -> String:
	match it.kind:
		"coin":
			return "item_coin"
		"gear":
			return "item_sword"
		"gift":
			return "item_bread"
		"consumable":
			return "item_potion"
		"knowledge":
			return "item_letter"
		"junk":
			return "item_cloth"
	return "item_sack"


func person(p: Vector2, body: Color, r: float, tall: float, sname: String = "") -> void:
	var c: Vector2 = iso(p)
	d_poly(ellipse_pts(c, r * 1.5, r * 0.75), Color(0, 0, 0, 0.35))
	if sname != "" and d_sprite(sname, p):
		return
	d_circle(c + Vector2(0, -tall * 0.45), r, body)
	d_circle(c + Vector2(0, -tall), r * 0.7, Color(0.98, 0.85, 0.7))


func draw_world() -> void:
	var inn: bool = cur_room == "inn"
	var floor_col: Color = Color(0.46, 0.32, 0.2) if inn else Color(0.5, 0.5, 0.5)
	var wall_col: Color = Color(0.6, 0.45, 0.32) if inn else Color(0.66, 0.66, 0.66)
	draw_room_shell(floor_col, wall_col, inn)
	var items: Array = []
	for id in objs:
		var o: Dictionary = objs[id]
		if o.room != cur_room or o.type == "door":
			continue
		if o.type in ["counter", "stove", "ktable", "bar"]:
			# long furniture is drawn in chunks so people can walk in front of / behind it
			var long_x: bool = o.size.x >= o.size.y
			var n: int = maxi(1, ceili((o.size.x if long_x else o.size.y) / 56.0))
			for k in n:
				var f: float = (float(k) + 0.5) / float(n) - 0.5
				var cc: Vector2 = o.pos + (Vector2(o.size.x * f, 0) if long_x else Vector2(0, o.size.y * f))
				var cs: Vector2 = Vector2(o.size.x / float(n), o.size.y) if long_x else Vector2(o.size.x, o.size.y / float(n))
				items.append({"d": cc.x + cc.y + (cs.x + cs.y) * 0.5, "k": "chunk", "o": o, "c": cc, "s": cs})
		else:
			items.append({"d": o.pos.x + o.pos.y + (o.size.x + o.size.y) * 0.5, "k": "obj", "o": o})
	for fi in floor_items:
		if fi.room == cur_room:
			items.append({"d": fi.pos.x + fi.pos.y, "k": "floor", "f": fi})
	if phase == Phase.PASSAGE and hero_room == cur_room:
		items.append({"d": hero_pos.x + hero_pos.y + 2.0, "k": "hero"})
	if not in_cart:
		items.append({"d": pell.x + pell.y + 2.0, "k": "pell"})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	for it in items:
		match it.k:
			"obj":
				draw_obj(it.o)
			"chunk":
				draw_chunk(it.o, it.c, it.s)
			"floor":
				draw_floor_item(it.f)
			"hero":
				person(hero_pos, Color(0.95, 0.8, 0.2), 12.0, 40.0, "hero")
			"pell":
				person(pell, Color(0.3, 0.55, 0.85), 10.0, 32.0, "pell")
				if sprite("pell") == null:
					d_line(iso(pell) + Vector2(8, -12), iso(pell) + Vector2(20, -38), Color(0.8, 0.65, 0.3), 3.0)
	draw_marker()
	draw_labels()


func draw_room_shell(floor_col: Color, wall_col: Color, inn: bool) -> void:
	var r0: Vector2 = ROOM.position
	var W: float = ROOM.size.x
	var Hh: float = ROOM.size.y
	d_poly([iso(r0), iso(r0 + Vector2(W, 0)), iso(r0 + Vector2(W, 0), WALL_H), iso(r0, WALL_H)], shade(wall_col, 0.86))
	d_poly([iso(r0), iso(r0 + Vector2(0, Hh)), iso(r0 + Vector2(0, Hh), WALL_H), iso(r0, WALL_H)], shade(wall_col, 0.62))
	d_line(iso(r0, WALL_H), iso(r0 + Vector2(W, 0), WALL_H), shade(wall_col, 1.1), 3.0)
	d_line(iso(r0, WALL_H), iso(r0 + Vector2(0, Hh), WALL_H), shade(wall_col, 0.8), 3.0)
	for i in 11:
		for j in 8:
			var x0: float = float(i) * 80.0
			var y0: float = float(j) * 80.0
			var x1: float = minf(x0 + 80.0, W)
			var y1: float = minf(y0 + 80.0, Hh)
			var col: Color = floor_col if (i + j) % 2 == 0 else shade(floor_col, 0.9)
			d_poly([iso(r0 + Vector2(x0, y0)), iso(r0 + Vector2(x1, y0)), iso(r0 + Vector2(x1, y1)), iso(r0 + Vector2(x0, y1))], col)
	var edge: Color = Color(0.1, 0.07, 0.05)
	d_line(iso(r0 + Vector2(W, 0)), iso(r0 + Vector2(W, Hh)), edge, 3.0)
	d_line(iso(r0 + Vector2(0, Hh)), iso(r0 + Vector2(W, Hh)), edge, 3.0)
	if inn:
		var d: Dictionary = objs.get("door", {})
		if not d.is_empty():
			var ok: bool = d.state == "ok"
			var dy0: float = d.pos.y - 40.0
			var dy1: float = d.pos.y + 40.0
			d_poly([iso(Vector2(r0.x, dy0)), iso(Vector2(r0.x, dy1)), iso(Vector2(r0.x, dy1), 66.0), iso(Vector2(r0.x, dy0), 66.0)], Color(0.5, 0.33, 0.16) if ok else Color(0.22, 0.13, 0.09))
			if not ok:
				d_line(iso(Vector2(r0.x, dy0 + 10), 60.0), iso(Vector2(r0.x, dy1 - 14), 14.0), Color(0.05, 0.03, 0.02), 2.0)
		d_poly(ellipse_pts(iso(GRUB_SPAWN), 40.0, 20.0), shade(floor_col, 0.7))
		d_poly([iso(Vector2(ROOM.end.x - 14, 380)), iso(Vector2(ROOM.end.x, 380)), iso(Vector2(ROOM.end.x, 460)), iso(Vector2(ROOM.end.x - 14, 460))], Color(0.25, 0.45, 0.25))
		d_poly([iso(Vector2(DOORWAY_X - 45, ROOM.end.y - 14)), iso(Vector2(DOORWAY_X + 45, ROOM.end.y - 14)), iso(Vector2(DOORWAY_X + 45, ROOM.end.y)), iso(Vector2(DOORWAY_X - 45, ROOM.end.y))], Color(0.25, 0.45, 0.25))
		d_line(iso(Vector2(390, 684)), iso(Vector2(510, 684)), Color(0.3, 0.55, 0.8), 6.0)
		d_line(iso(Vector2(390, 684)), iso(Vector2(510, 684)), Color(0.75, 0.93, 1.0), 2.0)
	else:
		d_poly([iso(Vector2(DOORWAY_X - 45, r0.y)), iso(Vector2(DOORWAY_X + 45, r0.y)), iso(Vector2(DOORWAY_X + 45, r0.y), 66.0), iso(Vector2(DOORWAY_X - 45, r0.y), 66.0)], Color(0.22, 0.4, 0.22))


func draw_chunk(o: Dictionary, c: Vector2, s: Vector2) -> void:
	var block: String = {"counter": "block_counter", "stove": "block_stove", "ktable": "block_ktable", "bar": "block_bar"}.get(o.type, "")
	if block != "" and sprite(block) != null:
		d_sprite(block, c)
		return
	match o.type:
		"counter":
			cuboid(c, s, 30.0, Color(0.42, 0.42, 0.42))
		"stove":
			cuboid(c, s, 56.0, Color(0.3, 0.3, 0.3))
		"ktable":
			cuboid(c, s, 26.0, Color(0.5, 0.4, 0.3))
		"bar":
			cuboid(c, s, 16.0, Color(0.42, 0.26, 0.14))


func draw_obj(o: Dictionary) -> void:
	var p: Vector2 = o.pos
	var sn: String = obj_sprite(o)
	if sn != "" and sprite(sn) != null:
		if o.type == "grub" or o.type == "innkeeper":
			d_poly(ellipse_pts(iso(p), 18.0, 9.0), Color(0, 0, 0, 0.35))
		d_sprite(sn, p)
		if o.type == "barrel" and o.state == "kicked":
			d_line(iso(p + Vector2(30, 24), 0.0), iso(p + Vector2(34, -24), 60.0), Color(0.6, 0.88, 1.0), 4.0)
		if o.type == "table" and o.state == "gift":
			d_sprite("item_gift", p, 14.0)
		return
	match o.type:
		"pot":
			if o.state == "full":
				cylinder(p, 17.0, 30.0, Color(0.68, 0.42, 0.26))
			else:
				cylinder(p, 17.0, 7.0, Color(0.3, 0.2, 0.14))
				d_line(iso(p + Vector2(-12, 12), 2.0), iso(p + Vector2(14, -10), 8.0), Color(0.5, 0.3, 0.2), 3.0)
		"chest":
			var open: bool = o.state == "open"
			if open:
				cuboid(p, o.size, 16.0, Color(0.2, 0.13, 0.08))
				cuboid(p + Vector2(0, -22), Vector2(o.size.x, 6.0), 36.0, Color(0.45, 0.3, 0.14), 10.0)
			else:
				cuboid(p, o.size, 22.0, Color(0.55, 0.38, 0.17))
				d_line(iso(p + Vector2(0, -o.size.y / 2.0), 22.0), iso(p + Vector2(0, o.size.y / 2.0), 22.0), Color(0.85, 0.7, 0.25), 3.0)
		"grub":
			var c: Vector2 = iso(p)
			d_poly(ellipse_pts(c, 20.0, 10.0), Color(0, 0, 0, 0.35))
			var gc: Color = Color(0.4, 0.72, 0.3) if o.state == "ok" else Color(0.3, 0.45, 0.25)
			d_circle(c + Vector2(0, -12), 14.0, gc)
			d_circle(c + Vector2(-5, -15), 2.0, Color(0.05, 0.1, 0.02))
			d_circle(c + Vector2(5, -15), 2.0, Color(0.05, 0.1, 0.02))
		"board":
			cuboid(p, o.size, 66.0, Color(0.52, 0.38, 0.22), 14.0)
			cuboid(p + Vector2(0, 0), Vector2(6.0, 8.0), 14.0, Color(0.35, 0.25, 0.15))
			if o.state != "empty":
				d_poly([iso(p + Vector2(8, -12), 52.0), iso(p + Vector2(8, 12), 52.0), iso(p + Vector2(8, 12), 30.0), iso(p + Vector2(8, -12), 30.0)], Color(0.96, 0.93, 0.8))
		"barrel":
			cylinder(p, 18.0, 42.0, Color(0.5, 0.33, 0.16))
			if o.state == "kicked":
				d_line(iso(p + Vector2(30, 24), 0.0), iso(p + Vector2(34, -24), 60.0), Color(0.6, 0.88, 1.0), 4.0)
		"table":
			cuboid(p, o.size, 26.0, Color(0.52, 0.36, 0.2))
			if o.state == "gift":
				cuboid(p, Vector2(18.0, 18.0), 12.0, Color(0.85, 0.3, 0.4), 26.0)
		"cart":
			cuboid(p, o.size, 22.0, Color(0.4, 0.46, 0.52))
			cuboid(p, o.size - Vector2(10, 8), 10.0, Color(0.22, 0.25, 0.3), 14.0, false)


func draw_floor_item(fi: Dictionary) -> void:
	var it: Dictionary = fi.item
	var col: Color = Color(1, 0.85, 0.2) if it.kind == "coin" else Color(0.9, 0.9, 1.0)
	if it.kind == "knowledge":
		col = Color(0.7, 1.0, 0.8)
	d_poly(ellipse_pts(iso(fi.pos), 9.0, 4.5), Color(0, 0, 0, 0.3))
	if d_sprite(item_sprite(it), fi.pos):
		return
	cuboid(fi.pos, Vector2(14, 14), 8.0, col)


func draw_marker() -> void:
	## Bobbing arrow over the thing the E / F prompt refers to.
	if not (phase == Phase.SHIFT or phase == Phase.PASSAGE):
		return
	for t in reach_list():
		var lb: Array = labels(t)
		if lb[0] == "" and lb[1] == "":
			continue
		var pos: Vector2 = t.ref.pos
		var top: float = 70.0 if t.kind == "obj" else (56.0 if t.kind == "hero" else 24.0)
		var bob: float = sin(float(Time.get_ticks_msec()) / 160.0) * 3.0
		var a: Vector2 = iso(pos, top + 14.0) + Vector2(0, bob)
		d_poly([a + Vector2(-8, -10), a + Vector2(8, -10), a], Color(1, 0.92, 0.3))
		return


func draw_labels() -> void:
	for id in objs:
		var o: Dictionary = objs[id]
		if o.room != cur_room:
			continue
		var p: Vector2 = o.pos
		match o.type:
			"pot":
				if o.state == "broken" and phase == Phase.SHIFT:
					txt(iso(p, 20.0) + Vector2(-20, 0), "broken", 11, Color(0.95, 0.5, 0.4))
			"chest":
				if o.state == "open" and o.item != null:
					txt(iso(p, 52.0) + Vector2(-40, 0), String(o.item.name), 11, Color(1, 0.9, 0.5))
				if o.gap:
					txt(iso(p, 40.0) + Vector2(-16, 0), "GAP!", 12, Color(1, 0.4, 0.4))
			"door":
				if o.state == "broken":
					txt(iso(Vector2(ROOM.position.x, p.y), 76.0) + Vector2(-14, 0), "broken", 11, Color(0.95, 0.5, 0.4))
			"grub":
				txt(iso(p, 34.0) + Vector2(-18, 0), "Grub" + (" (out cold)" if o.state == "out" else ""), 11, Color(0.7, 0.95, 0.6))
			"board":
				txt(iso(p, 84.0) + Vector2(-24, 0), "NOTICES", 10, Color(0.9, 0.8, 0.55))
			"barrel":
				if o.state == "kicked":
					txt(iso(p, 70.0) + Vector2(-14, 0), "crack", 11, Color(0.6, 0.88, 1.0))
			"table":
				txt(iso(p, 40.0) + Vector2(-26, 0), "gift table" if o.state == "empty" else "gift!", 11, Color(0.95, 0.85, 0.65))
			"cart":
				txt(iso(p, 30.0) + Vector2(-14, 0), "CART", 11, Color(0.85, 0.9, 0.95))
			"innkeeper":
				txt(iso(p, 46.0) + Vector2(-26, 0), "Innkeeper", 11, Color(1, 0.88, 0.6))
			"bar":
				txt(iso(p, 30.0) + Vector2(-14, 0), "BAR", 10, Color(1, 0.88, 0.6))
			"counter", "stove", "ktable":
				txt(iso(p, 40.0 if o.type == "stove" else 26.0) + Vector2(-24, 0), String(o.type).to_upper(), 10, Color(0.85, 0.85, 0.9))
	for fi in floor_items:
		if fi.room == cur_room and pell.distance_to(fi.pos) < 120.0:
			txt(iso(fi.pos, 22.0) + Vector2(-30, 0), String(fi.item.name), 11, Color(1, 1, 1))
	if cur_room == "inn":
		txt(iso(Vector2(450, 684), 4.0) + Vector2(-26, 22), "THE SEAM", 11, Color(0.7, 0.92, 1.0))
		txt(iso(Vector2(DOORWAY_X, ROOM.end.y), 0.0) + Vector2(-26, 18), "Kitchen v", 11, Color(0.7, 0.9, 0.6))
		txt(iso(Vector2(ROOM.end.x, 420), 0.0) + Vector2(-14, 24), "to Forest", 11, Color(0.6, 0.8, 0.55))
		txt(iso(ROOM.position, 0.0) + Vector2(20, 0), "THE SLEEPING STAG - INN", 13, Color(0.85, 0.75, 0.6))
	else:
		txt(iso(Vector2(DOORWAY_X, ROOM.position.y), 74.0) + Vector2(-14, 0), "Inn ^", 11, Color(0.7, 0.9, 0.6))
		txt(iso(ROOM.position, 0.0) + Vector2(20, 0), "INN KITCHEN", 13, Color(0.85, 0.8, 0.7))
	if phase == Phase.PASSAGE and hero_room == cur_room:
		txt(iso(hero_pos, 44.0) + Vector2(-16, 14), "HERO", 11, Color(1, 0.9, 0.4))
	if not in_cart:
		txt(iso(pell, 0.0) + Vector2(-9, 20), "Pell", 11, Color(0.6, 0.8, 1))


func draw_world_hud() -> void:
	## Crisp (non-pixelated) bits that sit on top of the world.
	if phase == Phase.PASSAGE and hero_room == cur_room and bark_time > 0.0:
		var bp: Vector2 = iso(hero_pos, 66.0)
		box(Rect2(bp + Vector2(-8, -24), Vector2(font.get_string_size(bark_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 14, 24)), Color(1, 1, 1, 0.92))
		txt(bp + Vector2(-1, -7), bark_text, 13, Color(0.1, 0.1, 0.1))
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
	var coin_txt: String = "Coin: %d" % total_coin()
	if carried_coin > 0:
		coin_txt += " (%d carried, expire)" % carried_coin
	txt(Vector2(x, y), "Actions left: %d    %s" % [actions, coin_txt], 14)
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
		y += 24.0 if String(l).length() < 62 else 42.0


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


func draw_shop() -> void:
	var r: Rect2 = overlay("THE SLEEPING STAG - BAR")
	var y: float = r.position.y + 90.0
	txt(Vector2(r.position.x + 24, y), "Your coin: %d%s" % [total_coin(), ("  (%d carried - spend first, they expire)" % carried_coin) if carried_coin > 0 else ""], 15, Color(1, 0.9, 0.4))
	y += 36.0
	var stock: Array = shop_stock()
	for i in stock.size():
		var col: Color = Color(0.93, 0.9, 0.82) if total_coin() >= int(stock[i].price) else Color(0.5, 0.5, 0.55)
		txt(Vector2(r.position.x + 24, y), "[%d] %s - %d coin" % [i + 1, stock[i].name, stock[i].price], 16, col)
		y += 32.0
	y += 20.0
	para(Vector2(r.position.x + 24, y), "Prices rise with the Hero's act. Your wage does not.", 550.0, 13, Color(0.75, 0.75, 0.8))
	txt(Vector2(r.position.x + 24, r.end.y - 20), "[Esc] close", 13, Color(0.6, 0.6, 0.65))


func draw_hero_talk() -> void:
	var r: Rect2 = overlay("SPEAK TO THE HERO")
	var y: float = r.position.y + 90.0
	para(Vector2(r.position.x + 24, y), "Nobody talks to the cleaner. Nobody expects the cleaner to talk back.", 550.0, 14, Color(0.8, 0.8, 0.85))
	y += 50.0
	txt(Vector2(r.position.x + 24, y), "[1] Greet him   (Charm)", 16, Color(1, 0.85, 0.9))
	y += 32.0
	txt(Vector2(r.position.x + 24, y), "[2] Remind him the pots belong to someone   (Compassion)", 16, Color(0.6, 0.9, 0.6))
	y += 32.0
	txt(Vector2(r.position.x + 24, y), "[3] Tell him a chest is cursed   (Control)", 16, Color(0.9, 0.7, 0.5))
	txt(Vector2(r.position.x + 24, r.end.y - 20), "[Esc] say nothing     (Talking draws his attention.)", 13, Color(0.6, 0.6, 0.65))


func draw_fight() -> void:
	if fight.is_empty():
		return
	var r: Rect2 = overlay("FIGHT THE HERO")
	var y: float = r.position.y + 84.0
	txt(Vector2(r.position.x + 24, y), "You  %d/%d" % [maxi(0, fight.ph), fight.pm], 15, Color(0.6, 0.8, 1))
	bar(Vector2(r.position.x + 120, y - 12), 300.0, float(fight.ph) / float(fight.pm), Color(0.4, 0.7, 0.95))
	y += 30.0
	txt(Vector2(r.position.x + 24, y), "Hero %d/%d" % [maxi(0, fight.hh), fight.hm], 15, Color(1, 0.85, 0.4))
	bar(Vector2(r.position.x + 120, y - 12), 300.0, float(fight.hh) / float(fight.hm), Color(0.9, 0.7, 0.25))
	y += 40.0
	var start: int = maxi(0, fight.log.size() - 7)
	for i in range(start, fight.log.size()):
		txt(Vector2(r.position.x + 24, y), String(fight.log[i]), 14, Color(0.9, 0.9, 0.95))
		y += 24.0
	txt(Vector2(r.position.x + 24, r.end.y - 44), "[1] Attack with the %s     [2] Run" % fight.w.name, 15, Color(1, 0.95, 0.6))
	txt(Vector2(r.position.x + 24, r.end.y - 20), "Better gear in your satchel makes you tougher. He is a Hero, and you are a cleaner.", 12, Color(0.6, 0.6, 0.65))


func draw_note_menu() -> void:
	var r: Rect2 = overlay("WRITE A NOTE")
	var y: float = r.position.y + 90.0
	txt(Vector2(r.position.x + 24, y), "The Hero always reads the notice board.", 15)
	y += 40.0
	txt(Vector2(r.position.x + 24, y), "[1] 'Please be gentle with the pots. They have feelings.'   (Compassion)", 15, Color(0.6, 0.9, 0.6))
	y += 30.0
	txt(Vector2(r.position.x + 24, y), "[2] 'URGENT: wolf in the forest. Go now.'   (Control)", 15, Color(0.9, 0.7, 0.5))
	txt(Vector2(r.position.x + 24, r.end.y - 20), "[Esc] cancel   (1 action; counts as your pinned notice)", 13, Color(0.6, 0.6, 0.65))


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
		"control": "Every quest the Hero takes is one you wrote. You cast every role from the shadows.",
		"defiance": "You beat the Hero. The story looks for a new Villain and Pell is already standing in the Tower.",
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
