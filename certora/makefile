munged: $(wildcard ../src/*.sol) munging.patch
	@rm -rf munged
	@cp -r ../src munged
	@patch -p0 -d munged < munging.patch

record:
	diff -ruN ../src munged | sed 's+\.\./src/++g' | sed 's+munged/++g' > munging.patch

clean:
	rm -rf munged

.PHONY: record clean # do not add munged here, as it is useful to protect munged edits
