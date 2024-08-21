package haxeserver.repro;

import haxe.Json;
import haxe.Rest;
import haxe.display.Display;
import haxe.display.Protocol;
import haxe.display.Server;
import haxe.io.Path;
import js.Node;
import js.Node.console;
import js.node.Buffer;
import js.node.ChildProcess;
import js.node.child_process.ChildProcess as ChildProcessObject;
import js.node.stream.Readable;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileInput;

import haxeLanguageServer.DisplayServerConfig;
import haxeLanguageServer.documents.HxTextDocument;
import haxeserver.process.HaxeServerProcessConnect;
import haxeserver.process.HaxeServerProcessNode;
import haxeserver.process.IHaxeServerProcess;
import haxeserver.repro.Utils.makeRelative;
import haxeserver.repro.Utils.printTimers;
import haxeserver.repro.Utils.shellCommand;
import languageServerProtocol.protocol.Protocol.DidChangeTextDocumentParams;

using StringTools;
using haxeLanguageServer.extensions.DocumentUriExtensions;
using haxeserver.repro.ReplayRecording;

class ReplayRecording {
	static inline var REPRO_PATCHFILE = 'status.patch';
	static inline var UNTRACKED_DIR:String = "untracked";
	static inline var FILE_CONTENTS_DIR:String = "files";
	static inline var STASH_NAME:String = "Stash before replay";

	// Recording configuration
	var root:String = "./";
	var config:ServerRecordingConfig;
	var userConfig:Dynamic;
	var displayServer:DisplayServerConfig;
	var displayArguments:Array<String>;

	// VCS data
	var vcsStatus:VcsStatus = None;
	var createdStash:Bool = false;

	// Replay configuration
	var path:String;
	var silent:Bool = false;
	var noInteractive:Bool = false;
	var noWatchers:Bool = false;
	var logTimes:Bool = false;
	var port:Null<Int> = null;
	var filename:String = "repro.log";

	// Replay state
	var protocolVersion:Float = 1.0;
	var lineNumber:Int = 0;
	var running:Bool = false;
	var muted:Bool = false;
	var stepping:Bool = false;
	var abortOnFailure:Bool = false;
	var displayNextResponse:Bool = false;
	var displayNextTimings:Bool = false;
	var currentAssert:Assertion = None;
	var assertions = new Map<Int, AssertionItem>();

	var times = new Map<String, Timings>();
	var timers = new Map<String, Array<{line:Int, timer:Timer}>>();

	/**
	 * When `abortOnFailure` hit a failure;
	 * We only continue to gather failed assertions for reporting.
	 */
	var aborted:Bool = false;

	var file:FileInput;
	var extractor = Extractor.init();
	var server:ChildProcessObject;
	var client:HaxeServerAsync;
	var started(get, never):Bool;
	function get_started():Bool return client != null;

	public static function plural(nb:Int):String return nb != 1 ? "s" : "";

	public static function main() {
		var path:String = null;
		var silent:Bool = false;
		var noInteractive:Bool = false;
		var noWatchers:Bool = false;
		var logTimes:Bool = false;
		var port:Null<Int> = null;
		var filename:String = null;

		var handler = hxargs.Args.generate([
			@doc("Path to the recording directory (mandatory)")
			["--path"] => p -> path = p,
			@doc("Log file to use in the recording directory. Default is `repro.log`.")
			["--file"] => f -> filename = f,
			@doc("Port to use internally for haxe server. Should *not* refer to an existing server. Default is `7000`.")
			["--port"] => (p:Int) -> port = p,
			@doc("This recording was made without filesystem watchers.")
			["--no-watchers"] => () -> noWatchers = true,
			@doc("Skip all prompts.")
			["--no-interactive"] => () -> noInteractive = true,
			@doc("Only show results.")
			["--silent"] => () -> silent = true,
			@doc("Log timing per request type.")
			["--times"] => () -> logTimes = true,
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
			console.error('Invalid recording path provided, skipping replay.');
			Sys.exit(1);
		}

		var replay = new ReplayRecording(path, silent, noInteractive, noWatchers, logTimes, port, filename);
		replay.run();
	}

	public function new(
		path:String,
		silent:Bool = false,
		noInteractive:Bool = false,
		noWatchers:Bool = false,
		logTimes:Bool = false,
		port:Null<Int> = null,
		filename:String = "repro.log",
	) {
		this.path = path;
		this.silent = silent;
		this.noInteractive = noInteractive;
		this.noWatchers = noWatchers;
		this.logTimes = logTimes;
		this.port = port;

		var filepath = Path.join([path, filename]);
		if (!FileSystem.exists(filepath) || FileSystem.isDirectory(filepath)) {
			console.error('Invalid recording file provided, skipping replay.');
			Sys.exit(1);
		}

		this.file = File.read(filepath);
	}

	// TODO: callback..
	public function run() {
		if (running) throw 'Replay already started.';
		running = true;
		next();
	}

	function start(cb:Void->Void):Void {
		if (port == null) {
			// println("Using internal haxe server");
			server = null;

			var process:HaxeServerProcessNode = null;
			process = new HaxeServerProcessNode("haxe", [], cb);
			client = new HaxeServerAsync(() -> process);
		} else {
			// println('Using haxe server on port $port');

			// Allowed to fail -- lets user hook to their own server
			server = ChildProcess.spawn("haxe", ["--wait", Std.string(port)]);
			Sys.sleep(0.5);

			var process = new HaxeServerProcessConnect("haxe", port, []);
			client = new HaxeServerAsync(() -> process);
			cb();
		}
	}

	function pause(resume:Void->Void, ?msg:String = "Paused. Press <ENTER> to resume."):Void {
		if (aborted || noInteractive) resume();
		Sys.print(msg + " ");

		var line = Sys.stdin().readLine();
		if (line == 'q') {
			cleanup();
			return exit(0);
		}

		resume();
	}

	function done():Void {
		var exitCode = 0;

		if (assertions.iterator().hasNext()) {
			var nb = 0;
			var nbFail = 0;
			var detailed = new StringBuf();
			var summary = new StringBuf();

			for (l => res in assertions) {
				nb++;
				summary.add(res.success ? "." : "F");

				if (!res.success) {
					nbFail++;
					detailed.add('$l: assertion failed ${res.assert} at line ${res.lineApplied}\n');
				}
			}

			Sys.print('$nb assertion${nb.plural()} with $nbFail failure${nbFail.plural()}');
			if (nbFail > 0) Sys.print(': ${summary.toString()}');
			Sys.println('');
			if (!silent) Sys.println(detailed.toString());
			if (nbFail > 0) exitCode = 1;
		}

		if (logTimes) {
			displayTimingsTable("Replay timings:", times);

			// TODO: allow user to change through some argument
			var reportMode:TimersReporting = Aggregate;
			// var reportMode:TimersReporting = Details('display/completion');
			switch (reportMode) {
				case None:

				case Aggregate:
					displayTimingsTable("Haxe timers:", [for (r => data in timers) {
						var timings = Lambda.fold(
							data,
							(item, res) -> {
								total: res.total + (item.timer.time * 1000),
								count: res.count + 1,
								max: Math.max(Math.ceil(item.timer.time * 1000), res.max)
							},
							{total: 0.0, count: 0, max: 0}
						);

						if (timings.total == 0) continue;
						r => timings;
					}]);

				case Details(request):
					var buf = new StringBuf();
					buf.add('\nHaxe timers:\n');
					for (_ in 0...20) buf.add('-');

					for (r => data in timers) {
						if (request != null && request != r) continue;

						// TODO: adjust output
						for (d in data) {
							buf.add('\nL');
							buf.add(d.line);
							buf.add(' - ');
							buf.add(r);
							printTimers(buf, d.timer);
						}
					}

					Sys.println(buf.toString());
			}
		}

		pause(() -> {
			cleanup();
			Sys.exit(exitCode);
		}, "Done. Press <ENTER> to cleanup and exit.");
	}

	function next() {
		var next = Node.process.nextTick.bind(next, []);
		if (file.eof()) return done();

		var line = getLine();
		if (line == "") return next();
		var l = lineNumber;

		try {
			switch (line.charCodeAt(0)) {
				case '#'.code: return next();

				case _ if (extractor.match(line)):
					// trace(l, extractor.entry);

					switch (extractor.entry) {
						// Comment with timings
						case _ if (extractor.kind == Comment):
							return next();

						// Assertions
						case Assert:
							clearAssert();
							currentAssert = switch (cast extractor.rest :AssertionKind) {
								case null:
									Sys.println('$l: Invalid assertion "$line"');
									exit(1);
									None;

								case ExpectReached:
									assertionResult(l, !aborted, ExpectReached(l));

								case ExpectUnreachable:
									assertionResult(l, aborted, ExpectUnreachable(l));

								case ExpectFailure: ExpectFailure(l);
								case ExpectSuccess: ExpectSuccess(l);
								case ExpectItemCount: ExpectItemCount(l, extractor.id);
								case ExpectOutput: ExpectOutput(l, getFileContent());
							}

							next();

						// Initialization

						case Root:
							root = Path.normalize(extractor.method);
							next();

						case UserConfig:
							userConfig = getData();
							next();

						case ServerRecordingConfig:
							config = getData();
							if (config.version != null) protocolVersion = config.version;
							next();

						// TODO: actually use this
						case Haxe:
							var haxeVersion = getLine();
							next();

						// TODO: actually use this
						case DisplayServer:
							displayServer = getData();
							next();

						case DisplayArguments:
							displayArguments = getData();
							next();

						case CheckoutGitRef:
							println('$l: > Checkout git ref');
							checkoutGitRef(getLine(), next);

						case ApplyGitPatch:
							println('$l: > Apply git patch');
							applyGitPatch(next);

						case AddGitUntracked:
							println('$l: > Add untracked files');
							addGitUntracked(next);

						case CheckoutSvnRevision:
							println('$l: > Checkout svn revision');
							checkoutSvnRevision(getLine(), next);

						case ApplySvnPatch:
							println('$l: > Apply svn patch');
							applySvnPatch(next);

						// Direct communication between client and server

						case Compile:
							if (!started) {
								println('$l: replay not started yet. Use "- start" before sending requests.');
								exit(1);
							}

							if (!aborted) {
								var line = getLine();
								var data:Array<String> = cast Json.parse(line);
								serverRequest(l, null, extractor.method, true, data, next);
							} else {
								getLine();
								next();
							}

						case ServerRequest:
							if (!started) {
								println('$l: replay not started yet. Use "- start" before sending requests.');
								exit(1);
							}

							if (!aborted) {
								var line = getLine();
								switch (line.charCodeAt(0)) {
									case '{'.code:
										var data:Dynamic = Json.parse(line);
										serverJsonRequest(l, extractor.id, extractor.method, data, next);

									case _:
										var data:Array<String> = cast Json.parse(line);
										serverRequest(l, extractor.id, extractor.method, false, data, next);
								}
							} else {
								getLine();
								next();
							}

						case ServerRequestQueued:
							// Nothing to do?
							next();

						case ServerRequestCancelled:
							// Nothing to do?
							getLine();
							next();

						case ServerResponse:
							// var id = extractor.id;
							// var method = extractor.method;
							// Disabled printing for now as it can be confused with actual result from replay...
							// var idDesc = id == null ? '' : ' #$id';
							// var methodDesc = method == null ? '' : ' "$method"';
							// var desc = (id != null || method != null) ? " for" : "";
							// println('$l: < Server response${desc}${idDesc}${methodDesc}');
							// TODO: check against actual result
							getLine();
							next();

						case ServerError:
							// var id = extractor.id;
							// var method = extractor.method;
							// Disabled printing for now as it can be confused with actual result from replay...
							// var idDesc = id == null ? '' : ' #$id';
							// var methodDesc = method == null ? '' : ' "$method"';
							// if (id == null && method == null) methodDesc = " request";
							// println('$l: < Server error while executing${idDesc}${methodDesc}');
							// TODO: check against actual error
							getFileContent();
							next();

						case ServerLog:
							getFileContent();
							next();

						case CompilationResult | CompilationError:
							// Disabled printing for now as it can be confused with actual result from replay...
							// var fail = (extractor.entry.match(CompilationError) || extractor.method == "failed") ? "failed" : "ok";
							// println('$l: < Compilation result: $fail');
							// TODO: check against actual result
							getFileContent();
							next();

						// Editor events

						case DidChangeTextDocument:
							var event:DidChangeTextDocumentParams = getData();

							if (protocolVersion < 1.1 || noWatchers) {
								var start = Date.now().getTime();
								println('$l: Apply document change to ${event.textDocument.uri.toFsPath().toString()}');
								didChangeTextDocument(event, next);
								if (logTimes) logTime("didChangeTextDocument", Date.now().getTime() - start);
							} else {
								println('$l: Skipped document change event for ${event.textDocument.uri.toFsPath().toString()}');
								next();
							}

						case FileCreated:
							var id = extractor.id;
							var content = id == 0
								? ""
								: File.getContent(Path.join([path, FILE_CONTENTS_DIR, '$id.contents']));

							var path = maybeConvertPath(getData());
							FileSystem.createDirectory(Path.directory(path));
							File.saveContent(path, content);
							next();

						case FileChanged:
							var id = extractor.id;
							var content = File.getContent(Path.join([path, FILE_CONTENTS_DIR, '$id.contents']));
							var path = maybeConvertPath(getData());
							FileSystem.createDirectory(Path.directory(path));
							File.saveContent(path, content);
							next();

						case FileDeleted:
							var path = maybeConvertPath(getData());
							FileSystem.deleteFile(path);
							next();

						// Commands

						case Start:
							start(
								userConfig != null
									? serverJsonRequest.bind(l, 0, "initialize", userConfig, next)
									: next
							);

						case Pause:
							pause(next);

						case Abort:
							aborted = true;
							done();

						case AbortOnFailure:
							abortOnFailure = extractor.id == null || extractor.id == 1;
							next();

						case Mute:
							muted = extractor.id == null || extractor.id == 1;
							next();

						case StepByStep:
							stepping = extractor.id == null || extractor.id == 1;
							next();

						case DisplayResponse:
							displayNextResponse = true;
							next();

						case DisplayTimings:
							displayNextTimings = true;
							next();

						case Echo:
							println('$l: ${extractor.method}');
							next();

						case ShellCommand:
							var cmd = getLine();
							println('$l: shell cmd `$cmd`');
							shellCommand(cmd, next);

						case entry:
							println('$l: Unhandled entry: $entry');
							exit(1);
					}

				case _:
					trace('$l: Unexpected line:\n$line');
			}
		} catch (e) {
			console.error(e);
			exit(1);
		}
	}

	function clearAssert():Void {
		// Set previous assertion as failed (if any)
		currentAssert = switch (currentAssert) {
			case None: None;
			// TODO: add logs if !silent
			case _: assertionResult(null, false);
		}
	}

	function assertionResult(l:Null<Int>, result:Null<Bool>, ?assert:Assertion):Assertion {
		if (assert == null) assert = currentAssert;

		assertions.set(switch (assert) {
			case ExpectReached(l) | ExpectUnreachable(l) | ExpectFailure(l)
				 | ExpectSuccess(l) | ExpectItemCount(l, _) | ExpectOutput(l, _):
				l;

			case None: throw 'Invalid assertion result';
		}, {
			assert: assert,
			lineApplied: l,
			success: result
		});

		currentAssert = None;
		return currentAssert;
	}

	function cleanup():Void {
		if (file != null) file.close();
		file = null;

		switch (vcsStatus) {
			case GitReference(ref): resetGit(ref);
			case SvnRevision(rev): resetSvn(rev);
			case None:
		}

		// No need to close the client, it's not stateful
		if (server != null) server.kill();
	}

	function exit(code:Int = 1):Void {
		cleanup();
		Sys.exit(code);
	}

	function println(s:String, ignoreSilent:Bool = false):Void {
		if (!aborted && !muted && (ignoreSilent || !silent)) Sys.println(s);
	}

	function onServerMessage(msg:String):Void {
		Sys.print('\x1b[2m');
		Sys.print(msg);
		Sys.println('\x1b[0m');
	}

	function displayTimingsTable(heading:String, times:Map<String, Timings>):Void {
		// Skip empty timings
		if (!times.keys().hasNext()) return;

		var buf = new StringBuf();
		buf.add('\n');

		var pad = 2;
		var cols = [heading, "Count", "Total (s)", "Average (ms)", "Max (ms)"];
		var colSize = cols.map(s -> s.length);

		var times = [for (k => v in times) {
			if (k.length > colSize[0]) colSize[0] = k.length;

			var countStr = Std.string(v.count);
			if (countStr.length > colSize[1]) colSize[1] = countStr.length;

			var totalStr = Std.string(Math.round(v.total) / 1000);
			if (totalStr.length > colSize[2]) colSize[2] = totalStr.length;

			// var avg = Math.round((v.total / v.count) / 10) / 100;
			var avgStr = Std.string(Math.round(v.total / v.count));

			k => {count: countStr, total: totalStr, avg: avgStr, max: v.max};
		}];

		var len = 0;
		for (i => c in cols) {
			len += colSize[i] + pad;
			buf.add(c);
			if (i < colSize.length) for (_ in 0...(colSize[i]-c.length+pad)) buf.add(' ');
		}
		buf.add('\n');
		for (_ in 0...len) buf.add('-');
		buf.add('\n');

		for (k => v in times) {
			buf.add(k);
			for (_ in 0...(colSize[0]-k.length+pad)) buf.add(' ');
			buf.add(v.count);
			for (_ in 0...(colSize[1]-v.count.length+pad)) buf.add(' ');
			buf.add(v.total);
			for (_ in 0...(colSize[2]-v.total.length+pad)) buf.add(' ');
			buf.add(v.avg);
			for (_ in 0...(colSize[3]-v.avg.length+pad)) buf.add(' ');
			buf.add(v.max);
			buf.add('\n');
		}

		Sys.println(buf.toString());
	}

	function getLine(?skipEmpty:Bool = true, ?skipComments:Bool = true):String {
		lineNumber++;
		try {
			var ret = file.readLine();
			if (skipEmpty && ret == "") return getLine(true, skipComments);
			if (skipComments && ret.charCodeAt(0) == '#'.code) return getLine(skipEmpty, true);
			return ret;
		} catch(_) {
			return "";
		}
	}

	function getFileContent():String {
		var next = getLine(false, false);

		if (next == "<<EOF") {
			var ret = new StringBuf();
			while (true) {
				var line = getLine(false, false);
				if (line == "EOF") break;
				ret.add(line);
				ret.add("\n");
			}
			return ret.toString();
		}

		return next;
	}

	function getData<T:{}>():T
		return cast Json.parse(getLine());

	function git(args:Rest<String>):String {
		var proc = ChildProcess.spawnSync("git", args.toArray());
		if (proc.status > 0) throw (proc.stderr:Buffer).toString().trim();
		return (proc.stdout:Buffer).toString().trim();
	}

	function checkoutGitRef(ref:String, next:Void->Void):Void {
		var gitRef = git("rev-parse", "--abbrev-ref", "HEAD");
		if (gitRef == "HEAD") gitRef = git("rev-parse", "--short", "HEAD");
		vcsStatus = GitReference(gitRef);

		if (git("status", "--porcelain").trim() != "") {
			createdStash = true;
			git("stash", "save", "--include-untracked", STASH_NAME);
		}

		git("checkout", ref);
		next();
	}

	function applyGitPatch(next:Void->Void):Void {
		git("apply", "--allow-empty", "--whitespace=fix", Path.join([path, REPRO_PATCHFILE]));
		next();
	}

	function addGitUntracked(next:Void->Void):Void {
		var untracked = Path.join([path, UNTRACKED_DIR]);

		function copyUntracked(root:String) {
			var dir = Path.join([untracked, root]);
			for (entry in FileSystem.readDirectory(dir)) {
				var entryPath = Path.join([untracked, root, entry]);

				if (FileSystem.isDirectory(entryPath)) {
					copyUntracked(Path.join([root, entry]));
				} else {
					var target = Path.join([root, entry]);
					var targetDir = Path.directory(target);

					if (targetDir != "" && !FileSystem.exists(targetDir))
						FileSystem.createDirectory(targetDir);

					File.saveContent(target, File.getContent(entryPath));
				}
			}
		}

		copyUntracked(".");
		next();
	}

	function resetGit(ref:String):Void {
		// TODO: store those steps somewhere so they can be executed manually
		// even after a crash or an interruption
		git("clean", "-f", "-d");
		git("reset", "--hard");
		git("checkout", ref);
		if (createdStash) git("stash", "pop");
	}

	function svn(args:Rest<String>):String {
		var args = args.toArray();
		var shelf = args[0].startsWith('x-');
		var proc = ChildProcess.spawnSync(
			"svn",
			args,
			shelf ? {env: {SVN_EXPERIMENTAL_COMMANDS: "shelf3"}} : {}
		);

		if (proc.status > 0) throw (proc.stderr:Buffer).toString().trim();
		return (proc.stdout:Buffer).toString().trim();
	}

	function checkoutSvnRevision(revision:String, next:Void->Void):Void {
		var prevRevision = svn("info", "--show-item", "revision");
		vcsStatus = SvnRevision(prevRevision);

		if (svn("status") != "") {
			createdStash = true;
			svn("x-shelve", STASH_NAME);
		}

		svn("update", "-r", revision);
		next();
	}

	function applySvnPatch(next:Void->Void):Void {
		svn("patch", "--strip=0", Path.join([path, REPRO_PATCHFILE]));
		next();
	}

	function resetSvn(revision:String):Void {
		// TODO: store those steps somewhere so they can be executed manually
		// even after a crash or an interruption
		svn("revert", "-R", ".");
		svn("cleanup", "--remove-unversioned");
		svn("update", "-r", revision);
		if (createdStash) svn("x-unshelve", "--drop", STASH_NAME);
	}

	function maybeConvertPath(a:String):String {
		var isCwd = a.startsWith("--cwd ");
		if (isCwd) a = a.substr("--cwd ".length);

		var relative = makeRelative(a, root);
		if (relative != null) return isCwd ? '--cwd $relative' : relative;

		try {
			var data:{params:{file:String}} = cast Json.parse(a);
			var relative = makeRelative(data.params.file, root);

			if (relative != null) {
				data.params.file = relative;
				return Json.stringify(data);
			}
		} catch (_) {}

		return a;
	}

	function serverJsonRequest(
		l:Int,
		id:Null<Int>,
		method:String,
		params:Dynamic,
		cb:Void->Void
	):Void {
		var args = displayArguments.concat([
			"--display",
			Json.stringify({method: method, id: id, params: params})
		]);
		serverRequest(l, id, method, false, args, next);
	}

	function serverRequest(
		l:Int,
		id:Null<Int>,
		request:String,
		isCompilation:Bool,
		params:Array<String>,
		cb:Void->Void
	):Void {
		var next = function() {
			clearAssert();
			if (stepping) pause(cb);
			else cb();
		}

		if (isCompilation) {
			println('$l: > Compilation "$request"', displayNextResponse);
		} else {
			var idDesc = id == null ? '' : ' #$id';
			println('$l: > Server request$idDesc "$request"', displayNextResponse);
		}

		params = params.map(maybeConvertPath);
		var start = Date.now().getTime();

		client.rawRequest(
			displayNextTimings
				? ["-D display-details", "--times", "-D macro-times"].concat(params)
				: ["-D", "display-details"].concat(params),
			onServerResponse(isCompilation ? "compilation" : request, l, start, next),
			err -> throw err
		);
	}

	function onServerResponse(
		request:String,
		l:Int,
		start:Float,
		next:Void->Void
	):HaxeServerRequestResult->Void {
		return function(res) {
			if (logTimes) logTime(request, Date.now().getTime() - start);

			var hasError = res.hasError;
			var out:String = res.stderr.toString();

			switch (currentAssert) {
				case ExpectOutput(_, expected):
					hasError = out != expected;

					if (hasError) {
						final a = new diff.FileData(haxe.io.Bytes.ofString(expected), "expected", Date.now());
						final b = new diff.FileData(haxe.io.Bytes.ofString(out), "actual", Date.now());
						var ctx:diff.Context = {
							file1: a,
							file2: b,
							context: 10
						}
						final script = diff.Analyze.diff2Files(ctx);
						var diff = diff.Printer.printUnidiff(ctx, script);
						diff = diff.split("\n").slice(3).join("\n");
						println(diff, true);
					}

					assertionResult(l, !hasError);

				case _:
			}

			switch (request) {
				case "compilation":
					if (hasError) println('$l: => Compilation error:\n' + out.trim(), true);
					else if (displayNextResponse) {
						println(out.trim(), true);
					}

				case _:
					switch (extractResult(out)) {
						case JsonResult(res):
							if (res.result != null && res.result.timers != null) {
								if (displayNextTimings) {
									var buf = new StringBuf();
									buf.add('\x1b[2m');
									printTimers(buf, res.result.timers);
									buf.add('\x1b[0m');
									println(buf.toString());
								}

								var parent = timers.exists(request)
									? timers.get(request)
									: { var arr = []; timers.set(request, arr); arr; };

								parent.push({line: l, timer: res.result.timers});
							}

							switch (request) {
								case "display/completion":
									var res:CompletionResult = cast res.result;
									var nbItems = try res.result.items.length catch(_) 0;

									if (displayNextResponse) {
										println('$l => Completion request returned $nbItems items', true);
										// if (hasError) println(out.trim(), true);
										// if (res != null) println(haxe.Json.stringify(res, "  "));
										if (hasError || res == null) println(out.trim(), true);
									}

									switch (currentAssert) {
										case ExpectItemCount(_, null):
											hasError = nbItems == 0;
											assertionResult(l, !hasError);

										case ExpectItemCount(_, c):
											hasError = c != nbItems;
											assertionResult(l, !hasError);

										case _:
											hasError = false;
									}

									if (hasError) println('$l: => Completion request failed', true);

								case "server/contexts" if (displayNextResponse):
									var contexts:Array<HaxeServerContext> = cast res.result.result;
									for (c in contexts) {
										println('  ${c.index} ${c.desc} (${c.platform}, ${c.defines.length} defines)', true);
										println('    signature: ${c.signature}', true);
										// println('    defines: ${c.defines.map(d -> d.key).join(", ")}', true);
									}

								// TODO: other special case handling

								case _:
									if (hasError || displayNextResponse) {
										var hasError = hasError ? "(has error)" : "";
										println('$l: => Server response: $hasError', true);
									}

									// if (displayNextResponse) println(Json.stringify(res, "  "), true);
									if (displayNextResponse) {
										println(Std.string(res), true);
										println(out.trim(), true);
									}
							}

						case Raw(out):
							if (hasError || displayNextResponse) {
								var hasError = res.hasError ? "(has error)" : "";
								println('$l: => Server response: $hasError', true);
							}

							if (displayNextResponse) println(out, true);

						case Empty:
							if (request == "display/completion") hasError = true;
							if (hasError || displayNextResponse) println('$l: => Empty server response', true);
					}
			}

			switch (currentAssert) {
				case ExpectFailure(_): assertionResult(l, hasError);
				case ExpectSuccess(_): assertionResult(l, !hasError);
				case _:
			}

			if (displayNextResponse) {
				var serverOut = res.stdout?.toString();
				if (serverOut != "") onServerMessage(serverOut.trim());
			}

			if (displayNextResponse) displayNextResponse = false;
			if (displayNextTimings) displayNextTimings = false;
			if (hasError && abortOnFailure) {
				println('Failure detected, aborting rest of script.', true);
				aborted = true;
				exit(1); // TODO: find a way to configure with or without asserts
			}

			next();
		}
	}

	function extractResult<T:{}>(out:String):ResponseKind<T> {
		var lines = out.split("\n");
		var last = lines.length > 1 ? lines.pop() : "";
		switch [lines.length, last] {
			case [1, ""]:
				var json = try Json.parse(lines[0]) catch(e) null;
				if (json == null) return Raw(out);
				return JsonResult(json);

			case [n, _]:
				var out = lines.join("\n") + (last == "" ? "" : '\n$last');
				return out == "" ? Empty : Raw(out);
		}
	}

	function logTime(k:String, t:Float):Void {
		var old = times.get(k);
		if (old == null) times.set(k, {count: 1, total: t, max: t});
		else times.set(k, {count: old.count + 1, total: old.total + t, max: Math.max(t, old.max)});
	}

	function didChangeTextDocument(event:DidChangeTextDocumentParams, next:Void->Void):Void {
		var path = maybeConvertPath(event.textDocument.uri.toFsPath().toString());
		var content = File.getContent(path);
		var doc = new HxTextDocument(event.textDocument.uri, "", 0, content);
		doc.update(event.contentChanges, event.textDocument.version);
		File.saveContent(path, doc.content);
		next();
	}
}

typedef AssertionItem = {
	var assert:Assertion;
	@:optional var lineApplied:Int;
	@:optional var success:Bool;
}

enum Assertion {
	None;
	ExpectReached(line:Int);
	ExpectUnreachable(line:Int);
	ExpectFailure(line:Int);
	ExpectSuccess(line:Int);
	ExpectItemCount(line:Int, count:Null<Int>);
	ExpectOutput(line:Int, output:String);
}

enum abstract AssertionKind(String) {
	var ExpectReached = "true";
	var ExpectUnreachable = "false";
	var ExpectFailure = "fail";
	var ExpectSuccess = "success";
	var ExpectItemCount = "items";
	var ExpectOutput = "output";
}

enum ResponseKind<T:{}> {
	JsonResult(json:Response<T>);
	Raw(out:String);
	Empty;
}

enum VcsStatus {
	GitReference(ref:String);
	SvnRevision(rev:String);
	None;
}

// TODO: allow multiple requests?
enum TimersReporting {
	None;
	Aggregate;
	Details(?request:String);
}

typedef Timings = {
	final count:Int;
	final total:Float;
	final max:Float;
}

typedef ServerRecordingConfig = {
	var enabled:Bool;
	var path:String;
	var exclude:Array<String>;
	var excludeUntracked:Bool;
	var watch:Array<String>;
	@:optional var version:Float;
}
