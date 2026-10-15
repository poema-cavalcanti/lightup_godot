class_name SessionEconomy
extends RefCounted

# ---------------------------------------------------------------------------
# A multiplayer match's gold, purchases and equipment, carried across the scene
# changes between a level (Game.tscn) and the Town between levels (Town.tscn).
# Each scene keeps working on its own references to these arrays (Game's
# player_gold / player_inventory / player_equipped, Town's identical ones), so
# this class only does the hand-off: Game.store()s them when it leaves for Town
# and take()s them back when it loads again.
#
# Still session-only: nothing here is saved, and a fresh match (the lobby's
# Start Game) always starts empty -- see NetworkManager._begin_game().
# ---------------------------------------------------------------------------

static var gold: Array[int] = []
static var inventory: Array[Dictionary] = []
static var equipped: Array[Dictionary] = []
static var carry: bool = false  # true only between a scene saving them and the next Game adopting them

static func store(new_gold: Array[int], new_inventory: Array[Dictionary], new_equipped: Array[Dictionary]) -> void:
	gold = new_gold
	inventory = new_inventory
	equipped = new_equipped
	carry = true

# Game.tscn, on load: true if the arrays above are a match in progress for this many players
# (the caller then adopts them); false means start empty. Either way the hand-off is consumed.
static func take(player_count: int) -> bool:
	var usable: bool = carry and NetworkManager.is_multiplayer and gold.size() == player_count and inventory.size() == player_count and equipped.size() == player_count
	carry = false
	return usable
