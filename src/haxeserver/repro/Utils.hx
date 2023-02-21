package haxeserver.repro;

import haxe.display.Protocol.Timer;
import haxe.io.Path;
import js.node.Buffer;
import js.node.ChildProcess;

using StringTools;

// TODO: add support for assertions
function shellCommand(cmd:String, cb:Void->Void):Void {
	var proc = ChildProcess.spawnSync(cmd);
	if (proc.status > 0) {
		var buf:Buffer = proc.stderr;
		if (buf != null) Sys.println(buf.toString().trim());
	}

	var buf:Buffer = proc.stdout;
	if (buf != null) Sys.println(buf.toString().trim());

	cb();
}

function makeRelative(path:String, root:String):String {
	if (path.charCodeAt(0) == "/".code) {
		if (path.startsWith(root)) {
			path = path.substr(root.length);
			if (path.charCodeAt(0) == '/'.code) path = path.substr(1);
			if (path == "") path = ".";
			return path;
		}

		throw 'Absolute path outside root not handled yet ($path)';
	}

	if (path.charCodeAt(1) == ":".code && path.charCodeAt(2) == "/".code) {
		var norm = Path.normalize(path);
		var upper = norm.toUpperCase();
		var root = Path.normalize(root).toUpperCase();

		if (upper.startsWith(root)) {
			path = norm.substr(root.length);
			if (path.charCodeAt(0) == '/'.code) path = path.substr(1);
			if (path == "") path = ".";
			return path;
		}

		throw 'Absolute path outside root not handled yet ($path)';
	}

	return null;
}

function printTimer(buf:StringBuf, timerData:Timer, depth:Int) {
	buf.add('\n');
	for (_ in 0...depth) buf.add('  ');
	buf.add('- ');

	if (timerData.path == "") buf.add('[root]');
	else buf.add(timerData.path);

	buf.add(' (');
	buf.add(secondsToMs(timerData.time));
	buf.add(')');
	if (timerData.children != null) for (c in timerData.children) printTimer(buf, c, depth + 1);
}

function secondsToMs(seconds:Float):String {
	return Math.round(seconds * 10000) / 10 + 'ms';
}
