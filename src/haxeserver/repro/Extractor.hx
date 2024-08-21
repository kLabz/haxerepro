package haxeserver.repro;

import haxeLanguageServer.ServerRecordingEntryKind;

@:forward(match)
abstract Extractor(EReg) from EReg {
	private function new(r:EReg) this = r;
	public static function init():Extractor
		return new Extractor(
			~/^(?:\+(\d+(?:\.\d+)?)s )?(>|<|-|#) (\w+)(?: (\d+))?(?: "([^"]+)")?(?: (.+))?$/
		);

	public var delta(get, never):Null<Float>;
	function get_delta():Null<Float> {
		var raw = this.matched(1);
		if (raw == null) return null;
		return Std.parseFloat(raw);
	}

	public var kind(get, never):ServerRecordingEntryKind;
	function get_kind():ServerRecordingEntryKind return cast this.matched(2);

	public var entry(get, never):RecordingEntry;
	function get_entry():RecordingEntry return cast this.matched(3);

	public var id(get, never):Null<Int>;
	function get_id():Null<Int> {
		var raw = this.matched(4);
		if (raw == null) return null;
		return Std.parseInt(raw);
	}

	public var method(get, never):String;
	function get_method():String return this.matched(5);

	public var rest(get, never):String;
	function get_rest():String return this.matched(6);

	public function getSimplifiedLine():String {
		var buf = new StringBuf();
		buf.add(kind);
		buf.add(" ");
		buf.add(entry);

		if (id != null) {
			buf.add(" ");
			buf.add(id);
		}

		if (method != null) {
			buf.add(' "');
			buf.add(method);
			buf.add('"');
		}

		if (rest != null) {
			buf.add(" ");
			buf.add(rest);
		}

		return buf.toString();
	}
}
