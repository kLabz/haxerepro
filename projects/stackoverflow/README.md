# Repro for "Stack overflow" error

This repro has been recorded on `haxeserver` project while writing haxerepro
tools.

Clone the repository somewhere, and install its dependencies:

```
git clone --recursive -b poc/repro-tool https://github.com/kLabz/haxeserver.git
cd haxeserver
haxelib newrepo
haxelib install --always install.hxml
```

You can then run [haxerepro tools](https://github.com/kLabz/haxerepro) on this recording, from `haxeserver` folder:

```
node /path/to/haxerepro/bin/replay.js --path /path/to/haxerepro-stackoverflow --file repro-min.log
```

On linux, you probably need `repro-min-linux.log` to reproduce the issue without
additional errors:

```
node /path/to/haxerepro/bin/replay.js --path /path/to/haxerepro-stackoverflow --file repro-min-linux.log
```
