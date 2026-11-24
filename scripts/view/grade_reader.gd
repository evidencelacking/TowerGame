extends RefCounted
## Reading many grades or complaints at once for a view (#487, #488). One grade asks every person which room they
## belong to, so grading every room of a big tower one by one is rooms times people. The sim's own evaluation avoids that
## with stress tables built in one pass (EvalTables.build_stress) that Grades reads while `batch` is set; this does
## the same around a view's reading and puts `batch` back. Nothing is written to the tower: the tables are derived.

const EvalTablesScript := preload("res://scripts/sim/eval_tables.gd")


## Switches the tower's grades to read from fresh stress tables. Returns what to hand to end().
static func begin(tower: Object) -> Variant:
	var was: Variant = tower.grades.batch
	tower.grades.batch = EvalTablesScript.build_stress(tower.people, tower.grades)
	return was


static func end(tower: Object, was: Variant) -> void:
	tower.grades.batch = was
