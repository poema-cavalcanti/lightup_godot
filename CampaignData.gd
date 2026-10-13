class_name CampaignData
extends RefCounted

# ---------------------------------------------------------------------------
# Pure data: the ten campaign puzzles, plus every piece of cutscene dialog
# and the pure function that decides which branch to show. CampaignManager
# owns *when* to show a cutscene and tracks the play-by-play history;
# everything here is stateless and only cares about that history array.
#
# Dialog arrays are pre-split one sentence (or short beat) per element --
# Cutscene.gd shows exactly one element per "Continue" press, replacing the
# previous line rather than appending to it (matching a classic dialogue
# box, and the "like in Stardew Valley" reference).
#
# Each level lists several interchangeable puzzle layouts under
# "puzzle_rows_options" rather than a single fixed one -- CampaignManager
# picks one at random each time that level is (re)started, so replaying
# the campaign (or retrying a level) doesn't always show the exact same
# board. Levels 7-10 currently only have one option each; drop more
# more puzzle layouts into their "puzzle_rows_options" list the same way
# to get the same variety there.
# ---------------------------------------------------------------------------

const LEVELS: Array[Dictionary] = [
	{
		"puzzle_rows_options": [
			[
			".0........", ".#.1.#..##", "......#...", "..#.....1.", ".#..01....",
			"....1#..#.", ".2.....1..", "...0......", "##..1.1.3.", "........#.",
			],
			[
			"....3...1.", "1..3.3....", "..........", "....#...2.", ".2....#..#",
			"2..0....3.", ".1...2....", "..........", "....#.0..#", ".0...1....",
			],
			[
			"#.#..1...0", "..2.......", "........##", "....0.....", "0.....#...",
			"...0.....2", ".....3....", "#1........", ".......#..", "#...#..0.1",
			],
		],
	},
	{
		"puzzle_rows_options": [
			[
			"#........#", "..#...1...", "...3..#.2.", ".13....#..", "..........",
			"..........", "..#....12.", ".#.0..3...", "...#...1..", "#........1",
			],
			[
			"....0.....", "....0#.1..", ".1........", "...2..1...", ".2......1#",
			"##......2.", "...#..3...", "........1.", "..1.2#....", ".....#....",
			],
			[
			".#........", "...#.#.3.2", ".1....1...", "..0.....#.", ".#........",
			"........3.", ".1.....2..", "...#....#.", "0.1.1.0...", "........#.",
			],
		],
	},
	{
		"puzzle_rows_options": [
			[
			"...3.1....", ".......1..", ".#.#..3...", "..#....#.#", "3...##....",
			"....##...#", "#.2....2..", "...2..1.2.", "..2.......", "....#.0...",
			],
			[
			".3.##.....", ".....#1..#", "......#...", ".#2......1", ".#.......#",
			"#.......1.", "0......21.", "...#......", "1..#0.....", ".....#0.0.",
			],
			[
			".......2..", "..0..3#...", "#...2...0.", ".1........", ".1.....2..",
			"..0.....2.", "........1.", ".#...0...#", "...##..0..", "..0.......",
			],
			[
			"0...0....1", "..#.......", "..1..1.10.", "..........", "..2......#",
			"0......0..", "..........", ".#0.3..#..", ".......#..", "0....#...2",
			],
		],
	},
	{
		"puzzle_rows_options": [
			[
			"2.#..2..#..1.#", "..1..1........", "1...1.1.....00", "..............", ".......10..1..",
			"0...0..#....##", "....0#.....2..", "..#.....11....", "#0....1..#...#", "..1..##.......",
			"..............", "#1.....1.0...#", "........1..1..", "#.#..0..#..#.#",
			],
			[
			"#.#..##.0....#", "...4..#....#..", ".#......1.#..3", "..2.0.2.....#.", "....#....#1...",
			"#.#...#......1", "........1.#.##", "1#.3.2........", "1......#...#.#", "...10....#....",
			".#.....3.#.3..", "2..#.1......#.", "..0....#..#...", "#....#.#0..1.#",
			],
			[
			".3......1..#..", "....#......2.2", "01#.....#.#0..", "..#...........", "....#.#.1#..0.",
			"#.0.2.#.......", "........2#....", "....1#........", ".......0.#.#.#", ".0..1#.0.1....",
			"...........#..", "..1#.0.....#2#", "3.#......0....", "..1..#......#.",
			],
		],
	},
	{
		"puzzle_rows_options": [
			[
			"......#2.2....", ".3#...#.....#.", ".....#......2.", "..............", "#...3....#....",
			".....2..1..0..", "0...........##", "11...........0", "..2..1..#.....", "....0....#...2",
			"..............", ".#......#.....", ".#.....1...00.", "....1.0.......",
			],
			[
			"..#..#.....3..", "..1...00......", "1..0........##", "...1...22.#1..", "......#.......",
			"...#..#......#", ".#.#....01..#.", ".#..31....#.1.", "#......#..0...", ".......2......",
			"..2#.1#...#...", "01........0..#", "......#0...1..", "..0.....#..#..",
			],
			[
			".#........#...", "...1..3......#", "..1....###.#..", "#..2..#...2.0.", "..#..1........",
			"..2......#....", "..#...0#..#.1.", ".2.1..##...1..", "....#......#..", "........2..2..",
			".2.3...1..#..#", "..#.#1#....#..", "0......2..0...", "...1........0.",
			],
		],
	},
	{
		"puzzle_rows_options": [
			[
			"....#..0......", "..2..#...11...", "..#...2.#..00.", ".2............", ".1...#..#....#",
			"..0.2..1.3..1.", "#....#.....#..", "..#.....#....1", ".#..#.4..#.#..", "0....4..0...1.",
			"............0.", ".##..#.#...#..", "...21...2..2..", "......#..#....",
			],
			[
			"......#...1...", ".01.2......00.", ".#.....2....#.", "0...##...#....", "...2...1..0.1.",
			"......0...#...", "..#.#...#....2", "1....#...2.2..", "...2...0......", ".2.1..2...#...",
			"....0...##...#", "....0...##...#", ".1#......0.#2.", "...#...#......",
			],
			[
			"....##........", "...12..#1.....", ".....3..#1....", "........#...2.", "..2.#....2..##",
			".1#3...2...#.1", ".#...0........", "........1...1.", "#.#...0...##0.", "12..#....0.#..",
			".#...#........", "....##..#.....", ".....22..11...", "........#1....",
			],
		],
	},
	{
		"puzzle_rows_options": [
			[
			".....0..#..#.#1...#...2..", ".2....1..2....#.....1###.", "2##.....#.0...11.#..#.3..", ".#...1.#......0..#.......",
			".##....1........2........", ".....1...0#..#....##.#..1", "0....0.##..2.##..#.....#.", "..00..1###.......##.11...",
			"....#...1..#....###...2.#", "..#......2.1...2.#.#...#.", "0###..#......1.....#..2..", "#....11...2....##.3.....1",
			"............#............", "#.....2.##....#...##....#", "..3..#.....0......#..##1#", ".#...#.#.#...#.3......#..",
			"1.#...###....1..#...2....", "...#2.##.......###1..#2..", ".2.....#..2#.0..##.0....#", "2..2.0#....#..#3...#.....",
			"........#........#....##.", ".......1..1......#.3...1.", "..#.2..#.0#...1.2.....0##", ".###1.....#....#..#....2.",
			"..1...0...##.#..1..1.....",
			],
		],
	},
	{
		"puzzle_rows_options": [
			[
			"0..##..1...###0..#1.....#", "....##..##.......2.1.11..", ".01.#.........2.#..#..#..", ".#........1......#.#....#",
			".......#1.......#.....###", ".0##.1.....#.3.#...1...#.", "#.......0#1##..#.0.......", "##.#..3.#...........#...#",
			"..1.#....0...00..2#.1..0.", ".....##...1.....#.2....#.", "0.1.....#......1..#..1...", "1....#..#...1.....#2....#",
			"#.....2....##1....#.....#", "#....0#.....1...0..3....#", "...#..#..#......2.....0.#", ".1....0.#.....2...##.....",
			".#..1.01..##...#....1.#..", "#...#...........#.2..#.3#", ".......#.1..#####.......#", ".0...#...#.#.3.....2.##2.",
			"#1#.....#.......##.......", "1....#.2......#........#.", "..#..#..3.2.........0.#1.", "..00.1.2.......01..##....",
			"#.....##..###0...2..##..#",
			],
		],
	},
	{
		"puzzle_rows_options": [
			[
			"#0..1.....0#.#.##...#1.##", "#................01.....#", "...0.#.1.#...#...0.......", "1..0..##..2....0.....##..",
			"#......1..#1...#..10....2", "....#....0..1....3#...#..", ".2..1#.0.##...1......#...", ".0#..1.0#..2....###.###..",
			"#......#.....#...0.......", "1..1#.....2...#...##..2..", "......2..#...2.1..#.2#..1", "#.#.....1.#......1..#...#",
			".....2......0......0.....", "#...#..0......1.2.....#.1", "#..##.#..#.3...2..#......", "..1..2#...#...1.....#0..#",
			".......1...1.....1......#", "..1#0.###....#..00.#..##.", "...1......#...2#.#.01..2.", "..#...##....#..#....#....",
			"#....11..0...02..1......#", "..#0.....2....#..#2..#..#", ".......0...1...#.1.#.1...", "0.....#1................#",
			"##.2#...##.#.#2.....#..1#",
			],
		],
	},
	{
		"puzzle_rows_options": [
			[
			"...2.....1..2....0##2.#1.", "#....1..2..#...0...2.....", "#...#0..1#...0..#........", "...#.........#..#1.###..#",
			"2..#0...............0.2..", "#1.#...#....#..1.#2...##.", "#....0......#..0#........", "1..#.#.2..#.#....#.#.....",
			"..0#..#.1.#.#.0.2.....##.", ".#...#1...#...#.......2.2", "........###.2.####.......", "..##...................#.",
			"0....####.#...#.2##0....#", ".#...................0#..", ".......####.#.###........", "#.#.......#...#...##...1.",
			".11.....0.#.2.#.2.#..11..", ".....1.1....0.0..#.2.1..#", "........#0..#......1....#", ".0#...#1.#..#....0...#.0#",
			"..#.#...............##..#", "2..#00.##..1.........3...", "........1..#...#1..#3...#", ".....#...2...#..2..#....#",
			".12.###0....0..#.....#...",
			],
		],
	},
]

const CHAPTER_ORDINALS: Array[String] = [
	"One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten",
]

# --- Fixed, always-the-same intro (shown before level 1 ever starts) -------
const CHAPTER_ONE_INTRO: Array[String] = [
	"For your first job you'll be lighting up the Necromancer's Guild office's old dungeon.",
	"They're moving to that fancy new building closer to the cemetery and it's got the whole guild busy preparing.",
	"That's where you come in.",
	"In order to stay on schedule they need a little extra help getting ready to clean up their dungeons.",
	"It's so dark down there they can hardly tell which surfaces are covered in blood and bones so what you've got to do is just get the place nice and bright for the cleaning crew.",
	"The Guild has been kind enough to inform us that there is an old security spell in effect that summons an undead golem but it's one of those light sensitive spells!",
	"Isn't that lucky?",
	"You probably won't even see it with how quickly you work.",
	"You did say you could do it under five minutes, right?",
	"Speaking of light spells you did read the safety instructions for your Twinkle Scintillations Inc Lumen Lighter spell right?",
	"The Lumen's don't like to look at each other so watch out for that.",
	"Well that enough talking.",
	"I'll let you get to it.",
]

# --- After level 1 (branches on whether the boss was summoned) -------------
const AFTER_LEVEL_1_CLEAN: Array[String] = [
	"Great job on that first dungeon!",
	"You finished that up right quick!",
	"The Guild only has two more of these in the building so keep on hustling and you'll be done in no time!",
]
const AFTER_LEVEL_1_BOSS: Array[String] = [
	"Wow that was dramatic, wasn't it?",
	"Not to worry there's only two more of these in the building so just pick up the pace and hopefully you won't have to deal any more golems.",
]

# --- After level 2 (branches on the level 1 + level 2 combination) ---------
const AFTER_LEVEL_2_NEVER: Array[String] = [
	"You're great at this!",
	"Just one more left, swift boots.",
	"I've already gotten some leads on another job because of this.",
	"I'll give you the details when you're done.",
]
const AFTER_LEVEL_2_STRUGGLED: Array[String] = [
	"Oof.",
	"You doing okay there, buddy?",
	"Listen, there's just one dungeon left here at the guild so just try to stay alive.",
	"If you survive this last dungeon we can talk about the next job.",
	"Kidding about the 'if'!",
	"I believe in you 100%!",
]
const AFTER_LEVEL_2_IMPROVED: Array[String] = [
	"Look who finally got the hang of this!",
	"Good job!",
	"Now don't slack off, I've already gotten some leads on another job.",
	"I'll give you the details when you're done.",
]

# --- After level 3 onward, and the ending: same 7-way split, chosen by ----
# --- evaluate_boss_path() below. Content not written yet -- placeholders. --
const BOSS_PATH_PLACEHOLDER: Dictionary = {
	1: ["Path 1"],
	2: ["Path 2"],
	3: ["Path 3"],
	4: ["Path 4"],
	5: ["Path 5"],
	6: ["Path 6"],
	7: ["Path 7"],
}
const ENDING_PLACEHOLDER: Dictionary = {
	1: ["Ending 1"],
	2: ["Ending 2"],
	3: ["Ending 3"],
	4: ["Ending 4"],
	5: ["Ending 5"],
	6: ["Ending 6"],
	7: ["Ending 7"],
}

# Decides which of the 7 branches applies, given the full boss-summon
# history so far (one bool per completed level, true = boss was summoned
# that level). The 7 cases as described aren't quite mutually exclusive as
# literally numbered (e.g. "summoned every level" is also "summoned this
# level and the majority"), so this checks the two extremes first (never /
# always), then the exact-50% tie, then splits the remaining minority/
# majority cases by whether the just-finished level was itself a summon --
# giving each of the 7 outcomes a distinct, non-overlapping condition.
static func evaluate_boss_path(boss_summoned_history: Array[bool]) -> int:
	var total_levels: int = boss_summoned_history.size()
	var summon_count: int = 0
	for was_summoned: bool in boss_summoned_history:
		if was_summoned:
			summon_count += 1
	var just_completed_summoned: bool = boss_summoned_history[total_levels - 1]

	if summon_count == 0:
		return 1
	if summon_count == total_levels:
		return 7
	if summon_count == total_levels / 2.0:
		return 4
	if summon_count < total_levels / 2.0:
		return 2 if just_completed_summoned else 3
	return 5 if just_completed_summoned else 6
