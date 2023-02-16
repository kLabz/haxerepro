package haxeserver.repro;

enum abstract RecordingEntry(String) {
	// Initialization
	var Root = "root";
	var UserConfig = "userConfig";
	var ServerRecordingConfig = "serverRecordingConfig";
	var DisplayServer = "displayServer";
	var DisplayArguments = "displayArguments";
	var CheckoutGitRef = "checkoutGitRef";
	var ApplyGitPatch = "applyGitPatch";
	var AddGitUntracked = "addGitUntracked";
	var CheckoutSvnRevision = "checkoutSvnRevision";
	var ApplySvnPatch = "applySvnPatch";

	// Direct communication between client and server
	var ServerRequest = "serverRequest";
	var ServerRequestQueued = "serverRequestQueued";
	var ServerRequestCancelled = "serverRequestCancelled";
	var ServerResponse = "serverResponse";
	var ServerError = "serverError";
	var CompilationResult = "compilationResult";

	// Commands
	var Assert = "assert";
	var Start = "start";
	var Pause = "pause";
	var Echo = "echo";
	var Mute = "mute";
	var StepByStep = "stepByStep";
	var DisplayResponse = "displayResponse";
	var Abort = "abort";
	var AbortOnFailure = "abortOnFailure";
	var ShellCommand = "shell";

	// Editor events
	var DidChangeTextDocument = "didChangeTextDocument";
	var FileCreated = "fileCreated";
	var FileDeleted = "fileDeleted";
	var FileChanged = "fileChanged";
}
