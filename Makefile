# For convenience, add the following to your aliases:
# `function f() { make forge ARGS="$*"; }`

forge:
	@FOUNDRY_PROFILE=no_via_ir forge $(ARGS)

.PHONY: forge
