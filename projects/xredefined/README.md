# Repro for "X is redefined from X" error

## 1st repro - Get initial issue leading to x redefined

```
node /path/to/haxerepro/bin/replay.js --path recording --file repro.log
```

Expected output:

```
3: Trigger first error that leads to X redefined from X
4: ----------------------------------------------------
12: > Server request "cache build"
15: > Server request "server/invalidate"
19: > Server request "server/contexts"
  3 load_core_class (js, 3 defines)
    signature: 54e8126e2d80def32b1f2f78791a7488
  2 load_core_class (eval, 4 defines)
    signature: ba6b1c082bc0d77cc09ca5f81809c1f0
  1 get_macro_context (eval, 20 defines)
    signature: 03f8c3216332b3d1d6f3df4af521331e
  0 after_init_macros (js, 16 defines)
    signature: be71fc52ec50d6d1b20d5b77751880e0
24: data.args.|
26: > Server request "display/completion"
26 => Completion request returned 23 items
31: data.args.|
33: > Server request "display/completion"
33 => Completion request returned 23 items
38: > Server request "compilation"
38: => Compilation error:
src/TestsMain.hx:7: characters 12-33 : [2] Instance constructor not found: CodeBuilder
Failure detected, aborting rest of script.
```

## 2nd repro - Get x redefined error

```
node /path/to/haxerepro/bin/replay.js --path recording --file repro-1.log
```

Expected output:

```
3: Trigger X redefined from X
4: ----------------------------------------------------
12: > Server request "cache build"
15: > Server request "server/invalidate"
20: data.args.|
22: > Server request "display/completion"
22 => Completion request returned 23 items
27: data.args.|
29: > Server request "display/completion"
29 => Completion request returned 23 items
34: data.args.|
36: > Server request "display/completion"
36 => Completion request returned 23 items
41: > Server request "compilation"
41: => Compilation error:
Type name CodeBuilder is redefined from module CodeBuilder (03f8c3216332b3d1d6f3df4af521331e)
Failure detected, aborting rest of script.
```

## 3rd repro - Broken completion

```
cd repro/xredefined
node /path/to/haxerepro/bin/replay.js --path recording --file repro-2.log
```

Expected output:

```
3: Trigger completion error
4: ----------------------------------------------------
13: > Server request "cache build"
13: => Server response:

16: > Server request "server/invalidate"
21: data.args.|
23: > Server request "display/completion"
23 => Completion request returned 23 items
28: data.args.|
30: > Server request "display/completion"
30 => Completion request returned 23 items
35: data.args.|
37: > Server request "display/completion"
37 => Completion request returned 23 items
41: data.args.|
43: > Server request "display/completion"
43 => Completion request returned 0 items
4 assertions with 0 failures
```
