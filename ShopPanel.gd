extends CanvasLayer

# ---------------------------------------------------------------------------
# The shop window used in Endless Mode and multiplayer: the same shop art and
# item cards (ShopItemCard.tscn) as Town.tscn's shop, as a reusable overlay.
# Layout lives in ShopPanel.tscn; this script fills in the item cards and
# reports clicks.
#
# It knows nothing about networking or where gold lives. The owner (see
# ShopManager.gd) gives it two callables when it's set up -- "how much gold do
# I have" and "how many of this item do I own" -- and listens for
# purchase_requested. A click does not change anything here: the owner decides
# whether the purchase happens and then calls show_result() and refresh().
# ---------------------------------------------------------------------------

signal purchase_requested(item_id: String)
signal closed  # the window went from open to closed (X button, Escape, or the owner closing it)

const CARD_SCENE: PackedScene = preload("res://ShopItemCard.tscn")
const CARD_TEXT_LEFT_WITHOUT_ICON: float = 16.0  # where a card's text starts when the item has no icon (with one it's in the scene)

@onready var title_label: Label = %ShopTitleLabel
@onready var gold_label: Label = %ShopGoldLabel
@onready var items_root: Control = %ShopItems

var _get_gold: Callable = Callable()
var _get_owned: Callable = Callable()  # takes an item_id, returns how many the local player owns
var _cards: Dictionary = {}  # item_id -> {"owned_label": Label, "status_label": Label}

func _ready() -> void:
	%ShopCloseButton.pressed.connect(close)

func setup(get_gold: Callable, get_owned: Callable) -> void:
	_get_gold = get_gold
	_get_owned = get_owned

func is_open() -> bool:
	return visible

func open(title: String, item_ids: Array) -> void:
	title_label.text = title
	_populate_items(item_ids)
	refresh()
	visible = true

func close() -> void:
	var was_open: bool = visible
	visible = false
	if was_open:
		closed.emit()

# Re-reads gold and owned counts -- call after anything that may have changed them.
func refresh() -> void:
	gold_label.text = "Your gold: %d" % _current_gold()
	for item_id: String in _cards:
		_cards[item_id]["owned_label"].text = "Owned: %d" % _current_owned(item_id)

# Shows the outcome of a purchase attempt on that item's card.
func show_result(item_id: String, success: bool, message: String) -> void:
	if not _cards.has(item_id):
		return
	var status_label: Label = _cards[item_id]["status_label"]
	status_label.text = message
	status_label.add_theme_color_override("font_color", Constants.STATUS_SUCCESS_COLOR if success else Constants.STATUS_ERROR_COLOR)

func _current_gold() -> int:
	return int(_get_gold.call()) if _get_gold.is_valid() else 0

func _current_owned(item_id: String) -> int:
	return int(_get_owned.call(item_id)) if _get_owned.is_valid() else 0

func _populate_items(item_ids: Array) -> void:
	# remove_child first so the old cards leave the list immediately rather than
	# lingering (and taking up space) until the end of the frame.
	for child in items_root.get_children():
		items_root.remove_child(child)
		child.queue_free()
	_cards.clear()
	for item_id: String in item_ids:
		_add_item_card(item_id)

func _add_item_card(item_id: String) -> void:
	var item: Dictionary = ItemData.get_item(item_id)
	if item.is_empty():
		return

	var card: Control = CARD_SCENE.instantiate()
	items_root.add_child(card)

	var icon_texture: Texture2D = ItemData.get_item_icon(item_id)
	var icon_rect: TextureRect = card.get_node("Icon")
	icon_rect.texture = icon_texture
	icon_rect.visible = icon_texture != null
	var text_column: Control = card.get_node("TextColumn")
	if icon_texture == null:
		text_column.position.x = CARD_TEXT_LEFT_WITHOUT_ICON

	(card.get_node("TextColumn/NameLabel") as Label).text = item.get("name", item_id)
	(card.get_node("TextColumn/CostLabel") as Label).text = "%d gold" % int(item.get("cost", 0))
	var owned_label: Label = card.get_node("TextColumn/OwnedLabel")
	var status_label: Label = card.get_node("TextColumn/StatusLabel")

	var buy_button: Button = card.get_node("BuyButton")
	buy_button.focus_mode = Control.FOCUS_NONE  # so Space (the attack key) can't "press" a focused Buy button
	buy_button.pressed.connect(_on_buy_pressed.bind(item_id))
	PixelButton.apply(buy_button)

	_cards[item_id] = {"owned_label": owned_label, "status_label": status_label}

func _on_buy_pressed(item_id: String) -> void:
	var cost: int = int(ItemData.get_item(item_id).get("cost", 0))
	if _current_gold() < cost:
		show_result(item_id, false, "Not enough gold!")
		return
	show_result(item_id, true, "")  # clear any old message while the request is in flight
	purchase_requested.emit(item_id)
