class_name CollisionConfig

## Named 2D physics layer values.
const LAYER_WORLD: int = 1
const LAYER_ACTORS: int = 2
const LAYER_ONEWAY: int = 4
const LAYER_WEAPONS: int = 8
const LAYER_PICKUP: int = 16
const LAYER_HELD_WEAPONS: int = 32

## Pre-built masks for common object types.
const MASK_ACTOR_BODY: int = LAYER_WORLD | LAYER_ONEWAY
const MASK_GROUND_WEAPON: int = LAYER_WORLD | LAYER_WEAPONS
const MASK_HELD_WEAPON: int = LAYER_WORLD
const MASK_PROJECTILE: int = LAYER_WORLD | LAYER_ACTORS
const MASK_PICKUP: int = LAYER_WEAPONS
const MASK_KILLZONE: int = LAYER_ACTORS | LAYER_WEAPONS | LAYER_HELD_WEAPONS
const MASK_GROUND_CHECK: int = LAYER_WORLD | LAYER_ONEWAY
const MASK_AI_NAV_RAYS: int = LAYER_WORLD | LAYER_ONEWAY
