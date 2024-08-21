package haxeserver.repro;

import actions.Core;

function main() {
	var cwd:String = Core.getInput('cwd');
	if (cwd != null) Sys.setCwd(cwd);

	var path:String = Core.getInput('path');
	var silent:Bool = Core.getBooleanInput('silent');
	var noWatchers:Bool = Core.getBooleanInput('no-watchers');
	var filename:String = Core.getInput('file');

	var replay = new ReplayRecording(path, silent, true, noWatchers, true, null, filename);
	replay.run();
}
