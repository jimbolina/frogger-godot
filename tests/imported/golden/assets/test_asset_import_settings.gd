extends AssetTest
## Every imported texture, WAV and Ogg under assets/ follows the project
## import policy ([ImportPolicyCheck]).


func test_sidecars_follow_the_project_policy() -> void:
	ImportPolicyCheck.check(self, PackedStringArray([ASSETS]))
