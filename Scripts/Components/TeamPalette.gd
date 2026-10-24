class_name TeamPalette

## The one team-colour table. Health bars, the HUD scoreboard, the swap
## timer and the overhead ActorMarker all read it, so they can never
## disagree. (Body/hand sprites per team live in TeamMember.)

const COLORS: Array[Color] = [Color.GREEN, Color.RED, Color.PURPLE, Color.YELLOW]

static func color(team_id: int) -> Color:
	if team_id < 0 or team_id >= COLORS.size():
		return Color.WHITE
	return COLORS[team_id]
