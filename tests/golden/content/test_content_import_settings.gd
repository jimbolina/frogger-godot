extends GutTest
## Every imported texture and font under content/ follows the project import
## policy ([ImportPolicyCheck]).


func test_sidecars_follow_the_project_policy() -> void:
	ImportPolicyCheck.check(self, PackedStringArray([ImportedAssets.SHIPPABLE_ROOT]))
