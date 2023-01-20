class TestsMain {
	public static function main() {
		buildSimplest();
	}

	macro static function buildSimplest() {
		var cb = new CodeBuilder(null);
		cb.build();
		return macro {}
	}
}
