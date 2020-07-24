# [WIP] faffer
faffer is like a fuzzer, but a bit lazier. Instead of trying *to run* a thing every way it can run, it tries *to not-run* a thing every way it can run.

It's an experiment in using a fuzzing/tree-shaking approach to finding unresolved dependencies on external programs. I'll be comparing this against results from the other/static side of the problem in https://github.com/abathur/resholved. 

If it is useful for ferreting anything out that resholved is missing, or provides verification that enables resholved to solve some cases with additional confidence, it'll likely have a future. If not, it'll probably just be a weird experiment?
