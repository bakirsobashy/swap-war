class_name TeamPalette

## The one team-colour table. Health bars, the HUD scoreboard, the swap
## timer and the overhead ActorMarker all read it, so they can never
## disagree. (Body/hand sprites per team live in TeamMember.)
##
## The colours are the fighter sprites' own fills (character_round*.png), so
## every UI colour matches the body it labels: mint #37D98C, coral #FC5C65,
## lavender #9179FF, amber #FFB600.
const COLORS: Array[Color] = [
	Color(0.215686, 0.85098, 0.54902),    # green
	Color(0.988235, 0.360784, 0.396078),  # red
	Color(0.568627, 0.47451, 1.0),        # purple
	Color(1.0, 0.713725, 0.0),            # yellow
]
## Notebook Doodle ink: outline every team-coloured text/mark with it — the
## lighter lavender/amber are faint on the paper UI without one.
const INK := Color(0.121569, 0.121569, 0.121569)

static func color(team_id: int) -> Color:
	if team_id < 0 or team_id >= COLORS.size():
		return Color.WHITE
	return COLORS[team_id]
