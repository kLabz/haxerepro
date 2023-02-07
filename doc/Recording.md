# Recording tool

The recording tool has been included in [my fork](https://github.com/kLabz/haxe-languageserver/tree/poc/server-recording) of Haxe LSP server.

## Usage with vshaxe

I also pushed a custom version of vshaxe in [my fork](https://github.com/kLabz/vshaxe/tree/poc/server-recorder), which uses above version of
Haxe LSP.

### Build without lix/vshaxe-build

If for some reasons you have issues building with vshaxe-build / lix (or if you
want to skip the 2M files downloaded in node_modules), I have also included a
vanilla haxe way in those two forks.

For both projects, you can install dependencies in a local haxelib repository by
doing:

```
haxelib newrepo
haxelib install --always install.hxml
```

You can then build with the hxml files, respectively `build-client.hxml` and
`build.hxml` for vshaxe and haxe LSP server.

If your vshaxe repository isn't in your vscode extensions folder, you may want
to package it and install it. You can do so with the following, _after_ removing
the `vscode:prepublish` npm script from `package.json`, like vshaxe-build does.

```
npx vsce package
code --install-extension vshaxe-2.26.0.vsix
```

## Usage with any LSP compatible editor

Same as above, you can build my Haxe LSP server [fork](https://github.com/kLabz/haxe-languageserver/tree/poc/server-recording) with:

```
haxelib newrepo
haxelib install --always install.hxml
haxe build.hxml
```

You can then use this version as your haxe LSP server in your editor.

## Configuration

To enable server recording, add `haxe.serverRecording` object to your editor
and/or workspace configuration:

```json
"haxe.serverRecording": {
  "enabled": true,
  "path": ".haxelsp/recording/",
  "watch": [],
  "exclude": [],
  "excludeUntracked": false
}
```

Where:
 * `enabled` should be set to `true` when you want to record
 * `path` is where recording data will be stored, relative to your workspace root
 * `watch` is an array of paths (`String`) to watch for changes during
   recording. Put any (text) resource influencing compilation that is likely to
   change during your coding session in there.
 * `exclude` is currently used to ignore changes in paths:
	 * for `git` diffs (including of untracked files), as a git ignore pattern
	 * for `svn` untracked files, without support for wildcards
 * `excludeUntracked` will ignore untracked (including non-ignored untracked
   files) from diffs stored in the recording.

Changes will apply after you restart your haxe LSP server (on vscode, it should
happen automatically when you save your workspace settings). You should then see
a `.haxelsp/recording/current/` folder with at least a `repro.log` file containing
the recordings.

Each time you restart your LSP server, that `current` directory will be wiped
and replaced with a new recording. You can save current recording **before**
restarting language server if something interesting happened by launching the
`"Haxe: Export current recording"` command via the command palette.

The `current` folder will be copied into `.haxelsp/recording/YYYYMMDD-HHMMSS/`
folder, corresponding to the time of the export. The `current` folder will _not_
be cleared, so you can continue recording if the server is still usable.

**Note:** in other editors, you would have to bind something to the
`haxe/exportServerRecording` LSP request. You can pass an optional config object
to set the export path: `{"dest": "some/path"}`.`
