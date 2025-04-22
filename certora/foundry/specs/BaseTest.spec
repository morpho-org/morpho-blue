use builtin rule verifyFoundryFuzzTests;

override function init_fuzz_tests(method f, env e) {
    setUp(e);
}
