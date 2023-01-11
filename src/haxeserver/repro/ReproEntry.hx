package haxeserver.repro;

enum abstract ReproEntry(String) {
	// Initialization
	var Root = "root";
	var UserConfig = "userConfig";
	var DisplayServer = "displayServer";
	var DisplayArguments = "displayArguments";
	var CheckoutGitRef = "checkoutGitRef";
	var ApplyGitPatch = "applyGitPatch";
	var AddGitUntracked = "addGitUntracked";

	// Direct communication between client and server
	var ServerRequest = "serverRequest";
	var ServerResponse = "serverResponse";
	var ServerError = "serverError";
	var CompilationResult = "compilationResult";

	// Commands
	var Start = "start";
	var Pause = "pause";
	var Echo = "echo";
	var StepByStep = "stepByStep";
	var DisplayResponse = "displayResponse";
	var AbortOnFailure = "abortOnFailure";

	// Editor events
	var DidChangeTextDocument = "didChangeTextDocument";
	var FileCreated = "fileCreated";
	var FileDeleted = "fileDeleted";
}