package haxeserver.repro;

import haxe.ds.IntMap;
import haxe.io.Path;
import js.Node;
import js.Node.console;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileInput;

using StringTools;
using Safety;

class AnalyzeRecording {
	static var nbExtractor = ~/[0-9]+/;

	// Configuration
	var path:String;
	var filename:String = "repro.log";

	// Analyze options
	// TODO?

	// State
	var lineNumber:Int = 0;
	var file:FileInput;
	var extractor = Extractor.init();

	var lastQueueTime:Null<TimeInfo> = null;
	var lastTotalTime:Null<TimeInfo> = null;
	var queue = new IntMap<RequestTiming>();
	var timings = new IntMap<RequestTiming>();

	public static function main() new AnalyzeRecording();

	function new() {
		var handler = hxargs.Args.generate([
			@doc("Path to the (non reduced) repro recording directory (mandatory)")
			["--path"] => p -> path = p,
			@doc("Log file to use in the recording directory. Default is `repro.log`.")
			["--file"] => f -> filename = f,
			_ => a -> {
				Sys.println('Unknown argument $a');
				Sys.exit(1);
			}
		]);

		var args = Sys.args();
		if (args.length == 0) return Sys.println(handler.getDoc());
		handler.parse(args);

		if (path == null || path == "") {
			Sys.println(handler.getDoc());
			Sys.exit(1);
		}

		if (!FileSystem.exists(path) || !FileSystem.isDirectory(path)) {
			console.error('Invalid recording path provided, aborting.');
			Sys.exit(1);
		}

		var filepath = Path.join([path, filename]);
		if (!FileSystem.exists(filepath) || FileSystem.isDirectory(filepath)) {
			console.error('Invalid recording file provided, aborting.');
			Sys.exit(1);
		}
		this.file = File.read(filepath);

		next();
	}

	function done():Void {
		// Export timings
		var outPath = Path.join([path, "timings.csv"]);
		var out = File.write(outPath);
		out.writeString('Request id,Display method,Total time,Own time,Queue time,Waited for\n');
		for (t in timings) {
			var totalTime = t.totalTime.or(0);
			var queueTime = t.queueTime.or(0);
			var ownTime = totalTime - queueTime;
			out.writeString('${t.id},${t.method},$totalTime,$ownTime,$queueTime,${t.stack.map(i -> i.method).join(" ")}\n');
		}
		out.close();
		Sys.println('Printed timings to $outPath');

		cleanup();
	}

	function next() {
		var next = Node.process.nextTick.bind(next, []);
		if (file.eof()) return done();

		var line = getLine();
		if (line == "") return next();
		var l = lineNumber;

		try {
			switch (line.charCodeAt(0)) {
				case '#'.code:
					return next();

				case _ if (extractor.match(line)):
					// trace(l, extractor.entry);

					switch (extractor.entry) {
						// Comment with timings
						case _ if (extractor.kind == Comment && (cast extractor.entry) == "Request"):
							var rest = extractor.rest;
							if (rest.startsWith("has been queued") && nbExtractor.match(rest)) {
								var ms = Std.parseInt(nbExtractor.matched(0));
								lastQueueTime = {line: l, time: ms};
							} else if (rest.startsWith("total time") && nbExtractor.match(rest)) {
								var ms = Std.parseInt(nbExtractor.matched(0));
								lastTotalTime = {line: l, time: ms};
							}

							next();

						case _ if (extractor.kind == Comment):
							next();

						// Assertions
						case Assert:
							next();

						// Initialization

						case UserConfig | DisplayServer | DisplayArguments | ServerRecordingConfig | CheckoutGitRef | CheckoutSvnRevision:
							getLine();
							next();


						case Root | ApplyGitPatch | AddGitUntracked | ApplySvnPatch:
							next();

						// Direct communication between client and server

						case ServerRequest:
							var item = queue.get(extractor.id);

							if (item != null) {
								item.execLine = l;
								item.method = extractor.method;

								if (lastQueueTime != null && lastQueueTime.line == l - 1) {
									item.queueTime = lastQueueTime.time;
									lastQueueTime = null;
								}
							} else if (extractor.id != null) {
								queue.set(extractor.id, {
									id: extractor.id,
									method: extractor.method,
									startTime: extractor.delta,
									execLine: l,
									stack: []
								});
							}

							// ↓ Request args available there if needed
							nextLine();

							next();

						case ServerRequestQueued:
							queue.set(extractor.id, {
								id: extractor.id,
								startTime: extractor.delta,
								queueLine: l,
								stack: []
							});

							next();

						case ServerRequestCancelled:
							var item = queue.get(extractor.id);
							if (item != null) {
								item.method = extractor.method;
								item.cancelled = true;
								item.cancelLine = l;
								timings.set(extractor.id, item);
								queue.remove(extractor.id);
							}

							// ↓ Request args available there if needed
							nextLine();

							next();

						case ServerResponse:
							var item = queue.get(extractor.id);

							if (item != null) {
								if (lastTotalTime != null && lastTotalTime.line == l - 1) {
									item.totalTime = lastTotalTime.time;
									lastTotalTime = null;
								}
								timings.set(extractor.id, item);
								queue.remove(extractor.id);
							}

							var stackItem = {
								line: l,
								id: extractor.id,
								method: extractor.method
							};

							for (item in queue) item.stack.push(stackItem);

							// ↓ Request args available there if needed
							nextLine();

							next();

						case ServerLog:
							// TODO: extract some infos?
							getFileContent();
							next();

						case ServerError | CompilationResult | CompilationError:
							getFileContent();
							next();

						// Editor events

						case DidChangeTextDocument | FileCreated | FileDeleted | FileChanged:
							getLine();
							next();

						// Commands

						// We shouldn't really add commands before reducingg
						case Start | Pause | Abort | AbortOnFailure | StepByStep | DisplayResponse | Echo | Mute:
							next();

						// We shouldn't really add commands before reducingg
						case ShellCommand:
							getLine();
							next();

						case entry:
							println('$l: Unhandled entry: $entry');
							exit(1);
					}

				case _:
					trace('$l: Unexpected line:\n$line');
			}
		} catch (e) {
			console.error(e);
			cleanup();
		}
	}

	function cleanup():Void {
		file.close();
	}

	inline function exit(code:Int = 1):Void Sys.exit(code);
	inline function println(s:String):Void Sys.println(s);

	function getLine():String {
		lineNumber++;
		var ret = file.readLine();
		return ret;
	}

	function getFileContent():String {
		var next = nextLine();

		if (next == "<<EOF") {
			var ret = new StringBuf();
			while (true) {
				var line = getLine();
				if (line == "EOF") break;
				ret.add(line);
				ret.add("\n");
			}
			return ret.toString();
		}

		return next;
	}

	function nextLine():String {
		// TODO: handle EOF
		while (true) {
			var ret = getLine();
			if (ret == "") continue;
			if (ret.charCodeAt(0) == '#'.code) continue;
			return ret;
		}
	}
}

typedef TimeInfo = {
	var line:Int;
	var time:Int; // msg
}

typedef RequestTiming = {
	var id:Null<Int>;
	var startTime:Float; // s
	@:optional var method:String;
	@:optional var cancelled:Bool;
	@:optional var queueTime:Int; // ms
	@:optional var totalTime:Int; // ms
	@:optional var queueLine:Int;
	@:optional var cancelLine:Int;
	@:optional var execLine:Int;
	var stack:Array<ServerRequestEntry>;
}

typedef ServerRequestEntry = {
	var line:Int;
	var id:Int;
	var method:String;
}
