class_name CollisionConfig

## Named 2D physics layer values.
const LAYER_WORLD: int = 1
const LAYER_ACTORS: int = 2
const LAYER_ONEWAY: int = 4
const LAYER_WEAPONS: int = 8
const LAYER_PICKUP: int = 16
const LAYER_HELD_WEAPONS: int = 32

## Pre-built masks for common object types.
const MASK_GROUND_WEAPON: int = LAYER_WORLD | LAYER_WEAPONS
