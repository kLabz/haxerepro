package actions;

import js.lib.Promise;

typedef InputOptions = {
	@:optional var required:Bool;
	@:optional var trimWhitespace:Bool;
}

typedef AnnotationProperties = {
	@:optional var title:String;
	@:optional var file:String;
	@:optional var startLine:Int;
	@:optional var endLine:Int;
	@:optional var startColumn:Int;
	@:optional var endColumn:Int;
}

@:jsRequire("@actions/core")
extern class Core {
	static function getInput(name:String, ?options:InputOptions):String;
	static function getMultilineInput(name:String, ?options:InputOptions):Array<String>;
	static function getBooleanInput(name:String, ?options:InputOptions):Bool;

	static function debug(message:String):Void;
	static function info(message:String):Void;
	static function error(message:String, ?properties:AnnotationProperties):Void;
	static function warning(message:String, ?properties:AnnotationProperties):Void;
	static function notice(message:String, ?properties:AnnotationProperties):Void;
	static function setFailed(message:String):Void;

	static function startGroup(name:String):Void;
	static function endGroup():Void;
	static function group<T>(name:String, f:Void->Promise<T>):Promise<T>;
}
