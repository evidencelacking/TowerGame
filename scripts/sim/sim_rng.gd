extends RefCounted
## The simulation's only random source: PCG32 on integers, seeded and saveable.
## Never use randi, randf or RandomNumberGenerator in the simulation.

const MULTIPLIER := 6364136223846793005
const INCREMENT := 1442695040888963407  # odd, fixed stream
const MASK32 := 0xFFFFFFFF
const RANGE32 := 0x100000000

## The whole generator state. Saved with the Tower.
var state: int = 0


func _init(seed_value: int = 0) -> void:
	reseed(seed_value)


func reseed(seed_value: int) -> void:
	state = 0
	next_u32()
	state += seed_value
	next_u32()


## Next 32-bit unsigned value (0 to 4294967295).
func next_u32() -> int:
	var old := state
	state = old * MULTIPLIER + INCREMENT  # wraps in 64 bits on every machine
	# Logical shifts: GDScript >> is arithmetic, so mask off the sign fill.
	var xorshifted := ((((old >> 18) & 0x3FFFFFFFFFFF) ^ old) >> 27) & MASK32
	var rot := (old >> 59) & 31
	return ((xorshifted >> rot) | (xorshifted << ((32 - rot) & 31))) & MASK32


## Uniform integer in [0, bound), bound 1 to 2^32. Rejection sampling avoids modulo bias.
## Each draw is accepted with probability above one half, so the loop ends.
func next_below(bound: int) -> int:
	assert(bound > 0 and bound <= RANGE32, "bound must be 1 to 2^32")
	var limit := RANGE32 - (RANGE32 % bound)
	var value := next_u32()
	while value >= limit:
		value = next_u32()
	return value % bound
