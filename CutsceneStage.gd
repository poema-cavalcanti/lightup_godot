class_name CutsceneStage
extends Control

# ---------------------------------------------------------------------------
# Base script for a hand-built, per-cutscene scene: res://cutscenes/<scene_key>.tscn
# (e.g. res://cutscenes/chapter_1_intro.tscn). Cutscene.gd instances that scene
# into its Stage area when the matching cutscene opens, and calls play_line()
# every time a dialogue line is shown. The dialogue TEXT stays in
# CampaignData (it branches too much to live in animation tracks); this scene
# only owns the visuals -- sprites, backgrounds, camera moves, effects.
#
# To make a cutscene:
#   1. Copy res://cutscenes/_template.tscn to res://cutscenes/<scene_key>.tscn.
#      (The stage is the full 1280x720 window; the dialogue bar and chapter
#      title are drawn on top of it at the bottom / top-left, so keep key
#      action out of the bottom ~150px.)
#   2. Add your nodes and animate them in the scene's AnimationPlayer, in a
#      single animation named "cutscene" (or change animation_name below).
#   3. In the Animation editor, insert MARKERS on the timeline (right-click the
#      time ruler -> Insert Marker) named line_0, line_1, line_2, ... -- one at
#      the start of the beat that should play when that dialogue line appears.
#      Optionally add a marker named "end" to close the last line's beat.
#
# When dialogue line N is shown, the animation plays from marker line_N up to
# marker line_(N+1) (or "end", or the end of the animation for the last line),
# then stops and holds its final pose until the next line. A line with no
# marker simply plays nothing, so a cutscene can animate only some of its
# lines. Need something different (skippable beats, waiting on the animation
# before Continue works, etc.)? Override play_line() in a script that extends
# this one -- Cutscene.gd only ever calls play_line().
# ---------------------------------------------------------------------------

# Found automatically (first AnimationPlayer anywhere below this node) if left
# empty, which is the usual case.
@export var animation_player: AnimationPlayer
@export var animation_name: StringName = &"cutscene"

func _ready() -> void:
	if animation_player == null:
		var players: Array[Node] = find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			animation_player = players[0] as AnimationPlayer

# Called by Cutscene.gd each time dialogue line `line_index` (0-based) is shown,
# including line 0 when the cutscene first opens.
func play_line(line_index: int) -> void:
	if animation_player == null or not animation_player.has_animation(animation_name):
		return
	var animation: Animation = animation_player.get_animation(animation_name)
	var start_marker: StringName = StringName("line_%d" % line_index)
	if not animation.has_marker(start_marker):
		return
	var next_marker: StringName = StringName("line_%d" % (line_index + 1))
	var end_marker: StringName = &""  # empty = play to the end of the animation
	if animation.has_marker(next_marker):
		end_marker = next_marker
	elif animation.has_marker(&"end"):
		end_marker = &"end"
	animation_player.play_section_with_markers(animation_name, start_marker, end_marker)
