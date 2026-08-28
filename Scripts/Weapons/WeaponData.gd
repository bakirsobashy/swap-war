class_name WeaponData
extends Resource

## Unique weapon archetype name used as the database key.
@export var weapon_name: String = ""

## "melee" or "ranged".
@export var category: String = "melee"

## Base damage dealt per hit or per projectile.
@export var damage: float = 10.0

## Seconds between attacks / shots.
@export var attack_cooldown: float = 0.5

## 0.0..1.0 chance to deal a critical hit.
@export var critical_chance: float = 0.0

## Number of successful melee hits or ranged shots before the weapon breaks.
@export var durability: int = 10

## Physical knockback applied to RigidBody2D victims.
@export var knockback: float = 300.0

## How far the weapon thrusts forward during a melee attack.
@export var attack_thrust_distance: float = 32.0

## How long the melee attack window lasts.
@export var attack_thrust_duration: float = 0.15

## Total arc (in degrees) for sword slash visuals.
@export var slash_arc_degrees: float = 90.0

## Projectile speed for ranged weapons.
@export var projectile_speed: float = 600.0

## How long a projectile lives before despawning.
@export var projectile_lifetime: float = 1.0

## Display texture for the weapon when held / on the ground.
@export var texture: Texture2D = null
