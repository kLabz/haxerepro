package haxeserver.repro;

import haxe.display.Protocol.Timer;
import haxe.io.Path;
import js.node.Buffer;
import js.node.ChildProcess;

using StringTools;

// TODO: add support for assertions
function shellCommand(cmd:String, cb:Void->Void):Void {
	var proc = ChildProcess.spawnSync(cmd, {shell: true});

	if (proc.status > 0) {
		Sys.print('\x1b[31m');
		Sys.print('-> Error code ${proc.status}');
		Sys.println('\x1b[0m');

		var buf:Buffer = proc.stderr;
		if (buf != null) {
			var out = buf.toString().trim();
			if (out != "") Sys.println(out);
		}
	}

	var buf:Buffer = proc.stdout;
	if (buf != null) {
		if (buf != null) {
			var out = buf.toString().trim();
			if (out != "") Sys.println(out);
		}
	}

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

function printCol(buf:StringBuf, colSize:Array<Int>, col:Int, content:String, alignRight:Bool) {
	if (!alignRight) buf.add(content);
	for (_ in 0...(colSize[col]-content.length)) buf.add(' ');
	if (alignRight) buf.add(content);
	buf.add(' | ');
}

function printTimers(buf:StringBuf, timers:Timer) {
	if (timers.time == 0) return;

	var cols = ["name", "time(s)", "%", "p%", "#"];
	var colSize = cols.map(s -> s.length);
	var printCol = printCol.bind(buf, colSize);

	function growCol(col:Int, size:Int) if (size > colSize[col]) colSize[col] = size;

	function loop(t:Timer, depth:Int) {
		growCol(0, depth * 2 + t.name.length);
		growCol(1, Std.string(Math.round(t.time * 1000) / 1000).length);
		if (t.percentTotal != null) growCol(2, Std.string(Math.round(t.percentTotal)).length);
		if (t.percentParent != null) growCol(3, Std.string(Math.round(t.percentParent)).length);
		if (t.calls != null) growCol(4, Std.string(t.calls).length);
		if (t.children != null) for (t in t.children) loop(t, depth + 1);
	}

	loop(timers, 0);

	buf.add('\n');
	for (i => c in cols) printCol(i, c, i > 0);
	buf.add('info\n');
	printTimer(buf, colSize, timers, 0);
}

function printTimer(buf:StringBuf, colSize:Array<Int>, t:Timer, depth:Int) {
	var printCol = printCol.bind(buf, colSize);

	function print(name) {
		for (_ in 0...(depth-1)) name = "  " + name;

		printCol(0, name, false);
		printCol(1, Std.string(Math.round(t.time * 1000) / 1000), true);
		printCol(2, t.percentTotal == null ? '' : Std.string(Math.round(t.percentTotal)), true);
		printCol(3, t.percentParent == null ? '' : Std.string(Math.round(t.percentParent)), true);
		printCol(4, t.calls == null ? '' : Std.string(t.calls), true);
		if (t.info != null) buf.add(t.info);
		buf.add('\n');
	}

	var w = 0;
	var isRoot = t.name == "";

	if (isRoot) {
		w = Lambda.fold(colSize, (c, acc) -> acc + c + 3, -1);
		for (_ in 0...w) buf.add('-');
		buf.add('\n');
	} else {
		print(t.name);
	}

	if (t.children != null) for (t in t.children) printTimer(buf, colSize, t, depth + 1);

	if (isRoot) {
		for (_ in 0...w) buf.add('-');
		buf.add('\n');
		print("total");
	}
}

function secondsToMs(seconds:Float):String {
	return Math.round(seconds * 10000) / 10 + 'ms';
}
