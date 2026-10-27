class_name RewardSetup
extends RefCounted
## Transfers supplied executable reward records into detached gameplay definitions.

var definitions: Array[RewardDefinition] = []
var error: String = ""

## Requires every source reward ID, retaining modified values and flag precedence.
static func from_table(table: ScoreTable) -> RewardSetup:
	var result := RewardSetup.new()
	result.error = table.error
	if not result.error.is_empty():
		return result
	if table.values.size() != 24 or table.flags.size() != 24:
		result.error = "SCORE_BOOK requires all 24 source reward records"
		return result
	for index: int in 24:
		var reward := RewardDefinition.new()
		reward.value = table.values[index]
		reward.flags = table.flags[index]
		result.definitions.append(reward)
	return result
